import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/data/services/profile_service.dart';
import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/features/calendar/events/calendar_events_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final authApiProvider = Provider<AuthApi>((ref) => AuthApi());
final realtimeCalendarProvider = ChangeNotifierProvider<CalendarEventsProvider>(
  (ref) => CalendarEventsProvider(),
);

final authProvider = StateNotifierProvider<AuthNotifier, bool>((ref) {
  return AuthNotifier(ref, ref.watch(apiServiceProvider));
});

// Provider to check if user has admin access
final adminAccessProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('admin_access') ?? false;
});

class AuthNotifier extends StateNotifier<bool> {
  final ApiService _apiService;
  final Ref _ref;

  AuthNotifier(this._ref, this._apiService) : super(false) {
    _checkToken();
  }

  Future<void> _checkToken() async {
    final token = await const FlutterSecureStorage().read(key: 'auth_token');
    state = token != null;
  }

  Future<bool> login(String email, String password) async {
    try {
      final authResponse = await _apiService.login(email, password);
      if (authResponse != null) {
        state = true;

        // Load user profile after successful login
        try {
          final profileService = ProfileService();
          await profileService.getUserProfile();
          // Profile loaded successfully - could store in shared preferences or state
        } catch (e) {
          // Profile not found or error loading - this is normal for new users
          print('No existing profile found: $e');
        }

        // Connect realtime calendar after token available
        try {
          final auth = _ref.read(authApiProvider);
          await _ref.read(realtimeCalendarProvider).connectRealtime(auth);
        } catch (_) {}

        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    await _apiService.logout();
    // Close realtime channel
    try {
      _ref.read(realtimeCalendarProvider).disposeRealtime();
    } catch (_) {}
    // Clear admin access on logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_access', false);
    await prefs.setBool('pin_verified', false);
    state = false;
  }

  Future<bool> register(
    String email,
    String password,
    String firstName,
    String lastName, {
    DateTime? dateOfBirth,
  }) async {
    try {
      await _apiService.createUser(
        email,
        password,
        firstName,
        lastName,
        dateOfBirth: dateOfBirth,
      );
      state = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  // Check if user has admin access
  Future<bool> hasAdminAccess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('admin_access') ?? false;
  }
}
