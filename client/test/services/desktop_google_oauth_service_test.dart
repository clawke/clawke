import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:client/services/desktop_google_oauth_service.dart';

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
  group('DesktopGoogleOAuthService', () {
    test('completes browser loopback OAuth flow', () async {
      final browserBody = Completer<String>();
      final jwt = _fakeJwt({
        'sub': 'google-user-1',
        'email': 'user@example.com',
        'name': 'Clawke User',
      });
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((
          options,
          requestStream,
          cancelFuture,
        ) async {
          expect(options.uri.toString(), 'https://oauth2.googleapis.com/token');
          final form = await _readFormBody(requestStream);
          expect(form['client_id'], 'desktop-client-id');
          expect(form['code'], 'oauth-code');
          expect(form['code_verifier'], 'verifier-token');
          expect(form['grant_type'], 'authorization_code');
          expect(form['redirect_uri'], startsWith('http://127.0.0.1:'));
          expect(form['redirect_uri'], isNot(endsWith('/')));
          expect(form.containsKey('client_secret'), isFalse);

          return ResponseBody.fromString(
            jsonEncode({'id_token': jwt, 'access_token': 'access-token'}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
            },
          );
        });

      final service = DesktopGoogleOAuthService(
        clientId: 'desktop-client-id',
        dio: dio,
        randomString: (length) =>
            length == 32 ? 'state-token' : 'verifier-token',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          expect(mode, LaunchMode.externalApplication);
          expect(uri.host, 'accounts.google.com');
          expect(uri.queryParameters['client_id'], 'desktop-client-id');
          expect(uri.queryParameters['state'], 'state-token');
          expect(uri.queryParameters['code_challenge_method'], 'S256');
          expect(uri.queryParameters['redirect_uri'], isNotEmpty);
          expect(uri.queryParameters['redirect_uri'], isNot(endsWith('/')));

          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          unawaited(
            _sendLoopbackCallback(
              redirectUri,
              uri,
            ).then(browserBody.complete, onError: browserBody.completeError),
          );
          return true;
        },
      );

      final account = await service.signIn();
      final completionHtml = await browserBody.future;

      expect(account.id, 'google-user-1');
      expect(account.email, 'user@example.com');
      expect(account.displayName, 'Clawke User');
      expect(account.idToken, jwt);
      expect(account.accessToken, 'access-token');
      expect(completionHtml, contains('window.close()'));
      expect(completionHtml, contains('Returning to Clawke'));
      expect(completionHtml, contains('如果浏览器没有自动关闭'));
    });

    test('sends client secret when configured', () async {
      final jwt = _fakeJwt({
        'sub': 'google-user-1',
        'email': 'user@example.com',
      });
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((
          options,
          requestStream,
          cancelFuture,
        ) async {
          final form = await _readFormBody(requestStream);
          expect(form['client_secret'], 'desktop-client-secret');

          return ResponseBody.fromString(
            jsonEncode({'id_token': jwt, 'access_token': 'access-token'}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
            },
          );
        });

      final service = DesktopGoogleOAuthService(
        clientId: 'desktop-client-id',
        clientSecret: 'desktop-client-secret',
        dio: dio,
        randomString: (length) =>
            length == 32 ? 'state-token' : 'verifier-token',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          unawaited(_sendLoopbackCallback(redirectUri, uri));
          return true;
        },
      );

      final account = await service.signIn();

      expect(account.id, 'google-user-1');
    });

    test('surfaces Google token error details', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((
          options,
          requestStream,
          cancelFuture,
        ) async {
          return ResponseBody.fromString(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'Bad Request',
            }),
            400,
            headers: {
              Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
            },
          );
        });

      final service = DesktopGoogleOAuthService(
        clientId: 'desktop-client-id',
        dio: dio,
        randomString: (length) =>
            length == 32 ? 'state-token' : 'verifier-token',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          unawaited(_sendLoopbackCallback(redirectUri, uri));
          return true;
        },
      );

      await expectLater(
        service.signIn(),
        throwsA(
          isA<DesktopGoogleOAuthException>().having(
            (e) => e.message,
            'message',
            contains('invalid_grant - Bad Request'),
          ),
        ),
      );
    });

    test('builds account from Google token response', () {
      final jwt = _fakeJwt({
        'sub': 'google-user-1',
        'email': 'user@example.com',
        'name': 'Clawke User',
        'picture': 'https://example.com/avatar.png',
      });

      final account = DesktopGoogleOAuthService.accountFromTokenForTest({
        'id_token': jwt,
        'access_token': 'access-token',
      });

      expect(account.id, 'google-user-1');
      expect(account.email, 'user@example.com');
      expect(account.displayName, 'Clawke User');
      expect(account.photoUrl, 'https://example.com/avatar.png');
      expect(account.idToken, jwt);
      expect(account.accessToken, 'access-token');
    });

    test('rejects token response without Google user identity', () {
      final jwt = _fakeJwt({'email': 'user@example.com'});

      expect(
        () => DesktopGoogleOAuthService.accountFromTokenForTest({
          'id_token': jwt,
          'access_token': 'access-token',
        }),
        throwsA(isA<DesktopGoogleOAuthException>()),
      );
    });

    test('rejects malformed id token', () {
      expect(
        () => DesktopGoogleOAuthService.decodeJwtPayloadForTest('not-a-jwt'),
        throwsA(isA<DesktopGoogleOAuthException>()),
      );
    });
  });
}

String _fakeJwt(Map<String, dynamic> claims) {
  final header = _base64UrlJson({'alg': 'none', 'typ': 'JWT'});
  final payload = _base64UrlJson(claims);
  return '$header.$payload.';
}

String _base64UrlJson(Map<String, dynamic> value) =>
    base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<String> _sendLoopbackCallback(Uri redirectUri, Uri authUri) async {
  final client = HttpClient();
  try {
    final callbackUri = redirectUri.replace(
      queryParameters: {
        'code': 'oauth-code',
        'state': authUri.queryParameters['state']!,
      },
    );
    final request = await client.getUrl(callbackUri);
    final response = await request.close();
    return utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _readFormBody(
  Stream<Uint8List>? requestStream,
) async {
  if (requestStream == null) return {};
  final builder = BytesBuilder();
  await for (final chunk in requestStream) {
    builder.add(chunk);
  }
  return Uri.splitQueryString(utf8.decode(builder.takeBytes()));
}
