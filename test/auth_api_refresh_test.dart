import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:emotion_ai/data/auth_api.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('AuthApi token refresh flow', () {
    late Dio dio;
    late DioAdapter adapter;
    late MockSecureStorage storage;
    late AuthApi authApi;
    String? capturedAuthHeader;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://test')); // base doesn't matter
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedAuthHeader = options.headers['Authorization'] as String?;
            handler.next(options);
          },
        ),
      );
      storage = MockSecureStorage();
      authApi = AuthApi(dio: dio, storage: storage);
    });

    test(
      'getValidAccessToken triggers refresh when only refresh token exists',
      () async {
        when(() => storage.read(key: any(named: 'key'))).thenAnswer(
          (invocation) async =>
              invocation.namedArguments[#key] == 'refresh_token' ? 'r1' : null,
        );
        when(
          () =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')),
        ).thenAnswer((_) async {});

        adapter.onPost(
          '/v1/api/auth/refresh',
          (server) => server.reply(200, {
            'access_token': 'a1',
            'token_type': 'bearer',
            'expires_in': 1800,
          }),
          data: {'refresh_token': 'r1'},
        );

        final token = await authApi.getValidAccessToken();
        expect(token, equals('a1'));

        // Ensure subsequent requests carry Authorization header
        adapter.onGet(
          '/protected',
          (server) => server.reply(200, {'ok': true}),
        );
        final res = await dio.get('/protected');
        expect(res.statusCode, 200);
        expect(res.data, containsPair('ok', true));
        expect(capturedAuthHeader, equals('Bearer a1'));
      },
    );

    test('401 on request triggers refresh and retries successfully', () async {
      // Only refresh token is present initially
      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async =>
            invocation.namedArguments[#key] == 'refresh_token' ? 'r1' : null,
      );
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) async {});

      // Refresh endpoint
      adapter.onPost(
        '/v1/api/auth/refresh',
        (server) => server.reply(200, {
          'access_token': 'a1',
          'token_type': 'bearer',
          'expires_in': 1800,
        }),
        data: {'refresh_token': 'r1'},
      );

      // Protected endpoint: first attempt (no token) -> 401; retry after refresh -> 200
      var first = true;
      adapter.onGet('/protected', (server) {
        if (capturedAuthHeader == 'Bearer a1') {
          server.reply(200, {'ok': true});
        } else {
          // First attempt without Authorization header
          if (first) {
            first = false;
            server.reply(401, {'detail': 'unauthorized'});
          } else {
            server.reply(200, {'ok': true});
          }
        }
      });

      final res = await dio.get('/protected');
      expect(res.statusCode, 200);
      expect(res.data, containsPair('ok', true));
    });
  });
}
