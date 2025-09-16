import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../logging/mobile_logger.dart';
import '../../data/auth_api.dart';

class AuthInterceptor extends Interceptor {
  final AuthApi authApi;
  final MobileLogger logger;

  // Single-flight refresh coordination
  static bool _refreshInProgress = false;
  static Completer<void>? _refreshCompleter;

  AuthInterceptor({required this.authApi, required this.logger});

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final start = DateTime.now();
    options.extra['start_time'] = start;
    final reqId = options.extra['x_request_id'] ?? _generateRequestId();
    options.extra['x_request_id'] = reqId;
    options.headers['X-Request-ID'] = reqId;

    try {
      // Avoid triggering refresh pre-login: attach only if we already have a token
      String? token =
          authApi.accessToken ??
          await const FlutterSecureStorage().read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        token = await authApi.getValidAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (_) {}

    logger.info('request.start', {
      'method': options.method,
      'url': options.uri.toString(),
      'request_id': reqId,
    });
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = response.requestOptions.extra['start_time'] as DateTime?;
    final latency =
        start != null ? DateTime.now().difference(start).inMilliseconds : null;
    final reqId = response.requestOptions.extra['x_request_id'];
    logger.info('request.end', {
      'status': response.statusCode,
      'latency_ms': latency,
      'request_id': reqId,
      'url': response.requestOptions.uri.toString(),
      'method': response.requestOptions.method,
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final start = err.requestOptions.extra['start_time'] as DateTime?;
    final latency =
        start != null ? DateTime.now().difference(start).inMilliseconds : null;
    final reqId = err.requestOptions.extra['x_request_id'];
    logger.error('http.error', {
      'type': err.type.toString(),
      'status': err.response?.statusCode,
      'message': kDebugMode ? err.message : 'request_failed',
      'latency_ms': latency,
      'request_id': reqId,
      'url': err.requestOptions.uri.toString(),
      'method': err.requestOptions.method,
    });

    // Handle 401 single-flight refresh
    if (err.response?.statusCode == 401) {
      // Only retry once
      final alreadyRetried = err.requestOptions.extra['retried'] == true;
      if (alreadyRetried) {
        return handler.next(err);
      }

      try {
        await _ensureSingleFlightRefresh(authApi);
        // Mark retried to prevent loops
        final opts = err.requestOptions;
        opts.extra['retried'] = true;
        // Update Authorization header with fresh token
        final token =
            authApi.accessToken ??
            await const FlutterSecureStorage().read(key: 'access_token');
        if (token != null) {
          opts.headers['Authorization'] = 'Bearer $token';
        }
        final dio = authApi.dio;
        final response = await dio.request(
          opts.path,
          data: opts.data,
          queryParameters: opts.queryParameters,
          options: Options(
            method: opts.method,
            headers: opts.headers,
            responseType: opts.responseType,
            contentType: opts.contentType,
            followRedirects: opts.followRedirects,
            validateStatus: opts.validateStatus,
          ),
          cancelToken: opts.cancelToken,
          onSendProgress: opts.onSendProgress,
          onReceiveProgress: opts.onReceiveProgress,
        );
        return handler.resolve(response);
      } catch (_) {
        // Refresh failed → propagate 401
        return handler.next(err);
      }
    }

    handler.next(err);
  }

  static Future<void> _ensureSingleFlightRefresh(AuthApi auth) async {
    if (_refreshInProgress) {
      await _refreshCompleter?.future;
      return;
    }
    _refreshInProgress = true;
    _refreshCompleter = Completer<void>();
    try {
      await auth.refresh();
      _refreshCompleter?.complete();
    } finally {
      _refreshInProgress = false;
    }
  }

  String _generateRequestId() {
    final r = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${DateTime.now().millisecondsSinceEpoch}-${hex(8)}';
  }
}
