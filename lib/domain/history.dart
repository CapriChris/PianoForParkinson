import 'dart:convert';

import 'contracts.dart';

class HistoryPage {
  const HistoryPage(this.records, this.hasMore);
  final List<Json> records;
  final bool hasMore;
}

/// Reads sealed block summaries; never recomputes historical scores.
class TrendPoint {
  TrendPoint.fromRow(Json row)
    : blockId = row['block_id'] as String,
      date = recordedDate(row, 'ended_utc_ms'),
      summary = jsonDecode(row['result_json'] as String) as Json {
    final rate = summary['rates']?['primary'];
    if (rate is! Map ||
        summary['version'] != row['metric_version'] ||
        summary['comparison_key'] != row['comparison_key'] ||
        rate['numerator'] is! int ||
        rate['denominator'] is! int ||
        rate['denominator'] <= 0 ||
        rate['numerator'] < 0 ||
        rate['numerator'] > rate['denominator']) {
      throw const FormatException('Invalid sealed block rate');
    }
  }
  final String blockId;
  final DateTime date;
  final Json summary;
  int get numerator => summary['rates']['primary']['numerator'] as int;
  int get denominator => summary['rates']['primary']['denominator'] as int;
  double get fraction => numerator / denominator;
}

DateTime recordedDate(Json record, String field) =>
    DateTime.fromMillisecondsSinceEpoch(
      record[field] as int,
      isUtc: true,
    ).add(Duration(minutes: record['session_utc_offset_minutes'] as int));

String recordDateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
