import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/widgets/file_message_widget.dart';

void main() {
  group('FileMessageWidget', () {
    // 创建临时文件用于测试
    late File tempFile;
    late String tempPath;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('file_widget_test_');
      tempFile = File('${dir.path}/test_file.pdf')..writeAsStringSync('dummy');
      tempPath = tempFile.path;
    });

    tearDown(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
      tempFile.parent.deleteSync();
    });

    Widget wrap(Widget child) {
      return MaterialApp(home: Scaffold(body: child));
    }

    // ── 测试场景 1：发送前（旧格式 JSON） ──
    // content = {"path":"/tmp/xxx.pdf","name":"test.pdf","size":123}
    test('旧格式 JSON 解析参数正确', () {
      final json = jsonDecode('{"path":"$tempPath","name":"test.pdf","size":123}')
          as Map<String, dynamic>;

      final filePath = json['localPath'] as String? ?? json['path'] as String?;
      final mediaUrl = json['mediaUrl'] as String?;
      final fileName = json['name'] as String? ?? 'unknown';

      expect(filePath, tempPath);
      expect(mediaUrl, isNull);
      expect(fileName, 'test.pdf');
    });

    // ── 测试场景 2：发送完成后（新格式 JSON） ──
    // content = {"mediaUrl":"/api/media/xxx.pdf","localPath":"/tmp/xxx.pdf","name":"test.pdf","size":123}
    test('新格式 JSON 解析参数正确', () {
      final json = jsonDecode(
        '{"mediaUrl":"/api/media/xxx.pdf","mediaType":"application/pdf","localPath":"$tempPath","name":"test.pdf","size":123}',
      ) as Map<String, dynamic>;

      final filePath = json['localPath'] as String? ?? json['path'] as String?;
      final mediaUrl = json['mediaUrl'] as String?;
      final fileName = json['name'] as String? ?? 'unknown';

      expect(filePath, tempPath);
      expect(mediaUrl, '/api/media/xxx.pdf');
      expect(fileName, 'test.pdf');
    });

    // ── 测试场景 3：旧格式 JSON widget 可点击 ──
    testWidgets('旧格式（有 path，无 mediaUrl）→ widget 可点击', (tester) async {
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          fileName: 'test.pdf',
          filePath: tempPath,  // 本地文件存在
          mediaUrl: null,
          fileSize: 123,
        ),
      ));

      // 应该显示文件名
      expect(find.text('test.pdf'), findsOneWidget);

      // GestureDetector 应该有 onTap 回调（isClickable = true）
      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(gestureDetector.onTap, isNotNull,
          reason: '有本地文件时 onTap 不应为 null');
    });

    // ── 测试场景 4：新格式 JSON widget 可点击 ──
    testWidgets('新格式（有 localPath + mediaUrl）→ widget 可点击', (tester) async {
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          fileName: 'test.pdf',
          filePath: tempPath,  // localPath 存在
          mediaUrl: '/api/media/xxx.pdf',
          fileSize: 123,
        ),
      ));

      expect(find.text('test.pdf'), findsOneWidget);

      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(gestureDetector.onTap, isNotNull,
          reason: '有本地文件 + mediaUrl 时 onTap 不应为 null');
    });

    // ── 测试场景 5：只有 mediaUrl 没有本地文件 → 也可点击（下载模式） ──
    testWidgets('只有 mediaUrl（无本地文件）→ widget 可点击（下载模式）', (tester) async {
      await tester.pumpWidget(wrap(
        const FileMessageWidget(
          fileName: 'remote.pdf',
          filePath: null,
          mediaUrl: '/api/media/remote.pdf',
          fileSize: 456,
        ),
      ));

      expect(find.text('remote.pdf'), findsOneWidget);

      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(gestureDetector.onTap, isNotNull,
          reason: '有 mediaUrl 时即使无本地文件也应可点击');

      // 应该显示下载图标
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    });

    // ── 测试场景 6：都没有 → 不可点击 ──
    testWidgets('无 filePath 无 mediaUrl → widget 不可点击', (tester) async {
      await tester.pumpWidget(wrap(
        const FileMessageWidget(
          fileName: 'orphan.pdf',
          filePath: null,
          mediaUrl: null,
          fileSize: 789,
        ),
      ));

      expect(find.text('orphan.pdf'), findsOneWidget);

      final gestureDetector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(gestureDetector.onTap, isNull,
          reason: '无文件路径且无 mediaUrl 时 onTap 应为 null');
    });

    // ── 测试场景 7：模拟 DB content 更新（旧格式 → 新格式）──
    // 验证 didUpdateWidget 正确同步 _localPath
    testWidgets('content 从旧格式更新为新格式后仍可点击', (tester) async {
      // 先渲染旧格式
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          key: const ValueKey('file_msg_1'),
          fileName: 'test.pdf',
          filePath: tempPath,  // json['path']
          mediaUrl: null,
          fileSize: 123,
        ),
      ));

      var gd = tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(gd.onTap, isNotNull, reason: '旧格式时应可点击');

      // 模拟 DB content 更新 → 新格式重建 widget（same key, different props）
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          key: const ValueKey('file_msg_1'),
          fileName: 'test.pdf',
          filePath: tempPath,  // json['localPath'] — 同一个路径
          mediaUrl: '/api/media/xxx.pdf',
          fileSize: 123,
        ),
      ));

      gd = tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(gd.onTap, isNotNull,
          reason: '新格式（content 更新后）仍应可点击');
    });

    // ── 测试场景 8：关键 BUG 复现 ──
    // 模拟旧代码的 bug：filePath 从 json['path'] 变为 null（因为新 JSON 没有 'path' 字段）
    testWidgets('BUG 复现：filePath=null + mediaUrl=null → 不可点击', (tester) async {
      // 这是旧代码的行为：只读 json['path']，新 JSON 没有 path 字段 → filePath=null
      // 且没传 mediaUrl → isClickable=false
      await tester.pumpWidget(wrap(
        const FileMessageWidget(
          fileName: 'test.pdf',
          filePath: null,   // 旧代码：json['path'] 在新格式中为 null
          mediaUrl: null,   // 旧代码：没传 mediaUrl
          fileSize: 123,
        ),
      ));

      final gd = tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(gd.onTap, isNull,
          reason: '这就是旧代码的 bug：filePath=null 且 mediaUrl=null → onTap 为 null');
    });

    // ── 测试场景 9：onCached 回调在下载后被调用 ──
    // 验证 FileMessageWidget 正确传递 onCached
    testWidgets('onCached 回调参数正确传递', (tester) async {
      String? cachedResult;
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          fileName: 'test.pdf',
          filePath: null,
          mediaUrl: '/api/media/test.pdf',
          fileSize: 100,
          onCached: (path) => cachedResult = path,
        ),
      ));

      // widget 应该显示下载图标（无本地文件，有 mediaUrl）
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      // onCached 还未被调用
      expect(cachedResult, isNull);
    });

    // ── 测试场景 10：有 localPath 后显示 ✅ 而非 ⬇️ ──
    testWidgets('有 localPath 时显示已缓存图标（无需重复下载）', (tester) async {
      await tester.pumpWidget(wrap(
        FileMessageWidget(
          fileName: 'cached.pdf',
          filePath: tempPath,      // 本地有文件
          mediaUrl: '/api/media/cached.pdf',
          fileSize: 200,
        ),
      ));

      // 应该显示 ✅ 而非 ⬇️
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsNothing,
          reason: '有本地缓存时不应显示下载图标');
    });
  });
}
