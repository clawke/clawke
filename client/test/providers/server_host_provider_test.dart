import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/providers/server_host_provider.dart';

const _testForcedHttpUrl = String.fromEnvironment('CLAWKE_FORCE_HTTP_URL');
const _testForcedWsUrl = String.fromEnvironment('CLAWKE_FORCE_WS_URL');
const _testForcedToken = String.fromEnvironment('CLAWKE_FORCE_TOKEN');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes server addresses and derives websocket urls', () {
    expect(normalizeServerHttpUrl(''), kDefaultHttpUrl);
    expect(normalizeServerHttpUrl('127.0.0.1:8780/'), 'http://127.0.0.1:8780');
    expect(
      normalizeServerHttpUrl('http://127.0.0.1:8780/ws'),
      'http://127.0.0.1:8780',
    );
    expect(
      normalizeServerHttpUrl('https://relay.example.com/base/ws'),
      'https://relay.example.com/base',
    );
    expect(
      deriveWsUrlFromServerAddress('http://127.0.0.1:8780/ws'),
      'ws://127.0.0.1:8780/ws',
    );
    expect(
      deriveWsUrlFromServerAddress('https://relay.example.com/base/'),
      'wss://relay.example.com/base/ws',
    );
  });

  test(
    'setServerAddress clears a stale token when switching servers',
    () async {
      SharedPreferences.setMockInitialValues({
        'clawke_http_url': 'https://old-relay.example.com',
        'clawke_ws_url': 'wss://old-relay.example.com/ws',
        'clawke_token': 'old-token',
      });

      final notifier = ServerConfigNotifier();
      final initial = await notifier.ensureLoaded();
      expect(initial.token, 'old-token');

      await notifier.setServerAddress('http://127.0.0.1:18780');

      expect(notifier.state.httpUrl, 'http://127.0.0.1:18780');
      expect(notifier.state.wsUrl, 'ws://127.0.0.1:18780/ws');
      expect(notifier.state.token, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('clawke_token'), isEmpty);
    },
  );

  test(
    'setServerAddress clears logged out marker after manual login',
    () async {
      SharedPreferences.setMockInitialValues({'clawke_logged_out': true});

      final notifier = ServerConfigNotifier();
      await notifier.ensureLoaded();

      await notifier.setServerAddress('http://127.0.0.1:8780');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('clawke_logged_out'), isNull);
    },
  );

  test('setServerAddress stores normalized http and ws urls', () async {
    SharedPreferences.setMockInitialValues({});

    final notifier = ServerConfigNotifier();
    await notifier.ensureLoaded();

    await notifier.setServerAddress('http://127.0.0.1:18780/ws');

    expect(notifier.state.httpUrl, 'http://127.0.0.1:18780');
    expect(notifier.state.wsUrl, 'ws://127.0.0.1:18780/ws');
  });

  test('can inject non-persistent config for ui e2e', () async {
    SharedPreferences.setMockInitialValues({
      'clawke_http_url': 'http://127.0.0.1:8780',
      'clawke_ws_url': 'ws://127.0.0.1:8780/ws',
    });

    final notifier = ServerConfigNotifier(
      initialConfig: const ServerConfig(
        httpUrl: 'http://127.0.0.1:18780',
        wsUrl: 'ws://127.0.0.1:18780/ws',
      ),
      loadFromPrefs: false,
    );

    final loaded = await notifier.ensureLoaded();
    expect(loaded.httpUrl, 'http://127.0.0.1:18780');
    expect(loaded.wsUrl, 'ws://127.0.0.1:18780/ws');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('clawke_http_url'), 'http://127.0.0.1:8780');
    expect(prefs.getString('clawke_ws_url'), 'ws://127.0.0.1:8780/ws');
  });

  test('forced server config marks startup as forced direct mode', () {
    if (_testForcedHttpUrl.isEmpty || _testForcedWsUrl.isEmpty) {
      return;
    }

    expect(shouldUseForcedServerConfig(), isTrue);
  });

  test('forced server config preserves logged out marker', () async {
    if (_testForcedHttpUrl.isEmpty || _testForcedWsUrl.isEmpty) {
      return;
    }

    SharedPreferences.setMockInitialValues({
      'clawke_token': 'stale-token',
      'clawke_logged_out': true,
    });

    final notifier = ServerConfigNotifier();
    final loaded = await notifier.ensureLoaded();

    expect(loaded.httpUrl, _testForcedHttpUrl);
    expect(loaded.wsUrl, _testForcedWsUrl);
    expect(loaded.token, _testForcedToken);

    final prefs = await SharedPreferences.getInstance();
    if (_testForcedToken.isEmpty) {
      expect(prefs.getString('clawke_token'), isNull);
    } else {
      expect(prefs.getString('clawke_token'), _testForcedToken);
    }
    expect(prefs.getBool('clawke_logged_out'), isTrue);
  });
}
