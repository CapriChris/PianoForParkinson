import 'package:flutter/widgets.dart';

class SpeechNavigationObserver extends NavigatorObserver {
  SpeechNavigationObserver(this.stop);
  final VoidCallback stop;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => stop();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => stop();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      stop();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => stop();
}
