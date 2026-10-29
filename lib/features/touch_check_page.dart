import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_theme.dart';
import '../ui/qin_components.dart';
import '../app/page_title.dart';

class TouchCheckPage extends StatefulWidget {
  const TouchCheckPage({super.key, required this.c, required this.onContinue});
  final AppController c;
  final VoidCallback onContinue;
  @override
  State<TouchCheckPage> createState() => _TouchCheckPageState();
}

class _TouchCheckPageState extends State<TouchCheckPage> {
  @override
  void initState() {
    super.initState();
    widget.c.previewInterruptions.addListener(interrupted);
  }

  void interrupted() {
    if (mounted) setState(() => contacts.clear());
  }

  @override
  void dispose() {
    widget.c.previewInterruptions.removeListener(interrupted);
    super.dispose();
  }

  final contacts = <int, bool>{};
  bool verified = false;
  bool savingVerification = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final ready =
        MediaQuery.sizeOf(context).width >= 600 &&
        !MediaQuery.of(context).accessibleNavigation;
    return Scaffold(
      appBar: AppBar(title: PageTitle(c.text('双区配合', 'Two-zone coordination'))),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: ready && verified ? widget.onContinue : null,
            child: Text(c.text('完成检查，继续', 'Continue after check')),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.text('检查双触点支持', 'Check two-touch support'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.text(
                          '同时按住左右两块区域；检查不会生成训练成绩。',
                          'Hold both areas at the same time. This check creates no practice score.',
                        ),
                      ),
                      if (!ready)
                        Text(
                          c.text(
                            '当前窗口太窄或启用了读屏。请转为横屏或放大窗口；读屏时请使用逐音旋律练习。',
                            'The window is too narrow or a screen reader is active. Rotate or enlarge the window; with a screen reader, use guided melody practice.',
                          ),
                        ),
                      if (error != null && !verified)
                        QinStatus(text: error!, tone: QinTone.warning),
                      if (verified)
                        Text(
                          c.text(
                            '双触点已确认，可以继续。',
                            'Two touch points confirmed. You can continue.',
                          ),
                          style: TextStyle(
                            color: context.qin.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) async {
                    if (!ready) return;
                    setState(() {
                      contacts[event.pointer] =
                          event.localPosition.dx <
                          (constraints.maxWidth - 32) / 2;
                    });
                    if (verified || savingVerification) {
                      return;
                    }
                    try {
                      await c.refreshCapabilities();
                      if (!mounted || verified || savingVerification) return;
                      final confirmed =
                          contacts.values.contains(true) &&
                          contacts.values.contains(false) &&
                          (c.capabilities['max_verified_touch_points']
                                      as int? ??
                                  0) >=
                              2;
                      if (confirmed) {
                        savingVerification = true;
                        try {
                          await c.completeDualTouchCheck();
                          if (mounted) {
                            setState(() {
                              verified = true;
                              error = null;
                            });
                          }
                        } finally {
                          savingVerification = false;
                        }
                      } else if (contacts.length >= 2) {
                        setState(
                          () => error = c.text(
                            '尚未收到系统确认的双触点，请用两指同时按住。',
                            'Two system touch points have not been confirmed. Hold with two fingers.',
                          ),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = c.text(
                            '暂时无法完成检查或保存结果，请松手后重试。',
                            'Unable to complete or save the check. Release and try again.',
                          ),
                        );
                      }
                    }
                  },
                  onPointerUp: (event) =>
                      setState(() => contacts.remove(event.pointer)),
                  onPointerCancel: (event) =>
                      setState(() => contacts.remove(event.pointer)),
                  child: Row(
                    children: [
                      for (final left in [true, false])
                        Expanded(
                          child: Semantics(
                            label: left
                                ? c.text('左区', 'Left area')
                                : c.text('右区', 'Right area'),
                            value: contacts.values.contains(left)
                                ? c.text('已按下', 'Pressed')
                                : c.text('未按下', 'Not pressed'),
                            child: Container(
                              key: ValueKey(
                                left ? 'touch-check-left' : 'touch-check-right',
                              ),
                              height: 96,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: contacts.values.contains(left)
                                    ? context.qin.primary
                                    : context.qin.surface,
                                border: Border.all(
                                  color: context.qin.edge,
                                  width: context.qin.highContrast ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                left
                                    ? c.text('左区', 'Left area')
                                    : c.text('右区', 'Right area'),
                                style: TextStyle(
                                  color: contacts.values.contains(left)
                                      ? context.qin.onPrimary
                                      : context.qin.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
