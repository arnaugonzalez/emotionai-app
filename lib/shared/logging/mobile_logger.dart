import 'dart:convert';
import 'dart:collection';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MobileLogger {
  final bool enabled;
  final String level; // info|debug
  final int _capacity;
  final ListQueue<String> _buffer;
  bool _online = true;

  MobileLogger({this.enabled = false, this.level = 'info', int capacity = 2000})
    : _capacity = capacity,
      _buffer = ListQueue(capacity) {
    Connectivity().onConnectivityChanged.listen((result) {
      _online = result != ConnectivityResult.none;
    });
  }

  void info(String event, Map<String, dynamic> fields) =>
      _log('info', event, fields);
  void error(String event, Map<String, dynamic> fields) =>
      _log('error', event, fields);

  void _log(String lvl, String event, Map<String, dynamic> fields) {
    if (!enabled) return;
    if (level != 'debug' && lvl == 'debug') return;
    final data = <String, dynamic>{
      'ts_iso': DateTime.now().toUtc().toIso8601String(),
      'level': lvl,
      'event': event,
      'online': _online,
      'sdk': 'flutter',
      ..._redact(fields),
    };
    final line = jsonEncode(data);
    if (_buffer.length == _capacity) _buffer.removeFirst();
    _buffer.addLast(line);
    // Console sink
    // ignore: avoid_print
    print(line);
  }

  Map<String, dynamic> _redact(Map<String, dynamic> fields) {
    final copy = Map<String, dynamic>.from(fields);
    void redactKey(String k) {
      if (copy.containsKey(k)) copy[k] = 'REDACTED';
    }

    redactKey('Authorization');
    redactKey('access_token');
    redactKey('refresh_token');
    return copy;
  }

  List<String> dump() => _buffer.toList(growable: false);

  static String userHash(String? email) {
    if (email == null || email.isEmpty) return '';
    final bytes = utf8.encode(email.toLowerCase());
    return sha256.convert(bytes).toString().substring(0, 12);
  }
}
