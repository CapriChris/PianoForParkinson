import 'package:flutter/material.dart';

/// App text size is relative to the device's text scaling.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.percent);
  final TextScaler system;
  final int percent;

  @override
  double scale(double fontSize) => system.scale(fontSize) * percent / 100;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.percent == percent;
  @override
  int get hashCode => Object.hash(system, percent);
}

/// Music notation and keys retain the device's original text scaling.
TextScaler musicTextScalerOf(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler is AppTextScaler ? scaler.system : scaler;
}

class MusicTextScale extends StatelessWidget {
  const MusicTextScale({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: musicTextScalerOf(context)),
      child: child,
    );
  }
}
