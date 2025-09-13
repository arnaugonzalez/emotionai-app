import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models/user.dart';
import 'models/auth_response.dart';
import 'models/chat_response.dart';
import 'models/breathing_pattern.dart';
import 'models/breathing_session.dart';
import 'models/custom_emotion.dart';
import 'models/emotional_record.dart';
import 'models/user_limitations.dart';
import '../config/api_config.dart';

import '../utils/data_validator.dart';
import 'package:logger/logger.dart';
import 'exceptions/api_exceptions.dart';
import 'auth_api.dart';

class ApiService {
  final _storage = const FlutterSecureStorage();
  final _logger = Logger();
  final AuthApi _authApi;
  late final Dio _dio;

  ApiService({Dio? dio, AuthApi? authApi}) : _authApi = authApi ?? AuthApi() {
    _dio = dio ?? _authApi.dio;
  }

  Future<String?> _getToken() async {
    // Use AuthApi to ensure token is fresh and aligns with interceptor storage
    return await _authApi.getValidAccessToken();
  }

  // Deprecated: tokens are managed via AuthApi

  Future<void> _clearToken() async {
    await _storage.delete(key: 'auth_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Public getter for headers (used by sync service)
  Future<Map<String, String>> getHeaders() async {
    return await _getHeaders();
  }

  /// Handle HTTP response and throw appropriate exceptions
  T _handleResponse<T>(
    Response response,
    T Function(Map<String, dynamic>) parser,
  ) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      try {
        final data = response.data as Map<String, dynamic>;
        return parser(data);
      } catch (e) {
        _logger.e('Failed to parse response: $e');
        throw UnknownApiException('Invalid response format');
      }
    }
    throw ApiExceptionFactory.fromResponse(status, jsonEncode(response.data));
  }

  /// Handle HTTP response for list endpoints
  List<T> _handleListResponse<T>(
    Response response,
    T Function(Map<String, dynamic>) parser,
  ) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      try {
        final dynamic responseData = response.data;
        if (responseData is! List) {
          throw UnknownApiException(
            'Expected list response, got: ${responseData.runtimeType}',
          );
        }
        final List<dynamic> data = responseData;
        _logger.i('Processing ${data.length} items');
        final validatedData = DataValidator.validateApiResponseList(
          data,
          T.toString(),
        );
        return validatedData.map((json) => parser(json)).toList();
      } catch (e) {
        if (e is ApiException) rethrow;
        _logger.e('Failed to parse list response: $e');
        throw UnknownApiException('Invalid response format');
      }
    }
    throw ApiExceptionFactory.fromResponse(status, jsonEncode(response.data));
  }

  Future<User> createUser(
    String email,
    String password,
    String firstName,
    String lastName, {
    DateTime? dateOfBirth,
  }) async {
    // Use AuthApi to register and then fetch profile
    await _authApi.register(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
    final me = await _authApi.me();
    return User.fromJson(me);
  }

  Future<AuthResponse?> login(String email, String password) async {
    // Use AuthApi for login (stores access/refresh + expiry)
    final tokens = await _authApi.login(email: email, password: password);
    // Build AuthResponse using /auth/me for user data
    final me = await _authApi.me();
    return AuthResponse(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      tokenType: 'bearer',
      expiresIn: tokens.expiresIn,
      user: User.fromJson(me),
    );
  }

  Future<void> logout() async {
    await _clearToken();
  }

  // Emotional Records
  Future<EmotionalRecord> createEmotionalRecord(EmotionalRecord record) async {
    _logger.i(
      '📤 Creating emotional record: ${record.emotion} (intensity: ${record.intensity})',
    );

    try {
      final response = await _dio.post(
        ApiConfig.emotionalRecordsUrl(),
        data: record.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      _logger.i('📥 Emotional record response: ${response.statusCode}');
      return _handleResponse(response, (data) {
        _logger.i('✅ Emotional record created successfully: ${data['id']}');
        return EmotionalRecord.fromJson(data);
      });
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      _logger.e('❌ Network error creating emotional record: $e');
      throw ApiExceptionFactory.fromException(e);
    }
  }

  Future<List<EmotionalRecord>> getEmotionalRecords() async {
    try {
      _logger.i(
        'Fetching emotional records from ${ApiConfig.emotionalRecordsUrl()}',
      );

      final response = await _dio.get(
        ApiConfig.emotionalRecordsUrl(),
        options: Options(headers: await _getHeaders()),
      );
      _logger.i('Emotional records response: ${response.statusCode}');
      return _handleListResponse(
        response,
        (json) => EmotionalRecord.fromJson(json),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      _logger.e('Error fetching emotional records: $e');
      throw ApiExceptionFactory.fromException(e);
    }
  }

  // Breathing Sessions
  Future<BreathingSessionData> createBreathingSession(
    BreathingSessionData session,
  ) async {
    try {
      final response = await _dio.post(
        ApiConfig.breathingSessionsUrl(),
        data: session.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleResponse(
        response,
        (data) => BreathingSessionData.fromJson(data),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  Future<List<BreathingSessionData>> getBreathingSessions() async {
    try {
      _logger.i(
        'Fetching breathing sessions from ${ApiConfig.breathingSessionsUrl()}',
      );

      final response = await _dio.get(
        ApiConfig.breathingSessionsUrl(),
        options: Options(headers: await _getHeaders()),
      );
      _logger.i('Breathing sessions response: ${response.statusCode}');

      return _handleListResponse(
        response,
        (json) => BreathingSessionData.fromJson(json),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      _logger.e('Error fetching breathing sessions: $e');
      throw ApiExceptionFactory.fromException(e);
    }
  }

  // Breathing Patterns
  Future<BreathingPattern> createBreathingPattern(
    BreathingPattern pattern,
  ) async {
    try {
      final response = await _dio.post(
        ApiConfig.breathingPatternsUrl(),
        data: pattern.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleResponse(
        response,
        (data) => BreathingPattern.fromJson(data),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  Future<List<BreathingPattern>> getBreathingPatterns() async {
    try {
      final response = await _dio.get(
        ApiConfig.breathingPatternsUrl(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleListResponse(
        response,
        (json) => BreathingPattern.fromJson(json),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  // Custom Emotions
  Future<CustomEmotion> createCustomEmotion(CustomEmotion emotion) async {
    try {
      final response = await _dio.post(
        ApiConfig.customEmotionsUrl(),
        data: emotion.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleResponse(response, (data) => CustomEmotion.fromJson(data));
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  Future<List<CustomEmotion>> getCustomEmotions() async {
    try {
      final response = await _dio.get(
        ApiConfig.customEmotionsUrl(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleListResponse(
        response,
        (json) => CustomEmotion.fromJson(json),
      );
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  // User Limitations (from backend)
  Future<UserLimitations> getUserLimitations() async {
    try {
      final response = await _dio.get(
        ApiConfig.userLimitationsUrl(),
        options: Options(headers: await _getHeaders()),
      );
      return _handleResponse(response, (data) {
        // Map monthly fields from API to UserLimitations daily-like fields expected by UI
        final monthlyLimit = (data['monthly_token_limit'] ?? 250000) as int;
        final monthlyUsed = (data['monthly_tokens_used'] ?? 0) as int;
        // usagePercentage available if the widget needs it later
        final canMakeRequest = data['can_make_request'] ?? true;
        final limitMessage = data['limit_message'];
        final reset = data['limit_reset_time'];

        return UserLimitations(
          dailyTokenLimit: monthlyLimit,
          dailyTokensUsed: monthlyUsed,
          isUnlimited: false,
          canMakeRequest: canMakeRequest,
          limitMessage: limitMessage,
          limitResetTime: reset != null ? DateTime.parse(reset) : null,
          dailyCostLimit: 0,
          dailyCostUsed: 0,
        );
      });
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptionFactory.fromResponse(
        e.response?.statusCode ?? 0,
        jsonEncode(e.response?.data),
      );
    } catch (e) {
      throw ApiExceptionFactory.fromException(e);
    }
  }

  // Send chat message to backend using new API structure
  Future<ChatResponse> sendChatMessage(
    String message, {
    String agentType = 'therapy',
    Map<String, dynamic>? context,
  }) async {
    final response = await _dio.post(
      ApiConfig.chatUrl(),
      data: {
        'agent_type': agentType,
        'message': message,
        if (context != null) 'context': context,
      },
      options: Options(headers: await _getHeaders()),
    );
    if (response.statusCode == 200) {
      return ChatResponse.fromJson(response.data as Map<String, dynamic>);
    } else if (response.statusCode == 429) {
      final data = response.data as Map<String, dynamic>;
      throw Exception(
        data['message'] ?? data['detail'] ?? 'Rate limit exceeded',
      );
    } else {
      final data = response.data as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'Failed to send chat message');
    }
  }

  // Get available agents
  Future<List<Map<String, dynamic>>> getAgents() async {
    final response = await _dio.get(
      ApiConfig.agentsListUrl(),
      options: Options(headers: await _getHeaders()),
    );
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['agents']);
    } else {
      throw Exception('Failed to get agents');
    }
  }

  // Get agent status
  Future<Map<String, dynamic>> getAgentStatus(String agentType) async {
    final response = await _dio.get(
      ApiConfig.agentStatusUrl(agentType),
      options: Options(headers: await _getHeaders()),
    );
    if (response.statusCode == 200) {
      return response.data as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get agent status');
    }
  }

  // Clear agent memory
  Future<void> clearAgentMemory(String agentType) async {
    final response = await _dio.delete(
      ApiConfig.agentMemoryUrl(agentType),
      options: Options(headers: await _getHeaders()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to clear agent memory');
    }
  }

  // Get conversations
  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await _dio.get(
      '${ApiConfig.baseUrl}/v1/api/conversations',
      options: Options(headers: await _getHeaders()),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(response.data as List);
    } else {
      throw Exception('Failed to get conversations');
    }
  }

  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(ApiConfig.healthUrl());
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Dev seed endpoints
  Future<Map<String, dynamic>> devSeedLoadPresetData() async {
    final response = await _dio.post(
      ApiConfig.devSeedLoadPresetDataUrl(),
      options: Options(headers: await _getHeaders()),
    );
    return _handleResponse(response, (data) => data);
  }

  Future<Map<String, dynamic>> devSeedReset() async {
    final response = await _dio.post(
      ApiConfig.devSeedResetUrl(),
      options: Options(headers: await _getHeaders()),
    );
    return _handleResponse(response, (data) => data);
  }
}
