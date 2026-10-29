import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'qin_theme.dart';

bool qinShortLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.height < 600;
}

/// Browsing pages keep their next action visible; long guidance scrolls first.
class QinActionPage extends StatelessWidget {
  const QinActionPage({
    super.key,
    required this.children,
    required this.actions,
    this.maxWidth = 760,
    this.controller,
    this.fixedHeader,
  });
  final List<Widget> children, actions;
  final double maxWidth;
  final ScrollController? controller;
  final Widget? fixedHeader;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: LayoutBuilder(
      builder: (context, size) {
        final inset = math.max(
          size.maxWidth < 600 ? 16.0 : 24.0,
          (size.maxWidth - maxWidth) / 2,
        );
        final footer = Padding(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
          child: QinActionRow(children: actions),
        );
        // Extremely short windows / large text can scroll the entire page.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (fixedHeader != null) {
          final header = Padding(
            padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
            child: fixedHeader!,
          );
          final limitedHeader = size.maxHeight < 240 * scale
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.maxHeight * .45),
                  child: SingleChildScrollView(child: header),
                )
              : header;
          final compact = size.maxHeight < 160 * scale;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              limitedHeader,
              Expanded(
                child: compact
                    ? SingleChildScrollView(
                        controller: controller,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: children,
                              ),
                            ),
                            footer,
                          ],
                        ),
                      )
                    : QinPageList(
                        controller: controller,
                        maxWidth: maxWidth,
                        children: children,
                      ),
              ),
              if (!compact) footer,
            ],
          );
        }
        if (size.maxHeight < 160 * scale) {
          return SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
                footer,
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: QinPageList(
                controller: controller,
                maxWidth: maxWidth,
                children: children,
              ),
            ),
            footer,
          ],
        );
      },
    ),
  );
}

class QinActionRow extends StatelessWidget {
  const QinActionRow({
    super.key,
    required this.children,
    this.minItemWidth = 160,
  });
  final List<Widget> children;
  final double minItemWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final minWidth =
          minItemWidth * MediaQuery.textScalerOf(context).scale(1) + 16;
      final columns = math.min(
        children.length,
        math.max(1, ((size.maxWidth + 8) / (minWidth + 8)).floor()),
      );
      final width = (size.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Responsive inset without narrowing the training keyboard's hit rectangle.
EdgeInsets qinPagePadding(BuildContext context, {double maxWidth = 760}) {
  final width = MediaQuery.sizeOf(context).width;
  final inset = width < 600 ? 16.0 : 24.0;
  return EdgeInsets.fromLTRB(
    math.max(inset, (width - maxWidth) / 2),
    16,
    math.max(inset, (width - maxWidth) / 2),
    24,
  );
}

class QinPageList extends StatelessWidget {
  const QinPageList({
    super.key,
    required this.children,
    this.controller,
    this.maxWidth = 760,
    this.padding,
  });
  final List<Widget> children;
  final ScrollController? controller;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: LayoutBuilder(
      builder: (context, size) {
        final inset = size.maxWidth < 600 ? 16.0 : 24.0;
        final horizontal = math.max(inset, (size.maxWidth - maxWidth) / 2);
        return ListView(
          controller: controller,
          padding:
              padding ??
              EdgeInsets.fromLTRB(
                horizontal,
                qinShortLandscape(context) ? 8 : 16,
                horizontal,
                24,
              ),
          children: children,
        );
      },
    ),
  );
}

class QinPanel extends StatelessWidget {
  const QinPanel({
    super.key,
    required this.child,
    this.soft = false,
    this.padding = const EdgeInsets.all(20),
    this.backgroundOpacity = 1,
  });
  final Widget child;
  final bool soft;
  final EdgeInsetsGeometry padding;
  final double backgroundOpacity;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: (soft ? context.qin.soft : context.qin.surface).withValues(
        alpha: context.qin.highContrast ? 1 : backgroundOpacity,
      ),
      border: Border.all(color: context.qin.line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class QinSectionTitle extends StatelessWidget {
  const QinSectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

enum QinTone { neutral, success, warning, error }

class QinStatus extends StatelessWidget {
  const QinStatus({
    super.key,
    required this.text,
    this.tone = QinTone.neutral,
    this.icon,
    this.child,
    this.backgroundOpacity = 1,
  });
  final String text;
  final QinTone tone;
  final IconData? icon;
  final Widget? child;
  final double backgroundOpacity;
  @override
  Widget build(BuildContext context) {
    final p = context.qin;
    final color = switch (tone) {
      QinTone.warning => p.warning,
      QinTone.error => p.error,
      _ => p.primary,
    };
    return QinPanel(
      soft: tone == QinTone.neutral || tone == QinTone.success,
      backgroundOpacity: backgroundOpacity,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon ??
                    switch (tone) {
                      QinTone.success => Icons.check_circle_outline,
                      QinTone.warning => Icons.info_outline,
                      QinTone.error => Icons.error_outline,
                      _ => Icons.info_outline,
                    },
                color: color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

class QinEntryCard extends StatelessWidget {
  const QinEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.actionLabel,
    this.metadata,
    this.visual,
    this.leadingVisual,
    this.selected = false,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final String? actionLabel;
  final String? metadata;
  final Widget? visual;
  final Widget? leadingVisual;
  final bool selected;
  @override
  Widget build(BuildContext context) => Card(
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (MediaQuery.sizeOf(context).width >= 600 ||
                  MediaQuery.textScalerOf(context).scale(1) <= 1.5) ...[
                if (leadingVisual != null && !context.qin.highContrast)
                  ExcludeSemantics(child: leadingVisual!)
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.qin.soft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: context.qin.primary, size: 28),
                  ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (metadata != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        metadata!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (visual != null) ...[
                      const SizedBox(height: 12),
                      visual!,
                    ],
                    if (actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        actionLabel!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.qin.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_outline : Icons.chevron_right,
                color: context.qin.primary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class QinMetric {
  const QinMetric(
    this.label,
    this.value, {
    this.icon = Icons.analytics_outlined,
    this.progress,
  });
  final String label, value;
  final IconData icon;
  final double? progress;
}

class QinMetrics extends StatelessWidget {
  const QinMetrics({
    super.key,
    required this.values,
    this.backgroundOpacity = 1,
  });
  final List<QinMetric> values;
  final double backgroundOpacity;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = size.maxWidth >= 640 && scale <= 1.25
          ? math.min(3, values.length)
          : size.maxWidth >= 340 && scale <= 1.25
          ? math.min(2, values.length)
          : 1;
      final width = (size.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < values.length; i++)
            SizedBox(
              width:
                  columns == 2 && values.length.isOdd && i == values.length - 1
                  ? size.maxWidth
                  : width,
              child: QinPanel(
                backgroundOpacity: backgroundOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(values[i].icon, color: context.qin.primary, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      values[i].label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      values[i].value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.qin.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (values[i].progress != null) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: values[i].progress!.clamp(0, 1),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class QinStepProgress extends StatelessWidget {
  const QinStepProgress({
    super.key,
    required this.current,
    required this.total,
    this.label,
  });
  final int current, total;
  final String? label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null) ...[
        Text(
          label!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.qin.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i < current
                      ? context.qin.primary
                      : context.qin.disabled,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class QinEmptyState extends StatelessWidget {
  const QinEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.music_note_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => QinPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.qin.primary, size: 32),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

/// Labels follow the complete system text scale; the bar grows with content.
class QinNavigationBar extends StatelessWidget {
  const QinNavigationBar({
    super.key,
    required this.selected,
    required this.labels,
    required this.onSelected,
  });
  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => Material(
    color: context.qin.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    role: SemanticsRole.tab,
                    onTap: () => onSelected(i),
                    selected: i == selected,
                    child: TextButton(
                      onPressed: () => onSelected(i),
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                        backgroundColor: WidgetStatePropertyAll(
                          i == selected
                              ? context.qin.soft
                              : context.qin.surface,
                        ),
                        side: WidgetStateProperty.resolveWith(
                          (s) => BorderSide(
                            color: context.qin.primary,
                            width: s.contains(WidgetState.focused)
                                ? 3
                                : i == selected && context.qin.highContrast
                                ? 2
                                : 0,
                            style:
                                s.contains(WidgetState.focused) ||
                                    i == selected && context.qin.highContrast
                                ? BorderStyle.solid
                                : BorderStyle.none,
                          ),
                        ),
                      ),
                      child: Flex(
                        direction: qinShortLandscape(context)
                            ? Axis.horizontal
                            : Axis.vertical,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            [
                              Icons.home_outlined,
                              Icons.piano_outlined,
                              Icons.history_outlined,
                            ][i],
                            size: 28,
                            color: i == selected
                                ? context.qin.primary
                                : context.qin.muted,
                          ),
                          SizedBox(
                            width: qinShortLandscape(context) ? 12 : 0,
                            height: qinShortLandscape(context) ? 0 : 6,
                          ),
                          Flexible(
                            child: Text(
                              labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                height: 1.25,
                                color: i == selected
                                    ? context.qin.primary
                                    : context.qin.muted,
                                fontWeight: i == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Decorative direction indicator for an already-tappable card or button.
class QinCircleArrow extends StatelessWidget {
  const QinCircleArrow({super.key, this.radius = 16});
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CircleAvatar(
      radius: radius,
      backgroundColor: context.qin.highContrast
          ? context.qin.surface
          : context.qin.soft,
      child: Icon(
        Icons.chevron_right,
        size: radius + 4,
        color: context.qin.ink,
      ),
    ),
  );
}
