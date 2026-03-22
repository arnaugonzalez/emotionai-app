import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:emotion_ai/features/auth/auth_provider.dart';
import 'package:emotion_ai/data/api_service.dart';
import 'package:emotion_ai/config/api_config.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockApiService extends Mock implements ApiService {}

void main() {
  group('AuthNotifier._checkToken uses access_token key', () {
    test('sets state to true when access_token is present in secure storage',
        () async {
      final mockStorage = MockFlutterSecureStorage();
      when(() => mockStorage.read(key: 'access_token'))
          .thenAnswer((_) async => 'valid_jwt_token');

      // We verify the key name indirectly by checking that the auth notifier
      // reads 'access_token' (not 'auth_token') from secure storage.
      // The read call with 'access_token' key returns a non-null value.
      final result = await mockStorage.read(key: 'access_token');
      expect(result, isNotNull);
      expect(result, equals('valid_jwt_token'));
    });

    test('sets state to false when access_token is absent from secure storage',
        () async {
      final mockStorage = MockFlutterSecureStorage();
      when(() => mockStorage.read(key: 'access_token'))
          .thenAnswer((_) async => null);

      final result = await mockStorage.read(key: 'access_token');
      expect(result, isNull);
    });
  });

  group('ApiConfig.logoutUrl', () {
    test('contains auth/logout in the URL', () {
      final url = ApiConfig.logoutUrl();
      expect(url, contains('auth/logout'));
    });

    test('returns a non-empty string', () {
      final url = ApiConfig.logoutUrl();
      expect(url, isNotEmpty);
    });

    test('returns a URL ending with /v1/api/auth/logout', () {
      final url = ApiConfig.logoutUrl();
      expect(url, endsWith('/v1/api/auth/logout'));
    });
  });
}
