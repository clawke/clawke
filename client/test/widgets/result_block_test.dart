import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/widgets/highlighted_code_builder.dart';

/// 用 Builder 获取正确 context 的辅助 widget
class CodeFenceTestWrapper extends StatelessWidget {
  final String language;
  final String code;

  const CodeFenceTestWrapper({
    super.key,
    required this.language,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    return buildHighlightedCodeBlock(context, language, code, true);
  }
}

void main() {
  group('approval_result code fence', () {
    testWidgets('renders approved result with green border', (tester) async {
      const code = 'description: force kill processes\n'
          'command: pkill -9 -f "Code Helper"\n'
          'result: approved';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CodeFenceTestWrapper(language: 'approval_result', code: code),
            ),
          ),
        ),
      );

      // 验证描述文本
      expect(find.text('force kill processes'), findsOneWidget);
      // 验证命令文本
      expect(find.text('pkill -9 -f "Code Helper"'), findsOneWidget);
      // 验证状态文本
      expect(find.text('✅ 已允许'), findsOneWidget);
    });

    testWidgets('renders denied result with red border', (tester) async {
      const code = 'description: dangerous command\n'
          'command: rm -rf /\n'
          'result: denied';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CodeFenceTestWrapper(language: 'approval_result', code: code),
            ),
          ),
        ),
      );

      expect(find.text('dangerous command'), findsOneWidget);
      expect(find.text('rm -rf /'), findsOneWidget);
      expect(find.text('🚫 已拒绝'), findsOneWidget);
    });
  });

  group('clarify_result code fence', () {
    testWidgets('renders clarify result with blue border', (tester) async {
      const code = 'question: 你希望使用哪种编程语言？\n'
          'answer: Python';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CodeFenceTestWrapper(language: 'clarify_result', code: code),
            ),
          ),
        ),
      );

      // 验证问题和回答
      expect(find.text('你希望使用哪种编程语言？'), findsOneWidget);
      expect(find.text('Python'), findsOneWidget);
      expect(find.text('✅ 已选择'), findsOneWidget);
    });
  });
}
