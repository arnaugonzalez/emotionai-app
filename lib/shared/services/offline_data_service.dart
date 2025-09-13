import 'dart:async';
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import '../services/sqlite_helper.dart';
import '../../data/api_service.dart';
import '../../data/models/emotional_record.dart';
import '../../data/models/breathing_session.dart';
import '../../data/models/breathing_pattern.dart';
import '../../data/models/custom_emotion.dart';
import '../../config/api_config.dart';

final logger = Logger();

enum DataSource { local, remote, hybrid }

enum ConnectivityStatus { online, offline, unknown }

class DataResult<T> {
  final T? data;
  final bool isFromCache;
  final String? error;
  final ConnectivityStatus connectivityStatus;
  final DateTime lastSync;

  DataResult({
    this.data,
    this.isFromCache = false,
    this.error,
    this.connectivityStatus = ConnectivityStatus.unknown,
    DateTime? lastSync,
  }) : lastSync = lastSync ?? DateTime.now();

  bool get hasData => data != null;
  bool get hasError => error != null;
  bool get isOnline => connectivityStatus == ConnectivityStatus.online;
}

class OfflineDataService {
  static final OfflineDataService _instance = OfflineDataService._internal();
  factory OfflineDataService() => _instance;
  OfflineDataService._internal();

  final SQLiteHelper _sqliteHelper = SQLiteHelper();
  final ApiService _apiService = ApiService();

  ConnectivityStatus _connectivityStatus = ConnectivityStatus.unknown;
  Timer? _syncTimer;
  final Map<String, DateTime> _lastSyncTimes = {};

  // Connectivity status stream
  final StreamController<ConnectivityStatus> _connectivityController =
      StreamController<ConnectivityStatus>.broadcast();
  Stream<ConnectivityStatus> get connectivityStream =>
      _connectivityController.stream;

  ConnectivityStatus get currentConnectivityStatus => _connectivityStatus;

  /// Initialize the service and start background sync
  Future<void> initialize() async {
    await _checkConnectivity();
    _startPeriodicSync();
    logger.i('OfflineDataService initialized - Status: $_connectivityStatus');
  }

  /// Check connectivity by trying to reach backend
  Future<bool> _checkConnectivity() async {
    try {
      final response = await Dio().get(ApiConfig.healthUrl());
      final isOnline = response.statusCode == 200;
      final newStatus =
          isOnline ? ConnectivityStatus.online : ConnectivityStatus.offline;

      if (newStatus != _connectivityStatus) {
        _connectivityStatus = newStatus;
        _connectivityController.add(_connectivityStatus);
        logger.i('Connectivity changed to: $_connectivityStatus');
      }

      return isOnline;
    } catch (e) {
      final newStatus = ConnectivityStatus.offline;
      if (newStatus != _connectivityStatus) {
        _connectivityStatus = newStatus;
        _connectivityController.add(_connectivityStatus);
        logger.i('Connectivity changed to: $_connectivityStatus (Error: $e)');
      }
      return false;
    }
  }

  /// Start periodic background sync every 30 seconds
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnectivity();
      if (_connectivityStatus == ConnectivityStatus.online) {
        _backgroundSync();
      }
    });
  }

  /// Background sync of unsynced data
  Future<void> _backgroundSync() async {
    try {
      await _syncUnsyncedData();
      logger.i('Background sync completed');
    } catch (e) {
      logger.w('Background sync failed: $e');
    }
  }

  /// Sync all unsynced data to backend
  Future<void> _syncUnsyncedData() async {
    if (_connectivityStatus != ConnectivityStatus.online) return;

    try {
      // Sync emotional records
      final unsyncedEmotional =
          await _sqliteHelper.getUnsyncedEmotionalRecords();
      for (final record in unsyncedEmotional) {
        try {
          await _apiService.createEmotionalRecord(record);
          if (record.id != null) {
            await _sqliteHelper.markEmotionalRecordAsSynced(
              int.parse(record.id!),
            );
          }
        } catch (e) {
          logger.e('Failed to sync emotional record: $e');
        }
      }

      // Sync breathing sessions
      final unsyncedSessions =
          await _sqliteHelper.getUnsyncedBreathingSessions();
      for (final session in unsyncedSessions) {
        try {
          await _apiService.createBreathingSession(session);
          if (session.id != null) {
            await _sqliteHelper.markBreathingSessionAsSynced(
              int.parse(session.id!),
            );
          }
        } catch (e) {
          logger.e('Failed to sync breathing session: $e');
        }
      }

      // Sync breathing patterns
      final unsyncedPatterns =
          await _sqliteHelper.getUnsyncedBreathingPatterns();
      for (final patternMap in unsyncedPatterns) {
        try {
          final pattern = BreathingPattern.fromMap(patternMap);
          await _apiService.createBreathingPattern(pattern);
          await _sqliteHelper.markBreathingPatternAsSynced(
            patternMap['id'] as int,
          );
        } catch (e) {
          logger.e('Failed to sync breathing pattern: $e');
        }
      }

      logger.i('Unsynced data sync completed');
    } catch (e) {
      logger.e('Error syncing unsynced data: $e');
    }
  }

  /// Force a manual sync
  Future<bool> forceSyncAll() async {
    final wasOnline = await _checkConnectivity();
    if (wasOnline) {
      await _syncUnsyncedData();
    }
    return wasOnline;
  }

  // EMOTIONAL RECORDS
  Future<DataResult<List<EmotionalRecord>>> getEmotionalRecords({
    DataSource preferredSource = DataSource.hybrid,
  }) async {
    if (preferredSource == DataSource.local) {
      return _getEmotionalRecordsLocal();
    }
    if (preferredSource == DataSource.remote) {
      return _getEmotionalRecordsRemote();
    }
    return _getEmotionalRecordsHybrid();
  }

  Future<DataResult<List<EmotionalRecord>>> _getEmotionalRecordsLocal() async {
    try {
      final records = await _sqliteHelper.getEmotionalRecords();
      return DataResult(
        data: records,
        isFromCache: true,
        connectivityStatus: _connectivityStatus,
        lastSync: _lastSyncTimes['emotional_records'],
      );
    } catch (e) {
      return DataResult(
        error: 'Local data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<DataResult<List<EmotionalRecord>>> _getEmotionalRecordsRemote() async {
    try {
      if (!await _checkConnectivity()) {
        throw Exception('No internet connection');
      }

      final records = await _apiService.getEmotionalRecords();
      _lastSyncTimes['emotional_records'] = DateTime.now();

      return DataResult(
        data: records,
        isFromCache: false,
        connectivityStatus: ConnectivityStatus.online,
        lastSync: _lastSyncTimes['emotional_records'],
      );
    } catch (e) {
      return DataResult(
        error: 'Remote data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<DataResult<List<EmotionalRecord>>> _getEmotionalRecordsHybrid() async {
    // Try remote first, fallback to local
    final remoteResult = await _getEmotionalRecordsRemote();
    if (remoteResult.hasData) {
      return remoteResult;
    }

    // Fallback to local data
    final localResult = await _getEmotionalRecordsLocal();
    return DataResult(
      data: localResult.data,
      isFromCache: true,
      error: localResult.hasData ? null : 'No data available offline or online',
      connectivityStatus: _connectivityStatus,
      lastSync: _lastSyncTimes['emotional_records'],
    );
  }

  Future<bool> saveEmotionalRecord(EmotionalRecord record) async {
    try {
      // Always save locally first
      await _sqliteHelper.insertEmotionalRecord(record);
      logger.i('Emotional record saved locally');

      // Try to sync to backend if online
      if (await _checkConnectivity()) {
        try {
          await _apiService.createEmotionalRecord(record);
          logger.i('Emotional record synced to backend');
        } catch (e) {
          logger.w('Failed to sync emotional record to backend: $e');
          // Local save already successful, so return true
        }
      }
      return true;
    } catch (e) {
      logger.e('Failed to save emotional record: $e');
      return false;
    }
  }

  // BREATHING SESSIONS
  Future<DataResult<List<BreathingSessionData>>> getBreathingSessions({
    DataSource preferredSource = DataSource.hybrid,
  }) async {
    if (preferredSource == DataSource.local) {
      return _getBreathingSessionsLocal();
    }
    if (preferredSource == DataSource.remote) {
      return _getBreathingSessionsRemote();
    }
    return _getBreathingSessionsHybrid();
  }

  Future<DataResult<List<BreathingSessionData>>>
  _getBreathingSessionsLocal() async {
    try {
      final sessions = await _sqliteHelper.getBreathingSessions();
      return DataResult(
        data: sessions,
        isFromCache: true,
        connectivityStatus: _connectivityStatus,
        lastSync: _lastSyncTimes['breathing_sessions'],
      );
    } catch (e) {
      return DataResult(
        error: 'Local data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<DataResult<List<BreathingSessionData>>>
  _getBreathingSessionsRemote() async {
    try {
      if (!await _checkConnectivity()) {
        throw Exception('No internet connection');
      }

      final sessions = await _apiService.getBreathingSessions();
      _lastSyncTimes['breathing_sessions'] = DateTime.now();

      return DataResult(
        data: sessions,
        isFromCache: false,
        connectivityStatus: ConnectivityStatus.online,
        lastSync: _lastSyncTimes['breathing_sessions'],
      );
    } catch (e) {
      return DataResult(
        error: 'Remote data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<DataResult<List<BreathingSessionData>>>
  _getBreathingSessionsHybrid() async {
    final remoteResult = await _getBreathingSessionsRemote();
    if (remoteResult.hasData) {
      return remoteResult;
    }

    final localResult = await _getBreathingSessionsLocal();
    return DataResult(
      data: localResult.data,
      isFromCache: true,
      error: localResult.hasData ? null : 'No data available offline or online',
      connectivityStatus: _connectivityStatus,
      lastSync: _lastSyncTimes['breathing_sessions'],
    );
  }

  Future<bool> saveBreathingSession(BreathingSessionData session) async {
    try {
      await _sqliteHelper.insertBreathingSession(session);
      logger.i('Breathing session saved locally');

      if (await _checkConnectivity()) {
        try {
          await _apiService.createBreathingSession(session);
          logger.i('Breathing session synced to backend');
        } catch (e) {
          logger.w('Failed to sync breathing session to backend: $e');
        }
      }
      return true;
    } catch (e) {
      logger.e('Failed to save breathing session: $e');
      return false;
    }
  }

  // BREATHING PATTERNS
  Future<DataResult<List<BreathingPattern>>> getBreathingPatterns({
    DataSource preferredSource = DataSource.hybrid,
  }) async {
    // Always prefer local for breathing patterns since they rarely change
    final localResult = await _getBreathingPatternsLocal();
    if (localResult.hasData && localResult.data!.isNotEmpty) {
      return localResult;
    }

    // Fallback to remote if no local data
    if (preferredSource != DataSource.local) {
      final remoteResult = await _getBreathingPatternsRemote();
      if (remoteResult.hasData) {
        return remoteResult;
      }
    }

    return localResult;
  }

  Future<DataResult<List<BreathingPattern>>>
  _getBreathingPatternsLocal() async {
    try {
      final patterns = await _sqliteHelper.getBreathingPatterns();
      return DataResult(
        data: patterns,
        isFromCache: true,
        connectivityStatus: _connectivityStatus,
        lastSync: _lastSyncTimes['breathing_patterns'],
      );
    } catch (e) {
      return DataResult(
        error: 'Local data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<DataResult<List<BreathingPattern>>>
  _getBreathingPatternsRemote() async {
    try {
      if (!await _checkConnectivity()) {
        throw Exception('No internet connection');
      }

      final patterns = await _apiService.getBreathingPatterns();
      _lastSyncTimes['breathing_patterns'] = DateTime.now();

      return DataResult(
        data: patterns,
        isFromCache: false,
        connectivityStatus: ConnectivityStatus.online,
        lastSync: _lastSyncTimes['breathing_patterns'],
      );
    } catch (e) {
      return DataResult(
        error: 'Remote data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<bool> saveBreathingPattern(BreathingPattern pattern) async {
    try {
      await _sqliteHelper.insertBreathingPattern(pattern);
      logger.i('Breathing pattern saved locally');

      if (await _checkConnectivity()) {
        try {
          await _apiService.createBreathingPattern(pattern);
          logger.i('Breathing pattern synced to backend');
        } catch (e) {
          logger.w('Failed to sync breathing pattern to backend: $e');
        }
      }
      return true;
    } catch (e) {
      logger.e('Failed to save breathing pattern: $e');
      return false;
    }
  }

  // CUSTOM EMOTIONS (Local only - no backend endpoint yet)
  Future<DataResult<List<CustomEmotion>>> getCustomEmotions() async {
    try {
      final emotions = await _sqliteHelper.getCustomEmotions();
      return DataResult(
        data: emotions,
        isFromCache: true,
        connectivityStatus: _connectivityStatus,
      );
    } catch (e) {
      return DataResult(
        error: 'Local data error: $e',
        connectivityStatus: _connectivityStatus,
      );
    }
  }

  Future<bool> saveCustomEmotion(CustomEmotion emotion) async {
    try {
      await _sqliteHelper.insertCustomEmotion(emotion);
      logger.i('Custom emotion saved locally');
      return true;
    } catch (e) {
      logger.e('Failed to save custom emotion: $e');
      return false;
    }
  }

  /// Clean up resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivityController.close();
  }
}
