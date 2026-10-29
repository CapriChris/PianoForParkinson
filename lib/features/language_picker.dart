import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_theme.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final entry in {'zh-Hans': '简体中文', 'en': 'English'}.entries)
        Semantics(
          selected: c.locale == entry.key,
          child: OutlinedButton.icon(
            key: ValueKey('language-${entry.key}'),
            style: OutlinedButton.styleFrom(
              backgroundColor: c.locale == entry.key ? context.qin.soft : null,
              side: BorderSide(
                color: c.locale == entry.key
                    ? context.qin.primary
                    : context.qin.edge,
                width: c.locale == entry.key ? 2 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            onPressed: () => c.updateSettings(locale: entry.key),
            icon: Icon(
              c.locale == entry.key
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              size: 20,
            ),
            label: Text(entry.value),
          ),
        ),
    ],
  );
}
