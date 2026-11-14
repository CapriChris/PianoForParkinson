import 'package:flutter/material.dart';

/// Shared confirmation layout: equal actions stay side by side, while the
/// whole dialog can scroll on short screens or with large accessibility text.
class QinDialog extends StatelessWidget {
  const QinDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 24,
    ),
  });

  final Widget? title, content;
  final List<Widget> actions;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: insetPadding,
    title: title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?content,
        if (content != null && actions.isNotEmpty) const SizedBox(height: 24),
        if (actions.isNotEmpty) QinDialogActions(children: actions),
      ],
    ),
  );
}

class QinDialogActions extends StatelessWidget {
  const QinDialogActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const padding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    );
    final edge = WidgetStateProperty.resolveWith<BorderSide>(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? theme.disabledColor
            : theme.colorScheme.outline,
        width: states.contains(WidgetState.focused) ? 3 : 1,
      ),
    );
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            padding: padding,
            side: edge,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(padding: padding),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                padding: padding,
                side: WidgetStatePropertyAll(
                  BorderSide(color: theme.colorScheme.primary),
                ),
              ),
        ),
      ),
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: children[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
