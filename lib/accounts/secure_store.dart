import 'package:flutter/services.dart';

/// Only ciphertext lives on disk. Implementations are injectable for race tests.
abstract interface class SecureAccountStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AndroidSecureAccountStore implements SecureAccountStore {
  static const channel = MethodChannel('qin/account-vault/v1');

  @override
  Future<String?> read(String key) =>
      channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      channel.invokeMethod<void>('delete', {'key': key});
}
