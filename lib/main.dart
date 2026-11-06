import 'package:flutter/material.dart';

import 'accounts/account_app.dart';
import 'accounts/background_sync.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the native WorkManager entry point reachable in AOT builds.
  accountSyncBackgroundMain;
  runApp(const AccountApplication());
}
