import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kSmsRationalePromptedKey = 'hiqeo_sms_rationale_prompted_v1';

@immutable
class SosSmsBatchResult {
  const SosSmsBatchResult({
    this.supported = true,
    this.permissionDenied = false,
    this.sentCount = 0,
    this.failedCount = 0,
    this.sentPhones = const <String>[],
    this.failedPhones = const <String>[],
  });

  final bool supported;
  final bool permissionDenied;
  final int sentCount;
  final int failedCount;
  final List<String> sentPhones;
  final List<String> failedPhones;

  bool get anySent => sentCount > 0;
}

abstract interface class SosSmsSender {
  bool get isSupported;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<SosSmsBatchResult> sendSmsBatch({
    required List<String> phones,
    required String message,
  });
}

/// Pengirim SMS darurat langsung tanpa klik lewat Android `SmsManager`.
/// Pada iOS dan desktop, [isSupported] bernilai `false` sehingga alur otomatis
/// beralih ke fallback `sms:` sheet bawaan sistem.
class MethodChannelSosSmsSender implements SosSmsSender {
  const MethodChannelSosSmsSender();

  static const MethodChannel _channel =
      MethodChannel('id.nama.nama_app/sos_sms');

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasSmsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestSmsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SosSmsBatchResult> sendSmsBatch({
    required List<String> phones,
    required String message,
  }) async {
    if (!isSupported) {
      return SosSmsBatchResult(
        supported: false,
        failedCount: phones.length,
        failedPhones: phones,
      );
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'sendSmsBatch',
        <String, Object?>{
          'phones': phones,
          'message': message,
        },
      );
      if (raw == null) {
        return SosSmsBatchResult(
          supported: true,
          failedCount: phones.length,
          failedPhones: phones,
        );
      }
      final sentPhones = (raw['sentPhones'] as List<Object?>? ?? const <Object?>[])
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final failedPhones =
          (raw['failedPhones'] as List<Object?>? ?? const <Object?>[])
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
      return SosSmsBatchResult(
        supported: true,
        permissionDenied: raw['permissionDenied'] == true,
        sentCount: (raw['sentCount'] as num?)?.toInt() ?? sentPhones.length,
        failedCount: (raw['failedCount'] as num?)?.toInt() ?? failedPhones.length,
        sentPhones: sentPhones,
        failedPhones: failedPhones,
      );
    } catch (_) {
      return SosSmsBatchResult(
        supported: true,
        failedCount: phones.length,
        failedPhones: phones,
      );
    }
  }
}

/// Meminta izin `SEND_SMS` dengan penjelasan singkat yang jelas saat pengguna
/// menambahkan kontak darurat atau membuka layar SOS.
Future<bool> promptEmergencySmsPermission(
  BuildContext context, {
  SosSmsSender? sender,
  bool onlyOncePerInstall = false,
}) async {
  final resolved = sender ?? const MethodChannelSosSmsSender();
  if (!resolved.isSupported) return false;
  if (await resolved.hasPermission()) return true;

  if (onlyOncePerInstall) {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kSmsRationalePromptedKey) == true) {
        return false;
      }
      await prefs.setBool(_kSmsRationalePromptedKey, true);
    } catch (_) {}
  }

  if (!context.mounted) return false;

  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Izinkan SMS darurat otomatis?'),
      content: const Text(
        'Saat tombol SOS ditahan tanpa internet, Hiqeo langsung mengirim SMS '
        'berisi koordinat GPS, elevasi, sisa baterai, dan tautan Google Maps '
        'ke kontak daruratmu tanpa perlu menekan kirim lagi. Izin ini hanya '
        'dipakai ketika SOS diaktifkan.',
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('sms-rationale-later'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Nanti saja'),
        ),
        FilledButton(
          key: const ValueKey<String>('sms-rationale-allow'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Izinkan SMS'),
        ),
      ],
    ),
  );

  if (agreed != true) return false;
  return resolved.requestPermission();
}
