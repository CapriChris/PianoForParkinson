import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual bundled sound assets and content pass hashes and bounds',
    () async {
      final content = ContentRepository();
      await content.load();
      expect(content.notes, [0, 1, 2, 4, 2, 1, 0, 0]);
      expect(content.soundPack['assets'].length, 10);
      expect(content.song['rights']['status'], 'DEVELOPMENT_ONLY');
    },
  );
  test(
    'sampled piano carries author, derivative details and bundled license',
    () async {
      final content = ContentRepository();
      await content.load();
      for (final asset in (content.soundPack['assets'] as List).take(7)) {
        expect(asset['author'], 'Alexander Holm');
        expect(asset['license_id'], 'CC-BY-3.0');
        expect(asset['duration_ms'], 3000);
        expect(asset['modifications'], contains('transpose'));
        expect(asset['source_sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
      }
      final license = await rootBundle.loadString(
        'assets/content/piano_attribution.txt',
      );
      expect(license, contains('Alexander Holm'));
      expect(license, contains('Attribution 3.0 Unported'));
      expect(content.soundPack['assets'][7]['duration_ms'], 90);
    },
  );
}
