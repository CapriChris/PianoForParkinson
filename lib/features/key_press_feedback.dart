import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/qin_theme.dart';

/// Paints all key particles after the row's faces, including adjacent keys.
class KeyParticleLayer extends StatefulWidget {
  const KeyParticleLayer({super.key, required this.child});

  final Widget child;

  @override
  State<KeyParticleLayer> createState() => _KeyParticleLayerState();
}

class _KeyParticleLayerState extends State<KeyParticleLayer> {
  final keys = <KeyPressFeedbackState>{};
  final repaint = ValueNotifier(0);
  late final painter = _KeyParticleRowPainter(this);

  void invalidate() => repaint.value++;

  void add(KeyPressFeedbackState key) {
    keys.add(key);
    key.animation.addListener(invalidate);
    key.depression.addListener(invalidate);
    invalidate();
  }

  void remove(KeyPressFeedbackState key) {
    keys.remove(key);
    key.animation.removeListener(invalidate);
    key.depression.removeListener(invalidate);
    invalidate();
  }

  @override
  void dispose() {
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _KeyParticleScope(
    layer: this,
    child: RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: painter,
        child: RepaintBoundary(child: widget.child),
      ),
    ),
  );
}

class _KeyParticleScope extends InheritedWidget {
  const _KeyParticleScope({required this.layer, required super.child});

  final _KeyParticleLayerState layer;

  @override
  bool updateShouldNotify(_KeyParticleScope oldWidget) =>
      layer != oldWidget.layer;
}

class _KeyParticleRowPainter extends CustomPainter {
  _KeyParticleRowPainter(this.layer) : super(repaint: layer.repaint);

  final _KeyParticleLayerState layer;

  @override
  void paint(Canvas canvas, Size size) {
    final row = layer.context.findRenderObject()! as RenderBox;
    const padding = KeyParticlesPainter.padding;
    for (final key in layer.keys) {
      final progress = key.animation.value;
      if (progress <= 0 || progress >= 1) continue;
      final box = key.context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      canvas.save();
      canvas.transform(box.getTransformTo(row).storage);
      canvas.translate(-padding, -padding);
      key.particlePainter.paint(
        canvas,
        Size(box.size.width + 2 * padding, box.size.height + 2 * padding),
      );
      canvas.restore();
    }
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_KeyParticleRowPainter oldDelegate) =>
      layer != oldDelegate.layer;
}

/// Local visual feedback; it neither handles input nor schedules sound.
class KeyPressFeedback extends StatefulWidget {
  const KeyPressFeedback({
    super.key,
    required this.child,
    required this.color,
    this.pulse,
    this.resetToken,
    this.enabled = true,
    this.pressed = false,
  });
  final Widget child;
  final Color color;
  final Object? pulse, resetToken;
  final bool enabled, pressed;

  @override
  KeyPressFeedbackState createState() => KeyPressFeedbackState();
}

class KeyPressFeedbackState extends State<KeyPressFeedback>
    with TickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final depression = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 85),
    reverseDuration: const Duration(milliseconds: 120),
  );
  _KeyParticleLayerState? _particleLayer;
  late KeyParticlesPainter particlePainter = KeyParticlesPainter(
    animation,
    widget.color,
    depression,
  );
  bool motionAllowed = false, initialized = false;
  bool get held => widget.enabled && widget.pressed;
  bool get enabled => widget.enabled && motionAllowed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layer = context
        .dependOnInheritedWidgetOfExactType<_KeyParticleScope>()
        ?.layer;
    if (layer != _particleLayer) {
      _particleLayer?.remove(this);
      _particleLayer = layer;
      layer?.add(this);
    }
    motionAllowed =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!enabled) {
      animation.reset();
      depression.value = held ? 1 : 0;
    }
    if (!initialized) {
      initialized = true;
      depression.value = held ? 1 : 0;
      if (enabled && widget.pulse != null) animation.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(KeyPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color) {
      particlePainter = KeyParticlesPainter(
        animation,
        widget.color,
        depression,
      );
      _particleLayer?.invalidate();
    }
    final reset = widget.resetToken != oldWidget.resetToken;
    final strike = widget.pulse != null && widget.pulse != oldWidget.pulse;
    if (!enabled || reset) {
      animation.reset();
      depression.value = !reset && held ? 1 : 0;
    } else {
      if (strike) animation.forward(from: 0);
      if (held) {
        // Repeated demonstration notes strike again even on the same key.
        if (strike) {
          depression.forward(from: 0);
        } else {
          depression.forward();
        }
      } else {
        depression.reverse();
      }
    }
  }

  @override
  void deactivate() {
    _particleLayer?.remove(this);
    _particleLayer = null;
    super.deactivate();
  }

  @override
  void dispose() {
    animation.dispose();
    depression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.qin;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(palette.disabled, palette.edge, .42),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: depression,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: widget.child,
          ),
          builder: (context, child) {
            final depth = Curves.easeOutCubic.transform(depression.value);
            return Transform.translate(
              key: const ValueKey('key-face-translation'),
              offset: Offset(0, 5 * depth),
              transformHitTests: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: palette.ink.withValues(alpha: .14 - .08 * depth),
                      offset: Offset(0, 3 * (1 - depth)),
                      blurRadius: 4 * (1 - depth),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
        ),
        if (_particleLayer == null)
          Positioned(
            left: -KeyParticlesPainter.padding,
            right: -KeyParticlesPainter.padding,
            top: -KeyParticlesPainter.padding,
            bottom: -KeyParticlesPainter.padding,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(painter: particlePainter),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class KeyParticlesPainter extends CustomPainter {
  KeyParticlesPainter(this.animation, this.color, this.depression)
    : super(repaint: Listenable.merge([animation, depression]));
  static const padding = 22.0;
  final Animation<double> animation, depression;
  final Color color;

  Rect faceRect(Size size) => Rect.fromLTWH(
    padding,
    padding + 5 * Curves.easeOutCubic.transform(depression.value),
    math.max(0, size.width - padding * 2),
    math.max(0, size.height - padding * 2 - 6),
  );

  /// Each point starts outside the face and travels away from its nearest edge.
  Offset particleCenter(Size size, int index) {
    final face = faceRect(size);
    final along = ((index % 3) + 1) / 4;
    final travel = Curves.easeOutCubic.transform(animation.value);
    final distance = 4 + (8 + index % 3 * 2) * travel;
    return switch (index ~/ 3) {
      0 => Offset(face.left + face.width * along, face.top - distance),
      1 => Offset(face.right + distance, face.top + face.height * along),
      2 => Offset(face.left + face.width * along, face.bottom + distance),
      _ => Offset(face.left - distance, face.top + face.height * along),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1 || size.isEmpty) return;
    final paint = Paint()..color = color.withValues(alpha: (1 - t) * .88);
    for (var i = 0; i < 12; i++) {
      final center = particleCenter(size, i);
      final radius = (2.3 + (i % 3) * .45) * (1 - .3 * t);
      if (i.isEven) {
        final diamond = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
      } else {
        canvas.drawCircle(center, radius * .75, paint);
      }
    }
  }

  @override
  bool shouldRepaint(KeyParticlesPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.animation != animation ||
      oldDelegate.depression != depression;
}
