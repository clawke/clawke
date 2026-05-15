import 'package:client/providers/app_version_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fullVersion includes build number when present', () {
    const info = AppVersionInfo(version: '1.1.22', buildNumber: '71');

    expect(info.fullVersion, '1.1.22+71');
  });

  test('fullVersion falls back to version when build number is empty', () {
    const info = AppVersionInfo(version: '1.1.22', buildNumber: '');

    expect(info.fullVersion, '1.1.22');
  });
}
