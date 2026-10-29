import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/piano_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(PianoApp(controller: controller));
  unawaited(controller.initialize());
}
