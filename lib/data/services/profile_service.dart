import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user_profile.dart';
import '../models/therapy_context.dart';
import '../../config/api_config.dart';
import '../auth_api.dart';

class ProfileService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Dio _dio;

  ProfileService({Dio? dio}) : _dio = dio ?? AuthApi().dio;

  Future<String?> _getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get user profile
  Future<UserProfile?> getUserProfile() async {
    try {
      final response = await _dio.get(
        ApiConfig.profileUrl(),
        options: Options(headers: await _getHeaders()),
      );

      print('DEBUG: Profile API response status: ${response.statusCode}');
      print('DEBUG: Profile API response body: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        print('DEBUG: Parsed profile data: $data');

        try {
          final profile = UserProfile.fromJson(data);
          print('DEBUG: Successfully created UserProfile object');
          return profile;
        } catch (parseError) {
          print('DEBUG: Error parsing profile data: $parseError');
          print('DEBUG: Data that failed to parse: $data');
          throw Exception('Failed to parse profile data: $parseError');
        }
      } else if (response.statusCode == 404) {
        print('DEBUG: Profile not found (404)');
        return null; // Profile not found
      } else {
        print(
          'DEBUG: Profile API error: ${response.statusCode} - ${response.data}',
        );
        throw Exception('Failed to get profile: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(
        'Error getting profile: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      print('DEBUG: Exception in getUserProfile: $e');
      throw Exception('Error getting profile: $e');
    }
  }

  /// Create or update user profile
  Future<UserProfile> createOrUpdateProfile(
    Map<String, dynamic> profileData,
  ) async {
    try {
      final response = await _dio.post(
        ApiConfig.profileUrl(),
        data: profileData,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        return UserProfile.fromJson(data);
      } else {
        throw Exception('Failed to save profile: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception('Error saving profile: ${e.response?.data ?? e.message}');
    } catch (e) {
      throw Exception('Error saving profile: $e');
    }
  }

  /// Get profile completion status
  Future<ProfileStatus> getProfileStatus() async {
    try {
      final response = await _dio.get(
        ApiConfig.profileStatusUrl(),
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return ProfileStatus.fromJson(data);
      } else {
        throw Exception('Failed to get profile status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(
        'Error getting profile status: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error getting profile status: $e');
    }
  }

  /// Get therapy context and AI insights
  Future<TherapyContext?> getTherapyContext() async {
    try {
      final response = await _dio.get(
        ApiConfig.therapyContextUrl(),
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return TherapyContext.fromJson(data);
      } else if (response.statusCode == 404) {
        return null; // No therapy context found
      } else {
        throw Exception(
          'Failed to get therapy context: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw Exception(
        'Error getting therapy context: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error getting therapy context: $e');
    }
  }

  /// Update therapy context and AI insights
  Future<TherapyContext> updateTherapyContext(
    Map<String, dynamic> contextData,
  ) async {
    try {
      final response = await _dio.put(
        ApiConfig.therapyContextUrl(),
        data: contextData,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return TherapyContext.fromJson(data);
      } else {
        throw Exception(
          'Failed to update therapy context: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw Exception(
        'Error updating therapy context: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error updating therapy context: $e');
    }
  }

  /// Clear therapy context and AI insights
  Future<bool> clearTherapyContext() async {
    try {
      final response = await _dio.delete(
        ApiConfig.therapyContextUrl(),
        options: Options(headers: await _getHeaders()),
      );

      return response.statusCode == 200;
    } on DioException catch (e) {
      throw Exception(
        'Error clearing therapy context: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error clearing therapy context: $e');
    }
  }

  /// Get AI agent personality settings and context
  Future<Map<String, dynamic>?> getAgentPersonality() async {
    try {
      final response = await _dio.get(
        ApiConfig.agentPersonalityUrl(),
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 404) {
        return null; // No agent personality data found
      } else {
        throw Exception(
          'Failed to get agent personality: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw Exception(
        'Error getting agent personality: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error getting agent personality: $e');
    }
  }

  /// Update AI agent personality settings and context
  Future<Map<String, dynamic>> updateAgentPersonality(
    Map<String, dynamic> personalityData,
  ) async {
    try {
      final response = await _dio.put(
        ApiConfig.agentPersonalityUrl(),
        data: personalityData,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data;
      } else {
        throw Exception(
          'Failed to update agent personality: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      throw Exception(
        'Error updating agent personality: ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      throw Exception('Error updating agent personality: $e');
    }
  }
}
