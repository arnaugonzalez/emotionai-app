import 'package:dio/dio.dart';
import 'auth_api.dart';

class ApiClient {
  final Dio dio;
  final AuthApi auth;

  ApiClient._(this.dio, this.auth);

  factory ApiClient() {
    final auth = AuthApi();
    return ApiClient._(auth.dio, auth);
  }
}
