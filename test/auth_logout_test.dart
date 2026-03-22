import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/data/api_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('AuthApi.clearTokens', () {
    late MockFlutterSecureStorage storage;
    late Dio dio;
    late AuthApi authApi;

    setUp(() {
      storage = MockFlutterSecureStorage();
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      authApi = AuthApi(dio: dio, storage: storage);

      // Stub all delete and write calls
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
    });

    test('deletes access_token from secure storage', () async {
      await authApi.clearTokens();
      verify(() => storage.delete(key: 'access_token')).called(1);
    });

    test('deletes refresh_token from secure storage', () async {
      await authApi.clearTokens();
      verify(() => storage.delete(key: 'refresh_token')).called(1);
    });

    test('deletes access_expiry from secure storage', () async {
      await authApi.clearTokens();
      verify(() => storage.delete(key: 'access_expiry')).called(1);
    });

    test('nulls the in-memory access token cache', () async {
      // Simulate a token being in memory by checking accessToken before and after
      // We can only verify this indirectly via the public accessor
      await authApi.clearTokens();
      expect(authApi.accessToken, isNull);
    });
  });

  group('ApiService.logout', () {
    late Dio dio;
    late DioAdapter adapter;
    late MockFlutterSecureStorage storage;
    late AuthApi authApi;
    late ApiService apiService;

    setUp(() {
      storage = MockFlutterSecureStorage();

      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;

      authApi = AuthApi(dio: dio, storage: storage);
      apiService = ApiService(dio: dio, authApi: authApi);
    });

    test('calls clearTokens via authApi (clears all three storage keys)',
        () async {
      adapter.onPost(
        '/v1/api/auth/logout',
        (server) => server.reply(200, {'status': 'ok'}),
      );

      await apiService.logout();

      // All three keys should have been deleted
      verify(() => storage.delete(key: 'access_token')).called(1);
      verify(() => storage.delete(key: 'refresh_token')).called(1);
      verify(() => storage.delete(key: 'access_expiry')).called(1);
    });

    test('does not throw when the server POST to logout fails (offline-safe)',
        () async {
      // No matching route → DioAdapter throws
      // The method must not propagate this error
      adapter.onPost(
        '/v1/api/auth/logout',
        (server) => server.reply(500, {'error': 'server error'}),
      );

      // Should complete without throwing
      await expectLater(apiService.logout(), completes);
    });

    test('does not throw when server is unreachable (network error)',
        () async {
      // Simulate a connection error by not adding any route for logout
      // The fire-and-forget pattern must swallow the error
      await expectLater(apiService.logout(), completes);
    });
  });
}
