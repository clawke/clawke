import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:client/services/config_api_service.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/l10n/l10n.dart';

/// 会话设置页面 — iOS 风格抽屉式导航
///
/// conversationId 为 null = 创建模式（点创建时生成 UUID）
/// conversationId 有值 = 编辑模式（返回时自动保存）
class ConversationSettingsSheet extends ConsumerStatefulWidget {
  final String? conversationId;
  final String accountId;
  /// 创建成功后的回调
  final void Function(String conversationId)? onCreated;

  const ConversationSettingsSheet({
    super.key,
    this.conversationId,
    required this.accountId,
    this.onCreated,
  });

  /// 快捷打开方法（编辑已有会话）— 全屏 push
  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    required String accountId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationSettingsSheet(
          conversationId: conversationId,
          accountId: accountId,
        ),
      ),
    );
  }

  /// 创建模式打开（点创建才生成 ID 并创建会话）
  static Future<void> showCreate(
    BuildContext context, {
    required String accountId,
    void Function(String conversationId)? onCreated,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationSettingsSheet(
          accountId: accountId,
          onCreated: onCreated,
        ),
      ),
    );
  }

  @override
  ConsumerState<ConversationSettingsSheet> createState() =>
      _ConversationSettingsSheetState();
}

class _ConversationSettingsSheetState
    extends ConsumerState<ConversationSettingsSheet> {
  final _api = ConfigApiService();
  bool _loading = true;
  bool _saving = false;

  bool get _isCreateMode => widget.conversationId == null;

  // 可选列表
  List<String> _availableModels = [];
  List<SkillInfo> _availableSkills = [];

  // 当前配置
  String? _selectedModel;
  Set<String> _selectedSkills = {};
  String _skillMode = 'priority';
  final _nameController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _workDirController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _systemPromptController.dispose();
    _workDirController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) setState(() => _loading = true);

    if (_isCreateMode && !refresh) {
      final results = await Future.wait([
        _api.getModels(accountId: widget.accountId, refresh: refresh),
        _api.getSkills(accountId: widget.accountId, refresh: refresh),
      ]);
      if (!mounted) return;
      setState(() {
        _availableModels = results[0] as List<String>;
        _availableSkills = results[1] as List<SkillInfo>;
        _nameController.text = 'New Chat';
        _loading = false;
      });
      return;
    }

    final results = await Future.wait([
      _api.getModels(accountId: widget.accountId, refresh: refresh),
      _api.getSkills(accountId: widget.accountId, refresh: refresh),
      _api.getConvConfig(widget.conversationId!),
      ref.read(conversationRepositoryProvider)
          .getConversationName(widget.conversationId!),
    ]);

    final models = results[0] as List<String>;
    final skills = results[1] as List<SkillInfo>;
    final config = results[2] as ConvConfig;
    final convName = results[3] as String?;

    if (!mounted) return;
    setState(() {
      _availableModels = models;
      _availableSkills = skills;
      if (!refresh) {
        _nameController.text = convName ?? '';
        _selectedModel = config.modelId;
        _selectedSkills = (config.skills ?? []).toSet();
        _skillMode = config.skillMode ?? 'priority';
        _systemPromptController.text = config.systemPrompt ?? '';
        _workDirController.text = config.workDir ?? '';
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final newName = _nameController.text.trim();

    // 创建模式：生成 UUID 并创建会话
    late final String convId;
    if (_isCreateMode) {
      convId = const Uuid().v4();
      await ref.read(conversationRepositoryProvider).createConversation(
        conversationId: convId,
        accountId: widget.accountId,
        type: 'ai',
        name: newName.isNotEmpty ? newName : widget.accountId,
      );
    } else {
      convId = widget.conversationId!;
    }

    // 保存配置
    final config = ConvConfig(
      convId: convId,
      accountId: widget.accountId,
      modelId: _selectedModel,
      skills: _selectedSkills.isEmpty ? null : _selectedSkills.toList(),
      skillMode: _selectedSkills.isEmpty ? null : _skillMode,
      systemPrompt: _systemPromptController.text.trim().isEmpty
          ? null
          : _systemPromptController.text.trim(),
      workDir: _workDirController.text.trim().isEmpty
          ? null
          : _workDirController.text.trim(),
    );
    await _api.saveConvConfig(convId, config);

    // 编辑模式：保存会话名称
    if (!_isCreateMode && newName.isNotEmpty) {
      await ref
          .read(conversationRepositoryProvider)
          .renameConversation(convId, newName);
    }

    if (mounted) {
      setState(() => _saving = false);
      // 创建模式：先关闭页面，再执行 callback (callback内部可能会push新页面，顺序不能错)
      if (_isCreateMode) {
        Navigator.of(context).pop();
      }
      widget.onCreated?.call(convId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // 编辑模式：返回时自动保存
        // 创建模式：返回 = 取消，不创建
        if (didPop && !_isCreateMode) _save();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
              _isCreateMode ? context.l10n.newConversation : context.l10n.conversationSettings),
          actions: [
            if (_isCreateMode)
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  context.l10n.create,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Gateway ──
                  _sectionLabel('Gateway'),
                  _buildGatewayCard(colorScheme),
                  const SizedBox(height: 24),

                  // ── 会话名称 ──
                  _sectionLabel(context.l10n.conversationName),
                  _buildNameInput(colorScheme),
                  const SizedBox(height: 24),

                  // ── 模型 ──
                  _sectionLabel(context.l10n.model),
                  _buildModelCard(colorScheme),
                  const SizedBox(height: 24),

                  // ── Skills ──
                  _sectionLabel('Skills'),
                  _buildSkillPanel(colorScheme),
                  const SizedBox(height: 24),

                  // ── 系统提示词 ──
                  _sectionLabel(context.l10n.systemPrompt),
                  _buildContentCard(
                    icon: Icons.description_outlined,
                    iconColor: const Color(0xFF60A5FA),
                    iconBg: const Color(0xFF60A5FA).withOpacity(0.12),
                    content: _systemPromptController.text.trim(),
                    placeholder: context.l10n.notSet,
                    onTap: () => _openSystemPromptEditor(colorScheme),
                  ),
                  const SizedBox(height: 24),

                  // ── 工作目录 ──
                  _sectionLabel(context.l10n.workDir),
                  _buildContentCard(
                    icon: Icons.folder_outlined,
                    iconColor: colorScheme.onSurfaceVariant,
                    iconBg: colorScheme.onSurfaceVariant.withOpacity(0.08),
                    content: _workDirController.text.trim(),
                    placeholder: 'default',
                    onTap: () => _openWorkDirEditor(colorScheme),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Section label
  // ═══════════════════════════════════════
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // 会话名称 — 左对齐输入框，带图标
  // ═══════════════════════════════════════
  Widget _buildNameInput(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _nameController,
                style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: context.l10n.enterConversationName,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Gateway 卡片 — Gateway 名称 + 会话 ID 小字
  // ═══════════════════════════════════════
  Widget _buildGatewayCard(ColorScheme colorScheme) {
    final sessionId = widget.conversationId ?? context.l10n.generatedAfterCreate;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.06),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.dns_outlined,
                  size: 16, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.accountId,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ID: $sessionId',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // 模型卡片 — 显示模型名称
  // ═══════════════════════════════════════
  Widget _buildModelCard(ColorScheme colorScheme) {
    final displayModel = _selectedModel ?? context.l10n.defaultModel;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openModelPicker(colorScheme),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.layers_rounded,
                    size: 16, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayModel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // Skill 面板 — E 风格，整体连接
  // ═══════════════════════════════════════
  Widget _buildSkillPanel(ColorScheme colorScheme) {
    final selectedList = _selectedSkills
        .map((name) => _availableSkills.where((s) => s.name == name).firstOrNull)
        .whereType<SkillInfo>()
        .toList();
    final modeText = _skillMode == 'exclusive' ? context.l10n.exclusiveTrigger : context.l10n.priorityTrigger;
    final dotColors = [
      const Color(0xFF34D399),
      const Color(0xFF60A5FA),
      const Color(0xFF6C63FF),
      const Color(0xFFFB923C),
      const Color(0xFFF472B6),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header — 点击进入 Skill 修改页
          InkWell(
            onTap: () => _openSkillPicker(colorScheme),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.build_rounded,
                        size: 16, color: Color(0xFF34D399)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedList.isEmpty
                              ? context.l10n.skillsNotEnabled
                              : context.l10n.skillsEnabledCount(selectedList.length),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (selectedList.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            modeText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _skillMode == 'exclusive'
                                  ? const Color(0xFFFB923C)
                                  : colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                ],
              ),
            ),
          ),
          // Skill list items
          if (selectedList.isNotEmpty) ...[
            Divider(height: 1, thickness: 1,
                color: colorScheme.outlineVariant.withOpacity(0.15)),
            ...selectedList.asMap().entries.map((entry) {
              final i = entry.key;
              final skill = entry.value;
              final isLast = i == selectedList.length - 1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: colorScheme.outlineVariant.withOpacity(0.1),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        color: dotColors[i % dotColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skill.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (skill.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                skill.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // 内容卡片 — 图标左侧居中，内容居中，箭头右侧
  // ═══════════════════════════════════════
  Widget _buildContentCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String content,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasContent = content.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasContent ? content : placeholder,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: hasContent
                      ? colorScheme.onSurfaceVariant.withOpacity(0.6)
                      : colorScheme.onSurfaceVariant.withOpacity(0.25),
                  fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // 模型选择器 — 子页面（抽屉式 push）
  // ═══════════════════════════════════════
  void _openModelPicker(ColorScheme colorScheme) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _ModelPickerPage(
          models: _availableModels,
          selected: _selectedModel,
          onRefresh: () async {
            final models = await _api.getModels(
                accountId: widget.accountId, refresh: true);
            setState(() => _availableModels = models);
            return models;
          },
        ),
      ),
    );
    if (result != null || result == '') {
      setState(() => _selectedModel = result!.isEmpty ? null : result);
    }
  }

  // ═══════════════════════════════════════
  // Skill 选择器 — 子页面（抽屉式 push）
  // ═══════════════════════════════════════
  void _openSkillPicker(ColorScheme colorScheme) async {
    final result = await Navigator.of(context).push<_SkillPickerResult?>(
      MaterialPageRoute(
        builder: (_) => _SkillPickerPage(
          availableSkills: _availableSkills,
          selectedSkills: Set.from(_selectedSkills),
          skillMode: _skillMode,
          onRefresh: () async {
            final skills = await _api.getSkills(
                accountId: widget.accountId, refresh: true);
            setState(() => _availableSkills = skills);
            return skills;
          },
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedSkills = result.selected;
        _skillMode = result.mode;
      });
    }
  }

  // ═══════════════════════════════════════
  // 系统提示词编辑器 — 子页面
  // ═══════════════════════════════════════
  void _openSystemPromptEditor(ColorScheme colorScheme) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _TextEditorPage(
          title: context.l10n.systemPrompt,
          hint: context.l10n.systemPromptHint,
          initialValue: _systemPromptController.text,
          maxLines: 8,
        ),
      ),
    );
    if (result != null) {
      setState(() => _systemPromptController.text = result);
    }
  }

  // ═══════════════════════════════════════
  // 工作目录编辑器 — 子页面
  // ═══════════════════════════════════════
  void _openWorkDirEditor(ColorScheme colorScheme) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _WorkDirPage(
          initialValue: _workDirController.text,
        ),
      ),
    );
    if (result != null) {
      setState(() => _workDirController.text = result);
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Model Picker 子页面
// ═══════════════════════════════════════════════════════════
class _ModelPickerPage extends StatefulWidget {
  final List<String> models;
  final String? selected;
  final Future<List<String>> Function()? onRefresh;

  const _ModelPickerPage({required this.models, this.selected, this.onRefresh});

  @override
  State<_ModelPickerPage> createState() => _ModelPickerPageState();
}

class _ModelPickerPageState extends State<_ModelPickerPage> {
  late List<String> _models;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _models = List.from(widget.models);
  }

  Future<void> _refresh() async {
    if (widget.onRefresh == null) return;
    setState(() => _refreshing = true);
    try {
      final newModels = await widget.onRefresh!();
      if (mounted) setState(() => _models = newModels);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(context.l10n.selectModel),
        actions: [
          if (widget.onRefresh != null)
            IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 20),
              tooltip: context.l10n.refreshModelList,
              onPressed: _refreshing ? null : _refresh,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 默认模型
                _buildModelItem(null, context.l10n.defaultModel, colorScheme),
                if (_models.isEmpty)
                  // 空状态提示
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.gatewayNoModelSupport,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._models.map(
                    (m) => _buildModelItem(m, m, colorScheme),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelItem(
    String? value,
    String label,
    ColorScheme colorScheme,
  ) {
    final isSelected = widget.selected == value;
    return InkWell(
      onTap: () => Navigator.of(context).pop(value ?? ''),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded,
                  size: 20, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Skill Picker 子页面 — 搜索 + Toggle + Mode
// ═══════════════════════════════════════════════════════════
class _SkillPickerResult {
  final Set<String> selected;
  final String mode;
  const _SkillPickerResult({required this.selected, required this.mode});
}

class _SkillPickerPage extends StatefulWidget {
  final List<SkillInfo> availableSkills;
  final Set<String> selectedSkills;
  final String skillMode;
  final Future<List<SkillInfo>> Function()? onRefresh;

  const _SkillPickerPage({
    required this.availableSkills,
    required this.selectedSkills,
    required this.skillMode,
    this.onRefresh,
  });

  @override
  State<_SkillPickerPage> createState() => _SkillPickerPageState();
}

class _SkillPickerPageState extends State<_SkillPickerPage> {
  late Set<String> _selected;
  late String _mode;
  late List<SkillInfo> _skills;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedSkills);
    _mode = widget.skillMode;
    _skills = List.from(widget.availableSkills);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (widget.onRefresh == null) return;
    setState(() => _refreshing = true);
    try {
      final newSkills = await widget.onRefresh!();
      if (mounted) setState(() => _skills = newSkills);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Filter & sort: selected first
    final filtered = _searchQuery.isEmpty
        ? _skills
        : _skills.where((s) =>
            s.name.toLowerCase().contains(_searchQuery) ||
            s.description.toLowerCase().contains(_searchQuery));
    final sorted = filtered.toList()
      ..sort((a, b) {
        final aS = _selected.contains(a.name) ? 0 : 1;
        final bS = _selected.contains(b.name) ? 0 : 1;
        if (aS != bS) return aS - bS;
        if (aS == 0 && bS == 0) {
          final selList = _selected.toList();
          return selList.indexOf(a.name) - selList.indexOf(b.name);
        }
        return a.name.compareTo(b.name);
      });

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {});
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context)
                .pop(_SkillPickerResult(selected: _selected, mode: _mode)),
          ),
          title: Text(context.l10n.selectSkills),
          actions: [
            if (widget.onRefresh != null)
              IconButton(
                icon: _refreshing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 20),
                tooltip: context.l10n.refreshSkillsList,
                onPressed: _refreshing ? null : _refresh,
              ),
          ],
        ),
        body: _skills.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.extension_off_rounded,
                          size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.gatewayNoSkillSupport,
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.clickRefreshToRetry,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
          children: [

            // Chips row for selected
            if (_selected.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _selected.toList().map((name) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name.replaceFirst('gstack-openclaw-', ''),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _selected.remove(name)),
                            child: Icon(Icons.close_rounded,
                                size: 14, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Mode toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildModeBtn(context.l10n.priorityTrigger, 'priority', colorScheme),
                    _buildModeBtn(context.l10n.exclusiveTrigger, 'exclusive', colorScheme),
                  ],
                ),
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: context.l10n.searchSkills,
                  hintStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                  isDense: true,
                  filled: true,
                  fillColor:
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),

            const SizedBox(height: 8),

            // Skill list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final skill = sorted[index];
                  final selected = _selected.contains(skill.name);
                  return _buildSkillToggleItem(skill, selected, colorScheme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBtn(String label, String value, ColorScheme colorScheme) {
    final isActive = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? Colors.white
                  : colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkillToggleItem(
    SkillInfo skill,
    bool selected,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selected.remove(skill.name);
          } else {
            _selected.add(skill.name);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (skill.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44, height: 26,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch.adaptive(
                  value: selected,
                  activeColor: colorScheme.primary,
                  onChanged: (v) {
                    setState(() {
                      if (v) {
                        _selected.add(skill.name);
                      } else {
                        _selected.remove(skill.name);
                      }
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 文本编辑器子页面（系统提示词）
// ═══════════════════════════════════════════════════════════
class _TextEditorPage extends StatefulWidget {
  final String title;
  final String hint;
  final String initialValue;
  final int maxLines;

  const _TextEditorPage({
    required this.title,
    required this.hint,
    required this.initialValue,
    this.maxLines = 6,
  });

  @override
  State<_TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<_TextEditorPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 工作目录子页面
// ═══════════════════════════════════════════════════════════
class _WorkDirPage extends StatefulWidget {
  final String initialValue;
  const _WorkDirPage({required this.initialValue});

  @override
  State<_WorkDirPage> createState() => _WorkDirPageState();
}

class _WorkDirPageState extends State<_WorkDirPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
        title: Text(context.l10n.workDir),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(
                    fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: context.l10n.workDirHint,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.3),
                  ),
                  prefixIcon: Icon(Icons.folder_outlined,
                      size: 18,
                      color:
                          colorScheme.onSurfaceVariant.withOpacity(0.4)),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear,
                              size: 18,
                              color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                          onPressed: () => setState(() => _controller.clear()),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                context.l10n.workDirNote,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
