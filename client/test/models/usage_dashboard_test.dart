import 'package:client/models/usage_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UsageDashboard parses summary, model, and recent usage', () {
    final dashboard = UsageDashboard.fromJson({
      'gateway_id': 'hermes',
      'summary': {
        'input': 100,
        'output': 50,
        'cacheRead': 20,
        'cacheWrite': 5,
        'reasoning': 7,
        'total': 182,
      },
      'todayMessages': 3,
      'totalConversations': 9,
      'today': {'input': 10, 'output': 5, 'total': 15},
      'hourly': [
        {'hour': '13:00', 'tokens': 15},
      ],
      'daily': [
        {'date': '2026-05-11', 'input': 10, 'output': 5, 'total': 15},
      ],
      'models': [
        {
          'model': 'claude-sonnet',
          'provider': 'anthropic',
          'calls': 2,
          'input': 100,
          'output': 50,
          'total': 150,
        },
      ],
      'recent': [
        {
          'gateway_id': 'hermes',
          'conversation_id': 'conv_1',
          'model': 'claude-sonnet',
          'provider': 'anthropic',
          'created_at': 1778500000000,
          'input': 10,
          'output': 5,
          'total': 15,
        },
      ],
    });

    expect(dashboard.gatewayId, 'hermes');
    expect(dashboard.summary.total, 182);
    expect(dashboard.summary.cacheRead, 20);
    expect(dashboard.summary.cacheWrite, 5);
    expect(dashboard.summary.reasoning, 7);
    expect(dashboard.today.output, 5);
    expect(dashboard.todayMessages, 3);
    expect(dashboard.totalConversations, 9);
    expect(dashboard.hourly.single.hour, '13:00');
    expect(dashboard.hourly.single.total, 15);
    expect(dashboard.models.single.calls, 2);
    expect(dashboard.recent.single.conversationId, 'conv_1');
    expect(dashboard.hasUsage, isTrue);
  });

  test('UsageDashboard accepts snake case cache fields', () {
    final totals = UsageTotals.fromJson({'cache_read': 3, 'cache_write': 4});

    expect(totals.cacheRead, 3);
    expect(totals.cacheWrite, 4);
  });
}
