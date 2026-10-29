import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';

Json sealedRow({int numerator = 2, int denominator = 3}) => {
  'block_id': 'block',
  'ended_utc_ms': 0,
  'session_utc_offset_minutes': 480,
  'comparison_key': 'condition',
  'metric_version': 'metrics',
  'result_json': canonical({
    'comparison_key': 'condition',
    'version': 'metrics',
    'rates': {
      'primary': {'numerator': numerator, 'denominator': denominator},
    },
  }),
};

void main() {
  test('sealed ratio and date use the recorded timezone offset', () {
    final point = TrendPoint.fromRow(sealedRow());
    expect(point.fraction, closeTo(2 / 3, .0001));
    expect(recordDateLabel(point.date), '1970-01-01 08:00');
    final western = sealedRow()..['session_utc_offset_minutes'] = -300;
    expect(
      recordDateLabel(TrendPoint.fromRow(western).date),
      '1969-12-31 19:00',
    );
  });
  test('invalid or empty denominators cannot become misleading points', () {
    for (final row in [
      sealedRow(denominator: 0),
      sealedRow(numerator: -1),
      sealedRow(numerator: 4),
    ]) {
      expect(() => TrendPoint.fromRow(row), throwsFormatException);
    }
  });
  test(
    'mismatched sealed condition or version is rejected without recomputation',
    () {
      expect(
        () => TrendPoint.fromRow(sealedRow()..['comparison_key'] = 'other'),
        throwsFormatException,
      );
      expect(
        () => TrendPoint.fromRow(sealedRow()..['metric_version'] = 'other'),
        throwsFormatException,
      );
    },
  );
}
