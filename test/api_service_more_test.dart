import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart';

import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/config/api_config.dart';
import 'package:emotion_ai/data/models/custom_emotion.dart';

class DummyAuthApi extends AuthApi {
  DummyAuthApi(Dio dio) : super(dio: dio);
  @override
  Future<String?> getValidAccessToken() async => 'token123';
}

void main() {
  group('ApiService more endpoints', () {
    late Dio dio;
    late DioAdapter adapter;
    late ApiService api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      api = ApiService(dio: dio, authApi: DummyAuthApi(dio));
    });

    test('getUserLimitations parses fields', () async {
      adapter.onGet(
        ApiConfig.userLimitationsUrl(),
        (server) => server.reply(200, {
          'period': '2025-09',
          'monthly_token_limit': 250000,
          'monthly_tokens_used': 12345,
          'remaining_tokens': 237655,
          'usage_percentage': 4.94,
          'can_make_request': true,
          'limit_message': null,
          'limit_reset_time': DateTime(2025, 10, 1).toIso8601String(),
        }),
      );

      final ul = await api.getUserLimitations();
      expect(ul.dailyTokenLimit, 250000);
      expect(ul.dailyTokensUsed, 12345);
      expect(ul.canMakeRequest, isTrue);
    });

    test('custom emotions list and create', () async {
      adapter
        ..onGet(
          ApiConfig.customEmotionsUrl(),
          (server) => server.reply(200, [
            {
              'id': 'c1',
              'name': 'gratitude',
              'color': 0xFFFFEB3B,
              'created_at': DateTime.now().toIso8601String(),
            },
          ]),
        )
        ..onPost(
          ApiConfig.customEmotionsUrl(),
          (server) => server.reply(200, {
            'id': 'c2',
            'name': 'focus',
            'color': 0xFF42A5F5,
            'created_at': DateTime.now().toIso8601String(),
          }),
        );

      final list = await api.getCustomEmotions();
      expect(list, isA<List<CustomEmotion>>());
      expect(list.first.name, 'gratitude');

      final created = await api.createCustomEmotion(
        CustomEmotion(
          name: 'focus',
          color: 0xFF42A5F5,
          createdAt: DateTime.now(),
        ),
      );
      expect(created.name, 'focus');
    });

    test('chat 429 error bubble up message', () async {
      adapter.onPost(
        ApiConfig.chatUrl(),
        (server) => server.reply(429, {'message': 'Rate limit exceeded'}),
      );

      expect(() => api.sendChatMessage('hello'), throwsA(isA<Exception>()));
    });
  });
}
