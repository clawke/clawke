import 'package:client/upgrade/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdatePolicy', () {
    test('omits version metadata when in-app updates are disabled', () {
      final data = AppUpdatePolicy.buildSyncData(
        lastSeq: 12,
        appVersion: '1.1.28',
        platform: 'macos',
        arch: 'arm64',
        inAppUpdatesEnabled: false,
      );

      expect(data, {'last_seq': 12});
    });

    test('includes version metadata when in-app updates are enabled', () {
      final data = AppUpdatePolicy.buildSyncData(
        lastSeq: 12,
        appVersion: '1.1.28',
        platform: 'macos',
        arch: 'arm64',
        inAppUpdatesEnabled: true,
      );

      expect(data, {
        'last_seq': 12,
        'app_version': '1.1.28',
        'platform': 'macos',
        'arch': 'arm64',
      });
    });
  });
}
