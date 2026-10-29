import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_theme.dart';

class TextSizeControl extends StatefulWidget {
  const TextSizeControl({super.key, required this.c});
  final AppController c;
  @override
  State<TextSizeControl> createState() => _TextSizeControlState();
}

class _TextSizeControlState extends State<TextSizeControl> {
  bool saving = false;

  Future<void> save(int? value) async {
    setState(() => saving = true);
    try {
      await widget.c.saveTextScale(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.c.text(
                '字号设置未保存，请重试。',
                'Text size was not saved. Please retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    if (!saving) {
      final controller = widget.c;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.clearTextScalePreview(),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.c.textScalePercent;
    final value = custom ?? 100;
    final display = '$value%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.format_size, color: context.qin.primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.c.text('字号大小', 'Text size'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                display,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: context.qin.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Slider(
          key: const ValueKey('text-size-slider'),
          value: value.toDouble(),
          min: 80,
          max: 120,
          divisions: 8,
          label: '$value%',
          semanticFormatterCallback: (v) =>
              widget.c.text('字号 ${v.round()}%', 'Text size ${v.round()}%'),
          onChanged: saving
              ? null
              : (v) => widget.c.previewTextScale(v.round()),
          onChangeEnd: saving ? null : (v) => save(v.round()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('text-size-follow-system'),
            onPressed: saving || custom == null ? null : () => save(null),
            icon: Icon(custom == null ? Icons.check : Icons.refresh, size: 20),
            label: Text(widget.c.text('跟随系统', 'Follow system')),
          ),
        ),
      ],
    );
  }
}
