import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/breathing_session.dart';
import '../services/sqlite_helper.dart';
import '../../data/api_service.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class BreathingSessionNotifier extends StateNotifier<BreathingSessionData?> {
  final ApiService _apiService;

  BreathingSessionNotifier(this._apiService) : super(null);

  Future<void> saveSession(BreathingSessionData session) async {
    try {
      await _apiService.createBreathingSession(session);
      logger.i('Session saved to backend successfully');
    } catch (e) {
      logger.w('Failed to save to backend, falling back to local storage: $e');
      // Fallback to SQLite if the backend is unreachable
      try {
        final sqliteHelper = SQLiteHelper();
        await sqliteHelper.insertBreathingSession(session);
        logger.i('Session saved locally successfully');
      } catch (e) {
        logger.e('Failed to save session locally: $e');
        rethrow;
      }
    }
  }
}

final breathingSessionProvider =
    StateNotifierProvider<BreathingSessionNotifier, BreathingSessionData?>(
      (ref) => BreathingSessionNotifier(ApiService()),
    );
