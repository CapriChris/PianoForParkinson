import 'package:flutter/widgets.dart';

/// `inactive` alone can be a banner/volume overlay, not an actual departure.
/// Android reports input takeover separately through WINDOW_FOCUS_LOST.
bool trainingIsHidden(AppLifecycleState state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;
