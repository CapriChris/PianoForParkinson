import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/integration/remote_api.dart';

void main() {
  test('HTTP and non-API base are refused', () {
    expect(() => RemoteApi('http://example.com/api'), throwsFormatException);
    expect(() => RemoteApi('https://example.com/'), throwsFormatException);
  });

  test('subpath deployment API URLs are built correctly', () {
    final api = RemoteApi('https://ccqspace.site/pd-rehab/api/');
    expect(
      api.uri('/auth/login').toString(),
      'https://ccqspace.site/pd-rehab/api/auth/login',
    );
    expect(
      api.uri('/integration/v1/records', {
        'patient_id': 'abc',
      }).queryParameters['patient_id'],
      'abc',
    );
  });

  test('tokens are absent before login and remain RAM only', () {
    final api = RemoteApi('https://example.com/api');
    expect(api.signedIn, isFalse);
    expect(api.currentToken, isNull);
    api.signOut();
    expect(api.signedIn, isFalse);
  });
}
