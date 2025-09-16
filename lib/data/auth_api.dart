import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../config/api_config.dart';

class AuthTokens {
  final String accessToken;
  final String? refreshToken;
  final int expiresIn;
  AuthTokens({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
  });
}

class AuthApi {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  String? _inMemoryAccess;
  DateTime? _accessExpiry;
  bool _refreshInProgress = false;
  Completer<void>? _refreshCompleter;

  AuthApi({Dio? dio, FlutterSecureStorage? storage})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              sendTimeout: ApiConfig.sendTimeout,
            ),
          ),
      _storage = storage ?? const FlutterSecureStorage() {
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  // Expose Dio client for consumers without leaking private field
  Dio get dio => _dio;

  Future<AuthTokens> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final res = await _dio.post(
      ApiConfig.registerUrl(),
      data: {
        'email': email,
        'password': password,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    );
    final data = res.data as Map<String, dynamic>;
    return _storeTokensFromAuthResponse(data);
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post(
      ApiConfig.loginUrl(),
      data: {'email': email, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    return _storeTokensFromAuthResponse(data);
  }

  Future<AuthTokens> refresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) {
      throw DioException(
        requestOptions: RequestOptions(path: ApiConfig.refreshUrl()),
        error: 'Missing refresh token',
      );
    }
    final res = await _dio.post(
      ApiConfig.refreshUrl(),
      data: {'refresh_token': refreshToken},
    );
    final data = res.data as Map<String, dynamic>;
    final access = data['access_token'] as String;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 1800;
    await _persistAccess(access, expiresIn);
    return AuthTokens(
      accessToken: access,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get(ApiConfig.meUrl());
    return res.data as Map<String, dynamic>;
  }

  String? get accessToken => _inMemoryAccess;

  Future<String?> getValidAccessToken() async {
    await _ensureFreshAccessToken();
    if (_inMemoryAccess != null && _inMemoryAccess!.isNotEmpty) {
      return _inMemoryAccess;
    }
    return await _storage.read(key: 'access_token');
  }

  Future<void> _persistAccess(String token, int expiresIn) async {
    _inMemoryAccess = token;
    final now = DateTime.now();
    _accessExpiry = now.add(Duration(seconds: expiresIn));
    await _storage.write(key: 'access_token', value: token);
    await _storage.write(
      key: 'access_expiry',
      value: _accessExpiry!.toIso8601String(),
    );
  }

  Future<void> _persistRefresh(String token) async {
    await _storage.write(key: 'refresh_token', value: token);
  }

  Future<AuthTokens> _storeTokensFromAuthResponse(
    Map<String, dynamic> data,
  ) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 1800;
    await _persistAccess(access, expiresIn);
    if (refresh != null) await _persistRefresh(refresh);
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: expiresIn,
    );
  }

  bool _isAccessExpiringSoon() {
    try {
      if (_inMemoryAccess == null) return true;
      // Prefer JWT exp if present; fallback to stored expiry
      if (JwtDecoder.isExpired(_inMemoryAccess!)) return true;
      final exp = JwtDecoder.getExpirationDate(_inMemoryAccess!);
      final nowPlus60 = DateTime.now().add(const Duration(seconds: 60));
      return exp.isBefore(nowPlus60);
    } catch (_) {
      if (_accessExpiry == null) return true;
      return _accessExpiry!.isBefore(
        DateTime.now().add(const Duration(seconds: 60)),
      );
    }
  }

  Future<void> _ensureFreshAccessToken() async {
    if (!_isAccessExpiringSoon()) return;
    // Debounce concurrent refreshes
    if (_refreshInProgress) {
      await _refreshCompleter?.future;
      return;
    }
    _refreshInProgress = true;
    _refreshCompleter = Completer<void>();
    try {
      await refresh();
      _refreshCompleter?.complete();
    } finally {
      _refreshInProgress = false;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  final AuthApi _auth;
  _AuthInterceptor(this._auth);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      await _auth._ensureFreshAccessToken();
      final token =
          _auth.accessToken ??
          await const FlutterSecureStorage().read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // proceed without token
    }
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // If unauthorized, try a single refresh then retry
    if (err.response?.statusCode == 401) {
      try {
        await _auth.refresh();
        final req = await _retry(err.requestOptions);
        return handler.resolve(req);
      } catch (_) {
        // fall through to original error
      }
    }
    return handler.next(err);
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final options = Options(
      method: requestOptions.method,
      headers: requestOptions.headers,
      responseType: requestOptions.responseType,
      contentType: requestOptions.contentType,
    );
    final dio = _auth._dio;
    return dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
      cancelToken: requestOptions.cancelToken,
      onSendProgress: requestOptions.onSendProgress,
      onReceiveProgress: requestOptions.onReceiveProgress,
    );
  }
}
