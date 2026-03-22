import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/data/services/profile_service.dart';
import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/features/calendar/events/calendar_events_provider.dart';
import 'package:emotion_ai/shared/providers/app_providers.dart' show apiServiceProvider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApi());
final realtimeCalendarProvider = ChangeNotifierProvider<CalendarEventsProvider>(
  (ref) => CalendarEventsProvider(),
);

final authProvider = StateNotifierProvider<AuthNotifier, bool>((ref) {
  return AuthNotifier(ref, ref.watch(apiServiceProvider));
});

// Admin access provider — removed hardcoded admin PIN (TD-001).
// Admin access should be granted via backend role, not client-side PIN.

class AuthNotifier extends StateNotifier<bool> {
  final ApiService _apiService;
  final Ref _ref;

  AuthNotifier(this._ref, this._apiService) : super(false) {
    _checkToken();
  }

  Future<void> _checkToken() async {
    final token = await const FlutterSecureStorage().read(key: 'access_token');
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
          // Profile not found — normal for new users
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
    // Clear pin verification on logout
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: 'pin_verified', value: 'false');
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

  // Admin access should be determined by backend roles, not client-side storage.
}
