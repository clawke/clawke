import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/providers/server_host_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'injected config does not mutate persisted server preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'clawke_http_url': 'http://user-server.example.com',
        'clawke_ws_url': 'ws://user-server.example.com/ws',
        'clawke_token': 'user-token',
      });

      final notifier = ServerConfigNotifier(
        initialConfig: const ServerConfig(
          httpUrl: 'http://127.0.0.1:18780',
          wsUrl: 'ws://127.0.0.1:18780/ws',
          token: '',
        ),
        loadFromPrefs: false,
      );
      final config = await notifier.ensureLoaded();

      expect(config.httpUrl, 'http://127.0.0.1:18780');
      expect(config.wsUrl, 'ws://127.0.0.1:18780/ws');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('clawke_http_url'),
        'http://user-server.example.com',
      );
      expect(
        prefs.getString('clawke_ws_url'),
        'ws://user-server.example.com/ws',
      );
      expect(prefs.getString('clawke_token'), 'user-token');
    },
  );
}
