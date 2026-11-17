import 'package:ecoearn_app/update/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version comparison', () {
    expect(isNewer('1.0.12', '1.0.9'), isTrue); // numbers, not text
    expect(isNewer('1.1.0', '1.0.99'), isTrue);
    expect(isNewer('1.0.9', '1.0.9'), isFalse);
    expect(isNewer('1.0.8', '1.0.9'), isFalse);
    expect(isNewer('2', '1.9.9'), isTrue);
  });

  test('a developer run never updates', () {
    expect(Updater().enabled, appVersion.isNotEmpty);
  });
}
