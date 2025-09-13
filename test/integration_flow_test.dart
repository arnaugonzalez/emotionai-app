import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart';

import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/config/api_config.dart';
import 'package:emotion_ai/data/models/emotional_record.dart';

class StubAuthApi extends AuthApi {
  StubAuthApi(Dio dio) : super(dio: dio);
  @override
  Future<AuthTokens> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    return AuthTokens(accessToken: 'a1', refreshToken: 'r1', expiresIn: 1800);
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    return AuthTokens(accessToken: 'a1', refreshToken: 'r1', expiresIn: 1800);
  }

  @override
  Future<Map<String, dynamic>> me() async {
    return {
      'id': 'u1',
      'email': 'test@example.com',
      'first_name': 'Test',
      'last_name': 'User',
      'is_verified': false,
    };
  }

  @override
  Future<String?> getValidAccessToken() async => 'a1';
}

void main() {
  group('Integration flow (mocked)', () {
    late Dio dio;
    late DioAdapter adapter;
    late ApiService api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://mock'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      api = ApiService(dio: dio, authApi: StubAuthApi(dio));
    });

    test('register -> profile create -> record create -> list records', () async {
      // Health
      adapter.onGet(
        ApiConfig.healthUrl(),
        (server) => server.reply(200, {'status': 'healthy'}),
      );

      // Profile create
      adapter.onPost(
        ApiConfig.profileUrl(),
        (server) => server.reply(200, {
          'first_name': 'Test',
          'last_name': 'User',
          'user_profile_data': {'personality': 'INTJ'},
        }),
      );

      // Create record
      adapter.onPost(
        ApiConfig.emotionalRecordsUrl(),
        (server) => server.reply(200, {
          'id': 'r1',
          'emotion': 'happy',
          'intensity': 7,
          'description': 'ok',
          'created_at': DateTime.now().toIso8601String(),
          'source': 'database',
        }),
      );

      // List records
      adapter.onGet(
        ApiConfig.emotionalRecordsUrl(),
        (server) => server.reply(200, [
          {
            'id': 'r1',
            'source': 'database',
            'emotion': 'happy',
            'intensity': 7,
            'description': 'ok',
            'created_at': DateTime.now().toIso8601String(),
            'color': null,
          },
        ]),
      );

      // Exercise
      final ok = await api.checkHealth();
      expect(ok, isTrue);

      // Profile via ApiService uses AuthApi for register; we skip direct profile call here as it's in ProfileService
      final rec = await api.createEmotionalRecord(
        EmotionalRecord(
          source: 'test',
          description: 'ok',
          emotion: 'happy',
          color: 0,
          createdAt: DateTime.now(),
          intensity: 7,
        ),
      );
      expect(rec.emotion, 'happy');

      final list = await api.getEmotionalRecords();
      expect(list.length, 1);
      expect(list.first.emotion, 'happy');
    });
  });
}
