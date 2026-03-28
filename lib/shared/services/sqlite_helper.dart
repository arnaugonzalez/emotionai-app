import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/emotional_record.dart';
import '../../data/models/breathing_session.dart';
import '../../data/models/breathing_pattern.dart';
import '../../data/models/custom_emotion.dart';
import 'package:logger/logger.dart';

final logger = Logger();

// Isolate functions
Future<List<EmotionalRecord>> _processEmotionalRecordsInIsolate(
  List<Map<String, dynamic>> maps,
) async {
  return maps.map((map) => EmotionalRecord.fromMap(map)).toList();
}

Future<List<BreathingSessionData>> _processBreathingSessionsInIsolate(
  List<Map<String, dynamic>> maps,
) async {
  return maps.map((map) => BreathingSessionData.fromMap(map)).toList();
}

Future<List<BreathingPattern>> _processBreathingPatternsInIsolate(
  List<Map<String, dynamic>> maps,
) async {
  return maps.map((map) => BreathingPattern.fromMap(map)).toList();
}

Future<List<CustomEmotion>> _processCustomEmotionsInIsolate(
  List<Map<String, dynamic>> maps,
) async {
  return List.generate(maps.length, (i) => CustomEmotion.fromMap(maps[i]));
}

class SQLiteHelper {
  static final SQLiteHelper _instance = SQLiteHelper._internal();
  factory SQLiteHelper() => _instance;

  SQLiteHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('emotion_ai.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    logger.i('Initializing database at path: $path');

    return await openDatabase(
      path,
      version: 11, // v11: deleted_at for offline delete sync
      onCreate: (db, version) async {
        logger.i('Creating database tables for version $version');

        await db.execute('''
          CREATE TABLE emotional_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            source TEXT,
            description TEXT,
            emotion TEXT,
            color TEXT,
            customEmotionName TEXT,
            customEmotionColor INTEGER,
            intensity INTEGER DEFAULT 5,
            triggers TEXT,
            notes TEXT,
            contextData TEXT,
            tags TEXT,
            tagConfidence REAL,
            processedForTags INTEGER DEFAULT 0,
            recordedAt TEXT,
            synced INTEGER DEFAULT 0,
            sync_attempts INTEGER DEFAULT 0,
            last_sync_attempt TEXT,
            deleted_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE breathing_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            pattern TEXT,
            rating REAL,
            comment TEXT,
            synced INTEGER DEFAULT 0,
            deleted_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE breathing_patterns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            inhaleSeconds INTEGER,
            holdSeconds INTEGER,
            exhaleSeconds INTEGER,
            cycles INTEGER,
            restSeconds INTEGER,
            synced INTEGER DEFAULT 0,
            deleted_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE custom_emotions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            color INTEGER,
            deleted_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE ai_conversation_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            conversationId TEXT,
            summary TEXT,
            context TEXT,
            tokensUsed INTEGER
          )
        ''');
        logger.i('Creating token_usage table');
        await db.execute('''
          CREATE TABLE token_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            model TEXT,
            promptTokens INTEGER,
            completionTokens INTEGER,
            costInCents REAL
          )
        ''');
        logger.i('Creating daily_token_usage table');
        await db.execute('''
          CREATE TABLE daily_token_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId TEXT NOT NULL,
            date TEXT NOT NULL,
            promptTokens INTEGER NOT NULL DEFAULT 0,
            completionTokens INTEGER NOT NULL DEFAULT 0,
            costInCents REAL NOT NULL DEFAULT 0,
            UNIQUE(userId, date)
          )
        ''');
        logger.i('Daily token usage table created successfully');

        // Insert preset breathing patterns
        await _insertPresetBreathingPatterns(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        logger.i('Upgrading database from version $oldVersion to $newVersion');

        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS custom_emotions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              color INTEGER
            )
          ''');
        }
        if (oldVersion < 7) {
          // Add new columns for custom emotions
          await db.execute('''
            ALTER TABLE emotional_records
            ADD COLUMN customEmotionName TEXT;
          ''');
          await db.execute('''
            ALTER TABLE emotional_records
            ADD COLUMN customEmotionColor INTEGER;
          ''');
        }
        if (oldVersion < 8) {
          logger.i(
            'Upgrading to version 8: Adding AI memory and token usage tables',
          );
          // Add new tables for AI memory and token usage
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ai_conversation_memories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT,
              conversationId TEXT,
              summary TEXT,
              context TEXT,
              tokensUsed INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS token_usage (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT,
              model TEXT,
              promptTokens INTEGER,
              completionTokens INTEGER,
              costInCents REAL
            )
          ''');
          logger.i('AI memory and token usage tables created successfully');
        }
        if (oldVersion < 9) {
          logger.i('Upgrading to version 9: Adding daily token usage table');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS daily_token_usage (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              userId TEXT NOT NULL,
              date TEXT NOT NULL,
              promptTokens INTEGER NOT NULL DEFAULT 0,
              completionTokens INTEGER NOT NULL DEFAULT 0,
              costInCents REAL NOT NULL DEFAULT 0,
              UNIQUE(userId, date)
            )
          ''');
        }
        if (oldVersion < 10) {
          logger.i(
            'Upgrading to version 10: Adding missing emotional_records columns',
          );
          final cols = [
            'ALTER TABLE emotional_records ADD COLUMN intensity INTEGER DEFAULT 5',
            'ALTER TABLE emotional_records ADD COLUMN triggers TEXT',
            'ALTER TABLE emotional_records ADD COLUMN notes TEXT',
            'ALTER TABLE emotional_records ADD COLUMN contextData TEXT',
            'ALTER TABLE emotional_records ADD COLUMN tags TEXT',
            'ALTER TABLE emotional_records ADD COLUMN tagConfidence REAL',
            'ALTER TABLE emotional_records ADD COLUMN processedForTags INTEGER DEFAULT 0',
            'ALTER TABLE emotional_records ADD COLUMN recordedAt TEXT',
            'ALTER TABLE emotional_records ADD COLUMN sync_attempts INTEGER DEFAULT 0',
            'ALTER TABLE emotional_records ADD COLUMN last_sync_attempt TEXT',
          ];
          for (final sql in cols) {
            try {
              await db.execute(sql);
            } catch (_) {
              // Column may already exist — safe to ignore
            }
          }
        }
        if (oldVersion < 11) {
          logger.i('Upgrading to version 11: Adding deleted_at for offline delete sync');
          const tables = [
            'emotional_records',
            'breathing_sessions',
            'breathing_patterns',
            'custom_emotions',
          ];
          for (final tbl in tables) {
            try {
              await db.execute('ALTER TABLE $tbl ADD COLUMN deleted_at TEXT');
            } catch (_) {
              // Column already exists on a fresh install — safe to ignore
            }
          }
        }
      },
    );
  }

  Future<void> _insertPresetBreathingPatterns(Database db) async {
    // Define preset patterns
    final presets = [
      {
        'name': '4-7-8 Relaxation Breath',
        'inhaleSeconds': 4,
        'holdSeconds': 7,
        'exhaleSeconds': 8,
        'cycles': 4,
        'restSeconds': 2,
        'synced': 1,
      },
      {
        'name': 'Box Breathing',
        'inhaleSeconds': 4,
        'holdSeconds': 4,
        'exhaleSeconds': 4,
        'cycles': 4,
        'restSeconds': 4,
        'synced': 1,
      },
      {
        'name': 'Calm Breath',
        'inhaleSeconds': 3,
        'holdSeconds': 0,
        'exhaleSeconds': 6,
        'cycles': 5,
        'restSeconds': 1,
        'synced': 1,
      },
      {
        'name': 'Wim Hof Method',
        'inhaleSeconds': 2,
        'holdSeconds': 0,
        'exhaleSeconds': 2,
        'cycles': 30,
        'restSeconds': 0,
        'synced': 1,
      },
      {
        'name': 'Deep Yoga Breath',
        'inhaleSeconds': 5,
        'holdSeconds': 2,
        'exhaleSeconds': 5,
        'cycles': 10,
        'restSeconds': 1,
        'synced': 1,
      },
    ];

    // Insert each preset
    for (final pattern in presets) {
      await db.insert('breathing_patterns', pattern);
    }
  }

  // EmotionalRecord CRUD Operations
  Future<void> insertEmotionalRecord(EmotionalRecord record) async {
    final db = await database;
    await db.insert(
      'emotional_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<EmotionalRecord>> getEmotionalRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'emotional_records',
      where: 'deleted_at IS NULL',
    );
    return compute(_processEmotionalRecordsInIsolate, maps);
  }

  Future<void> deleteAllEmotionalRecords() async {
    final db = await database;
    await db.delete('emotional_records');
  }

  Future<List<EmotionalRecord>> getUnsyncedEmotionalRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'emotional_records',
      where: 'synced = ? AND deleted_at IS NULL',
      whereArgs: [0],
    );
    return compute(_processEmotionalRecordsInIsolate, maps);
  }

  Future<void> markEmotionalRecordAsSynced(int id) async {
    final db = await database;
    await db.update(
      'emotional_records',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark emotional record as synced (string ID version for sync compatibility)
  Future<void> markEmotionalRecordSynced(String recordId) async {
    final db = await database;
    await db.update(
      'emotional_records',
      {'synced': 1, 'last_sync_attempt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  /// Update sync attempt for emotional record
  Future<void> updateSyncAttempt(String recordId, String errorMessage) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE emotional_records 
      SET sync_attempts = sync_attempts + 1,
          last_sync_attempt = ?
      WHERE id = ?
    ''',
      [DateTime.now().toIso8601String(), recordId],
    );
  }

  /// Get sync statistics
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;
    try {
      final syncedCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM emotional_records WHERE synced = 1',
            ),
          ) ??
          0;

      final unsyncedCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM emotional_records WHERE synced = 0',
            ),
          ) ??
          0;

      final failedCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM emotional_records WHERE sync_attempts > 3',
            ),
          ) ??
          0;

      return {
        'synced': syncedCount,
        'unsynced': unsyncedCount,
        'failed': failedCount,
        'total': syncedCount + unsyncedCount,
      };
    } catch (e) {
      logger.e('❌ Failed to get sync stats: $e');
      return {'synced': 0, 'unsynced': 0, 'failed': 0, 'total': 0};
    }
  }

  /// Clean up old synced records
  Future<void> cleanupOldRecords() async {
    final db = await database;
    try {
      await db.rawDelete('''
        DELETE FROM emotional_records 
        WHERE synced = 1 
        AND id NOT IN (
          SELECT id FROM emotional_records 
          WHERE synced = 1 
          ORDER BY date DESC 
          LIMIT 100
        )
      ''');
      logger.i('🧹 Cleaned up old synced records');
    } catch (e) {
      logger.e('❌ Failed to cleanup old records: $e');
    }
  }

  // BreathingSession CRUD Operations
  Future<void> insertBreathingSession(BreathingSessionData session) async {
    final db = await database;
    await db.insert(
      'breathing_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BreathingSessionData>> getBreathingSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'breathing_sessions',
      where: 'deleted_at IS NULL',
    );
    return compute(_processBreathingSessionsInIsolate, maps);
  }

  Future<void> deleteAllBreathingSessions() async {
    final db = await database;
    await db.delete('breathing_sessions');
  }

  Future<List<BreathingSessionData>> getUnsyncedBreathingSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'breathing_sessions',
      where: 'synced = ? AND deleted_at IS NULL',
      whereArgs: [0],
    );
    return compute(_processBreathingSessionsInIsolate, maps);
  }

  Future<void> markBreathingSessionAsSynced(int id) async {
    final db = await database;
    await db.update(
      'breathing_sessions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // BreathingPattern CRUD Operations
  Future<List<BreathingPattern>> getBreathingPatterns() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'breathing_patterns',
        where: 'deleted_at IS NULL',
      );
      return compute(_processBreathingPatternsInIsolate, maps);
    } catch (e) {
      // Table may not exist yet if older version
      return [];
    }
  }

  Future<void> insertBreathingPattern(BreathingPattern pattern) async {
    final db = await database;

    // Check if table exists
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='breathing_patterns'",
    );

    if (tables.isEmpty) {
      // Create table if it doesn't exist
      await db.execute('''
        CREATE TABLE breathing_patterns (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          inhaleSeconds INTEGER,
          holdSeconds INTEGER,
          exhaleSeconds INTEGER,
          cycles INTEGER,
          restSeconds INTEGER,
          synced INTEGER DEFAULT 0
        )
      ''');
    }

    await db.insert('breathing_patterns', {
      'name': pattern.name,
      'inhaleSeconds': pattern.inhaleSeconds,
      'holdSeconds': pattern.holdSeconds,
      'exhaleSeconds': pattern.exhaleSeconds,
      'cycles': pattern.cycles,
      'restSeconds': pattern.restSeconds,
      'synced': 0, // Not synced by default
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markBreathingPatternAsSynced(int id) async {
    final db = await database;
    await db.update(
      'breathing_patterns',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedBreathingPatterns() async {
    final db = await database;
    return await db.query(
      'breathing_patterns',
      where: 'synced = ? AND deleted_at IS NULL',
      whereArgs: [0],
    );
  }

  // Additional sync-related methods for emotional records

  Future<List<EmotionalRecord>> getAllEmotionalRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'emotional_records',
      where: 'deleted_at IS NULL',
    );
    return compute(_processEmotionalRecordsInIsolate, maps);
  }

  // Additional sync-related methods for breathing sessions
  Future<List<BreathingSessionData>> getAllBreathingSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'breathing_sessions',
      where: 'deleted_at IS NULL',
    );
    return compute(_processBreathingSessionsInIsolate, maps);
  }

  // Additional sync-related methods for breathing patterns
  Future<List<BreathingPattern>> getAllBreathingPatterns() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'breathing_patterns',
        where: 'deleted_at IS NULL',
      );
      return compute(_processBreathingPatternsInIsolate, maps);
    } catch (e) {
      // Table may not exist yet if older version
      return [];
    }
  }

  // Custom Emotions CRUD Operations
  Future<int> insertCustomEmotion(CustomEmotion emotion) async {
    final db = await database;
    return await db.insert('custom_emotions', emotion.toMap());
  }

  Future<List<CustomEmotion>> getCustomEmotions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'custom_emotions',
      where: 'deleted_at IS NULL',
    );
    return compute(_processCustomEmotionsInIsolate, maps);
  }

  Future<List<CustomEmotion>> getAllCustomEmotions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'custom_emotions',
      where: 'deleted_at IS NULL',
    );
    return compute(_processCustomEmotionsInIsolate, maps);
  }

  Future<int> updateCustomEmotion(CustomEmotion emotion) async {
    final db = await database;
    return await db.update(
      'custom_emotions',
      emotion.toMap(),
      where: 'id = ?',
      whereArgs: [emotion.id],
    );
  }

  Future<int> deleteCustomEmotion(int id) async {
    final db = await database;
    return await db.delete('custom_emotions', where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-delete: marks row as pending remote deletion.
  /// SyncManager will hard-delete after API confirms 204.
  Future<void> softDeleteEmotionalRecord(int id) async {
    final db = await database;
    await db.update(
      'emotional_records',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDeleteEmotionalRecord(int id) async {
    final db = await database;
    await db.delete('emotional_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> softDeleteBreathingSession(int id) async {
    final db = await database;
    await db.update(
      'breathing_sessions',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDeleteBreathingSession(int id) async {
    final db = await database;
    await db.delete('breathing_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> softDeleteBreathingPattern(int id) async {
    final db = await database;
    await db.update(
      'breathing_patterns',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDeleteBreathingPattern(int id) async {
    final db = await database;
    await db.delete('breathing_patterns', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> softDeleteCustomEmotion(int id) async {
    final db = await database;
    await db.update(
      'custom_emotions',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDeleteCustomEmotion(int id) async {
    final db = await database;
    await db.delete('custom_emotions', where: 'id = ?', whereArgs: [id]);
  }

  /// Get all records pending remote deletion (soft-deleted but not yet synced).
  Future<List<Map<String, dynamic>>> getPendingDeleteEmotionalRecords() async {
    final db = await database;
    return db.query('emotional_records', where: 'deleted_at IS NOT NULL');
  }

  Future<List<Map<String, dynamic>>> getPendingDeleteBreathingSessions() async {
    final db = await database;
    return db.query('breathing_sessions', where: 'deleted_at IS NOT NULL');
  }

  Future<List<Map<String, dynamic>>> getPendingDeleteBreathingPatterns() async {
    final db = await database;
    return db.query('breathing_patterns', where: 'deleted_at IS NOT NULL');
  }

  Future<List<Map<String, dynamic>>> getPendingDeleteCustomEmotions() async {
    final db = await database;
    return db.query('custom_emotions', where: 'deleted_at IS NOT NULL');
  }

  // Sync conflict tracking table creation
  Future<void> createSyncConflictsTable() async {
    final db = await database;

    // Check if table exists
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_conflicts'",
    );

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE sync_conflicts (
          id TEXT PRIMARY KEY,
          item_type TEXT NOT NULL,
          item_id TEXT NOT NULL,
          conflict_type TEXT NOT NULL,
          local_data TEXT NOT NULL,
          remote_data TEXT NOT NULL,
          detected_at TEXT NOT NULL,
          description TEXT NOT NULL,
          can_auto_resolve INTEGER NOT NULL DEFAULT 0
        )
      ''');

      logger.i('Created sync_conflicts table');
    }
  }
}
