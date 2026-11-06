import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import '../domain/contracts.dart';

const accountApiBase = String.fromEnvironment(
  'PD_API_BASE',
  defaultValue: 'https://ccqspace.site/pd-rehab/api',
);

class AccountSession {
  AccountSession({
    required this.user,
    required this.patient,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.deviceId,
    required this.base,
  });
  final Json user, patient;
  final String refreshToken, deviceId, base;
  final DateTime refreshExpiresAt;
  String get userId => user['id'] as String;
  String get patientId => patient['id'] as String;
  String get directory =>
      'account-${sha256.convert(utf8.encode('$base\n$userId'))}';
  bool get expired => !refreshExpiresAt.isAfter(DateTime.now().toUtc());

  factory AccountSession.parse(Json json) {
    final user = Map<String, dynamic>.from(json['user'] as Map);
    final patient = Map<String, dynamic>.from(json['patient'] as Map);
    if (user['role'] != 'PATIENT' ||
        !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch('${user['id']}') ||
        !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch('${patient['id']}') ||
        json['base'] != accountApiBase.trim().replaceFirst(RegExp(r'/$'), '') ||
        (json['refresh_token'] as String).length < 32) {
      throw const FormatException('Invalid account session');
    }
    return AccountSession(
      user: user,
      patient: patient,
      refreshToken: json['refresh_token'] as String,
      refreshExpiresAt: DateTime.parse(json['refresh_expires_at'] as String)
          .toUtc(),
      deviceId: json['device_id'] as String,
      base: json['base'] as String,
    );
  }

  Json toJson() => {
    'user': user,
    'patient': patient,
    'refresh_token': refreshToken,
    'refresh_expires_at': refreshExpiresAt.toIso8601String(),
    'device_id': deviceId,
    'base': base,
  };
}

class AccountVault {
  static const channel = MethodChannel('piano_companion/accounts/v1');
  Future<AccountSession?> read() async {
    final value = await channel.invokeMethod<String>('read');
    return value == null
        ? null
        : AccountSession.parse(jsonDecode(value) as Json);
  }

  Future<void> write(AccountSession session) => channel.invokeMethod<void>(
    'write',
    {'value': jsonEncode(session.toJson())},
  );
  Future<void> clear() => channel.invokeMethod<void>('clear');
  Future<bool> acquire() async =>
      await channel.invokeMethod<bool>('acquire') == true;
  Future<void> release() => channel.invokeMethod<void>('release');
  Future<void> scheduleSync() => channel.invokeMethod<void>('scheduleSync');
  Future<void> cancelSync() => channel.invokeMethod<void>('cancelSync');
}
