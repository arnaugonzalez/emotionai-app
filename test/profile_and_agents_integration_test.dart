import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart';

import 'package:emotion_ai/data/services/profile_service.dart';
import 'package:emotion_ai/config/api_config.dart';
import 'package:emotion_ai/data/auth_api.dart';

class DummyAuthApi extends AuthApi {
  DummyAuthApi(Dio dio) : super(dio: dio);
  @override
  Future<String?> getValidAccessToken() async => 'token123';
}

void main() {
  group('ProfileService + Agents endpoints (mocked)', () {
    late Dio dio;
    late DioAdapter adapter;
    late ProfileService profile;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://mock'));
      adapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = adapter;
      profile = ProfileService(dio: dio);
    });

    test('profile lifecycle and agents status/memory', () async {
      // Profile create/update
      adapter.onPost(
        ApiConfig.profileUrl(),
        (server) => server.reply(200, {
          'first_name': 'Test',
          'last_name': 'User',
          'user_profile_data': {'personality': 'INTJ'},
        }),
      );

      // Profile get
      adapter.onGet(
        ApiConfig.profileUrl(),
        (server) => server.reply(200, {
          'first_name': 'Test',
          'last_name': 'User',
          'user_profile_data': {'personality': 'INTJ'},
        }),
      );

      // Status
      adapter.onGet(
        ApiConfig.profileStatusUrl(),
        (server) => server.reply(200, {
          'has_profile': true,
          'profile_completeness': 0.9,
          'missing_fields': [],
        }),
      );

      // Therapy context
      adapter
        ..onPut(
          ApiConfig.therapyContextUrl(),
          (server) => server.reply(200, {
            'therapy_context': {'topic': 'sleep'},
          }),
        )
        ..onGet(
          ApiConfig.therapyContextUrl(),
          (server) => server.reply(200, {
            'therapy_context': {'topic': 'sleep'},
          }),
        )
        ..onDelete(
          ApiConfig.therapyContextUrl(),
          (server) => server.reply(200, {
            'message': 'Therapy context cleared successfully',
          }),
        );

      // Agents
      adapter
        ..onGet(
          ApiConfig.agentStatusUrl('therapy'),
          (server) =>
              server.reply(200, {'agent_type': 'therapy', 'ready': true}),
        )
        ..onDelete(
          ApiConfig.agentMemoryUrl('therapy'),
          (server) => server.reply(200, {'message': 'ok'}),
        );

      // Exercise
      final saved = await profile.createOrUpdateProfile({
        'first_name': 'Test',
        'last_name': 'User',
        'user_profile_data': {'personality': 'INTJ'},
      });
      expect(saved.firstName, 'Test');

      final got = await profile.getUserProfile();
      expect(got?.firstName, 'Test');

      final status = await profile.getProfileStatus();
      expect(status.profileCompleteness, greaterThan(0.5));

      final updated = await profile.updateTherapyContext({
        'therapy_context': {'topic': 'sleep'},
      });
      expect(updated.therapyContext?['topic'], isNotNull);

      final ctx = await profile.getTherapyContext();
      expect(ctx?.therapyContext?['topic'], 'sleep');

      final cleared = await profile.clearTherapyContext();
      expect(cleared, isTrue);
    });
  });
}
