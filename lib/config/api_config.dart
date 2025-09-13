/// API Configuration for EmotionAI App
///
/// Centralized configuration for all backend API endpoints and settings.
/// Supports multiple environments and automatic backend URL detection
/// based on launch configuration and device type.
///
/// This is the ONLY configuration system - replaces environment_config.dart
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Optional explicit BASE_URL override (e.g., https://emotionai.duckdns.org)
  static const String _explicitBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );
  // Launch configuration parameters
  static const String _environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static const String _backendType = String.fromEnvironment(
    'BACKEND_TYPE',
    defaultValue: 'local',
  );

  static const String _deviceType = String.fromEnvironment(
    'DEVICE_TYPE',
    defaultValue: 'auto',
  );

  static const String _dockerHost = String.fromEnvironment(
    'DOCKER_HOST',
    defaultValue: '192.168.77.140', // Update this to your machine's current IP
  );

  // Static base URLs for deployed environments
  static const Map<String, String> _deployedUrls = {
    'staging': 'https://staging-api.emotionai.app',
    'production': 'https://api.emotionai.app',
  };

  // API Configuration with dynamic URL building
  static String get baseUrl {
    if (_explicitBaseUrl.isNotEmpty) {
      return _explicitBaseUrl;
    }
    return _buildDynamicUrl();
  }

  static String _buildDynamicUrl() {
    // For deployed environments, use predefined URLs
    if (_backendType == 'deployed') {
      return _deployedUrls[_environment] ?? _deployedUrls['staging']!;
    }

    // For local/docker development, build URL based on device and backend type
    final host = _getHost();
    final port = _getPort();
    final protocol = _getProtocol();

    final url = '$protocol://$host:$port';
    print(
      '🔗 API Config: Built URL: $url (Backend: $_backendType, Device: $_deviceType, Environment: $_environment)',
    );
    return url;
  }

  static String _getHost() {
    switch (_backendType) {
      case 'docker':
        return _dockerHost;
      case 'local':
      default:
        return _getLocalHost();
    }
  }

  static String _getLocalHost() {
    // Auto-detect device type if not specified
    final deviceType =
        _deviceType == 'auto' ? _detectDeviceType() : _deviceType;

    switch (deviceType) {
      case 'emulator':
        return '10.0.2.2'; // Android emulator special IP
      case 'physical':
        return '192.168.77.140'; // Local network IP
      case 'desktop':
      case 'web':
        return 'localhost';
      default:
        // Fallback: try to detect based on environment name
        if (_environment.contains('emulator')) {
          return '10.0.2.2';
        } else if (_environment.contains('local')) {
          return 'localhost';
        } else {
          return '192.168.77.140'; // Default to physical device
        }
    }
  }

  static String _detectDeviceType() {
    // Enhanced device detection using platform information
    if (kIsWeb) {
      return 'web';
    }

    // Check environment hints first
    if (_environment.contains('emulator')) {
      return 'emulator';
    } else if (_environment.contains('local') ||
        _environment.contains('desktop')) {
      return 'desktop';
    }

    // Use platform detection as fallback
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        return 'desktop';
      } else if (Platform.isAndroid || Platform.isIOS) {
        // For mobile platforms, we assume physical device unless told otherwise
        // Android emulator detection is tricky, so we rely on environment variables
        return 'physical';
      }
    } catch (e) {
      // Platform detection failed, use environment fallback
    }

    return 'physical'; // Safe default for mobile apps
  }

  static String _getPort() {
    switch (_backendType) {
      case 'docker':
        return '8000'; // Standard Docker port
      case 'local':
      default:
        return '8000'; // Standard development port
    }
  }

  static String _getProtocol() {
    return _backendType == 'deployed' ? 'https' : 'http';
  }

  // Getters for configuration info
  static String get environment => _environment;
  static String get backendType => _backendType;
  static String get deviceType => _deviceType;
  static String get dockerHost => _dockerHost;

  // Timeout settings
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // API Endpoints
  // Base API paths
  static const String _health = '/health';
  static const String _healthDetailed = '/health/detailed';

  // Authentication endpoints
  static const String _v1 = '/v1/api';
  static const String _authLogin = '$_v1/auth/login';
  static const String _authRegister = '$_v1/auth/register';
  static const String _authRefresh = '$_v1/auth/refresh';
  static const String _authMe = '$_v1/auth/me';

  // Chat endpoints
  static const String _chatV1 = '$_v1/chat';
  static const String _agentsList = '$_v1/agents';
  static String _agentStatus(String agentType) =>
      '$_v1/agents/$agentType/status';
  static String _agentMemory(String agentType) =>
      '$_v1/agents/$agentType/memory';

  // Legacy endpoints (to be migrated)
  static const String _emotionalRecords = '$_v1/emotional_records';
  static const String _breathingSessions = '$_v1/breathing_sessions';
  static const String _breathingPatterns = '$_v1/breathing_patterns';

  // Data endpoints
  static const String _customEmotions = '$_v1/custom_emotions';

  // Profile endpoints
  static const String _profile = '$_v1/profile';
  static const String _profileStatus = '$_v1/profile/status';
  static const String _therapyContext = '$_v1/profile/therapy-context';
  static const String _agentPersonality = '$_v1/profile/agent-personality';

  // Usage endpoints
  static const String _userLimitations = '$_v1/user/limitations';

  // Test endpoints
  static const String _testConnection = '/test/phone';

  // Dev seed endpoints (dev-only on backend)
  static const String _devSeedLoadPresetData = '/dev/seed/load_preset_data';
  static const String _devSeedReset = '/dev/seed/reset';

  // Full URL builders
  static String healthUrl() => '$baseUrl$_health/';
  static String healthDetailedUrl() => '$baseUrl$_healthDetailed';
  static String loginUrl() => '$baseUrl$_authLogin';
  static String registerUrl() => '$baseUrl$_authRegister';
  static String refreshUrl() => '$baseUrl$_authRefresh';
  static String meUrl() => '$baseUrl$_authMe';
  static String chatUrl() => '$baseUrl$_chatV1';
  static String agentsListUrl() => '$baseUrl$_agentsList';
  static String agentStatusUrl(String agentType) =>
      '$baseUrl${_agentStatus(agentType)}';
  static String agentMemoryUrl(String agentType) =>
      '$baseUrl${_agentMemory(agentType)}';

  // Legacy URLs (for backward compatibility)
  static String emotionalRecordsUrl() => '$baseUrl$_emotionalRecords/';
  static String breathingSessionsUrl() => '$baseUrl$_breathingSessions/';
  static String breathingPatternsUrl() => '$baseUrl$_breathingPatterns/';

  // Data URLs
  static String customEmotionsUrl() => '$baseUrl$_customEmotions/';

  // Profile URLs
  static String profileUrl() => '$baseUrl$_profile';
  static String profileStatusUrl() => '$baseUrl$_profileStatus';
  static String therapyContextUrl() => '$baseUrl$_therapyContext';
  static String agentPersonalityUrl() => '$baseUrl$_agentPersonality';

  // Usage URLs
  static String userLimitationsUrl() => '$baseUrl$_userLimitations';

  static String testConnectionUrl() => '$baseUrl$_testConnection';
  static String devSeedLoadPresetDataUrl() => '$baseUrl$_devSeedLoadPresetData';
  static String devSeedResetUrl() => '$baseUrl$_devSeedReset';

  // HTTP Headers
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Map<String, String> authHeaders(String token) => {
    ...defaultHeaders,
    'Authorization': 'Bearer $token',
  };

  // Environment checks
  static bool get isDevelopment => _environment.startsWith('development');
  static bool get isStaging => _environment == 'staging';
  static bool get isProduction => _environment == 'production';
  static bool get isLocalBackend => _backendType == 'local';
  static bool get isDockerBackend => _backendType == 'docker';
  static bool get isDeployedBackend => _backendType == 'deployed';

  // Development utilities
  static void printConfig() {
    final detectedDeviceType = _detectDeviceType();

    print('');
    print('🚀 ===== EmotionAI API Configuration =====');
    print('📊 Environment: $_environment');
    print('🔧 Backend Type: $_backendType');
    print('📱 Device Type: $_deviceType (detected: $detectedDeviceType)');
    print('🌐 Base URL: $baseUrl');
    print('🔗 Host Resolution: ${_getHost()}');
    if (_backendType == 'docker') {
      print('🐳 Docker Host: $_dockerHost');
    }
    print('🔍 Debug Mode: $enableDebugLogs');
    print('📋 Mock Data: $enableMockData');
    print('');
    print('📡 Key Endpoints:');
    print('  🏥 Health: ${healthUrl()}');
    print('  🔐 Login: ${loginUrl()}');
    print('  💬 Chat: ${chatUrl()}');
    print('  📊 Records: ${emotionalRecordsUrl()}');
    print('');
    print('🔧 Platform Info:');
    print('  📱 Is Web: $kIsWeb');
    if (!kIsWeb) {
      try {
        print('  💻 Platform: ${Platform.operatingSystem}');
      } catch (e) {
        print('  💻 Platform: Unknown');
      }
    }
    print('========================================');
    print('');
  }

  // Enhanced configuration validation
  static bool validateConfiguration() {
    bool isValid = true;
    final issues = <String>[];

    // Check if backend type is valid
    if (!['local', 'docker', 'deployed'].contains(_backendType)) {
      issues.add('Invalid backend type: $_backendType');
      isValid = false;
    }

    // Check if device type is valid
    if (![
      'auto',
      'emulator',
      'physical',
      'desktop',
      'web',
      'any',
    ].contains(_deviceType)) {
      issues.add('Invalid device type: $_deviceType');
      isValid = false;
    }

    // Check if environment is valid
    if (![
      'development',
      'development_emulator',
      'development_local',
      'staging',
      'production',
    ].contains(_environment)) {
      issues.add('Invalid environment: $_environment');
      isValid = false;
    }

    if (!isValid) {
      print('❌ Configuration Issues Found:');
      for (final issue in issues) {
        print('  • $issue');
      }
    }

    return isValid;
  }

  // Feature flags (can be controlled per environment)
  static bool get enableCrisisDetection => true;
  static bool get enableAgentSelection => true;
  static bool get enableDebugLogs => isDevelopment;
  static bool get enableMockData => isDevelopment && !isDeployedBackend;

  // Mock data for development
  static bool get useMockEmotionalRecords => isDevelopment && enableMockData;
  static bool get useMockBreathingSessions => isDevelopment && enableMockData;

  // Launch configuration helpers
  static Map<String, String> get launchConfiguration => {
    'ENVIRONMENT': _environment,
    'BACKEND_TYPE': _backendType,
    'DEVICE_TYPE': _deviceType,
    'DOCKER_HOST': _dockerHost,
    'BASE_URL': baseUrl,
  };
}
