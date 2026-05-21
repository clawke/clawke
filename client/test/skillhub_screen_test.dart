import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/skillhub_item.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/skillhub_provider.dart';
import 'package:client/screens/skillhub_screen.dart';
import 'package:client/services/skillhub_api_service.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads catalog and sends search filters', (tester) async {
    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    expect(find.text('SkillHub'), findsWidgets);
    expect(find.text('安装Skill，给Agent插上翅膀。'), findsOneWidget);
    expect(find.text('GitHub Helper'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('全部 Gateway'), findsNothing);

    await tester.enterText(find.byType(TextField), 'git');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();

    expect(api.lastQuery, 'git');
    expect(api.lastGatewayType, isNull);

    await tester.tap(find.text('Coding'));
    await tester.pumpAndSettle();

    expect(api.lastCategory, 'coding');
    expect(api.lastTag, isNull);
  });

  testWidgets('shows localized SkillHub timeout error', (tester) async {
    final api = _FakeSkillHubApiService(
      listError: const SkillHubApiException(
        'SkillHub request timed out',
        actionError: 'receive_timeout',
      ),
    );
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    expect(find.text('SkillHub 服务响应较慢，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('The request took longer'), findsNothing);
    expect(find.text('SkillHub request timed out'), findsNothing);
  });

  testWidgets('uses English localized SkillHub labels', (tester) async {
    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api, locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Install Skills to extend your Agent.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Search'), findsOneWidget);

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    expect(find.text('Install Status'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Install'), findsOneWidget);
    expect(find.text('安装Skill，给Agent插上翅膀。'), findsNothing);
  });

  testWidgets('loads next catalog page when scrolled near bottom', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(
      listResults: [
        SkillHubListResult(
          items: List.generate(
            12,
            (index) => _skill(
              id: '${300 + index}',
              name: 'Page 1 Skill ${index + 1}',
              slug: 'page-1-skill-${index + 1}',
            ),
          ),
          nextCursor: '1779019593000:5773',
          total: 12,
        ),
        SkillHubListResult(
          items: [
            _skill(
              id: '400',
              name: 'Loaded More Skill',
              slug: 'loaded-more-skill',
            ),
          ],
          nextCursor: null,
          total: 1,
        ),
      ],
    );
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    expect(api.requestedCursors, [null]);
    expect(find.text('Loaded More Skill'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.requestedCursors, [null, '1779019593000:5773']);
    expect(find.text('Loaded More Skill'), findsOneWidget);
  });

  testWidgets('opens catalog item detail', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    expect(api.lastDetailId, '204');
    expect(find.text('SKILL.md'), findsWidgets);
    expect(find.text('# GitHub Helper'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '1.2.1',
      ),
      findsOneWidget,
    );
    expect(find.text('安装'), findsOneWidget);
  });

  testWidgets('mobile detail moves usage and Skill markdown to the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    final installTop = tester.getTopLeft(find.text('安装状态')).dy;
    final packageTop = tester.getTopLeft(find.text('包信息')).dy;
    final gatewayTop = tester.getTopLeft(find.text('兼容 Gateway')).dy;
    final usageTop = tester.getTopLeft(find.text('使用说明')).dy;
    final skillMdTop = tester.getTopLeft(find.text('# GitHub Helper')).dy;

    expect(installTop, lessThan(usageTop));
    expect(packageTop, lessThan(usageTop));
    expect(gatewayTop, lessThan(usageTop));
    expect(usageTop, lessThan(skillMdTop));
  });

  testWidgets('mobile detail lets long summary use the full panel width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const summary =
        '这是一个很长的 Skill 描述，用来确认详情页不会一直把正文压在头像右侧，'
        '而是让正文自动回到卡片完整宽度，减少头像下面的大块空白。';
    final api = _FakeSkillHubApiService(summary: summary);
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    final titleLeft = tester.getTopLeft(find.text('GitHub Helper')).dx;
    final summaryLeft = tester.getTopLeft(_contentText(summary)).dx;

    expect(summaryLeft, lessThan(titleLeft));
  });

  testWidgets('desktop detail lets long summary use the full panel width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const summary =
        '这是一个很长的 Skill 描述，用来确认桌面详情页不会一直把正文压在头像右侧，'
        '而是让正文自动回到卡片完整宽度，减少头像下面的大块空白。';
    final api = _FakeSkillHubApiService(summary: summary);
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    final titleLeft = tester.getTopLeft(find.text('GitHub Helper')).dx;
    final summaryLeft = tester.getTopLeft(_contentText(summary)).dx;

    expect(summaryLeft, lessThan(titleLeft));
  });

  testWidgets('detail hides gateway compatibility when gateway is unselected', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(compatibility: '');
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    expect(find.text('未选择 Gateway'), findsNothing);
  });

  testWidgets('install uses managed mode before asking for Gateway', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();

    expect(find.text('选择 Gateway'), findsNothing);
    expect(api.lastGatewayId, isNull);
    expect(api.lastGatewayType, isNull);
    expect(api.lastInstallMode, 'auto');
    expect(find.text('安装完成'), findsOneWidget);
  });

  testWidgets('fallback prompt sends selected gateway native install', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(
      installError: const SkillHubApiException(
        '请选择要安装到的 Gateway',
        actionError: 'fallback_gateway_required',
        details: {
          'gateways': [
            {
              'gatewayId': 'openclaw-local',
              'label': 'OpenClaw · 本机',
              'gatewayType': 'openclaw',
            },
            {
              'gatewayId': 'hermes-local',
              'label': 'Hermes · 本机',
              'gatewayType': 'hermes',
            },
          ],
        },
      ),
    );
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();

    expect(find.text('选择 Gateway'), findsOneWidget);
    expect(find.text('OpenClaw · 本机'), findsOneWidget);
    expect(find.text('Hermes · 本机'), findsOneWidget);
    await tester.tap(find.text('Hermes · 本机'));
    await tester.pumpAndSettle();

    expect(api.installCalls, 2);
    expect(api.lastGatewayId, 'hermes-local');
    expect(api.lastGatewayType, 'hermes');
    expect(api.lastInstallMode, 'gateway_native');
  });

  testWidgets('install failure snackbar text is selectable', (tester) async {
    final api = _FakeSkillHubApiService(
      installError: const SkillHubApiException(
        'gateway_id is required when gateway native install is needed.',
        actionError: 'account_required',
      ),
    );
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pump();

    expect(
      find.widgetWithText(
        SelectableText,
        'gateway_id is required when gateway native install is needed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows async install status updates from websocket', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(
      installResult: const SkillHubInstallResult(
        installId: 'skillhub_1',
        installed: false,
        status: 'accepted',
        message: '安装任务已提交',
      ),
    );
    final container = ProviderContainer(overrides: _testOverrides(api));
    addTearDown(container.dispose);
    await tester.pumpWidget(_testAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('安装任务已提交'), findsWidgets);

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'installing',
      'message': '正在安装',
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在安装 Skill'), findsOneWidget);

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'installed',
      'message': '安装完成',
    });
    await tester.pumpAndSettle();
    expect(find.text('安装完成'), findsWidgets);
  });

  testWidgets('detail status row reflects managed install progress', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(
      installResult: const SkillHubInstallResult(
        installId: 'skillhub_1',
        installed: false,
        status: 'accepted',
        message: '安装任务已提交',
      ),
    );
    final container = ProviderContainer(overrides: _testOverrides(api));
    addTearDown(container.dispose);
    await tester.pumpWidget(_testAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('安装任务已提交'), findsWidgets);

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'downloading',
      'message': '正在下载',
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('正在下载'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '安装中'), findsOneWidget);

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'installed',
      'message': '安装完成',
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('已安装'), findsWidgets);
  });

  testWidgets('detail status row keeps failed async install message readable', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(
      installResult: const SkillHubInstallResult(
        installId: 'skillhub_1',
        installed: false,
        status: 'accepted',
        message: '安装任务已提交',
      ),
    );
    final container = ProviderContainer(overrides: _testOverrides(api));
    addTearDown(container.dispose);
    await tester.pumpWidget(_testAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pump(const Duration(milliseconds: 100));

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'extracting',
      'message': '正在解压安装包',
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在解压安装包'), findsOneWidget);

    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'installId': 'skillhub_1',
      'status': 'failed',
      'message': '解压安装包失败：Illegal byte sequence',
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('解压安装包失败：Illegal byte sequence'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '安装'), findsOneWidget);
  });

  testWidgets('detail install button uses the same install action', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装'));
    await tester.pumpAndSettle();

    expect(api.lastInstalledId, '204');
    expect(api.lastGatewayId, isNull);
    expect(api.lastInstallMode, 'auto');
    expect(find.text('安装完成'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '已安装'), findsOneWidget);
  });

  testWidgets(
    'detail hides uninstalled sources and exposes built-in path on tooltip',
    (tester) async {
      final api = _FakeSkillHubApiService();
      const builtInPath = '/tmp/openclaw/skills/github-helper/SKILL.md';
      final skillsApi = _FakeSkillsApiService(
        installedSlugs: {'github-helper'},
        installedGatewayId: 'openclaw-local',
        pathPrefix: '/tmp/openclaw/skills',
      );
      await tester.pumpWidget(_testApp(api, skillsApi: skillsApi));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GitHub Helper'));
      await tester.pumpAndSettle();

      expect(find.text('SkillHub'), findsOneWidget);
      expect(find.text('未安装'), findsNothing);
      expect(find.text('OpenClaw · 本机'), findsWidgets);
      expect(find.text('内置安装'), findsWidgets);
      expect(find.text(builtInPath), findsNothing);
      expect(find.byTooltip(builtInPath), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      final tooltipState = tester.state<RawTooltipState>(
        find.byTooltip(builtInPath),
      );
      tooltipState.ensureTooltipVisible();
      await tester.pumpAndSettle();
      expect(find.text(builtInPath), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '安装'), findsOneWidget);
    },
  );

  testWidgets('detail can show built-in and SkillHub installed together', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    const skillHubPath = '/tmp/skillhub/github-helper/SKILL.md';
    const builtInPath = '/tmp/hermes/skills/github-helper/SKILL.md';
    final skillsApi = _FakeSkillsApiService(
      installedSlugs: {'github-helper'},
      installedGatewayId: 'hermes-local',
      pathPrefix: '/tmp/hermes/skills',
    );
    final container = ProviderContainer(
      overrides: _testOverrides(api, skillsApi: skillsApi),
    );
    addTearDown(container.dispose);
    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'slug': 'github-helper',
      'status': 'installed',
      'message': '安装完成',
      'path': skillHubPath,
    });
    await tester.pumpWidget(_testAppWithContainer(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    expect(find.text('SkillHub'), findsWidgets);
    expect(find.text('已安装'), findsWidgets);
    expect(find.text('Hermes · 本机'), findsWidgets);
    expect(find.text('内置安装'), findsWidgets);
    expect(find.text(skillHubPath), findsNothing);
    expect(find.text(builtInPath), findsNothing);
    expect(find.byTooltip(skillHubPath), findsOneWidget);
    expect(find.byTooltip(builtInPath), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, '已安装'), findsOneWidget);
  });

  testWidgets('catalog card shows built-in marker from skill cache', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    final skillCache = _FakeSkillCacheRepository(
      installedSlugs: {'github-helper'},
      installedGatewayId: 'openclaw-local',
    );
    await tester.pumpWidget(_testApp(api, skillCache: skillCache));
    await tester.pumpAndSettle();

    expect(find.text('GitHub Helper'), findsOneWidget);
    expect(find.text('内置安装'), findsOneWidget);
    expect(find.text('已安装'), findsNothing);
  });

  testWidgets('catalog built-in marker does not push summary down', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeSkillHubApiService(itemCount: 2);
    final skillCache = _FakeSkillCacheRepository(
      installedSlugs: {'skill-1'},
      installedGatewayId: 'openclaw-local',
    );
    await tester.pumpWidget(_testApp(api, skillCache: skillCache));
    await tester.pumpAndSettle();

    final summaries = _contentText('一个面向 GitHub 工作流的 Skill。');
    expect(summaries, findsNWidgets(2));
    final firstSummaryTop = tester.getTopLeft(summaries.at(0)).dy;
    final secondSummaryTop = tester.getTopLeft(summaries.at(1)).dy;
    expect((firstSummaryTop - secondSummaryTop).abs(), lessThan(1));
  });

  testWidgets('catalog card can show built-in and SkillHub installed markers', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    final skillCache = _FakeSkillCacheRepository(
      installedSlugs: {'github-helper'},
      installedGatewayId: 'openclaw-local',
    );
    final container = ProviderContainer(
      overrides: _testOverrides(api, skillCache: skillCache),
    );
    addTearDown(container.dispose);
    container.read(skillHubControllerProvider.notifier).handleInstallStatus({
      'slug': 'github-helper',
      'status': 'installed',
      'message': '安装完成',
    });
    await tester.pumpWidget(_testAppWithContainer(container));
    await tester.pumpAndSettle();

    expect(find.text('GitHub Helper'), findsOneWidget);
    expect(find.text('内置安装'), findsOneWidget);
    expect(find.text('已安装'), findsOneWidget);
  });

  testWidgets('detail does not offer install to another gateway', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService();
    final skillsApi = _FakeSkillsApiService(
      installedSlugs: {'github-helper'},
      installedGatewayId: 'hermes-local',
    );
    await tester.pumpWidget(_testApp(api, skillsApi: skillsApi));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub Helper'));
    await tester.pumpAndSettle();

    expect(find.text('内置安装'), findsWidgets);
    expect(find.text('Hermes · 本机'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '安装到其他 Gateway'), findsNothing);
    expect(find.widgetWithText(FilledButton, '安装'), findsOneWidget);
  });

  testWidgets('catalog card with long summary does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeSkillHubApiService(
      summary:
          'UI/UX design intelligence and implementation guidance for building polished interfaces. '
          'Use when the user asks for UI design, UX flows, information architecture, visual style direction, '
          'design systems, component specs, copy, accessibility, or implementation critique.',
    );
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog card omits bottom metadata and install shortcut', (
    tester,
  ) async {
    final api = _FakeSkillHubApiService(compatibility: '');
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    expect(find.text('No Tag'), findsNothing);
    expect(find.text('github'), findsNothing);
    expect(find.text('code'), findsNothing);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('未选择 Gateway'), findsNothing);
    expect(find.byTooltip('安装 GitHub Helper'), findsNothing);
  });

  testWidgets('catalog grid shows three cards per row on wide layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = _FakeSkillHubApiService(itemCount: 4);
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    final offsets = [
      tester.getTopLeft(find.text('Skill 1')),
      tester.getTopLeft(find.text('Skill 2')),
      tester.getTopLeft(find.text('Skill 3')),
      tester.getTopLeft(find.text('Skill 4')),
    ];

    expect(offsets[1].dy, offsets[0].dy);
    expect(offsets[2].dy, offsets[0].dy);
    expect(offsets[3].dy > offsets[0].dy, isTrue);
    expect(offsets[1].dx > offsets[0].dx, isTrue);
    expect(offsets[2].dx > offsets[1].dx, isTrue);
    expect(offsets[3].dx, offsets[0].dx);
  });
}

Widget _testApp(
  _FakeSkillHubApiService api, {
  _FakeSkillsApiService? skillsApi,
  SkillCacheRepository? skillCache,
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: _testOverrides(
      api,
      skillsApi: skillsApi,
      skillCache: skillCache,
    ),
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SkillHubScreen(showAppBar: true),
    ),
  );
}

Widget _testAppWithContainer(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      locale: Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SkillHubScreen(showAppBar: true),
    ),
  );
}

List<Override> _testOverrides(
  _FakeSkillHubApiService api, {
  _FakeSkillsApiService? skillsApi,
  SkillCacheRepository? skillCache,
}) {
  return [
    skillHubApiServiceProvider.overrideWithValue(api),
    skillsApiServiceProvider.overrideWithValue(
      skillsApi ?? _FakeSkillsApiService(),
    ),
    skillCacheRepositoryProvider.overrideWithValue(
      skillCache ?? _FakeSkillCacheRepository(),
    ),
    onlineGatewayListProvider.overrideWith((ref) {
      return Stream.value(const [
        GatewayInfo(
          gatewayId: 'openclaw-local',
          displayName: 'OpenClaw · 本机',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['chat', 'skills'],
        ),
        GatewayInfo(
          gatewayId: 'hermes-local',
          displayName: 'Hermes · 本机',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['chat', 'skills'],
        ),
      ]);
    }),
  ];
}

class _FakeSkillsApiService extends SkillsApiService {
  final Set<String> installedSlugs;
  final String? installedGatewayId;
  final String pathPrefix;

  _FakeSkillsApiService({
    this.installedSlugs = const {},
    this.installedGatewayId,
    this.pathPrefix = '/tmp/gateway/skills',
  });

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    if (installedGatewayId != null && scope?.gatewayId != installedGatewayId) {
      return const [];
    }
    return [
      for (final slug in installedSlugs)
        ManagedSkill(
          id: '${scope?.gatewayId ?? 'gateway'}/$slug',
          name: slug,
          description: '$slug skill',
          category: scope?.gatewayId ?? 'gateway',
          enabled: true,
          source: 'external',
          sourceLabel: scope?.label ?? '',
          writable: false,
          deletable: false,
          path: '$slug/SKILL.md',
          absolutePath: '$pathPrefix/$slug/SKILL.md',
          root: pathPrefix,
          updatedAt: 0,
          hasConflict: false,
        ),
    ];
  }
}

class _FakeSkillCacheRepository implements SkillCacheRepository {
  final Set<String> installedSlugs;
  final String? installedGatewayId;

  _FakeSkillCacheRepository({
    this.installedSlugs = const {},
    this.installedGatewayId,
  });

  @override
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return Stream.value(_skillsFor(gatewayId));
  }

  @override
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return _skillsFor(gatewayId);
  }

  @override
  Future<List<ManagedSkill>> syncGateway(
    SkillScope scope,
    String locale,
  ) async {
    return _skillsFor(scope.gatewayId);
  }

  List<ManagedSkill> _skillsFor(String? gatewayId) {
    if (installedGatewayId != null && gatewayId != installedGatewayId) {
      return const [];
    }
    return [
      for (final slug in installedSlugs)
        ManagedSkill(
          id: 'general/$slug',
          name: slug,
          description: '$slug skill',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke skills',
          writable: true,
          deletable: true,
          path: '$slug/SKILL.md',
          absolutePath: '/tmp/clawke-e2e-skills/$slug/SKILL.md',
          root: '/tmp/clawke-e2e-skills',
          updatedAt: 0,
          hasConflict: false,
        ),
    ];
  }

  @override
  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    return _skillsFor(
      scope.gatewayId,
    ).where((skill) => skill.id == id).firstOrNull;
  }

  @override
  Future<ManagedSkill?> getDetail(String id, SkillScope scope, String locale) {
    return getCachedSkill(id, scope, locale);
  }

  @override
  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id, SkillScope? scope) async {}

  @override
  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) async {}
}

class _FakeSkillHubApiService extends SkillHubApiService {
  final String? summary;
  final String? compatibility;
  final int itemCount;
  final List<SkillHubListResult>? listResults;
  final SkillHubInstallResult installResult;
  final SkillHubApiException? listError;
  String? lastQuery;
  String? lastCategory;
  String? lastTag;
  String? lastGatewayType;
  String? lastGatewayId;
  String? lastInstallMode;
  String? lastDetailId;
  String? lastInstalledId;
  int installCalls = 0;
  final SkillHubApiException? installError;
  final List<String?> requestedCursors = [];

  _FakeSkillHubApiService({
    this.summary,
    this.compatibility,
    this.itemCount = 1,
    this.listResults,
    this.installResult = const SkillHubInstallResult(
      installed: true,
      status: 'installed',
      message: '安装完成',
    ),
    this.listError,
    this.installError,
  });

  @override
  Future<SkillHubListResult> listSkills({
    String? query,
    String? category,
    String? tag,
    bool? featured,
    String? gatewayType,
    int? limit,
    String? cursor,
  }) async {
    lastQuery = query;
    lastCategory = category;
    lastTag = tag;
    lastGatewayType = gatewayType;
    requestedCursors.add(cursor);
    if (listError != null) throw listError!;
    final results = listResults;
    if (results != null && requestedCursors.length <= results.length) {
      return results[requestedCursors.length - 1];
    }
    return SkillHubListResult(
      items: List.generate(
        itemCount,
        (index) => _skill(
          id: '${204 + index}',
          name: itemCount == 1 ? 'GitHub Helper' : 'Skill ${index + 1}',
          slug: itemCount == 1 ? 'github-helper' : 'skill-${index + 1}',
          summary: summary,
          compatibility: compatibility,
        ),
      ),
      total: itemCount,
    );
  }

  @override
  Future<SkillHubItem> getSkill(String id, {String? gatewayType}) async {
    lastDetailId = id;
    lastGatewayType = gatewayType;
    return _skill(
      summary: summary,
      compatibility: compatibility,
      usage: '在 GitHub 仓库内处理 issue、PR、release 和 review。',
      originalSkillMd: '# GitHub Helper',
      packageSkillMdPaths: ['SKILL.md'],
    );
  }

  @override
  Future<SkillHubInstallResult> installSkill(
    SkillHubItem item, {
    String? gatewayId,
    String? gatewayType,
    String? installMode,
  }) async {
    installCalls += 1;
    if (installCalls == 1 && installError != null) throw installError!;
    lastInstalledId = item.id;
    lastGatewayId = gatewayId;
    lastGatewayType = gatewayType;
    lastInstallMode = installMode;
    return installResult;
  }
}

SkillHubItem _skill({
  String id = '204',
  String name = 'GitHub Helper',
  String slug = 'github-helper',
  String? summary,
  String? compatibility,
  String usage = '',
  String originalSkillMd = '',
  List<String> packageSkillMdPaths = const [],
}) {
  return SkillHubItem(
    id: id,
    slug: slug,
    name: name,
    summary: summary ?? '一个面向 GitHub 工作流的 Skill。',
    category: 'coding',
    tags: const ['github', 'code'],
    source: 'clawhub',
    sourceOwner: 'garrytan',
    sourceUrl: 'https://clawhub.ai/garrytan/github-helper',
    featured: true,
    downloadCount: 1200,
    version: '1.2.1',
    changelog: 'Initial release',
    license: 'MIT-0',
    packageUrl: 'https://clawke.ai/package.zip',
    packageSha256: 'sha256:abc',
    packageSize: 45678,
    compatibleGateways: const ['openclaw'],
    compatibility: compatibility ?? 'compatible',
    packageType: 'bundle',
    packageSkillMdPaths: packageSkillMdPaths,
    updatedAt: 1778664000000,
    status: 'published',
    usage: usage,
    originalSkillMd: originalSkillMd,
  );
}

Finder _contentText(String data) {
  return find.byWidgetPredicate((widget) {
    if (widget is Text) return widget.data == data;
    if (widget is SelectableText) return widget.data == data;
    return false;
  });
}
