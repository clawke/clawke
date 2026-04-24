import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/widgets/highlighted_code_builder.dart';
import 'package:client/l10n/app_localizations.dart';

/// 辅助 widget：在 build 中调用 buildHighlightedCodeBlock，
/// 拿到正确的 BuildContext
class _InlineCardHost extends StatelessWidget {
  final String language;
  final String code;
  const _InlineCardHost({required this.language, required this.code});

  @override
  Widget build(BuildContext context) {
    return buildHighlightedCodeBlock(context, language, code, true);
  }
}

/// 包裹一个带 i18n 的 MaterialApp
Widget _buildApp(Widget child, {Locale locale = const Locale('zh')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Inline Approval Card - 回调链路测试', () {
    setUp(() {
      setClarifyResponseCallback(null);
      setCardContentUpdateCallback(null);
    });

    tearDown(() {
      setClarifyResponseCallback(null);
      setCardContentUpdateCallback(null);
    });

    const approvalCode =
        'command: rm ~/test.txt\n'
        'description: 删除测试文件\n'
        'risk: medium';

    testWidgets('点击「允许」→ onRespond 收到 "y"', (tester) async {
      String? response;
      setClarifyResponseCallback((r) => response = r);

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      // 验证卡片渲染（中文 locale）
      expect(find.text('需要确认'), findsOneWidget);
      expect(find.text('rm ~/test.txt'), findsOneWidget);

      // 点击允许
      await tester.tap(find.text('允许'));
      await tester.pumpAndSettle();

      expect(response, 'y');
    });

    testWidgets('点击「拒绝」→ onRespond 收到 "n"', (tester) async {
      String? response;
      setClarifyResponseCallback((r) => response = r);

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      expect(response, 'n');
    });

    testWidgets('点击「允许」→ _onCardContentUpdate 被调用，参数正确', (tester) async {
      String? capturedCodeBlock;
      String? capturedReplacement;
      setClarifyResponseCallback((_) {});
      setCardContentUpdateCallback((codeBlock, replacement) {
        capturedCodeBlock = codeBlock;
        capturedReplacement = replacement;
      });

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('允许'));
      await tester.pumpAndSettle();

      // 验证 _onCardContentUpdate 被调用
      expect(
        capturedCodeBlock,
        isNotNull,
        reason: '_onCardContentUpdate 必须被调用',
      );
      expect(capturedCodeBlock, contains('```approval'));
      expect(capturedCodeBlock, contains('rm ~/test.txt'));
      expect(capturedCodeBlock, contains('```'));
      // 持久化层保存结构化结果，UI 再把 result fence 渲染成「已允许」。
      expect(capturedReplacement, contains('```approval_result'));
      expect(capturedReplacement, contains('result: approved'));
      expect(capturedReplacement, contains('rm ~/test.txt'));
    });

    testWidgets('点击「拒绝」→ _onCardContentUpdate replacement 包含「已拒绝」', (
      tester,
    ) async {
      String? capturedReplacement;
      setClarifyResponseCallback((_) {});
      setCardContentUpdateCallback((_, replacement) {
        capturedReplacement = replacement;
      });

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      expect(capturedReplacement, isNotNull);
      expect(capturedReplacement, contains('```approval_result'));
      expect(capturedReplacement, contains('result: denied'));
    });

    testWidgets('回调未设置时（null），点击不崩溃', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('允许'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('点击后按钮消失，显示「已允许」文本', (tester) async {
      setClarifyResponseCallback((_) {});

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      // 点击前：有按钮
      expect(find.text('允许'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);

      await tester.tap(find.text('允许'));
      await tester.pumpAndSettle();

      // 点击后：按钮消失，显示结果
      expect(find.text('已允许'), findsOneWidget);
    });

    testWidgets('重复点击只触发一次回调', (tester) async {
      int count = 0;
      setClarifyResponseCallback((_) => count++);

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('允许'));
      await tester.pumpAndSettle();

      // 点击后按钮已消失，验证回调只触发一次
      expect(count, 1);
    });

    testWidgets('English locale shows English text', (tester) async {
      setClarifyResponseCallback((_) {});

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'approval', code: approvalCode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmation Required'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
    });
  });

  group('Inline Clarify Card - 回调链路测试', () {
    setUp(() {
      setClarifyResponseCallback(null);
      setCardContentUpdateCallback(null);
    });

    tearDown(() {
      setClarifyResponseCallback(null);
      setCardContentUpdateCallback(null);
    });

    const clarifyCode =
        'question: 你想在哪个目录执行？\n'
        'choices:\n'
        '- /tmp\n'
        '- /home\n'
        '- /var';

    testWidgets('点击选项 → onRespond 收到选项文本', (tester) async {
      String? response;
      setClarifyResponseCallback((r) => response = r);

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'clarify', code: clarifyCode),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('你想在哪个目录执行？'), findsOneWidget);

      await tester.tap(find.text('/tmp'));
      await tester.pumpAndSettle();

      expect(response, '/tmp');
    });

    testWidgets('点击选项 → _onCardContentUpdate 被调用', (tester) async {
      String? capturedCodeBlock;
      String? capturedReplacement;
      setClarifyResponseCallback((_) {});
      setCardContentUpdateCallback((codeBlock, replacement) {
        capturedCodeBlock = codeBlock;
        capturedReplacement = replacement;
      });

      await tester.pumpWidget(
        _buildApp(
          const _InlineCardHost(language: 'clarify', code: clarifyCode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('/home'));
      await tester.pumpAndSettle();

      expect(
        capturedCodeBlock,
        isNotNull,
        reason: '_onCardContentUpdate 必须被调用',
      );
      expect(capturedCodeBlock, contains('```clarify'));
      expect(capturedReplacement, contains('```clarify_result'));
      expect(capturedReplacement, contains('/home'));
    });
  });
}
