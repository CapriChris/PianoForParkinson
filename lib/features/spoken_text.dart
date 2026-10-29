import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_theme.dart';

/// The voice action stays immediately before the first word, including when
/// the text wraps, and has a separate accessible tap target.
class SpokenText extends StatefulWidget {
  const SpokenText({
    super.key,
    required this.c,
    required this.text,
    this.style,
    this.enabled = true,
    this.compact = false,
    this.circularAligned = false,
    this.actionOnly = false,
  });
  final AppController c;
  final String text;
  final TextStyle? style;
  final bool enabled;
  final bool compact;
  final bool circularAligned;
  final bool actionOnly;

  @override
  State<SpokenText> createState() => _SpokenTextState();
}

class _SpokenTextState extends State<SpokenText> with WidgetsBindingObserver {
  final owner = Object();
  AppController get c => widget.c;
  void stop() => unawaited(c.stopSpeech(owner: owner).catchError((_) {}));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void didUpdateWidget(SpokenText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || !widget.enabled) stop();
  }

  @override
  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = ValueListenableBuilder<Object?>(
      valueListenable: c.activeSpeech,
      builder: (context, active, _) {
        final playing = identical(active, owner);
        return IconButton(
          style: IconButton.styleFrom(
            backgroundColor: playing ? context.qin.primary : context.qin.soft,
            foregroundColor: playing
                ? context.qin.onPrimary
                : context.qin.primary,
            shape: widget.circularAligned ? const CircleBorder() : null,
          ),
          tooltip: playing
              ? c.text('停止语音说明', 'Stop spoken guidance')
              : c.text('播放语音说明', 'Play spoken guidance'),
          onPressed: widget.enabled
              ? () => playing
                    ? c.stopSpeech(owner: owner)
                    : c.speak(widget.text, owner: owner)
              : null,
          icon: Icon(playing ? Icons.stop : Icons.volume_up_outlined),
        );
      },
    );
    if (widget.actionOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              c.text('朗读说明', 'Read instructions'),
              style: widget.style ?? Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      );
    }
    double topPadding = widget.compact ? 8 : 12;
    if (widget.circularAligned) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'M',
          style: widget.style ?? Theme.of(context).textTheme.bodyMedium,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      topPadding = ((60 - painter.preferredLineHeight) / 2).clamp(0.0, 30.0);
      painter.dispose();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        action,
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: topPadding,
              bottom: widget.compact ? 4 : 8,
            ),
            child: Text(widget.text, style: widget.style),
          ),
        ),
      ],
    );
  }
}
