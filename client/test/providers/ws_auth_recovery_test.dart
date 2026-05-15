import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/http_util.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/services/media_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  )
  handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'clawke_auth_uid': 'uid_1',
      'clawke_auth_securit': 'securit_1',
      'clawke_http_url': 'https://old.relay.clawke.ai',
      'clawke_ws_url': 'wss://old.relay.clawke.ai/ws',
      'clawke_token': 'old-token',
    });
    WsService.setUrl('wss://old.relay.clawke.ai/ws');
    WsService.setToken('old-token');
    MediaResolver.setBaseUrl('https://old.relay.clawke.ai');
    MediaResolver.setToken('old-token');
  });

  test('refreshes relay credentials for websocket auth recovery', () async {
    String? requestedPath;
    HttpUtil.setMockAdapter(
      _FakeHttpClientAdapter((options, stream, cancel) async {
        requestedPath = options.uri.path;
        final payload = jsonEncode({
          'success': true,
          'value': {
            'relayUrl': 'https://newid.relay.clawke.ai',
            'token': 'new-token',
          },
        });
        return ResponseBody.fromString(
          payload,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
          },
        );
      }),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(serverConfigProvider.notifier).ensureLoaded();
    final service = container.read(wsServiceProvider);
    container.read(wsMessageHandlerProvider);

    final recovered = await service.onAuthRecoveryRequired!();

    expect(recovered, isTrue);
    expect(requestedPath, endsWith('/clawke/relay/credentials.json'));
    expect(container.read(relayCredentialsProvider)?.token, 'new-token');

    final config = container.read(serverConfigProvider);
    expect(config.httpUrl, 'https://newid.relay.clawke.ai');
    expect(config.wsUrl, 'wss://newid.relay.clawke.ai/ws');
    expect(config.token, 'new-token');
    expect(WsService.currentUrl, 'wss://newid.relay.clawke.ai/ws');
    expect(WsService.currentToken, 'new-token');
    expect(MediaResolver.baseUrl, 'https://newid.relay.clawke.ai');
    expect(MediaResolver.authHeaders['Authorization'], 'Bearer new-token');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('clawke_token'), 'new-token');
  });

  test('returns false when relay credential refresh fails', () async {
    HttpUtil.setMockAdapter(
      _FakeHttpClientAdapter((options, stream, cancel) async {
        final payload = jsonEncode({
          'success': false,
          'actionError': 'login.required',
        });
        return ResponseBody.fromString(
          payload,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
          },
        );
      }),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(serverConfigProvider.notifier).ensureLoaded();
    final service = container.read(wsServiceProvider);
    container.read(wsMessageHandlerProvider);

    final recovered = await service.onAuthRecoveryRequired!();

    expect(recovered, isFalse);
    expect(container.read(authFailedProvider), isFalse);
    expect(container.read(serverConfigProvider).token, 'old-token');
    expect(WsService.currentToken, 'old-token');
  });
}
