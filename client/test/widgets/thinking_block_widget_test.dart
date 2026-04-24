import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/widgets/thinking_block_widget.dart';
import '../helpers/pump_helpers.dart';
import '../helpers/provider_overrides.dart';

void main() {
  group('ThinkingBlockWidget', () {
    testWidgets('渲染基本结构：Thinking 标题和 psychology 图标', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '让我分析一下这个问题...'),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 标题文本
      expect(find.text('Thinking'), findsOneWidget);
      // psychology 图标
      expect(find.byIcon(Icons.psychology), findsOneWidget);
      // 箭头图标
      expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    });

    testWidgets('isStreaming=true 显示 Thinking... 和 spinner', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '思考中...', isStreaming: true),
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('Thinking...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('isStreaming=false 默认折叠，不显示 spinner', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '这段内容默认不可见'),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // AnimatedCrossFade 时 firstChild = SizedBox.shrink 可见
      // content 区域在折叠状态下应该不可见（通过 AnimatedCrossFade 控制）
    });

    testWidgets('点击头部可展开，再次点击可折叠', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '可展开的内容'),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      // 初始：折叠状态，查找 AnimatedCrossFade 并检查状态
      final crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showFirst);

      // 点击展开
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      final crossFadeExpanded = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFadeExpanded.crossFadeState, CrossFadeState.showSecond);

      // 再次点击折叠
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      final crossFadeCollapsed = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFadeCollapsed.crossFadeState, CrossFadeState.showFirst);
    });

    testWidgets('isStreaming=true 默认展开', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '流式内容', isStreaming: true),
        overrides: overrides,
      );
      await tester.pump();

      final crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showSecond);
    });

    testWidgets('从 isStreaming=true 切换为 false 自动收起', (tester) async {
      final (overrides, _) = wsOverrides();

      // 先 pump streaming 状态
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: '流式内容', isStreaming: true),
        overrides: overrides,
      );
      await tester.pump();

      // 确认初始展开
      var crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showSecond);

      // 切换为非流式状态（模拟 thinking_done）
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: Scaffold(
              body: ThinkingBlockWidget(
                content: '流式内容（完成）',
                isStreaming: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 应自动收起
      crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showFirst);
    });

    testWidgets('空 content 不崩溃', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const ThinkingBlockWidget(content: ''),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      expect(find.text('Thinking'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
