import 'dart:async';

import 'package:flutter/material.dart';

import 'accounts/account_controller.dart';
import 'accounts/account_pages.dart';
import 'accounts/background_sync.dart';

@pragma('vm:entry-point')
void accountBackgroundMain() {
  unawaited(runAccountBackgroundSync());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final accounts = AccountController();
  runApp(AccountApplication(accounts: accounts));
  unawaited(accounts.restore());
}
