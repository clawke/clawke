import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/http_util.dart';

/// A simple fake adapter for Dio to intercept requests and return pre-defined responses.
class FakeHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) handler;

  FakeHttpClientAdapter(this.handler);

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
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('HttpUtil Unit Tests', () {
    test('doPost injects Cookie from SharedPreferences', () async {
      // 1. Arrange: set mock values
      SharedPreferences.setMockInitialValues({
        'clawke_auth_uid': 'test_uid_123',
        'clawke_auth_securit': 'test_securit_abc',
      });

      String? capturedCookie;

      // Setup fake adapter
      HttpUtil.setMockAdapter(FakeHttpClientAdapter((options, stream, cancel) async {
        // Capture headers sent out
        capturedCookie = options.headers['Cookie'];

        // Return dummy success
        final payload = jsonEncode({
          'success': true,
          'value': {'test': 'cookie_ok'},
        });
        return ResponseBody.fromString(payload, 200, headers: {
          Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
        });
      }));

      // 2. Act
      await HttpUtil.doPost('/test/endpoint');

      // 3. Assert
      expect(capturedCookie, contains('__UID=test_uid_123'));
      expect(capturedCookie, contains('__SECURIT=test_securit_abc'));
    });

    test('doPost throws ApiException on success: false', () async {
      SharedPreferences.setMockInitialValues({});

      HttpUtil.setMockAdapter(FakeHttpClientAdapter((options, stream, cancel) async {
        final payload = jsonEncode({
          'success': false,
          'actionError': 'custom.error.code',
          'actionMessage': 'You failed to login',
        });
        return ResponseBody.fromString(payload, 200, headers: {
           Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
        });
      }));

      // Expect an exception of type ApiException since success=false
      expect(
        () async => await HttpUtil.doPost('/test/fail'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'custom.error.code')),
      );
    });

    test('doPost parses direct success objects safely', () async {
      SharedPreferences.setMockInitialValues({});

      HttpUtil.setMockAdapter(FakeHttpClientAdapter((options, stream, cancel) async {
        final payload = jsonEncode({
          'success': true,
          'value': {'username': 'bob'},
        });
        return ResponseBody.fromString(payload, 200, headers: {
           Headers.contentTypeHeader: ['application/json;charset=UTF-8'],
        });
      }));

      final result = await HttpUtil.doPost('/test/ok');
      expect(result['success'], isTrue);
      expect(result['value']['username'], 'bob');
    });

    test('doPost handles non-200 HTTP status gracefully', () async {
      SharedPreferences.setMockInitialValues({});

      HttpUtil.setMockAdapter(FakeHttpClientAdapter((options, stream, cancel) async {
        // Return 500 error code
        return ResponseBody.fromString('Internal Server Error', 500);
      }));

      expect(
        () async => await HttpUtil.doPost('/test/500'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('网络返回状态异常：500'))),
      );
    });
  });
}
