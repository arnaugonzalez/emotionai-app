class ApiBaseHelper {
  static final String _base = const String.fromEnvironment('BASE_URL');
  static Uri endpoint(String path) => Uri.parse(_base).resolve(path);
}
