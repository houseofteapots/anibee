import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../settings_store.dart';

enum LockMode { unlock, setup }

/// App lock: 4-digit PIN + Face ID. Matches the approved mockup
/// (AniBee bee mark, "Enter Passcode", 4 dots, keypad, Face ID).
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.mode,
    required this.store,
    this.onUnlocked,
  });

  final LockMode mode;
  final SettingsStore store;
  final VoidCallback? onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _firstPin;
  String _error = '';
  int _wrongAttempts = 0;
  bool _faceIdBusy = false;

  String _hash(String pin) {
    return sha256.convert(utf8.encode('anibee-pin:$pin')).toString();
  }

  void _onDigit(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = '';
    });
    if (_pin.length == 4) {
      _submit();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (widget.mode == LockMode.setup) {
      if (_firstPin == null) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
        return;
      }
      if (_pin == _firstPin) {
        await widget.store.setPinHash(_hash(_pin));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Passcodes do not match. Try again.';
          _firstPin = null;
          _pin = '';
        });
      }
      return;
    }
    if (_hash(_pin) == widget.store.pinHash) {
      widget.onUnlocked?.call();
    } else {
      setState(() {
        _wrongAttempts += 1;
        _error = 'Wrong passcode.';
        _pin = '';
      });
    }
  }

  Future<void> _tryFaceId() async {
    if (_faceIdBusy) return;
    setState(() => _faceIdBusy = true);
    try {
      final LocalAuthentication auth = LocalAuthentication();
      final bool canCheck = await auth.canCheckBiometrics;
      if (!canCheck) {
        setState(() => _error = 'Face ID is not available on this device.');
        return;
      }
      final bool ok = await auth.authenticate(
        localizedReason: 'Unlock AniBee',
        biometricOnly: true,
      );
      if (ok) {
        if (widget.mode == LockMode.setup) {
          await widget.store.setFaceIdEnabled(true);
          if (mounted) Navigator.of(context).pop(true);
        } else {
          widget.onUnlocked?.call();
        }
      }
    } catch (_) {
      setState(() => _error = 'Face ID failed. Enter your passcode.');
    } finally {
      if (mounted) setState(() => _faceIdBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSetup = widget.mode == LockMode.setup;
    final String title = isSetup
        ? (_firstPin == null ? 'Set Passcode' : 'Confirm Passcode')
        : 'Enter Passcode';
    final Color accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A13),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (isSetup)
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.jpg',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                children: <TextSpan>[
                  const TextSpan(
                    text: 'Ani',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: 'Bee',
                    style: TextStyle(
                      color: accent,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                4,
                (int i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white54),
                  ),
                ),
              ),
            ),
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
            ],
            if (_wrongAttempts >= 5) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Too many wrong attempts. Wait before trying again.',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const Spacer(),
            _Keypad(
              onDigit: _wrongAttempts >= 5 ? null : _onDigit,
              onDelete: _onDelete,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _faceIdBusy ? null : _tryFaceId,
              icon: const Icon(Icons.face_rounded, color: Colors.white70),
              label: const Text(
                'Face ID',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onDelete});

  final ValueChanged<String>? onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final List<String> row in <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final String d in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _KeyButton(
                      label: d,
                      onTap: onDigit == null ? null : () => onDigit!(d),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(width: 88),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _KeyButton(
                label: '0',
                onTap: onDigit == null ? null : () => onDigit!('0'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _KeyButton(
                icon: Icons.backspace_outlined,
                onTap: onDelete,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Color(0xFF17171F),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: label != null
            ? Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}
