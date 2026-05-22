import 'package:client/upgrade/upgrade_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpgradeInfo', () {
    test('parses server compatibility update details', () {
      final info = UpgradeInfo.fromSystemStatus({
        'payload_type': 'system_status',
        'status': 'update_available',
        'upgrade': 2,
        'update_info': {
          'version': '3.8.2',
          'title': '需要升级客户端',
          'message': '当前服务端版本为 3.8.2，客户端版本为 3.8.1。请升级客户端到 3.8.2 后继续使用。',
          'download_url':
              'https://github.com/clawke/clawke/releases/tag/v3.8.2',
          'action': 'required_client_update',
          'client_version': '3.8.1',
          'server_version': '3.8.2',
        },
      });

      expect(info.isForced, isTrue);
      expect(info.title, '需要升级客户端');
      expect(info.message, contains('客户端版本为 3.8.1'));
      expect(info.action, 'required_client_update');
      expect(info.clientVersion, '3.8.1');
      expect(info.serverVersion, '3.8.2');
    });

    test('parses optional server compatibility warning details', () {
      final info = UpgradeInfo.fromSystemStatus({
        'payload_type': 'system_status',
        'status': 'update_available',
        'upgrade': 1,
        'update_info': {
          'version': '3.8.2',
          'title': '建议升级客户端',
          'message': '当前服务端版本为 3.8.2，客户端版本为 3.8.1。版本不完全一致，可能不兼容。',
          'download_url':
              'https://github.com/clawke/clawke/releases/tag/v3.8.2',
          'action': 'recommended_client_update',
          'client_version': '3.8.1',
          'server_version': '3.8.2',
        },
      });

      expect(info.isForced, isFalse);
      expect(info.title, '建议升级客户端');
      expect(info.message, contains('可能不兼容'));
      expect(info.action, 'recommended_client_update');
    });

    test('uses stable notification key for the same compatibility result', () {
      final first = UpgradeInfo.fromSystemStatus({
        'payload_type': 'system_status',
        'status': 'update_available',
        'upgrade': 1,
        'update_info': {
          'version': '3.8.2',
          'action': 'recommended_client_update',
          'client_version': '3.8.1',
          'server_version': '3.8.2',
        },
      });
      final second = UpgradeInfo.fromSystemStatus({
        'payload_type': 'system_status',
        'status': 'update_available',
        'upgrade': 1,
        'update_info': {
          'version': '3.8.2',
          'action': 'recommended_client_update',
          'client_version': '3.8.1',
          'server_version': '3.8.2',
        },
      });

      expect(first.notificationKey, second.notificationKey);
    });

    test('matches current semantic version while ignoring build number', () {
      final info = UpgradeInfo.fromSystemStatus({
        'payload_type': 'system_status',
        'status': 'update_available',
        'upgrade': 1,
        'update_info': {'version': 'v1.1.33'},
      });

      expect(info.targetsSameSemanticVersionAs('1.1.33+84'), isTrue);
      expect(info.targetsSameSemanticVersionAs('1.1.34+1'), isFalse);
    });
  });
}
