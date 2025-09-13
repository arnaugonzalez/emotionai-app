import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';

import '../api_service.dart';
import '../models/emotional_record.dart';
import 'local_database_service.dart';
import '../../config/api_config.dart';

/// Service for handling online/offline sync of data
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Logger _logger = Logger();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final ApiService _apiService = ApiService();
  final Connectivity _connectivity = Connectivity();

  bool _isOnline = false;
  bool _isSyncing = false;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Stream of sync status updates
  final StreamController<SyncStatus> _syncStatusController =
      StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Current sync status
  SyncStatus get currentStatus => SyncStatus(
    isOnline: _isOnline,
    isSyncing: _isSyncing,
    lastSyncTime: _lastSyncTime,
    pendingRecords: _pendingRecordsCount,
  );

  DateTime? _lastSyncTime;
  int _pendingRecordsCount = 0;

  /// Initialize the sync service
  Future<void> initialize() async {
    _logger.i('🔄 Initializing SyncService...');

    // Check initial connectivity
    await _checkConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Start periodic sync timer (every 30 seconds when online)
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline && !_isSyncing) {
        syncPendingRecords();
      }
    });

    // Update pending records count
    await _updatePendingCount();

    _logger.i('✅ SyncService initialized');
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      final wasOnline = _isOnline;

      _isOnline = !connectivityResults.contains(ConnectivityResult.none);

      if (_isOnline && !wasOnline) {
        _logger.i('🌐 Connection restored - checking backend availability');
        _isOnline = await _checkBackendAvailability();
      }

      _logger.i('📶 Connectivity status: ${_isOnline ? "Online" : "Offline"}');
      _broadcastStatus();

      // Trigger sync if we just came online
      if (_isOnline && !wasOnline) {
        syncPendingRecords();
      }
    } catch (e) {
      _logger.e('❌ Error checking connectivity: $e');
      _isOnline = false;
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _logger.i('📶 Connectivity changed: $results');
    _checkConnectivity();
  }

  /// Check if backend is actually available
  Future<bool> _checkBackendAvailability() async {
    try {
      _logger.i('🏥 Testing backend availability: ${ApiConfig.healthUrl()}');

      final response = await Dio().get(
        ApiConfig.healthUrl(),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      final isAvailable = response.statusCode == 200;
      _logger.i(
        '🏥 Backend ${isAvailable ? "available" : "unavailable"} (${response.statusCode})',
      );

      return isAvailable;
    } catch (e) {
      _logger.w('⚠️ Backend unavailable: $e');
      return false;
    }
  }

  /// Save emotional record with automatic online/offline handling
  Future<EmotionalRecord> saveEmotionalRecord(EmotionalRecord record) async {
    _logger.i(
      '💾 Saving emotional record: ${record.emotion} (${record.intensity})',
    );

    try {
      // Always save locally first
      await _localDb.saveEmotionalRecordLocal(record);
      _logger.i('✅ Record saved locally');

      // Try to sync immediately if online
      if (_isOnline) {
        try {
          final syncedRecord = await _syncSingleRecord(record);
          _logger.i('🌐 Record synced immediately');
          return syncedRecord;
        } catch (e) {
          _logger.w('⚠️ Immediate sync failed, will retry later: $e');
          if (record.id != null) {
            await _localDb.updateSyncAttempt(record.id!, e.toString());
          }
        }
      } else {
        _logger.i('📴 Offline - record queued for sync');
      }

      await _updatePendingCount();
      _broadcastStatus();

      return record;
    } catch (e) {
      _logger.e('❌ Failed to save emotional record: $e');
      rethrow;
    }
  }

  /// Sync a single record to backend
  Future<EmotionalRecord> _syncSingleRecord(EmotionalRecord record) async {
    try {
      _logger.i('🔄 Syncing record to backend: ${record.id}');

      final dio = Dio();
      final response = await dio.post(
        ApiConfig.emotionalRecordsUrl(),
        data: record.toJson(),
        options: Options(headers: await _apiService.getHeaders()),
      );

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;
        if (record.id != null) {
          await _localDb.markEmotionalRecordSynced(record.id!);
        }

        _logger.i('✅ Record synced successfully: ${record.id}');
        return EmotionalRecord.fromJson(responseData);
      } else {
        throw Exception(
          'Backend returned ${response.statusCode}: ${response.data}',
        );
      }
    } on DioException catch (e) {
      _logger.e('❌ Failed to sync record: ${e.response?.data ?? e.message}');
      rethrow;
    } catch (e) {
      _logger.e('❌ Failed to sync record: $e');
      rethrow;
    }
  }

  /// Sync all pending records
  Future<void> syncPendingRecords() async {
    if (_isSyncing || !_isOnline) {
      _logger.d('⏭️ Sync skipped - already syncing or offline');
      return;
    }

    _isSyncing = true;
    _broadcastStatus();

    try {
      _logger.i('🔄 Starting sync of pending records...');

      final pendingRecords = await _localDb.getUnsyncedEmotionalRecords();
      _logger.i('📋 Found ${pendingRecords.length} pending records to sync');

      int successCount = 0;
      int failCount = 0;

      for (final record in pendingRecords) {
        try {
          await _syncSingleRecord(record);
          successCount++;
        } catch (e) {
          failCount++;
          if (record.id != null) {
            await _localDb.updateSyncAttempt(record.id!, e.toString());
          }

          // Stop syncing if backend is unavailable
          if (e.toString().contains('Connection') ||
              e.toString().contains('timeout') ||
              e.toString().contains('SocketException')) {
            _logger.w('⚠️ Backend unavailable, stopping sync');
            _isOnline = false;
            break;
          }
        }
      }

      _lastSyncTime = DateTime.now();
      await _updatePendingCount();

      _logger.i('✅ Sync completed: $successCount success, $failCount failed');
    } catch (e) {
      _logger.e('❌ Sync process failed: $e');
    } finally {
      _isSyncing = false;
      _broadcastStatus();
    }
  }

  /// Update pending records count
  Future<void> _updatePendingCount() async {
    final stats = await _localDb.getSyncStats();
    _pendingRecordsCount = stats['unsynced'] ?? 0;
  }

  /// Broadcast current sync status
  void _broadcastStatus() {
    _syncStatusController.add(currentStatus);
  }

  /// Get all emotional records (local + synced)
  Future<List<EmotionalRecord>> getAllEmotionalRecords() async {
    return await _localDb.getAllEmotionalRecords();
  }

  /// Get sync statistics
  Future<Map<String, int>> getSyncStats() async {
    return await _localDb.getSyncStats();
  }

  /// Force immediate sync
  Future<void> forcSync() async {
    _logger.i('🔄 Force sync requested');
    await _checkConnectivity();
    if (_isOnline) {
      await syncPendingRecords();
    } else {
      throw Exception('Cannot sync while offline');
    }
  }

  /// Cleanup old records
  Future<void> cleanup() async {
    await _localDb.cleanupOldRecords();
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
    _localDb.close();
    _logger.i('🔒 SyncService disposed');
  }
}

/// Sync status data class
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final int pendingRecords;

  SyncStatus({
    required this.isOnline,
    required this.isSyncing,
    this.lastSyncTime,
    required this.pendingRecords,
  });

  @override
  String toString() {
    return 'SyncStatus(online: $isOnline, syncing: $isSyncing, pending: $pendingRecords)';
  }
}
