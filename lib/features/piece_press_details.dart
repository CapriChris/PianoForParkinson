import 'package:flutter/material.dart';

import '../domain/contracts.dart';
import '../domain/piano_piece.dart';

class PiecePressDetails extends StatelessWidget {
  const PiecePressDetails({
    super.key,
    required this.record,
    required this.chinese,
    this.piece,
  });
  final Json record;
  final bool chinese;
  final PianoPiece? piece;

  String milliseconds(Object? value) {
    if (value is! int) return '—';
    return '${value >= 0 ? '+' : ''}${(value / 1000).toStringAsFixed(1)} ms';
  }

  String reason(Object? code) => switch (code) {
    'success' => chinese ? '弹奏成功' : 'Success',
    'early_release' => chinese ? '提前松开' : 'Released early',
    'late_release' => chinese ? '松开过晚' : 'Released late',
    'interrupted' => chinese ? '按住期间发生中断' : 'Hold interrupted',
    _ => chinese ? '琴键或按下时机不符' : 'Wrong key or press timing',
  };

  @override
  Widget build(BuildContext context) {
    final presses = record['performance_trace']['notes'] as List;
    return Card(
      child: ExpansionTile(
        title: Text(chinese ? '每次按键明细' : 'Individual key presses'),
        subtitle: Text(
          chinese
              ? '负数表示提前，正数表示落后'
              : 'Negative means early, positive means late',
        ),
        children: [
          if (presses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(chinese ? '本次没有按键记录' : 'No key presses recorded'),
            )
          else
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: presses.length,
                itemBuilder: (context, index) {
                  final press = presses[index] as Map;
                  final key = press['key'] as int;
                  final pitch = piece == null
                      ? '${key + 1}'
                      : '${piece!.keyLabel(key)} · MIDI ${piece!.keyMidi(key)}';
                  final held = ((press['hold_duration_us'] as int) / 1000)
                      .toStringAsFixed(1);
                  final waited = ((press['waiting_us'] as int) / 1000)
                      .toStringAsFixed(1);
                  return ListTile(
                    leading: Icon(
                      press['success'] == true
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                    ),
                    title: Text('$pitch · ${reason(press['judgement'])}'),
                    subtitle: Text(
                      chinese
                          ? '按住 $held 毫秒 · 按下偏差 ${milliseconds(press['onset_offset_us'])}\n'
                                '松开偏差 ${milliseconds(press['release_offset_us'])} · 等待 $waited 毫秒'
                          : 'Held $held ms · Press ${milliseconds(press['onset_offset_us'])}\n'
                                'Release ${milliseconds(press['release_offset_us'])} · Waited $waited ms',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
