import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_theme.dart';

class AudioVolumeControl extends StatefulWidget {
  const AudioVolumeControl({
    super.key,
    required this.c,
    required this.settingKey,
    required this.title,
    required this.sampleLabel,
    this.onSample,
    this.description,
    this.embedded = false,
    this.icon,
  });
  final AppController c;
  final String settingKey, title, sampleLabel;
  final String? description;
  final bool embedded;
  final IconData? icon;
  final Future<void> Function()? onSample;
  @override
  State<AudioVolumeControl> createState() => _AudioVolumeControlState();
}

class _AudioVolumeControlState extends State<AudioVolumeControl> {
  double? draft;
  bool saving = false;
  Future<void> save(double value) async {
    setState(() => saving = true);
    try {
      await widget.c.updateAudioGain(widget.settingKey, value.round());
      if (mounted) setState(() => draft = null);
    } catch (_) {
      if (mounted) {
        setState(() => draft = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.c.text(
                '音量设置未保存，请重试。',
                'Volume was not saved. Please retry.',
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
  Widget build(BuildContext context) {
    final value =
        draft ?? (widget.c.settings[widget.settingKey] as int).toDouble();
    return Container(
      padding: EdgeInsets.all(widget.embedded ? 4 : 20),
      decoration: widget.embedded
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: context.qin.primary, size: 26),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(value / 10).round()}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.qin.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (widget.description != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Center(
              child: Slider(
                key: ValueKey(widget.settingKey),
                value: value,
                min: 0,
                max: 1000,
                divisions: 20,
                label: '${(value / 10).round()}%',
                semanticFormatterCallback: (v) => '${(v / 10).round()}%',
                onChanged: saving ? null : (v) => setState(() => draft = v),
                onChangeEnd: saving ? null : save,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: saving ? null : widget.onSample,
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(widget.sampleLabel),
            ),
          ),
        ],
      ),
    );
  }
}
