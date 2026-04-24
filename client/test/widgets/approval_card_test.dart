import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/providers/approval_provider.dart';
import 'package:client/widgets/approval_card.dart';
import '../helpers/pump_helpers.dart';
import '../helpers/provider_overrides.dart';

void main() {
  group('ApprovalCard', () {
    final request = ApprovalRequest(
      messageId: 'test_approval_1',
      conversationId: 'conv_1',
      command: 'rm -rf /tmp/test',
      description: 'AI 想要删除临时文件',
    );

    testWidgets('渲染基本结构：盾牌图标、标题、描述、命令', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedChoice;

      await pumpApp(
        tester,
        ApprovalCard(
          request: request,
          onRespond: (choice) => receivedChoice = choice,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 标题
      expect(find.text('需要确认'), findsOneWidget);
      // 盾牌图标
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      // 描述
      expect(find.text('AI 想要删除临时文件'), findsOneWidget);
      // 命令
      expect(find.text('rm -rf /tmp/test'), findsOneWidget);
      // 4 个按钮
      expect(find.text('允许'), findsOneWidget);
      expect(find.text('本次会话'), findsOneWidget);
      expect(find.text('始终允许'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
    });

    testWidgets('点击「允许」触发 onRespond("once")', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedChoice;

      await pumpApp(
        tester,
        ApprovalCard(
          request: request,
          onRespond: (choice) => receivedChoice = choice,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('允许'));
      expect(receivedChoice, 'once');
    });

    testWidgets('点击「拒绝」触发 onRespond("deny")', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedChoice;

      await pumpApp(
        tester,
        ApprovalCard(
          request: request,
          onRespond: (choice) => receivedChoice = choice,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拒绝'));
      expect(receivedChoice, 'deny');
    });

    testWidgets('点击「本次会话」触发 onRespond("session")', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedChoice;

      await pumpApp(
        tester,
        ApprovalCard(
          request: request,
          onRespond: (choice) => receivedChoice = choice,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('本次会话'));
      expect(receivedChoice, 'session');
    });

    testWidgets('点击「始终允许」触发 onRespond("always")', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedChoice;

      await pumpApp(
        tester,
        ApprovalCard(
          request: request,
          onRespond: (choice) => receivedChoice = choice,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('始终允许'));
      expect(receivedChoice, 'always');
    });

    testWidgets('空命令/描述不崩溃', (tester) async {
      final (overrides, _) = wsOverrides();
      final emptyRequest = ApprovalRequest(
        messageId: 'test_empty',
        conversationId: 'conv_1',
        command: '',
        description: '',
      );

      await pumpApp(
        tester,
        ApprovalCard(
          request: emptyRequest,
          onRespond: (_) {},
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('需要确认'), findsOneWidget);
    });
  });

  group('ClarifyCard', () {
    final request = ClarifyRequest(
      messageId: 'test_clarify_1',
      conversationId: 'conv_1',
      question: '你想在哪个目录执行？',
      choices: ['/tmp', '/home', '/var'],
    );

    testWidgets('渲染基本结构：问号图标、问题、选项按钮', (tester) async {
      final (overrides, _) = wsOverrides();

      await pumpApp(
        tester,
        ClarifyCard(
          request: request,
          onRespond: (_) {},
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 标题（ClarifyCard 也用「需要确认」标题）
      expect(find.text('需要确认'), findsOneWidget);
      // 问号图标
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      // 问题
      expect(find.text('你想在哪个目录执行？'), findsOneWidget);
      // 选项按钮
      expect(find.text('/tmp'), findsOneWidget);
      expect(find.text('/home'), findsOneWidget);
      expect(find.text('/var'), findsOneWidget);
      // 输入框
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('点击选项触发 onRespond', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedResponse;

      await pumpApp(
        tester,
        ClarifyCard(
          request: request,
          onRespond: (response) => receivedResponse = response,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('/tmp'));
      expect(receivedResponse, '/tmp');
    });

    testWidgets('输入自由文本并发送', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedResponse;

      await pumpApp(
        tester,
        ClarifyCard(
          request: request,
          onRespond: (response) => receivedResponse = response,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 输入文字
      await tester.enterText(find.byType(TextField), '/custom/path');
      await tester.pump();

      // 点击发送按钮
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(receivedResponse, '/custom/path');
    });

    testWidgets('空输入不触发 onRespond', (tester) async {
      final (overrides, _) = wsOverrides();
      String? receivedResponse;

      await pumpApp(
        tester,
        ClarifyCard(
          request: request,
          onRespond: (response) => receivedResponse = response,
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 不输入文字，直接点发送
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(receivedResponse, isNull);
    });

    testWidgets('无选项时只显示输入框', (tester) async {
      final (overrides, _) = wsOverrides();
      final noChoicesRequest = ClarifyRequest(
        messageId: 'test_no_choices',
        conversationId: 'conv_1',
        question: '请输入目标路径',
      );

      await pumpApp(
        tester,
        ClarifyCard(
          request: noChoicesRequest,
          onRespond: (_) {},
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      expect(find.text('请输入目标路径'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // 不应有「或输入自由回答」提示（无 choices 时不显示）
      expect(find.text('或输入自由回答：'), findsNothing);
    });
  });
}
