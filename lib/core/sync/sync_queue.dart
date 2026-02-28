/// Background Sync Queue for Managing Offline Operations
///
/// This service manages a queue of sync operations that need to be
/// processed when the device comes back online, with intelligent
/// batching, retry logic, and dead letter queue for failed items.
library;

import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import '../../shared/services/sqlite_helper.dart';

final logger = Logger();

enum SyncOperation { create, update, delete }

class SyncItem {
  final String id;
  final String type;
  final SyncOperation operation;
  final dynamic data;
  final DateTime timestamp;
  final int retryCount;
  final String? errorMessage;

  SyncItem({
    String? id,
    required this.type,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.errorMessage,
  }) : id = id ?? _generateId();

  static String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
  }

  static int _counter = 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'operation': operation.name,
      'data': jsonEncode(_serializeData(data)),
      'timestamp': timestamp.toIso8601String(),
      'retry_count': retryCount,
      'error_message': errorMessage,
    };
  }

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'],
      type: map['type'],
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == map['operation'],
      ),
      data: _deserializeData(map['type'], jsonDecode(map['data'])),
      timestamp: DateTime.parse(map['timestamp']),
      retryCount: map['retry_count'] ?? 0,
      errorMessage: map['error_message'],
    );
  }

  SyncItem copyWith({
    String? id,
    String? type,
    SyncOperation? operation,
    dynamic data,
    DateTime? timestamp,
    int? retryCount,
    String? errorMessage,
  }) {
    return SyncItem(
      id: id ?? this.id,
      type: type ?? this.type,
      operation: operation ?? this.operation,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  static Map<String, dynamic> _serializeData(dynamic data) {
    if (data == null) return {};

    if (data is Map<String, dynamic>) {
      return data;
    }

    // Use explicit type checks instead of unreliable dynamic member access
    try {
      return (data as dynamic).toJson() as Map<String, dynamic>;
    } catch (_) {
      try {
        return (data as dynamic).toMap() as Map<String, dynamic>;
      } catch (_) {
        throw Exception(
          'Unsupported data type for serialization: ${data.runtimeType}',
        );
      }
    }
  }

  static dynamic _deserializeData(String type, Map<String, dynamic> data) {
    // This would need to be expanded based on actual data models
    // For now, return the raw data
    return data;
  }
}

class SyncQueue {
  static final SyncQueue _instance = SyncQueue._internal();
  factory SyncQueue() => _instance;
  SyncQueue._internal();

  late SQLiteHelper _sqliteHelper;
  bool _isInitialized = false;

  /// Initialize the sync queue
  Future<void> initialize() async {
    if (_isInitialized) return;

    logger.i('🔄 Initializing SyncQueue');

    try {
      _sqliteHelper = SQLiteHelper();
      await _createTables();
      await _cleanupOldItems();

      _isInitialized = true;
      logger.i('✅ SyncQueue initialized successfully');
    } catch (e) {
      logger.e('❌ Failed to initialize SyncQueue: $e');
      rethrow;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _isInitialized = false;
  }

  /// Add an item to the sync queue
  Future<void> enqueue(SyncItem item) async {
    if (!_isInitialized) {
      throw Exception('SyncQueue not initialized');
    }

    try {
      final db = await _sqliteHelper.database;

      // Check if item already exists (deduplication)
      final existing = await db.query(
        'sync_queue',
        where: 'type = ? AND operation = ? AND data = ?',
        whereArgs: [
          item.type,
          item.operation.name,
          jsonEncode(SyncItem._serializeData(item.data)),
        ],
      );

      if (existing.isNotEmpty) {
        logger.i('🔄 Sync item already queued, skipping: ${item.type}');
        return;
      }

      await db.insert('sync_queue', item.toMap());
      logger.i('✅ Queued sync item: ${item.type} (${item.operation.name})');
    } catch (e) {
      logger.e('❌ Failed to enqueue sync item: $e');
      rethrow;
    }
  }

  /// Get the next batch of items to process
  Future<List<SyncItem>> dequeueUpTo(int maxItems) async {
    if (!_isInitialized) {
      throw Exception('SyncQueue not initialized');
    }

    try {
      final db = await _sqliteHelper.database;

      final maps = await db.query(
        'sync_queue',
        where: 'retry_count < ?',
        whereArgs: [3], // Max 3 retries
        orderBy: 'timestamp ASC',
        limit: maxItems,
      );

      final items = maps.map((map) => SyncItem.fromMap(map)).toList();

      logger.i('📤 Dequeued ${items.length} sync items');
      return items;
    } catch (e) {
      logger.e('❌ Failed to dequeue sync items: $e');
      return [];
    }
  }

  /// Mark an item as successfully processed
  Future<void> markProcessed(String itemId) async {
    if (!_isInitialized) return;

    try {
      final db = await _sqliteHelper.database;

      await db.delete('sync_queue', where: 'id = ?', whereArgs: [itemId]);

      logger.i('✅ Marked sync item as processed: $itemId');
    } catch (e) {
      logger.e('❌ Failed to mark item as processed: $e');
    }
  }

  /// Increment retry count for a failed item
  Future<void> incrementRetryCount(String itemId) async {
    if (!_isInitialized) return;

    try {
      final db = await _sqliteHelper.database;

      await db.rawUpdate(
        'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
        [itemId],
      );

      logger.i('🔄 Incremented retry count for item: $itemId');
    } catch (e) {
      logger.e('❌ Failed to increment retry count: $e');
    }
  }

  /// Move an item to dead letter queue after max retries
  Future<void> moveToDeadLetter(String itemId, String errorMessage) async {
    if (!_isInitialized) return;

    try {
      final db = await _sqliteHelper.database;

      // Get the item
      final maps = await db.query(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [itemId],
      );

      if (maps.isEmpty) return;

      final item = SyncItem.fromMap(maps.first);

      // Insert into dead letter queue
      await db.insert('sync_dead_letter', {
        ...item.toMap(),
        'error_message': errorMessage,
        'moved_at': DateTime.now().toIso8601String(),
      });

      // Remove from main queue
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [itemId]);

      logger.w('💀 Moved item to dead letter queue: $itemId');
    } catch (e) {
      logger.e('❌ Failed to move item to dead letter queue: $e');
    }
  }

  /// Get count of pending items
  Future<int> getPendingItemsCount() async {
    if (!_isInitialized) return 0;

    try {
      final db = await _sqliteHelper.database;

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE retry_count < 3',
      );

      return result.first['count'] as int? ?? 0;
    } catch (e) {
      logger.e('❌ Failed to get pending items count: $e');
      return 0;
    }
  }

  /// Get items by type
  Future<List<SyncItem>> getItemsByType(String type) async {
    if (!_isInitialized) return [];

    try {
      final db = await _sqliteHelper.database;

      final maps = await db.query(
        'sync_queue',
        where: 'type = ? AND retry_count < ?',
        whereArgs: [type, 3],
        orderBy: 'timestamp ASC',
      );

      return maps.map((map) => SyncItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('❌ Failed to get items by type: $e');
      return [];
    }
  }

  /// Get failed items from dead letter queue
  Future<List<SyncItem>> getFailedItems() async {
    if (!_isInitialized) return [];

    try {
      final db = await _sqliteHelper.database;

      final maps = await db.query(
        'sync_dead_letter',
        orderBy: 'moved_at DESC',
        limit: 50, // Limit to recent failures
      );

      return maps.map((map) => SyncItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('❌ Failed to get failed items: $e');
      return [];
    }
  }

  /// Retry a failed item from dead letter queue
  Future<void> retryFailedItem(String itemId) async {
    if (!_isInitialized) return;

    try {
      final db = await _sqliteHelper.database;

      // Get the item from dead letter queue
      final maps = await db.query(
        'sync_dead_letter',
        where: 'id = ?',
        whereArgs: [itemId],
      );

      if (maps.isEmpty) {
        logger.w('⚠️ Failed item not found: $itemId');
        return;
      }

      final item = SyncItem.fromMap(maps.first);

      // Reset retry count and re-queue
      final retriedItem = item.copyWith(
        retryCount: 0,
        errorMessage: null,
        timestamp: DateTime.now(),
      );

      await db.insert('sync_queue', retriedItem.toMap());

      // Remove from dead letter queue
      await db.delete('sync_dead_letter', where: 'id = ?', whereArgs: [itemId]);

      logger.i('🔄 Retried failed item: $itemId');
    } catch (e) {
      logger.e('❌ Failed to retry failed item: $e');
    }
  }

  /// Clear all items from queue (for testing/reset)
  Future<void> clearQueue() async {
    if (!_isInitialized) return;

    try {
      final db = await _sqliteHelper.database;

      await db.delete('sync_queue');
      await db.delete('sync_dead_letter');

      logger.i('🗑️ Cleared sync queue');
    } catch (e) {
      logger.e('❌ Failed to clear sync queue: $e');
    }
  }

  /// Get queue statistics
  Future<Map<String, int>> getQueueStats() async {
    if (!_isInitialized) return {};

    try {
      final db = await _sqliteHelper.database;

      final pendingResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE retry_count < 3',
      );

      final retryingResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE retry_count > 0 AND retry_count < 3',
      );

      final failedResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_dead_letter',
      );

      return {
        'pending': pendingResult.first['count'] as int? ?? 0,
        'retrying': retryingResult.first['count'] as int? ?? 0,
        'failed': failedResult.first['count'] as int? ?? 0,
      };
    } catch (e) {
      logger.e('❌ Failed to get queue stats: $e');
      return {};
    }
  }

  /// Create necessary database tables
  Future<void> _createTables() async {
    final db = await _sqliteHelper.database;

    // Main sync queue table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        error_message TEXT
      )
    ''');

    // Dead letter queue for failed items
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_dead_letter (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        error_message TEXT,
        moved_at TEXT NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_timestamp 
      ON sync_queue(timestamp)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_type 
      ON sync_queue(type)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_retry 
      ON sync_queue(retry_count)
    ''');
  }

  /// Clean up old processed items and expired failures
  Future<void> _cleanupOldItems() async {
    try {
      final db = await _sqliteHelper.database;

      // Remove old items from dead letter queue (older than 30 days)
      final cutoffDate =
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

      final deletedCount = await db.delete(
        'sync_dead_letter',
        where: 'moved_at < ?',
        whereArgs: [cutoffDate],
      );

      if (deletedCount > 0) {
        logger.i('🗑️ Cleaned up $deletedCount old failed sync items');
      }
    } catch (e) {
      logger.e('❌ Failed to cleanup old items: $e');
    }
  }
}
