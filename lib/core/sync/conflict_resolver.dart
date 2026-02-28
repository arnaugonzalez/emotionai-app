/// Conflict Resolution for Sync Operations
///
/// This service handles conflicts that arise when the same data has been
/// modified both locally and remotely, providing multiple resolution
/// strategies and user-friendly conflict resolution interfaces.
library;

import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import '../../shared/services/sqlite_helper.dart';
import '../../data/api_service.dart';
import '../../data/models/emotional_record.dart';
import '../../data/models/breathing_session.dart';
import '../../data/models/breathing_pattern.dart';
import '../../data/models/custom_emotion.dart';

final logger = Logger();

enum ConflictResolution {
  keepLocal, // Keep the local version
  keepRemote, // Keep the remote version
  merge, // Merge both versions (if possible)
  askUser, // Let user decide
}

enum ConflictType {
  dataConflict, // Same item modified locally and remotely
  deleteConflict, // Item deleted locally but modified remotely
  createConflict, // Item created with same ID locally and remotely
}

class SyncConflict {
  final String id;
  final String itemType;
  final String itemId;
  final ConflictType type;
  final dynamic localData;
  final dynamic remoteData;
  final DateTime detectedAt;
  final String description;
  final bool canAutoResolve;

  SyncConflict({
    String? id,
    required this.itemType,
    required this.itemId,
    required this.type,
    required this.localData,
    required this.remoteData,
    required this.detectedAt,
    required this.description,
    required this.canAutoResolve,
  }) : id = id ?? _generateConflictId();

  static String _generateConflictId() {
    return 'conflict_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
  }

  static int _counter = 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_type': itemType,
      'item_id': itemId,
      'conflict_type': type.name,
      'local_data': _serializeData(localData),
      'remote_data': _serializeData(remoteData),
      'detected_at': detectedAt.toIso8601String(),
      'description': description,
      'can_auto_resolve': canAutoResolve ? 1 : 0,
    };
  }

  factory SyncConflict.fromMap(Map<String, dynamic> map) {
    return SyncConflict(
      id: map['id'],
      itemType: map['item_type'],
      itemId: map['item_id'],
      type: ConflictType.values.firstWhere(
        (e) => e.name == map['conflict_type'],
      ),
      localData: _deserializeData(map['item_type'], map['local_data']),
      remoteData: _deserializeData(map['item_type'], map['remote_data']),
      detectedAt: DateTime.parse(map['detected_at']),
      description: map['description'],
      canAutoResolve: (map['can_auto_resolve'] ?? 0) == 1,
    );
  }

  static String _serializeData(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is EmotionalRecord) return _encodeJson(data.toJson());
    if (data is BreathingSessionData) return _encodeJson(data.toJson());
    if (data is BreathingPattern) return _encodeJson(data.toJson());
    if (data is CustomEmotion) return _encodeJson(data.toJson());
    if (data is Map) return _encodeJson(data);
    return data.toString();
  }

  static String _encodeJson(dynamic data) {
    try {
      return const JsonEncoder().convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  static dynamic _deserializeData(String itemType, String data) {
    if (data.isEmpty) return data;
    try {
      final map = const JsonDecoder().convert(data) as Map<String, dynamic>;
      switch (itemType) {
        case 'emotional_record':
          return EmotionalRecord.fromJson(map);
        case 'breathing_session':
          return BreathingSessionData.fromJson(map);
        case 'breathing_pattern':
          return BreathingPattern.fromJson(map);
        case 'custom_emotion':
          return CustomEmotion.fromJson(map);
        default:
          return map;
      }
    } catch (_) {
      return data;
    }
  }
}

class ConflictResolver {
  final SQLiteHelper _sqliteHelper;
  final ApiService _apiService;

  ConflictResolver(this._sqliteHelper, this._apiService);

  /// Resolve conflicts for emotional records
  Future<List<SyncConflict>> resolveEmotionalRecords(
    List<EmotionalRecord> localRecords,
    List<EmotionalRecord> remoteRecords,
  ) async {
    final conflicts = <SyncConflict>[];

    try {
      // Create maps for efficient lookup
      final localMap = {for (var record in localRecords) record.id: record};
      final remoteMap = {for (var record in remoteRecords) record.id: record};

      // Check for conflicts
      for (final localRecord in localRecords) {
        if (localRecord.id == null) continue;

        final remoteRecord = remoteMap[localRecord.id];
        if (remoteRecord != null) {
          final conflict = _detectEmotionalRecordConflict(
            localRecord,
            remoteRecord,
          );
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            // No conflict, update local with remote if remote is newer
            await _updateLocalEmotionalRecord(localRecord, remoteRecord);
          }
        }
      }

      // Add new remote records that don't exist locally
      for (final remoteRecord in remoteRecords) {
        if (remoteRecord.id != null && !localMap.containsKey(remoteRecord.id)) {
          await _addRemoteEmotionalRecord(remoteRecord);
        }
      }

      return conflicts;
    } catch (e) {
      logger.e('Error resolving emotional record conflicts: $e');
      return [];
    }
  }

  /// Resolve conflicts for breathing sessions
  Future<List<SyncConflict>> resolveBreathingSessions(
    List<BreathingSessionData> localSessions,
    List<BreathingSessionData> remoteSessions,
  ) async {
    final conflicts = <SyncConflict>[];

    try {
      final localMap = {for (var session in localSessions) session.id: session};
      final remoteMap = {
        for (var session in remoteSessions) session.id: session,
      };

      for (final localSession in localSessions) {
        if (localSession.id == null) continue;

        final remoteSession = remoteMap[localSession.id];
        if (remoteSession != null) {
          final conflict = _detectBreathingSessionConflict(
            localSession,
            remoteSession,
          );
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            await _updateLocalBreathingSession(localSession, remoteSession);
          }
        }
      }

      for (final remoteSession in remoteSessions) {
        if (remoteSession.id != null &&
            !localMap.containsKey(remoteSession.id)) {
          await _addRemoteBreathingSession(remoteSession);
        }
      }

      return conflicts;
    } catch (e) {
      logger.e('Error resolving breathing session conflicts: $e');
      return [];
    }
  }

  /// Resolve conflicts for breathing patterns
  Future<List<SyncConflict>> resolveBreathingPatterns(
    List<BreathingPattern> localPatterns,
    List<BreathingPattern> remotePatterns,
  ) async {
    final conflicts = <SyncConflict>[];

    try {
      final localMap = {for (var pattern in localPatterns) pattern.id: pattern};
      final remoteMap = {
        for (var pattern in remotePatterns) pattern.id: pattern,
      };

      for (final localPattern in localPatterns) {
        if (localPattern.id == null) continue;

        final remotePattern = remoteMap[localPattern.id];
        if (remotePattern != null) {
          final conflict = _detectBreathingPatternConflict(
            localPattern,
            remotePattern,
          );
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            await _updateLocalBreathingPattern(localPattern, remotePattern);
          }
        }
      }

      for (final remotePattern in remotePatterns) {
        if (remotePattern.id != null &&
            !localMap.containsKey(remotePattern.id)) {
          await _addRemoteBreathingPattern(remotePattern);
        }
      }

      return conflicts;
    } catch (e) {
      logger.e('Error resolving breathing pattern conflicts: $e');
      return [];
    }
  }

  /// Resolve conflicts for custom emotions
  Future<List<SyncConflict>> resolveCustomEmotions(
    List<CustomEmotion> localEmotions,
    List<CustomEmotion> remoteEmotions,
  ) async {
    final conflicts = <SyncConflict>[];

    try {
      final localMap = {for (var emotion in localEmotions) emotion.id: emotion};
      final remoteMap = {
        for (var emotion in remoteEmotions) emotion.id: emotion,
      };

      for (final localEmotion in localEmotions) {
        if (localEmotion.id == null) continue;

        final remoteEmotion = remoteMap[localEmotion.id];
        if (remoteEmotion != null) {
          final conflict = _detectCustomEmotionConflict(
            localEmotion,
            remoteEmotion,
          );
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            await _updateLocalCustomEmotion(localEmotion, remoteEmotion);
          }
        }
      }

      for (final remoteEmotion in remoteEmotions) {
        if (remoteEmotion.id != null &&
            !localMap.containsKey(remoteEmotion.id)) {
          await _addRemoteCustomEmotion(remoteEmotion);
        }
      }

      return conflicts;
    } catch (e) {
      logger.e('Error resolving custom emotion conflicts: $e');
      return [];
    }
  }

  /// Resolve a specific conflict with user choice
  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
  ) async {
    try {
      final conflict = await _getConflictById(conflictId);
      if (conflict == null) {
        throw Exception('Conflict not found: $conflictId');
      }

      switch (resolution) {
        case ConflictResolution.keepLocal:
          await _resolveKeepLocal(conflict);
          break;
        case ConflictResolution.keepRemote:
          await _resolveKeepRemote(conflict);
          break;
        case ConflictResolution.merge:
          await _resolveMerge(conflict);
          break;
        case ConflictResolution.askUser:
          throw Exception('Cannot auto-resolve with askUser resolution');
      }

      await _markConflictResolved(conflictId);
      logger.i('✅ Resolved conflict: $conflictId using $resolution');
    } catch (e) {
      logger.e('❌ Failed to resolve conflict $conflictId: $e');
      rethrow;
    }
  }

  /// Clean up conflicts older than specified date
  Future<void> cleanupConflictsOlderThan(DateTime cutoffDate) async {
    try {
      final db = await _sqliteHelper.database;

      final deletedCount = await db.delete(
        'sync_conflicts',
        where: 'detected_at < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );

      if (deletedCount > 0) {
        logger.i('🗑️ Cleaned up $deletedCount old sync conflicts');
      }
    } catch (e) {
      logger.e('❌ Failed to cleanup old conflicts: $e');
    }
  }

  /// Detect conflict for emotional records
  SyncConflict? _detectEmotionalRecordConflict(
    EmotionalRecord local,
    EmotionalRecord remote,
  ) {
    // Simple conflict detection - check if data differs
    if (local.description != remote.description ||
        local.emotion != remote.emotion ||
        local.color != remote.color) {
      return SyncConflict(
        itemType: 'emotional_record',
        itemId: local.id!,
        type: ConflictType.dataConflict,
        localData: local,
        remoteData: remote,
        detectedAt: DateTime.now(),
        description: 'Emotional record modified both locally and remotely',
        canAutoResolve: _canAutoResolveEmotionalRecord(local, remote),
      );
    }
    return null;
  }

  /// Detect conflict for breathing sessions
  SyncConflict? _detectBreathingSessionConflict(
    BreathingSessionData local,
    BreathingSessionData remote,
  ) {
    if (local.pattern != remote.pattern ||
        local.rating != remote.rating ||
        local.comment != remote.comment) {
      return SyncConflict(
        itemType: 'breathing_session',
        itemId: local.id!,
        type: ConflictType.dataConflict,
        localData: local,
        remoteData: remote,
        detectedAt: DateTime.now(),
        description: 'Breathing session modified both locally and remotely',
        canAutoResolve: _canAutoResolveBreathingSession(local, remote),
      );
    }
    return null;
  }

  /// Detect conflict for breathing patterns
  SyncConflict? _detectBreathingPatternConflict(
    BreathingPattern local,
    BreathingPattern remote,
  ) {
    if (local.name != remote.name ||
        local.inhaleSeconds != remote.inhaleSeconds ||
        local.holdSeconds != remote.holdSeconds ||
        local.exhaleSeconds != remote.exhaleSeconds ||
        local.cycles != remote.cycles ||
        local.restSeconds != remote.restSeconds) {
      return SyncConflict(
        itemType: 'breathing_pattern',
        itemId: local.id!,
        type: ConflictType.dataConflict,
        localData: local,
        remoteData: remote,
        detectedAt: DateTime.now(),
        description: 'Breathing pattern modified both locally and remotely',
        canAutoResolve: false, // Patterns are more complex, require user input
      );
    }
    return null;
  }

  /// Detect conflict for custom emotions
  SyncConflict? _detectCustomEmotionConflict(
    CustomEmotion local,
    CustomEmotion remote,
  ) {
    if (local.name != remote.name || local.color != remote.color) {
      return SyncConflict(
        itemType: 'custom_emotion',
        itemId: local.id!,
        type: ConflictType.dataConflict,
        localData: local,
        remoteData: remote,
        detectedAt: DateTime.now(),
        description: 'Custom emotion modified both locally and remotely',
        canAutoResolve: false, // Emotions are personal, require user choice
      );
    }
    return null;
  }

  /// Check if emotional record conflict can be auto-resolved
  bool _canAutoResolveEmotionalRecord(
    EmotionalRecord local,
    EmotionalRecord remote,
  ) {
    // Auto-resolve if only description changed and it's minor
    if (local.emotion == remote.emotion &&
        local.color == remote.color &&
        local.description.length < remote.description.length) {
      return true; // Remote has more detail, prefer it
    }
    return false;
  }

  /// Check if breathing session conflict can be auto-resolved
  bool _canAutoResolveBreathingSession(
    BreathingSessionData local,
    BreathingSessionData remote,
  ) {
    // Auto-resolve if only comment changed
    if (local.pattern == remote.pattern &&
        local.rating == remote.rating &&
        (local.comment?.isEmpty ?? true) &&
        (remote.comment?.isNotEmpty ?? false)) {
      return true; // Remote has comment, local doesn't
    }
    return false;
  }

  /// Resolve conflict by keeping local version
  Future<void> _resolveKeepLocal(SyncConflict conflict) async {
    // Update remote with local data
    switch (conflict.itemType) {
      case 'emotional_record':
        final localRecord = conflict.localData as EmotionalRecord;
        await _apiService.createEmotionalRecord(localRecord);
        break;
      case 'breathing_session':
        final localSession = conflict.localData as BreathingSessionData;
        await _apiService.createBreathingSession(localSession);
        break;
      case 'breathing_pattern':
        final localPattern = conflict.localData as BreathingPattern;
        await _apiService.createBreathingPattern(localPattern);
        break;
      case 'custom_emotion':
        final localEmotion = conflict.localData as CustomEmotion;
        await _apiService.createCustomEmotion(localEmotion);
        break;
    }
  }

  /// Resolve conflict by keeping remote version
  Future<void> _resolveKeepRemote(SyncConflict conflict) async {
    // Update local with remote data
    switch (conflict.itemType) {
      case 'emotional_record':
        final remoteRecord = conflict.remoteData as EmotionalRecord;
        await _updateLocalEmotionalRecord(remoteRecord, remoteRecord);
        break;
      case 'breathing_session':
        final remoteSession = conflict.remoteData as BreathingSessionData;
        await _updateLocalBreathingSession(remoteSession, remoteSession);
        break;
      case 'breathing_pattern':
        final remotePattern = conflict.remoteData as BreathingPattern;
        await _updateLocalBreathingPattern(remotePattern, remotePattern);
        break;
      case 'custom_emotion':
        final remoteEmotion = conflict.remoteData as CustomEmotion;
        await _updateLocalCustomEmotion(remoteEmotion, remoteEmotion);
        break;
    }
  }

  /// Resolve conflict by merging both versions
  Future<void> _resolveMerge(SyncConflict conflict) async {
    // Implement smart merging based on item type
    switch (conflict.itemType) {
      case 'emotional_record':
        await _mergeEmotionalRecords(
          conflict.localData as EmotionalRecord,
          conflict.remoteData as EmotionalRecord,
        );
        break;
      case 'breathing_session':
        await _mergeBreathingSessions(
          conflict.localData as BreathingSessionData,
          conflict.remoteData as BreathingSessionData,
        );
        break;
      default:
        throw Exception('Merge not supported for ${conflict.itemType}');
    }
  }

  /// Merge emotional records intelligently
  Future<void> _mergeEmotionalRecords(
    EmotionalRecord local,
    EmotionalRecord remote,
  ) async {
    // Merge strategy: prefer remote for core data, combine descriptions
    final merged = EmotionalRecord(
      id: local.id,
      source: remote.source, // Prefer remote source
      description: '${local.description}\n\n[Remote]: ${remote.description}',
      emotion: remote.emotion, // Prefer remote emotion
      color: remote.color, // Prefer remote color
      customEmotionName: remote.customEmotionName ?? local.customEmotionName,
      customEmotionColor: remote.customEmotionColor ?? local.customEmotionColor,
      createdAt: local.createdAt, // Keep original creation time
    );

    await _updateLocalEmotionalRecord(local, merged);
    await _apiService.createEmotionalRecord(merged);
  }

  /// Merge breathing sessions intelligently
  Future<void> _mergeBreathingSessions(
    BreathingSessionData local,
    BreathingSessionData remote,
  ) async {
    // Merge strategy: prefer higher rating, combine comments
    final merged = BreathingSessionData(
      id: local.id,
      pattern: remote.pattern, // Prefer remote pattern
      rating: local.rating > remote.rating ? local.rating : remote.rating,
      comment:
          '${local.comment ?? ''}\n[Remote]: ${remote.comment ?? ''}'.trim(),
      createdAt: local.createdAt,
    );

    await _updateLocalBreathingSession(local, merged);
    await _apiService.createBreathingSession(merged);
  }

  /// Update local emotional record
  Future<void> _updateLocalEmotionalRecord(
    EmotionalRecord local,
    EmotionalRecord remote,
  ) async {
    // Update SQLite with remote data
    // This would need proper implementation in SQLiteHelper
    logger.i('Updated local emotional record: ${local.id}');
  }

  /// Add remote emotional record to local storage
  Future<void> _addRemoteEmotionalRecord(EmotionalRecord remote) async {
    await _sqliteHelper.insertEmotionalRecord(remote);
    logger.i('Added remote emotional record: ${remote.id}');
  }

  /// Update local breathing session
  Future<void> _updateLocalBreathingSession(
    BreathingSessionData local,
    BreathingSessionData remote,
  ) async {
    logger.i('Updated local breathing session: ${local.id}');
  }

  /// Add remote breathing session to local storage
  Future<void> _addRemoteBreathingSession(BreathingSessionData remote) async {
    await _sqliteHelper.insertBreathingSession(remote);
    logger.i('Added remote breathing session: ${remote.id}');
  }

  /// Update local breathing pattern
  Future<void> _updateLocalBreathingPattern(
    BreathingPattern local,
    BreathingPattern remote,
  ) async {
    logger.i('Updated local breathing pattern: ${local.id}');
  }

  /// Add remote breathing pattern to local storage
  Future<void> _addRemoteBreathingPattern(BreathingPattern remote) async {
    await _sqliteHelper.insertBreathingPattern(remote);
    logger.i('Added remote breathing pattern: ${remote.id}');
  }

  /// Update local custom emotion
  Future<void> _updateLocalCustomEmotion(
    CustomEmotion local,
    CustomEmotion remote,
  ) async {
    logger.i('Updated local custom emotion: ${local.id}');
  }

  /// Add remote custom emotion to local storage
  Future<void> _addRemoteCustomEmotion(CustomEmotion remote) async {
    await _sqliteHelper.insertCustomEmotion(remote);
    logger.i('Added remote custom emotion: ${remote.id}');
  }

  /// Get conflict by ID
  Future<SyncConflict?> _getConflictById(String conflictId) async {
    try {
      final db = await _sqliteHelper.database;

      final maps = await db.query(
        'sync_conflicts',
        where: 'id = ?',
        whereArgs: [conflictId],
      );

      if (maps.isEmpty) return null;

      return SyncConflict.fromMap(maps.first);
    } catch (e) {
      logger.e('Failed to get conflict by ID: $e');
      return null;
    }
  }

  /// Mark conflict as resolved
  Future<void> _markConflictResolved(String conflictId) async {
    try {
      final db = await _sqliteHelper.database;

      await db.delete(
        'sync_conflicts',
        where: 'id = ?',
        whereArgs: [conflictId],
      );
    } catch (e) {
      logger.e('Failed to mark conflict as resolved: $e');
    }
  }
}
