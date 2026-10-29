import 'package:flutter/material.dart';

import '../domain/contracts.dart';
import 'cognitive_cue.dart';
import 'key_mark.dart';
import '../ui/note_label.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/note_colors.dart';
import 'key_press_feedback.dart';

double practiceKeyHeight(double bodyHeight) =>
    (bodyHeight * .38).clamp(96.0, 144.0);

class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({
    super.key,
    required this.count,
    required this.active,
    required this.onDown,
    required this.onUp,
    this.highlighted,
    this.highlightedKeys = const {},
    this.onMove,
    this.onLayout,
    this.textScale = 1000,
    this.showShapes = false,
    this.locked = false,
    this.highlightWhileLocked = false,
    this.interruptions,
    this.onInterrupted,
    this.labels,
    this.markShapes,
    this.splitZones,
    this.noteDegrees,
    this.showKeyMarks = true,
    this.demonstratingKeys = const {},
    this.demonstrationPulse,
  });
  final int count, textScale;
  final List<String>? labels;
  final List<int>? markShapes;
  final bool? splitZones;
  final bool showShapes, locked, highlightWhileLocked;
  final bool showKeyMarks;
  final List<int>? noteDegrees;
  final Set<int> demonstratingKeys;
  final Object? demonstrationPulse;
  final Listenable? interruptions;
  final VoidCallback? onInterrupted;
  final Set<int> active;
  final int? highlighted;
  final Set<int> highlightedKeys;
  final void Function(int pointer, int? key, bool disabled, Json coordinates)
  onDown;
  final void Function(int pointer, int? key, bool cancel, Json coordinates)
  onUp;
  final void Function(int pointer, Json coordinates)? onMove;
  final void Function(Json snapshot)? onLayout;
  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  @override
  void initState() {
    super.initState();
    widget.interruptions?.addListener(interrupted);
  }

  @override
  void didUpdateWidget(PianoKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.demonstratingKeys.isNotEmpty &&
        widget.demonstratingKeys.isEmpty) {
      pressPulses.clear();
    }
    if (oldWidget.interruptions != widget.interruptions) {
      oldWidget.interruptions?.removeListener(interrupted);
      widget.interruptions?.addListener(interrupted);
    }
  }

  void interrupted() {
    setState(() {
      bindings.clear();
      lastMove.clear();
      feedbackEpoch++;
    });
    widget.onInterrupted?.call();
  }

  @override
  void dispose() {
    widget.interruptions?.removeListener(interrupted);
    super.dispose();
  }

  final boxKey = GlobalKey();
  final bindings = <int, int?>{};
  final lastMove = <int, ({Offset point, int time})>{};
  final pressPulses = <int, int>{};
  int feedbackEpoch = 0;
  String? signature;
  int semanticPointer = -1;
  double width = 1;
  bool get splitZones => widget.splitZones ?? widget.count == 6;
  double get keyWidth =>
      (width - (widget.count - 1) * 8 - (splitZones ? 16 : 0)) / widget.count;
  double keyStart(int i) =>
      i * (keyWidth + 8) + (splitZones && i >= 3 ? 16 : 0);
  bool lit(int i) =>
      widget.highlighted == i || widget.highlightedKeys.contains(i);
  bool pressed(int i) =>
      !widget.locked &&
      widget.active.contains(i) &&
      bindings.values.contains(i);
  bool visibleTarget(int i) =>
      lit(i) && (!widget.locked || widget.highlightWhileLocked);
  Color keySurface(BuildContext context, int i) => pressed(i)
      ? widget.noteDegrees == null
            ? context.qin.primary
            : NoteColors.degree(widget.noteDegrees![i]).pressed
      : widget.noteDegrees != null
      ? context.qin.surface
      : visibleTarget(i)
      ? context.qin.soft
      : widget.locked || !widget.active.contains(i)
      ? context.qin.disabled
      : context.qin.surface;
  Color keyInk(BuildContext context, int i) => pressed(i)
      ? widget.noteDegrees == null
            ? context.qin.onPrimary
            : context.qin.highContrast
            ? context.qin.ink
            : NoteColors.degree(widget.noteDegrees![i]).ink
      : widget.active.contains(i) && (!widget.locked || visibleTarget(i))
      ? context.qin.ink
      : context.qin.muted;
  Json coordinates(Offset point, int timestamp) => {
    'x_norm': (point.dx / width * 1000000).round(),
    'y_norm':
        (point.dy /
                (boxKey.currentContext!.findRenderObject() as RenderBox)
                    .size
                    .height *
                1000000)
            .round(),
    'raw_timestamp_us': timestamp,
    'device_kind': 'TOUCH',
    'layout_snapshot_id': signature,
  };
  @override
  Widget build(BuildContext context) => MusicTextScale(
    child: LayoutBuilder(
      builder: (context, constraints) {
        width = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.onLayout == null) return;
          final box = boxKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          final origin = box.localToGlobal(Offset.zero),
              size = MediaQuery.sizeOf(context);
          final geometry = {
            'canvas_width_dp': size.width.round(),
            'canvas_height_dp': size.height.round(),
            'text_scale_permille': widget.textScale,
            'layout_id': splitZones
                ? 'DUAL_ZONE_SIX_KEYS'
                : widget.count == 2
                ? 'ALTERNATE_TWO_KEYS'
                : widget.count == 5
                ? 'COMPACT'
                : 'WIDE',
            'layout_version': 1,
            'coordinate_unit': 'MILLIDP',
            'keyboard_rect': [
              (origin.dx * 1000).round(),
              (origin.dy * 1000).round(),
              (box.size.width * 1000).round(),
              (box.size.height * 1000).round(),
            ],
            'keys': [
              for (var i = 0; i < widget.count; i++)
                {
                  'key_id': i,
                  'hit_rect': [
                    ((origin.dx + keyStart(i)) * 1000).round(),
                    (origin.dy * 1000).round(),
                    (keyWidth * 1000).round(),
                    (box.size.height * 1000).round(),
                  ],
                },
            ],
          };
          final next = digest(geometry);
          if (next != signature) {
            signature = next;
            widget.onLayout!({...geometry, 'snapshot_id': next});
          }
        });
        return Listener(
          key: boxKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (widget.locked) return;
            int? key;
            for (var i = 0; i < widget.count; i++) {
              if (e.localPosition.dx >= keyStart(i) &&
                  e.localPosition.dx < keyStart(i) + keyWidth) {
                key = i;
                break;
              }
            }
            bindings[e.pointer] = key;
            if (key != null && widget.active.contains(key)) {
              pressPulses[key] = (pressPulses[key] ?? 0) + 1;
            }
            widget.onDown(
              e.pointer,
              key,
              key != null && !widget.active.contains(key),
              coordinates(e.localPosition, e.timeStamp.inMicroseconds),
            );
            setState(() {});
          },
          onPointerMove: (e) {
            final previous = lastMove[e.pointer];
            final time = e.timeStamp.inMicroseconds;
            if (previous == null ||
                (e.localPosition - previous.point).distance >= 2 ||
                time - previous.time >= 50000) {
              lastMove[e.pointer] = (point: e.localPosition, time: time);
              widget.onMove?.call(
                e.pointer,
                coordinates(e.localPosition, time),
              );
            }
          },
          onPointerUp: (e) {
            if (!bindings.containsKey(e.pointer)) return;
            final key = bindings.remove(e.pointer);
            lastMove.remove(e.pointer);
            widget.onUp(
              e.pointer,
              key,
              false,
              coordinates(e.localPosition, e.timeStamp.inMicroseconds),
            );
            setState(() {});
          },
          onPointerCancel: (e) {
            final key = bindings.remove(e.pointer);
            lastMove.remove(e.pointer);
            widget.onUp(
              e.pointer,
              key,
              true,
              coordinates(e.localPosition, e.timeStamp.inMicroseconds),
            );
            setState(() {});
          },
          child: Row(
            children: [
              for (var i = 0; i < widget.count; i++) ...[
                if (i > 0) SizedBox(width: splitZones && i == 3 ? 24 : 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    enabled: !widget.locked && widget.active.contains(i),
                    selected: visibleTarget(i),
                    label:
                        '${Localizations.localeOf(context).languageCode == 'zh' ? '琴键' : 'Key'} ${widget.labels?[i] ?? '${i + 1}'}',
                    onTap: !widget.locked && widget.active.contains(i)
                        ? () {
                            final p = semanticPointer--;
                            setState(
                              () => pressPulses[i] = (pressPulses[i] ?? 0) + 1,
                            );
                            widget.onDown(p, i, false, {
                              'device_kind': 'ACCESSIBILITY',
                            });
                            widget.onUp(p, i, false, {
                              'device_kind': 'ACCESSIBILITY',
                            });
                          }
                        : null,
                    child: KeyPressFeedback(
                      key: ValueKey('key-feedback-$i'),
                      enabled:
                          !widget.locked ||
                          widget.demonstratingKeys.contains(i),
                      resetToken: feedbackEpoch,
                      pulse: widget.demonstratingKeys.contains(i)
                          ? (widget.demonstrationPulse, i)
                          : pressPulses[i],
                      pressed:
                          pressed(i) || widget.demonstratingKeys.contains(i),
                      color: widget.noteDegrees == null
                          ? context.qin.primary
                          : NoteColors.degree(widget.noteDegrees![i]).fill,
                      child: Container(
                        decoration: BoxDecoration(
                          color: keySurface(context, i),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.noteDegrees != null
                                ? context.qin.highContrast
                                      ? context.qin.ink
                                      : NoteColors.degree(
                                          widget.noteDegrees![i],
                                        ).fill
                                : visibleTarget(i)
                                ? context.qin.primary
                                : context.qin.edge,
                            width: visibleTarget(i)
                                ? 3
                                : context.qin.highContrast ||
                                      widget.noteDegrees != null
                                ? 2
                                : 1,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: NoteLabel(
                                  widget.labels?[i] ?? '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: keyInk(context, i),
                                  ),
                                ),
                              ),
                              if (widget.showKeyMarks &&
                                  widget.showShapes &&
                                  i < 3)
                                ShapeMark(
                                  shape: i,
                                  size: 24,
                                  color: keyInk(context, i),
                                )
                              else if (widget.showKeyMarks &&
                                  widget.textScale <= 1500)
                                KeyMark(
                                  shape: widget.markShapes?[i] ?? i,
                                  color: keyInk(context, i),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
