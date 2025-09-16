import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'config/api_config.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'shared/services/secure_env_service.dart';
import 'shared/providers/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';

final logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize critical features in parallel
  await Future.wait([
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
    SharedPreferences.getInstance(),
    dotenv.load(fileName: 'assets/.env'),
  ]);

  // Initialize secure environment service
  final secureEnv = SecureEnvService();
  await secureEnv.initialize();

  // Platform-specific optimizations
  if (!kIsWeb && kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Set up error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e('Flutter error: ${details.exception}\n${details.stack}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Platform error: $error\n$stack');
    return true;
  };

  // Validate API configuration
  if (!ApiConfig.validateConfiguration()) {
    logger.e('Invalid API configuration detected! App may not work correctly.');
  }

  // Print configuration for debugging
  if (ApiConfig.isDevelopment) {
    ApiConfig.printConfig();
  }

  // Initialize app with unified Riverpod state management
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Trigger app initialization
    Future.microtask(() {
      ref.read(appInitializationProvider);
      // Connect realtime calendar if token already present (Riverpod)
      final auth = ref.read(authApiProvider);
      auth.getValidAccessToken().then((token) async {
        if (token != null && token.isNotEmpty) {
          await ref.read(realtimeCalendarProvider).connectRealtime(auth);
        }
      });
    });
  }

  @override
  void dispose() {
    try {
      ref.read(realtimeCalendarProvider).disposeRealtime();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('pin_verified', false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final appInitAsync = ref.watch(appInitializationProvider);

    return MaterialApp.router(
      title: 'E-motion AI',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) {
        return appInitAsync.when(
          loading: () => const _AppLoadingScreen(),
          error: (error, stack) {
            logger.e('App initialization failed: $error\n$stack');
            // Still show the app but with limited functionality
            return child ?? const SizedBox.shrink();
          },
          data: (initialized) {
            if (!initialized) {
              logger.w(
                'App initialization incomplete, some features may not work',
              );
            }
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}

/// Loading screen shown during app initialization
class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.deepPurple.shade100, Colors.deepPurple.shade300],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.psychology, size: 64, color: Colors.white),
                SizedBox(height: 24),
                Text(
                  'E-motion AI',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                SizedBox(height: 16),
                Text(
                  'Initializing offline-first sync...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
