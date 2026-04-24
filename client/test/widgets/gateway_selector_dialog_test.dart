import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

/// 从 ConversationListScreen 中提取的 Gateway 选择器逻辑
/// 用于单独测试 dialog UI
Widget _buildGatewaySelectorDialog(
  BuildContext context,
  List<ConnectedAccount> accounts,
  void Function(ConnectedAccount?) onSelect,
) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return AlertDialog(
    title: const Text('新建会话'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '请选择 AI 后端',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        ...accounts.map((a) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.smart_toy_outlined, color: cs.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(a.accountId, style: tt.titleSmall)),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant.withOpacity(0.4), size: 20),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    ),
    contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
  );
}

void main() {
  group('Gateway selector dialog', () {
    final twoAccounts = [
      const ConnectedAccount(accountId: 'OpenClaw', agentName: 'OpenClaw'),
      const ConnectedAccount(accountId: 'nanobot', agentName: 'Nanobot'),
    ];

    Widget wrap(Widget child) {
      return ProviderScope(
        child: MaterialApp(home: Scaffold(body: child)),
      );
    }

    testWidgets('显示引导文字"请选择 AI 后端"', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.text('请选择 AI 后端'), findsOneWidget);
    });

    testWidgets('显示所有 gateway 的 accountId', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.text('OpenClaw'), findsOneWidget);
      expect(find.text('nanobot'), findsOneWidget);
    });

    testWidgets('每个选项都有 chevron_right 图标', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });

    testWidgets('每个选项都有 smart_toy 图标', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.byIcon(Icons.smart_toy_outlined), findsNWidgets(2));
    });

    testWidgets('点击选项返回对应的 account', (tester) async {
      ConnectedAccount? result;
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(
          ctx, twoAccounts, (a) => result = a,
        ),
      )));
      await tester.tap(find.text('nanobot'));
      expect(result?.accountId, 'nanobot');
    });

    testWidgets('无取消按钮（点击外部关闭）', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('标题显示"新建会话"', (tester) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => _buildGatewaySelectorDialog(ctx, twoAccounts, (_) {}),
      )));
      expect(find.text('新建会话'), findsOneWidget);
    });
  });
}
