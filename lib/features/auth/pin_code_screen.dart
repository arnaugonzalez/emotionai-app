import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

class PinCodeScreen extends StatefulWidget {
  final bool isSettingUp;
  const PinCodeScreen({super.key, this.isSettingUp = false});

  @override
  State<PinCodeScreen> createState() => _PinCodeScreenState();
}

class _PinCodeScreenState extends State<PinCodeScreen> {
  String _pin = '';
  String? _storedPinHash;
  String? _confirmPin;
  bool _isConfirming = false;
  static const int maxPinLength = 12;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Hash a PIN with SHA-256 for safe comparison and storage.
  static String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  Future<void> _loadPin() async {
    final hash = await _secureStorage.read(key: 'user_pin_hash');
    setState(() {
      _storedPinHash = hash;
    });
  }

  void _onKeyPressed(String value) {
    if (_pin.length < maxPinLength) {
      setState(() {
        _pin += value;
      });
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _onClear() {
    setState(() {
      _pin = '';
    });
  }

  Future<void> _submit() async {
    if (widget.isSettingUp) {
      if (!_isConfirming) {
        if (_pin.length < 4) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN must be at least 4 digits')),
          );
          return;
        }
        setState(() {
          _confirmPin = _pin;
          _pin = '';
          _isConfirming = true;
        });
      } else {
        if (_pin == _confirmPin) {
          await _secureStorage.write(
            key: 'user_pin_hash',
            value: _hashPin(_pin),
          );
          await _secureStorage.write(key: 'pin_verified', value: 'true');
          if (!mounted) return;
          context.pop(true);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PINs do not match')));
          setState(() {
            _pin = '';
            _confirmPin = null;
            _isConfirming = false;
          });
        }
      }
    } else {
      // Verify: user must have set a PIN — no default bypass
      if (_storedPinHash == null) {
        // No PIN stored — force setup
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PIN set. Please set up your PIN first.')),
        );
        return;
      }

      final enteredHash = _hashPin(_pin);
      if (enteredHash == _storedPinHash) {
        await _secureStorage.write(key: 'pin_verified', value: 'true');
        if (!mounted) return;
        context.go('/');
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
        setState(() {
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSettingUp
              ? (_isConfirming ? 'Confirm PIN' : 'Set PIN (4-12 digits)')
              : 'Enter PIN',
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // PIN Display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _pin.isEmpty ? 'Enter PIN...' : '*' * _pin.length,
              style: const TextStyle(fontSize: 24, letterSpacing: 2),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 20),

          // PIN Length indicator
          Text(
            '${_pin.length} / $maxPinLength digits',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 30),

          // Number pad
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                if (index == 9) {
                  // Clear button
                  return ElevatedButton(
                    onPressed: _pin.isNotEmpty ? _onClear : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade700,
                    ),
                    child: const Text('Clear', style: TextStyle(fontSize: 16)),
                  );
                }
                if (index == 10) {
                  // 0 button
                  return ElevatedButton(
                    onPressed:
                        _pin.length < maxPinLength
                            ? () => _onKeyPressed('0')
                            : null,
                    child: const Text('0', style: TextStyle(fontSize: 24)),
                  );
                }
                if (index == 11) {
                  // Backspace button
                  return ElevatedButton(
                    onPressed: _pin.isNotEmpty ? _onDelete : null,
                    child: const Icon(Icons.backspace, size: 24),
                  );
                }
                // Number buttons 1-9
                return ElevatedButton(
                  onPressed:
                      _pin.length < maxPinLength
                          ? () => _onKeyPressed('${index + 1}')
                          : null,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 24),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Submit button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _pin.length >= 4 ? _submit : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  widget.isSettingUp
                      ? (_isConfirming ? 'Confirm PIN' : 'Set PIN')
                      : 'Submit PIN',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
