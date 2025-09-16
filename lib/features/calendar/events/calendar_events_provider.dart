import 'package:flutter/foundation.dart';
import 'package:emotion_ai/data/models/breathing_session.dart';
import 'package:emotion_ai/data/models/emotional_record.dart';
import 'package:emotion_ai/config/api_config.dart';
import 'package:emotion_ai/utils/data_validator.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:emotion_ai/data/auth_api.dart';

final logger = Logger();

enum CalendarLoadState { loading, loaded, error }

// Isolate function for processing emotional records
Future<Map<DateTime, List<EmotionalRecord>>> _processEmotionalRecordsInIsolate(
  List<EmotionalRecord> records,
) async {
  final Map<DateTime, List<EmotionalRecord>> events = {};
  for (var record in records) {
    final normalizedDate = DateTime(
      record.createdAt.year,
      record.createdAt.month,
      record.createdAt.day,
    );
    events[normalizedDate] = events[normalizedDate] ?? [];
    events[normalizedDate]!.add(record);
  }
  return events;
}

// Isolate function for processing breathing sessions
Future<Map<DateTime, List<BreathingSessionData>>>
_processBreathingSessionsInIsolate(List<BreathingSessionData> sessions) async {
  final Map<DateTime, List<BreathingSessionData>> events = {};
  for (var session in sessions) {
    final normalizedDate = DateTime(
      session.createdAt.year,
      session.createdAt.month,
      session.createdAt.day,
    );
    events[normalizedDate] = events[normalizedDate] ?? [];
    events[normalizedDate]!.add(session);
  }
  return events;
}

// Isolate function for parsing JSON data with validation
Future<List<T>> _parseJsonDataInIsolate<T>(Map<String, dynamic> data) async {
  final List<dynamic> jsonData = data['data'];
  final String type = data['type'];

  try {
    if (type == 'emotional') {
      final validatedData = DataValidator.validateApiResponseList(
        jsonData,
        'EmotionalRecord',
      );
      return validatedData
              .map((item) => EmotionalRecord.fromJson(item))
              .toList()
          as List<T>;
    } else {
      final validatedData = DataValidator.validateApiResponseList(
        jsonData,
        'BreathingSession',
      );
      return validatedData
              .map((item) => BreathingSessionData.fromJson(item))
              .toList()
          as List<T>;
    }
  } catch (e) {
    logger.e('Error parsing $type data: $e');
    // Return empty list instead of crashing
    return <T>[];
  }
}

class CalendarEventsProvider extends ChangeNotifier {
  CalendarLoadState state = CalendarLoadState.loading;
  Map<DateTime, List<EmotionalRecord>> emotionalEvents = {};
  Map<DateTime, List<BreathingSessionData>> breathingEvents = {};
  String? errorMessage;
  WebSocketChannel? _ws;
  bool _wsConnected = false;
  AuthApi? _auth;

  /// Fetch events with comprehensive validation and error handling
  Future<void> fetchEvents() async {
    state = CalendarLoadState.loading;
    errorMessage = null;
    notifyListeners();

    try {
      logger.i('Fetching calendar events from backend...');

      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.connectTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
      );
      // Ensure Authorization header is included for protected endpoints
      final auth = _auth ?? AuthApi();
      final token = await auth.getValidAccessToken();
      final options = Options(
        headers:
            token != null
                ? ApiConfig.authHeaders(token)
                : ApiConfig.defaultHeaders,
      );
      final emotionalResponse = await dio
          .get(ApiConfig.emotionalRecordsUrl(), options: options)
          .timeout(const Duration(seconds: 8));
      final breathingResponse = await dio
          .get(ApiConfig.breathingSessionsUrl(), options: options)
          .timeout(const Duration(seconds: 8));

      logger.i(
        'API responses - Emotional: ${emotionalResponse.statusCode}, Breathing: ${breathingResponse.statusCode}',
      );

      if (emotionalResponse.statusCode == 200 &&
          breathingResponse.statusCode == 200) {
        // Validate response bodies
        final emotionalBody = emotionalResponse.data;
        final breathingBody = breathingResponse.data;

        logger.i(
          'Response bodies - Emotional length: ${emotionalBody.length}, Breathing length: ${breathingBody.length}',
        );

        if (emotionalBody == null || breathingBody == null) {
          throw Exception('Empty response from backend');
        }

        dynamic emotionalJson;
        dynamic breathingJson;

        emotionalJson = emotionalBody;
        breathingJson = breathingBody;

        // Ensure responses are lists
        if (emotionalJson is! List) {
          throw Exception(
            'Expected list response for emotional records, got: ${emotionalJson.runtimeType}',
          );
        }
        if (breathingJson is! List) {
          throw Exception(
            'Expected list response for breathing sessions, got: ${breathingJson.runtimeType}',
          );
        }

        logger.i('Parsing emotional records: ${emotionalJson.length} items');
        logger.i('Parsing breathing sessions: ${breathingJson.length} items');

        // Backend returns array directly, not wrapped in "data" field
        final emotionalData = await compute(
          _parseJsonDataInIsolate<EmotionalRecord>,
          {'data': emotionalJson, 'type': 'emotional'},
        );
        final breathingData = await compute(
          _parseJsonDataInIsolate<BreathingSessionData>,
          {'data': breathingJson, 'type': 'breathing'},
        );

        logger.i(
          'Successfully parsed - Emotional: ${emotionalData.length}, Breathing: ${breathingData.length}',
        );

        emotionalEvents = await compute(
          _processEmotionalRecordsInIsolate,
          emotionalData,
        );
        breathingEvents = await compute(
          _processBreathingSessionsInIsolate,
          breathingData,
        );

        logger.i('Calendar events processed successfully');
        state = CalendarLoadState.loaded;
        notifyListeners();
      } else {
        final error =
            'Backend error - Emotional: ${emotionalResponse.statusCode}, Breathing: ${breathingResponse.statusCode}';
        logger.e(error);
        throw Exception(error);
      }
    } on DioException catch (e) {
      logger.e('Network error fetching events: ${e.message}');
      errorMessage = 'Failed to reach server. Please check your connection.';
      state = CalendarLoadState.error;
      emotionalEvents = {};
      breathingEvents = {};
      notifyListeners();
    } catch (e) {
      logger.e('Error fetching calendar events: $e');
      errorMessage = e.toString();
      state = CalendarLoadState.error;

      // Provide fallback empty data to prevent UI crashes
      emotionalEvents = {};
      breathingEvents = {};

      notifyListeners();
    }
  }

  Future<void> connectRealtime(AuthApi auth) async {
    try {
      _auth = auth;
      final token = await auth.getValidAccessToken();
      if (token == null) return;
      final wsBase =
          ApiConfig.wsBaseUrl; // can be overridden by --dart-define=WS_BASE_URL
      final uri = Uri.parse('$wsBase/ws/calendar?token=$token');
      _ws = WebSocketChannel.connect(uri);
      _wsConnected = true;
      _ws!.stream.listen(
        (data) async {
          // For now, on any calendar event, refresh data
          await fetchEvents();
        },
        onError: (e) {
          _wsConnected = false;
        },
        onDone: () {
          _wsConnected = false;
        },
      );
    } catch (e) {
      _wsConnected = false;
    }
  }

  void disposeRealtime() {
    try {
      _ws?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _ws = null;
    _wsConnected = false;
  }
}
