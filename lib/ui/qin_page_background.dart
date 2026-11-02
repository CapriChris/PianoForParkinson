import 'package:flutter/material.dart';

import 'qin_theme.dart';

enum QinBackgroundTreatment { softened, clear, softenedWithTextGradient }

/// Decorative art belongs to the entire page, independently of its header.
class QinPageBackground extends StatelessWidget {
  const QinPageBackground({
    super.key,
    required this.asset,
    required this.aspectRatio,
    this.treatment = QinBackgroundTreatment.softened,
    this.textRegionHeight,
    this.fill = false,
  });
  final String asset;
  final double aspectRatio;
  final QinBackgroundTreatment treatment;
  final double? textRegionHeight;
  final bool fill;
  @override
  Widget build(BuildContext context) {
    if (context.qin.highContrast) return const SizedBox.shrink();
    final textGradient =
        treatment == QinBackgroundTreatment.softenedWithTextGradient;
    Widget image = Image.asset(
      asset,
      fit: fill ? BoxFit.cover : BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (treatment != QinBackgroundTreatment.clear) {
      image = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: const [Colors.transparent, Colors.white, Colors.white],
          stops: [0, textGradient ? .18 : .5, 1],
        ).createShader(bounds),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: textGradient
                ? const [0, .06, .85, 1]
                : const [0, .12, .65, 1],
          ).createShader(bounds),
          child: image,
        ),
      );
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (fill)
            Positioned.fill(child: image)
          else
            Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(aspectRatio: aspectRatio, child: image),
            ),
          if (textGradient && textRegionHeight != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Keep the scrim strong behind every line, then fade below the
              // header rather than fading through the subtitle itself.
              height: textRegionHeight! + 48,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0, textRegionHeight! / bounds.height, 1],
                ).createShader(bounds),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        context.qin.background.withValues(alpha: .90),
                        context.qin.background.withValues(alpha: .70),
                        context.qin.background.withValues(alpha: .0),
                        context.qin.background.withValues(alpha: .0),
                      ],
                      stops: const [0, .5, .82, 1],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Only card backgrounds become translucent; text and controls stay opaque.
class QinPageSurface extends StatelessWidget {
  const QinPageSurface({super.key, required this.child, this.opacity = .88});
  final Widget child;
  final double opacity;
  @override
  Widget build(BuildContext context) {
    final alpha = context.qin.highContrast ? 1.0 : opacity;
    return _QinSurfaceOpacity(
      opacity: alpha,
      child: Theme(
        data: Theme.of(context).copyWith(
          cardTheme: Theme.of(context).cardTheme
              .copyWith(color: context.qin.surface.withValues(alpha: alpha)),
        ),
        child: child,
      ),
    );
  }
}

class _QinSurfaceOpacity extends InheritedWidget {
  const _QinSurfaceOpacity({required this.opacity, required super.child});
  final double opacity;
  @override
  bool updateShouldNotify(_QinSurfaceOpacity oldWidget) =>
      opacity != oldWidget.opacity;
}

double qinContentOpacityOf(BuildContext context) => context.qin.highContrast
    ? 1
    : context
              .dependOnInheritedWidgetOfExactType<_QinSurfaceOpacity>()
              ?.opacity ??
          1;
