import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth_api.dart';

class AuthService {
  final AuthApi _api;
  final FlutterSecureStorage _storage;

  AuthService({AuthApi? api, FlutterSecureStorage? storage})
    : _api = api ?? AuthApi(),
      _storage = storage ?? const FlutterSecureStorage();

  Future<void> register(
    String email,
    String password, {
    String? firstName,
    String? lastName,
  }) async {
    await _api.register(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
  }

  Future<void> login(String email, String password) async {
    await _api.login(email: email, password: password);
  }

  Future<Map<String, dynamic>> me() async {
    return _api.me();
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'access_expiry');
    await _storage.delete(key: 'refresh_token');
  }
}
