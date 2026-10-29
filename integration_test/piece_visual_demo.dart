// Manual visual QA entry point; never use the user's normal application ID.
import 'package:flutter/widgets.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';

Future<void> main() async {
  if (!const bool.fromEnvironment('ISOLATED_TEST_PACKAGE')) {
    throw StateError('Visual QA requires the isolated validation package');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final c = AppController(databaseSubdirectory: 'piece-visual-0129');
  runApp(PianoApp(controller: c));
  await c.initialize();
  if (c.error == null) await c.updateSettings(locale: 'zh-Hans', onboard: true);
}
