/// Unified Sync Manager for Offline-First Architecture
///
/// This service coordinates all data synchronization between local SQLite
/// and remote API, providing conflict resolution, background sync queuing,
/// and intelligent data merging.
library;

import 'dart:async';
import 'dart:isolate';
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import '../../config/api_config.dart';
import '../../data/api_service.dart';
import '../../shared/services/sqlite_helper.dart';
import '../../data/models/emotional_record.dart';
import '../../data/models/breathing_session.dart';
import '../../data/models/breathing_pattern.dart';
import '../../data/models/custom_emotion.dart';
import 'sync_queue.dart';
import 'conflict_resolver.dart';

final logger = Logger();

enum SyncStatus {
  idle,
  syncing,
  syncingBackground,
  conflictDetected,
  failed,
  offline,
}

enum ConnectivityStatus { unknown, online, offline, limited }

class SyncState {
  final SyncStatus status;
  final ConnectivityStatus connectivity;
  final DateTime lastSyncTime;
  final int pendingItems;
  final String? currentOperation;
  final String? errorMessage;
  final List<SyncConflict> conflicts;

  const SyncState({
    required this.status,
    required this.connectivity,
    required this.lastSyncTime,
    required this.pendingItems,
    this.currentOperation,
    this.errorMessage,
    this.conflicts = const [],
  });

  SyncState copyWith({
    SyncStatus? status,
    ConnectivityStatus? connectivity,
    DateTime? lastSyncTime,
    int? pendingItems,
    String? currentOperation,
    String? errorMessage,
    List<SyncConflict>? conflicts,
  }) {
    return SyncState(
      status: status ?? this.status,
      connectivity: connectivity ?? this.connectivity,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingItems: pendingItems ?? this.pendingItems,
      currentOperation: currentOperation ?? this.currentOperation,
      errorMessage: errorMessage ?? this.errorMessage,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  bool get isOnline => connectivity == ConnectivityStatus.online;
  bool get hasConflicts => conflicts.isNotEmpty;
  bool get canSync => isOnline && status != SyncStatus.syncing;
}

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  // Dependencies
  late final SQLiteHelper _sqliteHelper;
  late final ApiService _apiService;
  late final SyncQueue _syncQueue;
  late final ConflictResolver _conflictResolver;

  // State management
  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get stateStream => _stateController.stream;

  SyncState _currentState = SyncState(
    status: SyncStatus.idle,
    connectivity: ConnectivityStatus.unknown,
    lastSyncTime: DateTime.now().subtract(const Duration(days: 1)),
    pendingItems: 0,
  );

  SyncState get currentState => _currentState;

  // Timers and isolates
  Timer? _connectivityTimer;
  Timer? _backgroundSyncTimer;
  Isolate? _syncIsolate;

  // Configuration
  static const Duration _connectivityCheckInterval = Duration(seconds: 15);
  static const Duration _backgroundSyncInterval = Duration(minutes: 5);

  /// Initialize the sync manager
  Future<void> initialize() async {
    logger.i('🔄 Initializing SyncManager');

    try {
      // Initialize dependencies
      _sqliteHelper = SQLiteHelper();
      _apiService = ApiService();
      _syncQueue = SyncQueue();
      _conflictResolver = ConflictResolver(_sqliteHelper, _apiService);

      // Initialize sync queue
      await _syncQueue.initialize();

      // Start connectivity monitoring
      _startConnectivityMonitoring();

      // Start background sync
      _startBackgroundSync();

      // Load initial state
      await _updatePendingItemsCount();
      await _checkConnectivity();

      logger.i('✅ SyncManager initialized successfully');
    } catch (e) {
      logger.e('❌ Failed to initialize SyncManager: $e');
      rethrow;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    logger.i('🔄 Disposing SyncManager');

    _connectivityTimer?.cancel();
    _backgroundSyncTimer?.cancel();
    _syncIsolate?.kill();

    await _stateController.close();
    await _syncQueue.dispose();
  }

  /// Force a complete sync of all data
  Future<bool> forceSync({bool showConflicts = true}) async {
    if (_currentState.status == SyncStatus.syncing) {
      logger.w('⚠️ Sync already in progress, skipping');
      return false;
    }

    if (!_currentState.isOnline) {
      logger.w('⚠️ Cannot sync while offline');
      _updateState(
        _currentState.copyWith(
          status: SyncStatus.offline,
          errorMessage: 'No internet connection available',
        ),
      );
      return false;
    }

    _updateState(
      _currentState.copyWith(
        status: SyncStatus.syncing,
        currentOperation: 'Starting full sync...',
        errorMessage: null,
      ),
    );

    try {
      logger.i('🔄 Starting force sync');

      // Step 1: Upload pending local changes
      await _uploadPendingChanges();

      // Step 2: Download remote changes
      await _downloadRemoteChanges();

      // Step 3: Resolve any conflicts
      if (showConflicts && _currentState.hasConflicts) {
        _updateState(
          _currentState.copyWith(
            status: SyncStatus.conflictDetected,
            currentOperation: 'Conflicts detected, user action required',
          ),
        );
        return false;
      }

      // Step 4: Update sync state
      await _updatePendingItemsCount();

      _updateState(
        _currentState.copyWith(
          status: SyncStatus.idle,
          lastSyncTime: DateTime.now(),
          currentOperation: null,
          pendingItems: 0,
        ),
      );

      logger.i('✅ Force sync completed successfully');
      return true;
    } catch (e) {
      logger.e('❌ Force sync failed: $e');

      _updateState(
        _currentState.copyWith(
          status: SyncStatus.failed,
          errorMessage: e.toString(),
          currentOperation: null,
        ),
      );

      return false;
    }
  }

  /// Queue an item for background sync
  Future<void> queueForSync<T>(
    String itemType,
    String itemId,
    T item,
    SyncOperation operation,
  ) async {
    try {
      await _syncQueue.enqueue(
        SyncItem(
          type: itemType,
          id: itemId,
          operation: operation,
          data: item,
          timestamp: DateTime.now(),
        ),
      );

      await _updatePendingItemsCount();

      // Trigger immediate sync if online and not busy
      if (_currentState.canSync && _currentState.pendingItems < 10) {
        unawaited(_processQueuedItems());
      }
    } catch (e) {
      logger.e('❌ Failed to queue item for sync: $e');
    }
  }

  /// Process queued sync items in background
  Future<void> _processQueuedItems() async {
    if (!_currentState.canSync) return;

    _updateState(
      _currentState.copyWith(
        status: SyncStatus.syncingBackground,
        currentOperation: 'Processing queued items...',
      ),
    );

    try {
      final items = await _syncQueue.dequeueUpTo(20); // Process in batches

      for (final item in items) {
        await _processSyncItem(item);
      }

      await _updatePendingItemsCount();

      _updateState(
        _currentState.copyWith(status: SyncStatus.idle, currentOperation: null),
      );
    } catch (e) {
      logger.e('❌ Failed to process queued items: $e');

      _updateState(
        _currentState.copyWith(
          status: SyncStatus.failed,
          errorMessage: e.toString(),
          currentOperation: null,
        ),
      );
    }
  }

  /// Process a single sync item
  Future<void> _processSyncItem(SyncItem item) async {
    try {
      switch (item.operation) {
        case SyncOperation.create:
          await _handleCreate(item);
          break;
        case SyncOperation.update:
          await _handleUpdate(item);
          break;
        case SyncOperation.delete:
          await _handleDelete(item);
          break;
      }

      // Mark as processed
      await _syncQueue.markProcessed(item.id);
    } catch (e) {
      logger.e('❌ Failed to process sync item ${item.id}: $e');

      // Increment retry count
      await _syncQueue.incrementRetryCount(item.id);

      // If max retries exceeded, move to dead letter queue
      if (item.retryCount >= 3) {
        await _syncQueue.moveToDeadLetter(item.id, e.toString());
      }
    }
  }

  /// Handle create operation
  Future<void> _handleCreate(SyncItem item) async {
    switch (item.type) {
      case 'emotional_record':
        final record = item.data as EmotionalRecord;
        await _apiService.createEmotionalRecord(record);
        await _sqliteHelper.markEmotionalRecordAsSynced(int.parse(record.id!));
        break;

      case 'breathing_session':
        final session = item.data as BreathingSessionData;
        await _apiService.createBreathingSession(session);
        await _sqliteHelper.markBreathingSessionAsSynced(
          int.parse(session.id!),
        );
        break;

      case 'breathing_pattern':
        final pattern = item.data as BreathingPattern;
        await _apiService.createBreathingPattern(pattern);
        await _sqliteHelper.markBreathingPatternAsSynced(
          int.parse(pattern.id!),
        );
        break;

      case 'custom_emotion':
        final emotion = item.data as CustomEmotion;
        await _apiService.createCustomEmotion(emotion);
        // Mark as synced in SQLite
        break;

      default:
        throw Exception('Unknown item type: ${item.type}');
    }
  }

  /// Handle update operation
  Future<void> _handleUpdate(SyncItem item) async {
    // Implementation depends on API supporting updates
    // For now, treat as create
    await _handleCreate(item);
  }

  /// Handle delete operation
  Future<void> _handleDelete(SyncItem item) async {
    // Implementation depends on API supporting deletes
    logger.w('Delete operations not yet implemented for ${item.type}');
  }

  /// Upload pending local changes to remote
  Future<void> _uploadPendingChanges() async {
    _updateState(
      _currentState.copyWith(currentOperation: 'Uploading local changes...'),
    );

    // Get unsynced items from local database
    final emotionalRecords = await _sqliteHelper.getUnsyncedEmotionalRecords();
    final breathingSessions =
        await _sqliteHelper.getUnsyncedBreathingSessions();
    final breathingPatterns =
        await _sqliteHelper.getUnsyncedBreathingPatterns();

    // Upload emotional records
    for (final record in emotionalRecords) {
      try {
        await _apiService.createEmotionalRecord(record);
        if (record.id != null) {
          await _sqliteHelper.markEmotionalRecordAsSynced(
            int.parse(record.id!),
          );
        }
      } catch (e) {
        logger.e('Failed to sync emotional record: $e');
        // Continue with other records
      }
    }

    // Upload breathing sessions
    for (final session in breathingSessions) {
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

    // Upload breathing patterns
    for (final patternMap in breathingPatterns) {
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
  }

  /// Download remote changes and merge with local data
  Future<void> _downloadRemoteChanges() async {
    _updateState(
      _currentState.copyWith(currentOperation: 'Downloading remote changes...'),
    );

    try {
      // Download all data types
      final remoteEmotionalRecords = await _apiService.getEmotionalRecords();
      final remoteBreathingSessions = await _apiService.getBreathingSessions();
      final remoteBreathingPatterns = await _apiService.getBreathingPatterns();
      final remoteCustomEmotions = await _apiService.getCustomEmotions();

      // Merge with local data and detect conflicts
      await _mergeEmotionalRecords(remoteEmotionalRecords);
      await _mergeBreathingSessions(remoteBreathingSessions);
      await _mergeBreathingPatterns(remoteBreathingPatterns);
      await _mergeCustomEmotions(remoteCustomEmotions);
    } catch (e) {
      logger.e('Failed to download remote changes: $e');
      rethrow;
    }
  }

  /// Merge emotional records with conflict detection
  Future<void> _mergeEmotionalRecords(
    List<EmotionalRecord> remoteRecords,
  ) async {
    final localRecords = await _sqliteHelper.getAllEmotionalRecords();
    final conflicts = await _conflictResolver.resolveEmotionalRecords(
      localRecords,
      remoteRecords,
    );

    if (conflicts.isNotEmpty) {
      _addConflicts(conflicts);
    }
  }

  /// Merge breathing sessions with conflict detection
  Future<void> _mergeBreathingSessions(
    List<BreathingSessionData> remoteSessions,
  ) async {
    final localSessions = await _sqliteHelper.getAllBreathingSessions();
    final conflicts = await _conflictResolver.resolveBreathingSessions(
      localSessions,
      remoteSessions,
    );

    if (conflicts.isNotEmpty) {
      _addConflicts(conflicts);
    }
  }

  /// Merge breathing patterns with conflict detection
  Future<void> _mergeBreathingPatterns(
    List<BreathingPattern> remotePatterns,
  ) async {
    final localPatterns = await _sqliteHelper.getAllBreathingPatterns();
    final conflicts = await _conflictResolver.resolveBreathingPatterns(
      localPatterns,
      remotePatterns,
    );

    if (conflicts.isNotEmpty) {
      _addConflicts(conflicts);
    }
  }

  /// Merge custom emotions with conflict detection
  Future<void> _mergeCustomEmotions(List<CustomEmotion> remoteEmotions) async {
    final localEmotions = await _sqliteHelper.getAllCustomEmotions();
    final conflicts = await _conflictResolver.resolveCustomEmotions(
      localEmotions,
      remoteEmotions,
    );

    if (conflicts.isNotEmpty) {
      _addConflicts(conflicts);
    }
  }

  /// Resolve a conflict with user choice
  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
  ) async {
    try {
      await _conflictResolver.resolveConflict(conflictId, resolution);

      // Remove conflict from current state
      final updatedConflicts =
          _currentState.conflicts.where((c) => c.id != conflictId).toList();

      _updateState(
        _currentState.copyWith(
          conflicts: updatedConflicts,
          status:
              updatedConflicts.isEmpty
                  ? SyncStatus.idle
                  : SyncStatus.conflictDetected,
        ),
      );
    } catch (e) {
      logger.e('Failed to resolve conflict $conflictId: $e');
      rethrow;
    }
  }

  /// Start connectivity monitoring
  void _startConnectivityMonitoring() {
    _connectivityTimer = Timer.periodic(_connectivityCheckInterval, (_) {
      _checkConnectivity();
    });

    // Initial check
    _checkConnectivity();
  }

  /// Start background sync
  void _startBackgroundSync() {
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) {
      if (_currentState.canSync && _currentState.pendingItems > 0) {
        unawaited(_processQueuedItems());
      }
    });
  }

  /// Check connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final response = await Dio().get(ApiConfig.healthUrl());
      final isOnline = response.statusCode == 200;
      final newStatus =
          isOnline ? ConnectivityStatus.online : ConnectivityStatus.limited;

      if (newStatus != _currentState.connectivity) {
        _updateState(_currentState.copyWith(connectivity: newStatus));

        // Trigger sync if we just came online
        if (isOnline && _currentState.pendingItems > 0) {
          unawaited(_processQueuedItems());
        }
      }
    } catch (e) {
      if (_currentState.connectivity != ConnectivityStatus.offline) {
        _updateState(
          _currentState.copyWith(connectivity: ConnectivityStatus.offline),
        );
      }
    }
  }

  /// Update pending items count
  Future<void> _updatePendingItemsCount() async {
    try {
      final count = await _syncQueue.getPendingItemsCount();

      if (count != _currentState.pendingItems) {
        _updateState(_currentState.copyWith(pendingItems: count));
      }
    } catch (e) {
      logger.e('Failed to update pending items count: $e');
    }
  }

  /// Add conflicts to current state
  void _addConflicts(List<SyncConflict> newConflicts) {
    final allConflicts = [..._currentState.conflicts, ...newConflicts];

    _updateState(
      _currentState.copyWith(
        conflicts: allConflicts,
        status: SyncStatus.conflictDetected,
      ),
    );
  }

  /// Update current state and notify listeners
  void _updateState(SyncState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }
}

/// Extension to add unawaited helper
extension Unawaited<T> on Future<T> {
  void get unawaited {}
}
