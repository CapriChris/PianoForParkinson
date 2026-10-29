import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    if (!RegExp(r'^qinban-0\.1\.14-(portrait-entry|touch-check)$')
        .hasMatch(name)) {
      return false;
    }
    await Directory('screenshots').create(recursive: true);
    await File('screenshots/$name.png').writeAsBytes(bytes);
    return true;
  },
);
