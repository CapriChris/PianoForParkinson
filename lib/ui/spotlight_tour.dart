import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/app_controller.dart';

enum SpotlightShape { circle, roundedRectangle, none }

class SpotlightStep {
  const SpotlightStep({
    this.target,
    required this.title,
    required this.message,
    this.prepare,
    this.advanceOnTap = true,
    this.shape = SpotlightShape.circle,
    this.padding = 8,
    this.borderRadius = 18,
  });
  final GlobalKey? target;
  final SpotlightShape shape;
  final double padding, borderRadius;
  final String title, message;
  final Future<void> Function()? prepare;
  final bool advanceOnTap;
}

/// Lives inside its route: drawers and other routes can open above the guide.
class SpotlightTour extends StatefulWidget {
  const SpotlightTour({
    super.key,
    required this.c,
    required this.preferenceKey,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.onFinish,
  });
  final AppController c;
  final String preferenceKey;
  final List<SpotlightStep> steps;
  final Widget child;
  final bool enabled;
  final Future<void> Function()? onFinish;
  @override
  State<SpotlightTour> createState() => _SpotlightTourState();
}

class _SpotlightTourState extends State<SpotlightTour>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final root = GlobalKey();
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool active = false, moving = false, finishing = false;
  int index = 0, epoch = 0;
  Rect? hole;
  bool get eligible =>
      widget.enabled &&
      widget.c.settings['spotlight_guides_enabled'] == true &&
      widget.c.settings[widget.preferenceKey] != true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(pointer);
    WidgetsBinding.instance.addPostFrameCallback((_) => begin());
  }

  @override
  void didUpdateWidget(SpotlightTour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!active && eligible) {
      finishing = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => begin());
    }
  }

  @override
  void didChangeMetrics() {
    if (active) WidgetsBinding.instance.addPostFrameCallback((_) => locate());
  }

  Future<void> begin() async {
    if (!mounted ||
        active ||
        finishing ||
        !eligible ||
        widget.steps.isEmpty ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    active = true;
    moving = false;
    if (!MediaQuery.disableAnimationsOf(context)) pulse.repeat(reverse: true);
    await select(0);
  }

  Future<void> select(int next) async {
    if (moving || !mounted) return;
    moving = true;
    final token = ++epoch;
    setState(() {
      index = next;
      hole = null;
    });
    try {
      await widget.steps[index].prepare?.call();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != epoch) return;
      final target = widget.steps[index].target?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: Duration.zero,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted && token == epoch) locate();
    } finally {
      if (mounted && token == epoch) setState(() => moving = false);
    }
  }

  RRect? get cutout => hole == null
      ? null
      : RRect.fromRectAndRadius(
          hole!,
          Radius.circular(
            widget.steps[index].shape == SpotlightShape.circle
                ? hole!.width / 2
                : widget.steps[index].borderRadius,
          ),
        );

  void locate() {
    if (!mounted || !active) return;
    final step = widget.steps[index];
    if (step.shape == SpotlightShape.none) {
      setState(() => hole = null);
      return;
    }
    final target = widget.steps[index].target?.currentContext
        ?.findRenderObject();
    final host = root.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        host is! RenderBox ||
        !target.attached ||
        !target.hasSize) {
      setState(() => hole = null);
      return;
    }
    if (step.shape == SpotlightShape.roundedRectangle) {
      final origin = target.localToGlobal(Offset.zero, ancestor: host);
      setState(() => hole = (origin & target.size).inflate(step.padding));
    } else {
      final center = target.localToGlobal(
        target.size.center(Offset.zero),
        ancestor: host,
      );
      final radius = math.min(
        76.0,
        math.max(30.0, target.size.shortestSide / 2 + 10),
      );
      setState(() => hole = Rect.fromCircle(center: center, radius: radius));
    }
  }

  void pointer(PointerEvent event) {
    if (!active ||
        moving ||
        event is! PointerUpEvent ||
        !widget.steps[index].advanceOnTap ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final host = root.currentContext?.findRenderObject();
    if (host is! RenderBox || hole == null) return;
    final local = host.globalToLocal(event.position);
    if (cutout?.contains(local) == true) {
      final token = epoch;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 260), () {
          if (mounted && active && token == epoch && !moving) next();
        }),
      );
    }
  }

  void next() {
    if (index + 1 == widget.steps.length) {
      unawaited(finish());
    } else {
      unawaited(select(index + 1));
    }
  }

  Future<void> finish() async {
    if (finishing) return;
    finishing = true;
    moving = false;
    ++epoch;
    pulse.stop();
    try {
      await widget.c.updateSettings(
        values: {...widget.c.settings, widget.preferenceKey: true},
      );
      if (!mounted) return;
      setState(() => active = false);
      await widget.onFinish?.call();
    } catch (_) {
      if (mounted) {
        finishing = false;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              widget.c.text(
                '引导进度未保存，请重试。',
                'Could not save the guide. Please retry.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    ++epoch;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(pointer);
    WidgetsBinding.instance.removeObserver(this);
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && active) unawaited(finish());
    },
    child: Stack(
      key: root,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (active)
          Positioned.fill(
            child: _OutsideCircle(
              hole: cutout,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (_, _) => CustomPaint(
                    painter: _SpotlightPainter(cutout, pulse.value),
                  ),
                ),
              ),
            ),
          ),
        if (active)
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final top =
                      hole == null ||
                      hole!.center.dy > constraints.maxHeight * .5;
                  return Align(
                    alignment: widget.steps[index].shape == SpotlightShape.none
                        ? Alignment.center
                        : top
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 480,
                          maxHeight:
                              widget.steps[index].shape == SpotlightShape.none
                              ? math.max(0, constraints.maxHeight - 32)
                              : constraints.maxHeight * .48,
                        ),
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            '${index + 1}/${widget.steps.length} · ${widget.steps[index].title}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(widget.steps[index].message),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    TextButton(
                                      key: const ValueKey('spotlight-skip'),
                                      onPressed: finishing ? null : finish,
                                      child: Text(
                                        widget.c.text('跳过引导', 'Skip guide'),
                                      ),
                                    ),
                                    if (index > 0)
                                      TextButton(
                                        onPressed: moving
                                            ? null
                                            : () => select(index - 1),
                                        child: Text(
                                          widget.c.text('上一步', 'Back'),
                                        ),
                                      ),
                                    FilledButton(
                                      key: const ValueKey('spotlight-next'),
                                      onPressed: moving || finishing
                                          ? null
                                          : next,
                                      child: Text(
                                        widget.c.text(
                                          index + 1 == widget.steps.length
                                              ? '完成'
                                              : '下一步',
                                          index + 1 == widget.steps.length
                                              ? 'Done'
                                              : 'Next',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    ),
  );
}

class _OutsideCircle extends SingleChildRenderObjectWidget {
  const _OutsideCircle({required this.hole, required super.child});
  final RRect? hole;
  @override
  RenderObject createRenderObject(BuildContext context) => _CircleHitTest(hole);
  @override
  void updateRenderObject(BuildContext context, _CircleHitTest renderObject) =>
      renderObject.hole = hole;
}

class _CircleHitTest extends RenderProxyBox {
  _CircleHitTest(this.hole);
  RRect? hole;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hole?.contains(position) == true) {
      return false;
    }
    super.hitTest(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole, this.pulse);
  final RRect? hole;
  final double pulse;
  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()..addRect(Offset.zero & size);
    if (hole != null) mask.addRRect(hole!);
    mask.fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: .68));
    if (hole != null) {
      canvas.drawRRect(
        hole!,
        Paint()
          ..color = Colors.white.withValues(alpha: .65 + pulse * .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + pulse * 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse;
}
