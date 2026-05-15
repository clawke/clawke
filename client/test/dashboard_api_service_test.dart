import 'dart:convert';
import 'dart:io';

import 'package:client/services/dashboard_api_service.dart';
import 'package:client/services/media_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedRequest {
  final String method;
  final Uri uri;

  const _RecordedRequest(this.method, this.uri);
}

void main() {
  late HttpServer server;
  late List<_RecordedRequest> requests;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    MediaResolver.setBaseUrl('http://127.0.0.1:${server.port}');
    MediaResolver.setToken('');
    server.listen((request) async {
      requests.add(_RecordedRequest(request.method, request.uri));

      final response = switch ((request.method, request.uri.path)) {
        ('GET', '/api/dashboard/usage') => {
          'gateway_id': request.uri.queryParameters['gateway_id'],
          'summary': {'input': 120, 'output': 80, 'total': 200},
          'todayMessages': 4,
          'totalConversations': 11,
          'today': {'input': 12, 'output': 8, 'total': 20},
          'hourly': [
            {'hour': '13:00', 'tokens': 20},
          ],
          'daily': [
            {'date': '2026-05-11', 'input': 12, 'output': 8, 'total': 20},
          ],
          'models': [
            {
              'model': 'claude-sonnet',
              'provider': 'anthropic',
              'calls': 1,
              'input': 12,
              'output': 8,
              'total': 20,
            },
          ],
          'recent': [
            {
              'gateway_id': 'hermes',
              'conversation_id': 'conv_1',
              'model': 'claude-sonnet',
              'provider': 'anthropic',
              'created_at': 1778500000000,
              'input': 12,
              'output': 8,
              'total': 20,
            },
          ],
        },
        _ => {'error': 'not_found'},
      };

      request.response
        ..statusCode = response.containsKey('error') ? 404 : 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('DashboardApiService requests gateway usage dashboard', () async {
    final api = DashboardApiService();

    final dashboard = await api.getUsage(gatewayId: 'hermes');

    expect(dashboard.gatewayId, 'hermes');
    expect(dashboard.summary.total, 200);
    expect(dashboard.todayMessages, 4);
    expect(dashboard.totalConversations, 11);
    expect(dashboard.hourly.single.total, 20);
    expect(dashboard.models.single.model, 'claude-sonnet');
    expect(dashboard.recent.single.conversationId, 'conv_1');
    expect(requests.single.method, 'GET');
    expect(requests.single.uri.path, '/api/dashboard/usage');
    expect(requests.single.uri.queryParameters['gateway_id'], 'hermes');
  });
}
