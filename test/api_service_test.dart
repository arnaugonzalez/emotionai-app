import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart';

import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/data/auth_api.dart';
import 'package:emotion_ai/config/api_config.dart';
import 'package:emotion_ai/data/models/emotional_record.dart';

class DummyAuthApi extends AuthApi {
  DummyAuthApi(Dio dio) : super(dio: dio);
  @override
  Future<String?> getValidAccessToken() async => 'token123';
}

void main() {
  group('ApiService', () {
    late Dio dio;
    late DioAdapter adapter;
    late ApiService api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      api = ApiService(dio: dio, authApi: DummyAuthApi(dio));
    });

    test('getEmotionalRecords returns list', () async {
      adapter.onGet(
        ApiConfig.emotionalRecordsUrl(),
        (server) => server.reply(200, [
          {
            'id': '1',
            'source': 'database',
            'emotion': 'happy',
            'intensity': 7,
            'description': 'desc',
            'created_at': DateTime.now().toIso8601String(),
            'color': null,
          },
        ]),
      );

      final list = await api.getEmotionalRecords();
      expect(list, isNotEmpty);
      expect(list.first.emotion, 'happy');
    });

    test('createEmotionalRecord posts and parses response', () async {
      adapter.onPost(
        ApiConfig.emotionalRecordsUrl(),
        (server) => server.reply(200, {
          'id': 'r1',
          'emotion': 'calm',
          'intensity': 5,
          'description': 'ok',
          'created_at': DateTime.now().toIso8601String(),
          'source': 'database',
        }),
      );

      final rec = await api.createEmotionalRecord(
        EmotionalRecord(
          source: 'test',
          description: 'ok',
          emotion: 'calm',
          color: 0,
          createdAt: DateTime.now(),
          intensity: 5,
        ),
      );

      expect(rec.emotion, 'calm');
    });
  });
}
