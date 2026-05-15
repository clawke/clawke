import 'dart:async';
import 'dart:io';

import 'package:client/core/ws_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('sendJson logs outbound payload with model-relevant fields', () {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };

    try {
      WsService().sendJson({
        'id': 'req_1',
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': 'hermes',
          'conversation_id': 'conv_1',
          'client_msg_id': 'cmsg_1',
        },
        'data': {'content': 'hello', 'type': 'text'},
      });
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      logs,
      contains(
        contains(
          '[WS] 📤 send: user_message payload={"id":"req_1","protocol":"cup_v2","event_type":"user_message","context":{"account_id":"hermes","conversation_id":"conv_1","client_msg_id":"cmsg_1"},"data":{"content":"hello","type":"text"}}',
        ),
      ),
    );
  });

  test(
    'classifies websocket upgrade failure with token as recoverable auth',
    () {
      expect(
        isRecoverableWsAuthError(
          "WebSocketException: Connection to 'https://relay/ws?token=old#' "
          'was not upgraded to websocket',
          hasToken: true,
        ),
        isTrue,
      );
      expect(
        isRecoverableWsAuthError(
          'WebSocketException: was not upgraded to websocket',
          hasToken: false,
        ),
        isFalse,
      );
      expect(
        isRecoverableWsAuthError('401 Unauthorized', hasToken: false),
        isTrue,
      );
    },
  );

  test('redacts token from websocket connection errors', () {
    final redacted = redactWsConnectError(
      "Connection to 'https://relay/ws?token=super-secret-token#' "
      'was not upgraded to websocket',
    );

    expect(redacted, contains('token=<redacted>'));
    expect(redacted, isNot(contains('super-secret-token')));
  });

  test(
    'recoverable auth failure uses recovery callback instead of retry loop',
    () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      var recoveryCalls = 0;
      var authFailed = false;
      var connectAttempts = 0;

      final service = WsService(
        connectChannel: (_) {
          connectAttempts += 1;
          return _failingWebSocketChannel(
            const WebSocketException(
              "Connection to 'https://relay/ws?token=stale-token#' "
              'was not upgraded to websocket',
            ),
          );
        },
      );

      try {
        WsService.setUrl('wss://relay/ws');
        WsService.setToken('stale-token');
        service.onAuthRecoveryRequired = () async {
          recoveryCalls += 1;
          return false;
        };
        service.onAuthFailed = () {
          authFailed = true;
        };

        await service.connect();

        expect(connectAttempts, 1);
        expect(recoveryCalls, 1);
        expect(authFailed, isTrue);
        expect(logs.where((line) => line.contains('Retry #')), isEmpty);
        expect(logs.join('\n'), isNot(contains('stale-token')));
      } finally {
        service.dispose();
        debugPrint = originalDebugPrint;
      }
    },
  );
}

WebSocketChannel _failingWebSocketChannel(Object error) {
  final channel = _MockWebSocketChannel();
  final sink = _MockWebSocketSink();
  when(() => channel.ready).thenAnswer((_) => Future<void>.error(error));
  when(() => channel.sink).thenReturn(sink);
  when(() => channel.stream).thenAnswer((_) => const Stream<dynamic>.empty());
  when(() => sink.close()).thenAnswer((_) async {});
  return channel;
}

class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}
