import 'package:emotion_ai/features/auth/auth_provider.dart';
import 'package:emotion_ai/features/auth/login_screen.dart';
import 'package:emotion_ai/features/auth/pin_code_screen.dart';
import 'package:emotion_ai/features/auth/register_screen.dart';
import 'package:emotion_ai/features/breathing_menu/breathing_menu.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:emotion_ai/shared/widgets/main_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/calendar/offline_calendar_screen.dart';
import '../features/color_wheel/color_wheel.dart';
import '../features/records/all_records_screen.dart';
import '../features/therapy_chat/screens/therapy_chat_screen.dart';
import '../features/profile/profile_screen.dart';
import '../shared/widgets/breating_session.dart';
import 'package:emotion_ai/data/models/breathing_pattern.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final loggedIn = authState;
      final loggingIn =
          state.uri.path == '/login' || state.uri.path == '/register';

      if (!loggedIn && !loggingIn) {
        return '/login';
      }

      if (loggedIn && loggingIn) {
        return '/';
      }

      const secureStorage = FlutterSecureStorage();
      final hasPin = await secureStorage.read(key: 'user_pin_hash') != null;
      final hasVerifiedPin = await secureStorage.read(key: 'pin_verified') == 'true';

      if (loggedIn && hasPin && !hasVerifiedPin && state.uri.path != '/pin') {
        return '/pin';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(path: '/pin', builder: (context, state) => const PinCodeScreen()),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/calendar',
            name: 'Calendar',
            builder: (context, state) => const OfflineCalendarScreen(),
          ),
          GoRoute(
            path: '/color_wheel',
            name: 'Color Wheel',
            builder: (context, state) => const ColorWheelScreen(),
          ),
          GoRoute(
            path: '/breathing_menu',
            name: 'Breathing Menu',
            builder: (context, state) => const BreathingMenuScreen(),
            routes: [
              GoRoute(
                path: 'session',
                name: 'Breathing Session',
                builder: (context, state) {
                  final pattern = state.extra as BreathingPattern;
                  return BreathingSessionScreen(pattern: pattern);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/all_records',
            name: 'All Records',
            builder: (context, state) => const AllRecordsScreen(),
          ),
          GoRoute(
            path: '/therapy_chat',
            name: 'Talk it Through',
            builder: (context, state) => const TherapyChatScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'Profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
