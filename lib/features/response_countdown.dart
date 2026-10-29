import 'package:flutter/material.dart';

import '../ui/qin_theme.dart';

/// A compact, stable response clock; kept away from the keyboard hit area.
class ResponseCountdown extends StatelessWidget {
  const ResponseCountdown({
    super.key,
    required this.remainingUs,
    required this.fraction,
    required this.chinese,
  });
  final int remainingUs;
  final double fraction;
  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final seconds = (remainingUs / 1000000).toStringAsFixed(1);
    final clock = <Widget>[
      Icon(
        Icons.hourglass_bottom_rounded,
        size: 18,
        color: context.qin.primary,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          chinese ? '本项剩余' : 'Time left',
          style: TextStyle(fontSize: 18, color: context.qin.muted),
        ),
      ),
      Text(
        chinese ? '$seconds 秒' : '$seconds s',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ];
    Widget track() => LinearProgressIndicator(
      value: fraction,
      minHeight: 4,
      color: context.qin.primary,
      backgroundColor: context.qin.disabled,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          key: const ValueKey('response-countdown'),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.qin.soft,
            border: Border.all(color: context.qin.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (context, size) =>
                size.maxWidth >= 280 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.25
                ? Row(
                    children: [
                      ...clock,
                      const SizedBox(width: 12),
                      SizedBox(width: 72, child: track()),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: clock),
                      const SizedBox(height: 6),
                      track(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
