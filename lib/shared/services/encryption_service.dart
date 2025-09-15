import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class EncryptionService {
  static const String _keyPrefix = 'encrypted_';
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final encrypt.Key _key;
  late final encrypt.IV _iv;

  EncryptionService._internal();

  Future<void> initialize() async {
    try {
      // Generate a device-specific key and IV
      final deviceId = await _getDeviceSpecificId();
      final keyBytes = sha256.convert(utf8.encode(deviceId)).bytes;
      _key = encrypt.Key(Uint8List.fromList(keyBytes.sublist(0, 32)));
      _iv = encrypt.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
    } catch (e) {
      logger.e('Failed to initialize encryption service: $e');
      rethrow;
    }
  }

  Future<String> _getDeviceSpecificId() async {
    try {
      // Try to get existing device ID
      String? deviceId;
      try {
        deviceId = await _secureStorage.read(key: 'device_id');
      } catch (e) {
        // Handle corrupted/old keystore values (e.g., BAD_DECRYPT)
        logger.w('SecureStorage read failed for device_id, resetting: $e');
        try {
          await _secureStorage.delete(key: 'device_id');
        } catch (_) {}
        deviceId = null;
      }

      if (deviceId == null) {
        // Generate new device ID if none exists
        final rand = Random.secure();
        final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
        deviceId = base64UrlEncode(bytes);
        await _secureStorage.write(key: 'device_id', value: deviceId);
      }

      return deviceId;
    } catch (e) {
      logger.e('Error getting device ID: $e');
      rethrow;
    }
  }

  String encryptKey(String plainText) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      logger.e('Error encrypting key: $e');
      rethrow;
    }
  }

  String decryptKey(String encryptedText) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final decrypted = encrypter.decrypt64(encryptedText, iv: _iv);
      return decrypted;
    } catch (e) {
      logger.e('Error decrypting key: $e');
      rethrow;
    }
  }

  Future<void> securelyStoreKey(String key, String value) async {
    try {
      final encryptedValue = encryptKey(value);
      await _secureStorage.write(key: _keyPrefix + key, value: encryptedValue);
    } catch (e) {
      logger.e('Error storing encrypted key: $e');
      rethrow;
    }
  }

  Future<String?> securelyRetrieveKey(String key) async {
    try {
      final encryptedValue = await _secureStorage.read(key: _keyPrefix + key);
      if (encryptedValue == null) return null;
      return decryptKey(encryptedValue);
    } catch (e) {
      // If decrypt/read fails due to corrupted keystore, drop the stored value
      logger.w('Error retrieving encrypted key, deleting stored value: $e');
      try {
        await _secureStorage.delete(key: _keyPrefix + key);
      } catch (_) {}
      return null;
    }
  }

  Future<void> securelyDeleteKey(String key) async {
    try {
      await _secureStorage.delete(key: _keyPrefix + key);
    } catch (e) {
      logger.e('Error deleting encrypted key: $e');
      rethrow;
    }
  }
}
