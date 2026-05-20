# Client 模块开发规则

适用于 `client/**` 下的 Flutter 原生客户端代码。开始修改 `client/**` 前，先读取根目录 `CLAUDE.md`，再读取本文件。

## 启动与验证

- macOS Client 调试必须在 `client/` 目录启动，并带上 `--dart-define=CLAWKE_RUNTIME_DIR=.runtime/mac-client`，避免落到 `~/Documents` 触发沙箱和 SQLite 路径问题
- Flutter 测试文件必须放在 `client/test/` 下，以 `_test.dart` 结尾
- 修改核心逻辑、状态流转、UI 行为后必须运行对应测试；常用命令：`flutter test --no-pub <test-file>`
- 多个 Flutter 命令不要并行跑，避免 startup lock 互相抢锁

## 文本可复制规范

- 内容型文本必须可选中复制：路径、ID、URL、版本号、错误信息、日志、正文、详情页字段值等，必须使用 `CopyableText`（`client/lib/widgets/copyable_text.dart`），禁止直接使用裸 `Text` 或散落的 `SelectableText`
- 控件型文案继续使用 `Text`：按钮、导航、筛选 chip、菜单项、Tab、状态徽标等以点击/切换为主的 UI 文案，不强制可选，避免和点击、拖拽、滚动手势冲突
- 全局 `SelectionArea` 只是桌面端兜底，不能当作详情页复制能力的唯一保障；详情页/管理页中用户可能复制的字段必须显式走 `CopyableText`
- 新增详情页或管理页如果包含内容型文本，必须复用 `CopyableText`，并把对应文件加入 `client/test/widgets/copyable_text_test.dart` 的静态扫描列表，防止回归

## 国际化规范

- 严禁新增中文硬编码 UI 文案。所有用户可见文本必须写入 `client/lib/l10n/app_zh.arb` 和 `client/lib/l10n/app_en.arb`，通过 `context.l10n` / `AppLocalizations` 使用
- 修改 ARB 后必须运行 `cd client && flutter gen-l10n`，并提交生成的 `app_localizations*.dart`
- 状态类 UI 文案必须优先由稳定状态码映射到本地化文本；不要把后端传来的中文 `message` 直接当作最终 UI 文案
- 技能、路径、ID、URL、错误详情、日志等用户数据保持原样显示，不做本地化翻译
- 测试中新增 UI 文案断言时，至少覆盖默认中文；涉及国际化改造时必须补一个英文 locale 的冒烟断言，防止页面漏接 l10n

## 字体规范

- 基准字体：`bodyMedium` = 16sp，所有其他文本样式基于此按比例放大/缩小
- 新代码禁止硬编码 `fontSize`，必须通过 `Theme.of(context).textTheme.bodyMedium` 等 textTheme 引用
- 现有硬编码字号逐步迁移，修改前需用户审核
- 用户可通过设置调整 `fontScale`（70%–130%），所有 textTheme 字号自动乘以该系数
- 详细字号对照表见 `docs/font-spec.md`

## UI 调整工作流

- 使用 UI-UX-Pro-Max skill 做 UI 调整时，必须先更新 `docs/private/demo/<feature-name>-demo.html`
- 内部 UI Demo / 预览统一放私有 demo 目录，不放公开 `docs/`
- 等用户确认预览效果后，再修改 `client/` 下的 Dart 代码
- 右上角主操作按钮必须统一为“图标 + 文字”，移动端和 PC / 大屏都必须同时显示图标与文字，不使用纯图标按钮
