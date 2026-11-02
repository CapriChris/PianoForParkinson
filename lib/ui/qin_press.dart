import 'package:flutter/material.dart';

/// One short press/release cycle, then the action. Disabled controls stay still.
class QinPress extends StatefulWidget {
  const QinPress({super.key, required this.onActivate, required this.builder});
  final VoidCallback? onActivate;
  final Widget Function(VoidCallback? activate) builder;
  @override
  State<QinPress> createState() => _QinPressState();
}

class _QinPressState extends State<QinPress>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 75),
    reverseDuration: const Duration(milliseconds: 95),
  );
  static final pointerOwners = <int, _QinPressState>{};
  bool running = false;
  bool get reduced =>
      context.dependOnInheritedWidgetOfExactType<QinMotionPolicy>()?.reduced ??
      MediaQuery.disableAnimationsOf(context);
  Future<void> runPress() async {
    if (running || widget.onActivate == null) return;
    running = true;
    try {
      if (!reduced) {
        await motion.forward().orCancel;
        await motion.reverse().orCancel;
      }
      if (mounted) widget.onActivate?.call();
    } on TickerCanceled {
      /* The originating control was removed. */
    } finally {
      running = false;
    }
  }

  @override
  void dispose() {
    pointerOwners.removeWhere((_, owner) => identical(owner, this));
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onActivate != null;
    return Listener(
      onPointerDown: (event) {
        // The innermost control owns feedback; pressing a button inside a card
        // must not animate or activate the containing card.
        if (pointerOwners.containsKey(event.pointer)) return;
        pointerOwners[event.pointer] = this;
        if (enabled && !reduced && !running) motion.forward();
      },
      onPointerUp: (event) => Future.microtask(() {
        if (pointerOwners[event.pointer] != this) return;
        pointerOwners.remove(event.pointer);
        if (mounted && !running) motion.reverse();
      }),
      onPointerCancel: (event) {
        if (pointerOwners[event.pointer] != this) return;
        pointerOwners.remove(event.pointer);
        if (!running) motion.reverse();
      },
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, motion.value * 1.5),
          child: Transform.scale(scale: 1 - motion.value * .035, child: child),
        ),
        child: widget.builder(enabled ? runPress : null),
      ),
    );
  }
}

class QinFilledButton extends StatelessWidget {
  const QinFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.clipBehavior = Clip.none,
  }) : icon = null,
       label = null;
  const QinFilledButton.icon({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.style,
    this.clipBehavior = Clip.none,
  }) : child = null;
  final VoidCallback? onPressed;
  final Widget? child, icon, label;
  final ButtonStyle? style;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onPressed,
    builder: (activate) => label == null
        ? FilledButton(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            child: child!,
          )
        : FilledButton.icon(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            icon: icon,
            label: label!,
          ),
  );
}

class QinOutlinedButton extends StatelessWidget {
  const QinOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.clipBehavior = Clip.none,
  }) : icon = null,
       label = null;
  const QinOutlinedButton.icon({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.style,
    this.clipBehavior = Clip.none,
  }) : child = null;
  final VoidCallback? onPressed;
  final Widget? child, icon, label;
  final ButtonStyle? style;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onPressed,
    builder: (activate) => label == null
        ? OutlinedButton(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            child: child!,
          )
        : OutlinedButton.icon(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            icon: icon,
            label: label!,
          ),
  );
}

class QinTextButton extends StatelessWidget {
  const QinTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.clipBehavior = Clip.none,
  }) : icon = null,
       label = null;
  const QinTextButton.icon({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.style,
    this.clipBehavior = Clip.none,
  }) : child = null;
  final VoidCallback? onPressed;
  final Widget? child, icon, label;
  final ButtonStyle? style;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onPressed,
    builder: (activate) => label == null
        ? TextButton(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            child: child!,
          )
        : TextButton.icon(
            onPressed: activate,
            style: style,
            clipBehavior: clipBehavior,
            icon: icon,
            label: label!,
          ),
  );
}

class QinIconButton extends StatelessWidget {
  const QinIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.style,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final ButtonStyle? style;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onPressed,
    builder: (activate) => IconButton(
      onPressed: activate,
      icon: icon,
      tooltip: tooltip,
      style: style,
    ),
  );
}

class QinInkWell extends StatelessWidget {
  const QinInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.surfaceBuilder,
  });
  final Widget Function(Widget child)? surfaceBuilder;
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final BorderRadius? borderRadius;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onTap,
    builder: (activate) {
      final ink = InkWell(
        onTap: activate,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: child,
      );
      return surfaceBuilder?.call(ink) ?? ink;
    },
  );
}

class QinListTile extends StatelessWidget {
  const QinListTile({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.selected = false,
    this.onTap,
    this.surfaceBuilder,
  });
  final Widget Function(Widget child)? surfaceBuilder;
  final Widget? title, subtitle, trailing, leading;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: onTap,
    builder: (activate) {
      final tile = ListTile(
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        leading: leading,
        selected: selected,
        onTap: activate,
      );
      return surfaceBuilder?.call(tile) ?? tile;
    },
  );
}

/// Interactive feedback follows the system accessibility setting, independently
/// of the app's optional decorative animation setting.
class QinMotionPolicy extends InheritedWidget {
  const QinMotionPolicy({
    super.key,
    required this.reduced,
    required super.child,
  });
  final bool reduced;
  @override
  bool updateShouldNotify(QinMotionPolicy oldWidget) =>
      reduced != oldWidget.reduced;
}

class QinBackButton extends StatelessWidget {
  const QinBackButton({super.key});
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: () => Navigator.maybePop(context),
    builder: (activate) => BackButton(onPressed: activate),
  );
}

/// Nested native controls consume card feedback without delaying their own input.
class QinPressBlock extends StatelessWidget {
  const QinPressBlock({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => QinPress(
    onActivate: null,
    builder: (_) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onLongPress: () {},
      child: child,
    ),
  );
}
