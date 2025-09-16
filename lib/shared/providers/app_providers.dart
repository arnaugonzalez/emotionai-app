/// Centralized Dependency Injection Providers
///
/// This file contains all Riverpod providers for the app, providing
/// a single source of truth for dependency injection and service management.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sqlite_helper.dart';
import '../services/offline_data_service.dart' hide ConnectivityStatus;
import '../../data/api_service.dart';
import '../services/enhanced_api_service.dart';
import '../services/circuit_breaker.dart';
import '../services/error_handler.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/sync/sync_queue.dart';
import '../../core/sync/conflict_resolver.dart';
import '../../features/calendar/events/offline_calendar_provider.dart';

/// Core Database Provider
final sqliteHelperProvider = Provider<SQLiteHelper>((ref) {
  return SQLiteHelper();
});

/// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Circuit Breaker Manager Provider
final circuitBreakerManagerProvider = Provider<CircuitBreakerManager>((ref) {
  return CircuitBreakerManager();
});

/// Error Handler Provider
final errorHandlerProvider = Provider<ErrorHandler>((ref) {
  return ErrorHandler();
});

/// Enhanced API Service Provider
final enhancedApiServiceProvider = Provider<EnhancedApiService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final circuitBreakerManager = ref.watch(circuitBreakerManagerProvider);
  final errorHandler = ref.watch(errorHandlerProvider);
  final sqliteHelper = ref.watch(sqliteHelperProvider);

  return EnhancedApiService(
    apiService: apiService,
    circuitBreakerManager: circuitBreakerManager,
    errorHandler: errorHandler,
    sqliteHelper: sqliteHelper,
  );
});

/// Offline Data Service Provider
final offlineDataServiceProvider = Provider<OfflineDataService>((ref) {
  return OfflineDataService();
});

/// Sync Queue Provider
final syncQueueProvider = Provider<SyncQueue>((ref) {
  return SyncQueue();
});

/// Conflict Resolver Provider
final conflictResolverProvider = Provider<ConflictResolver>((ref) {
  final sqliteHelper = ref.watch(sqliteHelperProvider);
  final apiService = ref.watch(apiServiceProvider);
  return ConflictResolver(sqliteHelper, apiService);
});

/// Sync Manager Provider - Main coordination service
final syncManagerProvider = Provider<SyncManager>((ref) {
  return SyncManager();
});

/// Sync State Stream Provider
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream;
});

/// Calendar Provider - Re-export for easier access
final calendarProvider = offlineCalendarProvider;

/// App Initialization State Provider
final appInitializationProvider = FutureProvider<bool>((ref) async {
  try {
    const bool syncEnabled = bool.fromEnvironment(
      'SYNC_ENABLED',
      defaultValue: true,
    );
    if (syncEnabled) {
      // Initialize all core services
      final syncManager = ref.read(syncManagerProvider);
      final offlineDataService = ref.read(offlineDataServiceProvider);
      await Future.wait([
        syncManager.initialize(),
        offlineDataService.initialize(),
      ]);
    }

    return true;
  } catch (e) {
    // Log error but don't fail completely
    return false;
  }
});

/// Connectivity State Provider
final connectivityProvider = StreamProvider<ConnectivityStatus>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream.map((state) => state.connectivity);
});

/// Pending Sync Items Count Provider
final pendingSyncItemsProvider = StreamProvider<int>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream.map((state) => state.pendingItems);
});

/// Sync Conflicts Provider
final syncConflictsProvider = StreamProvider<List<SyncConflict>>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream.map((state) => state.conflicts);
});

/// Error Handling Provider
final lastSyncErrorProvider = StreamProvider<String?>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream.map((state) => state.errorMessage);
});

/// App Errors Stream Provider
final appErrorsProvider = StreamProvider<AppError>((ref) {
  final errorHandler = ref.watch(errorHandlerProvider);
  return errorHandler.errorStream;
});

/// Circuit Breaker Status Provider
final circuitBreakerStatusProvider = Provider<Map<String, dynamic>>((ref) {
  final enhancedApiService = ref.watch(enhancedApiServiceProvider);
  return enhancedApiService.getCircuitBreakerStatus();
});
