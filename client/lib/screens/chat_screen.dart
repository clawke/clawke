import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
// path_provider used via MediaCacheService
import 'package:client/services/media_cache_service.dart';
import 'package:client/services/media_upload_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/models/message_model.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/chat_limit_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/reply_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/screens/conversation_settings_sheet.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/widgets/message_context_menu.dart';
import 'package:client/widgets/image_message_widget.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/widgets/file_message_widget.dart';
import 'package:client/widgets/mixed_message_widget.dart';
import 'package:client/widgets/staged_attachments_preview.dart';
import 'package:client/providers/staged_attachments_provider.dart';
import 'package:client/providers/upload_progress_provider.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/widgets/widget_factory.dart';
import 'package:client/widgets/thinking_block_widget.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:client/widgets/highlighted_code_builder.dart';
import 'package:client/providers/mermaid_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _focusNode;
  bool _isLoadingMore = false;

  final List<String> _messageHistory = [];
  int _historyIndex = 0;
  String? _draftText;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    // 监听滚动，到顶部时加载更多
    _scrollController.addListener(_onScroll);
    // 选中会话时清零未读
    // sync 由 WsMessageHandler._onConnected 统一处理，此处不再重复发送
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final convId = ref.read(selectedConversationIdProvider);
      if (convId != null) {
        ref.read(conversationRepositoryProvider).markAsRead(convId);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        final atStart =
            _controller.selection.isValid &&
            _controller.selection.isCollapsed &&
            _controller.selection.baseOffset == 0;

        if (_controller.text.isEmpty || atStart) {
          if (_messageHistory.isNotEmpty && _historyIndex > 0) {
            setState(() {
              if (_historyIndex == _messageHistory.length) {
                // 第一次向上翻历史前，保存当前输入框草稿
                _draftText = _controller.text;
              }
              _historyIndex--;
              _controller.text = _messageHistory[_historyIndex];
              _controller.selection = TextSelection.collapsed(
                offset: _controller.text.length,
              );
            });
            return KeyEventResult.handled;
          }
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final atEnd =
            _controller.selection.isValid &&
            _controller.selection.isCollapsed &&
            _controller.selection.baseOffset == _controller.text.length;

        if (_historyIndex < _messageHistory.length &&
            (_controller.text.isEmpty || atEnd)) {
          setState(() {
            _historyIndex++;
            if (_historyIndex < _messageHistory.length) {
              _controller.text = _messageHistory[_historyIndex];
            } else {
              // 恢复到用户刚开始输入的草稿状态
              _controller.text = _draftText ?? '';
              _draftText = null;
            }
            _controller.selection = TextSelection.collapsed(
              offset: _controller.text.length,
            );
          });
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_controller.text.isNotEmpty) {
          setState(() {
            _historyIndex = _messageHistory.length;
            _controller.clear();
            _draftText = null;
          });
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftLeft,
          ) &&
          !HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftRight,
          ) &&
          _controller.value.composing == TextRange.empty) {
        // Enter（无 Shift）→ 发送（仅在已连接且非流式状态下）
        final connected =
            ref.read(wsStateProvider).valueOrNull == WsState.connected;
        final currentConvId = ref.read(selectedConversationIdProvider);
        final waitingConvId = ref.read(waitingForReplyProvider);
        final isStreaming =
            ref.read(streamingMessageProvider) != null ||
            ref.read(streamingThinkingProvider) != null ||
            (waitingConvId != null && waitingConvId == currentConvId);
        if (connected && !isStreaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final text = _controller.text;
            if (text.endsWith('\n')) {
              _controller.text = text.substring(0, text.length - 1);
            }
            _handleSend();
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore) return;
    final position = _scrollController.position;
    // reverse: true 时，滚到顶部对应 maxScrollExtent
    if (position.pixels >= position.maxScrollExtent - 100) {
      _isLoadingMore = true;
      final convId = ref.read(selectedConversationIdProvider);
      if (convId != null) {
        ref.read(chatLimitProvider(convId).notifier).state += 50;
      }
      // 等待数据刷新后再允许下次加载
      Future.delayed(const Duration(milliseconds: 300), () {
        _isLoadingMore = false;
      });
    }
  }


  Future<void> _handleSend() async {
    final convId = ref.read(selectedConversationIdProvider);
    if (convId == null) return;
    final text = _controller.text.trim();
    final attachments = List<StagedAttachment>.of(ref.read(stagedAttachmentsProvider));

    // 没有文字也没有附件 → 不发送
    if (text.isEmpty && attachments.isEmpty) return;

    if (text.isNotEmpty &&
        (_messageHistory.isEmpty || _messageHistory.last != text)) {
      _messageHistory.add(text);
      if (_messageHistory.length > 100) _messageHistory.removeAt(0);
    }
    _historyIndex = _messageHistory.length;

    final editingMsg = ref.read(editingMessageProvider);
    final replyingTo = ref.read(replyingToProvider);
    final quoteId = editingMsg == null ? replyingTo?.messageId : null;
    final repo = ref.read(messageRepositoryProvider);

    // 从 conversations 表查出真正的 accountId（新会话的 convId 是 UUID，不等于 accountId）
    final convRepo = ref.read(conversationRepositoryProvider);
    final conv = await convRepo.getConversation(convId);
    final accountId = conv?.accountId ?? convId;

    // ── 立即清空 UI 状态（防重入 + 按钮立刻切换为 Stop）──
    ref.read(stagedAttachmentsProvider.notifier).clear();
    ref.read(editingMessageProvider.notifier).state = null;
    ref.read(replyingToProvider.notifier).state = null;
    ref.read(waitingForReplyProvider.notifier).state = convId;
    _controller.clear();

    SendResult result;

    if (attachments.isEmpty) {
      // 纯文本
      result = repo.sendMessage(
        accountId: accountId,
        conversationId: convId,
        content: text,
        senderId: 'local_user',
        quoteId: quoteId,
      );
    } else if (attachments.length == 1 && text.isEmpty) {
      // 单附件无文字 → 向后兼容原有类型
      final att = attachments.first;
      if (att.isImage) {
        if (att.bytes != null) {
          // 粘贴的图片需要先保存到临时文件
          _saveBytesAndSendImage(accountId, convId, att.bytes!);
          return;
        }
        final sendResult = await repo.sendImageMessage(
          accountId: accountId,
          conversationId: convId,
          senderId: 'local_user',
          filePath: att.path!,
          onProgress: (msgId, p) =>
              ref.read(uploadProgressProvider.notifier).update(msgId, p),
        );
        ref.read(uploadProgressProvider.notifier).remove(sendResult.clientMsgId);
        ref
            .read(wsMessageHandlerProvider)
            .trackRequest(sendResult.requestId, sendResult.clientMsgId, conversationId: convId);
        return;
      } else {
        final sendResult = await repo.sendFileMessage(
          accountId: accountId,
          conversationId: convId,
          senderId: 'local_user',
          filePath: att.path!,
          fileName: att.name ?? 'unknown',
          fileSize: att.size,
          onProgress: (msgId, p) =>
              ref.read(uploadProgressProvider.notifier).update(msgId, p),
        );
        ref.read(uploadProgressProvider.notifier).remove(sendResult.clientMsgId);
        ref
            .read(wsMessageHandlerProvider)
            .trackRequest(sendResult.requestId, sendResult.clientMsgId, conversationId: convId);
        return;
      }
    } else {
      // 混合消息 — 两步模式：先写 DB（本地路径），再上传更新
      // Phase 1: 构建本地版 JSON → 立即写入 DB → 消息瞬间出现
      final localJson = _buildLocalMixedJson(text, attachments);
      result = repo.insertMixedLocal(
        accountId: accountId,
        conversationId: convId,
        senderId: 'local_user',
        contentJson: localJson,
        quoteId: quoteId,
      );

      // Phase 2: HTTP 上传附件 → 更新 DB + 发送 WS
      try {
        final uploadedJson = await _buildMixedContentJson(text, attachments);
        repo.finalizeMixed(
          messageId: result.clientMsgId,
          requestId: result.requestId,
          accountId: accountId,
          conversationId: convId,
          contentJson: uploadedJson,
          quoteId: quoteId,
        );
      } catch (e) {
        debugPrint('[ChatScreen] Mixed upload failed: $e');
      }
    }

    // 注册待确认请求
    ref
        .read(wsMessageHandlerProvider)
        .trackRequest(result.requestId, result.clientMsgId, conversationId: convId);
  }

  /// 构建本地版混合消息 JSON（仅缓存文件到本地，无 HTTP 上传）
  String _buildLocalMixedJson(String text, List<StagedAttachment> attachments) {
    final atts = <Map<String, dynamic>>[];
    for (final a in attachments) {
      final cachedPath = a.path != null
          ? MediaCacheService.instance.cacheFileSync(a.path!)
          : '';
      if (cachedPath.isEmpty) continue;
      if (a.isImage) {
        atts.add({'type': 'image', 'path': cachedPath});
      } else {
        atts.add({
          'type': 'file',
          'path': cachedPath,
          'name': a.name ?? 'unknown',
          'size': a.size ?? 0,
        });
      }
    }
    return jsonEncode({'text': text, 'attachments': atts});
  }

  Future<String> _buildMixedContentJson(
    String text,
    List<StagedAttachment> attachments,
  ) async {
    final uploadService = MediaUploadService(baseUrl: MediaResolver.baseUrl);
    final atts = <Map<String, dynamic>>[];

    for (final a in attachments) {
      // 缓存到 App 目录
      final cachedPath = a.path != null
          ? MediaCacheService.instance.cacheFileSync(a.path!)
          : '';

      if (cachedPath.isEmpty) continue;

      try {
        // HTTP 上传每个附件到 CS（同 sendImageMessage/sendFileMessage）
        final result = await uploadService.upload(File(cachedPath));
        debugPrint('[ChatScreen] Mixed upload OK: ${result.mediaUrl}');

        if (a.isImage) {
          atts.add({
            'type': 'image',
            'mediaUrl': result.mediaUrl,
            'thumbUrl': result.thumbUrl,
            'thumbHash': result.thumbHash,
            'width': result.width,
            'height': result.height,
            'localPath': cachedPath, // 仅本地 DB 使用，发送时剥离
          });
        } else {
          atts.add({
            'type': 'file',
            'mediaUrl': result.mediaUrl,
            'mediaType': result.mediaType ?? 'application/octet-stream',
            'name': a.name ?? 'unknown',
            'size': a.size ?? 0,
            'localPath': cachedPath, // 仅本地 DB 使用，发送时剥离
          });
        }
      } catch (e) {
        debugPrint('[ChatScreen] Mixed upload failed: $e');
        // 上传失败时回退到本地路径（仅本机可读）
        if (a.isImage) {
          atts.add({'type': 'image', 'path': cachedPath});
        } else {
          atts.add({
            'type': 'file',
            'path': cachedPath,
            'name': a.name ?? 'unknown',
            'size': a.size ?? 0,
          });
        }
      }
    }

    return jsonEncode({'text': text, 'attachments': atts});
  }

  Future<void> _saveBytesAndSendImage(String accountId, String convId, Uint8List bytes) async {
    // 使用 MediaCacheService 缓存粘贴的图片
    final cachedPath = MediaCacheService.instance.cacheBytes(
      bytes,
      'paste_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    final sendResult = await ref
        .read(messageRepositoryProvider)
        .sendImageMessage(
          accountId: accountId,
          conversationId: convId,
          senderId: 'local_user',
          filePath: cachedPath,
        );
    ref
        .read(wsMessageHandlerProvider)
        .trackRequest(sendResult.requestId, sendResult.clientMsgId, conversationId: convId);
  }

  Future<void> _pickAndStageImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final notifier = ref.read(stagedAttachmentsProvider.notifier);
      for (final file in result.files) {
        if (file.path != null) {
          notifier.add(
            StagedAttachment(
              path: file.path!,
              type: 'image',
              name: file.name,
              size: file.size,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndStageFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result != null && result.files.isNotEmpty) {
      final notifier = ref.read(stagedAttachmentsProvider.notifier);
      for (final file in result.files) {
        if (file.path != null) {
          final isImage = StagedAttachment.isImagePath(file.path!);
          notifier.add(
            StagedAttachment(
              path: file.path!,
              type: isImage ? 'image' : 'file',
              name: file.name,
              size: file.size,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(wsStateProvider);
    final convId = ref.watch(selectedConversationIdProvider);
    final rawStreamingMsg = ref.watch(streamingMessageProvider);
    final rawStreamingThinking = ref.watch(streamingThinkingProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 只显示属于当前会话的流式消息
    final streamingMsg = (rawStreamingMsg is TextMessage &&
            rawStreamingMsg.conversationId != null &&
            rawStreamingMsg.conversationId != convId)
        ? null
        : rawStreamingMsg;
    final streamingThinking = (rawStreamingThinking is ThinkingMessage &&
            rawStreamingThinking.conversationId != null &&
            rawStreamingThinking.conversationId != convId)
        ? null
        : rawStreamingThinking;

    // 同步 Mermaid 渲染开关到全局 builder
    final mermaidEnabled = ref.watch(mermaidEnabledProvider);
    setMermaidEnabled(mermaidEnabled);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: _buildAppBarTitle(convId, colorScheme),
        actions: [
          if (convId != null)
            IconButton(
              icon: Icon(
                Icons.settings_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: context.l10n.conversationSettings,
              onPressed: () {
                final conversations = ref.read(conversationListProvider).valueOrNull;
                final conv = conversations
                    ?.where((c) => c.conversationId == convId)
                    .firstOrNull;
                if (conv != null) {
                  ConversationSettingsSheet.show(
                    context,
                    conversationId: convId,
                    accountId: conv.accountId,
                  );
                }
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: convId == null
          ? Center(
              child: Text(
                context.l10n.selectConversation,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          : _buildChatBody(
              convId,
              wsState.valueOrNull,
              streamingMsg,
              streamingThinking,
            ),
    );
  }

  Widget _buildAppBarTitle(String? convId, ColorScheme colorScheme) {
    if (convId == null) {
      return Text('Clawke');
    }
    final conversationsAsync = ref.watch(conversationListProvider);
    final name = conversationsAsync.valueOrNull
        ?.where((c) => c.conversationId == convId)
        .map((c) => c.name)
        .firstOrNull;
    return Text(
      name ?? convId,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildChatBody(
    String convId,
    WsState? wsState,
    TextMessage? streamingMsg,
    ThinkingMessage? streamingThinking,
  ) {
    final messagesAsync = ref.watch(chatMessagesProvider(convId));
    // hasStreaming: 是否需要显示流式气泡
    // 如果只有 streamingThinking（没有 streamingMsg），需要检查 DB 中是否已有该消息
    // 已持久化的消息由 _buildDbMessageItem 渲染 thinking 块，不需要重复显示
    bool hasStreaming = streamingMsg != null;
    if (!hasStreaming && streamingThinking != null) {
      // thinking-only 模式：检查 DB 中是否已有该消息
      final dbMessages = messagesAsync.valueOrNull;
      final alreadyInDb =
          dbMessages != null &&
          dbMessages.any((m) => m.messageId == streamingThinking.messageId);
      if (!alreadyInDb) {
        hasStreaming = true;
      }
    }

    final body = Column(
      children: [
        Expanded(
          child: messagesAsync.when(
            data: (dbMessages) {
              final itemCount = dbMessages.length + (hasStreaming ? 1 : 0);
              return ListView.builder(
                key: ValueKey('chat_$convId'),
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (hasStreaming) {
                    if (index == 0) {
                      return _buildStreamingItem(
                        streamingMsg,
                        streamingThinking,
                      );
                    }
                    final msgIndex = index - 1;
                    final olderMsg = msgIndex + 1 < dbMessages.length
                        ? dbMessages[msgIndex + 1]
                        : null;
                    return _buildDbMessageWithSeparator(
                      dbMessages[msgIndex],
                      olderMsg,
                    );
                  }
                  final olderMsg = index + 1 < dbMessages.length
                      ? dbMessages[index + 1]
                      : null;
                  return _buildDbMessageWithSeparator(
                    dbMessages[index],
                    olderMsg,
                  );
                },
              );
            },
            loading: () => messagesAsync.hasValue
                ? ListView.builder(
                    key: ValueKey('chat_$convId'),
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount:
                        messagesAsync.value!.length + (hasStreaming ? 1 : 0),
                    itemBuilder: (context, index) {
                      final dbMessages = messagesAsync.value!;
                      if (hasStreaming) {
                        if (index == 0) {
                          return _buildStreamingItem(
                            streamingMsg,
                            streamingThinking,
                          );
                        }
                        final msgIndex = index - 1;
                        final olderMsg = msgIndex + 1 < dbMessages.length
                            ? dbMessages[msgIndex + 1]
                            : null;
                        return _buildDbMessageWithSeparator(
                          dbMessages[msgIndex],
                          olderMsg,
                        );
                      }
                      final olderMsg = index + 1 < dbMessages.length
                          ? dbMessages[index + 1]
                          : null;
                      return _buildDbMessageWithSeparator(
                        dbMessages[index],
                        olderMsg,
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(context.l10n.loadFailed(e.toString()))),
          ),
        ),

        _buildInputAreaWithPaste(wsState),
      ],
    );

    // 桌面端：包裹 DropTarget 支持拖放文件
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return DropTarget(
        onDragDone: (details) {
          final notifier = ref.read(stagedAttachmentsProvider.notifier);
          for (final xFile in details.files) {
            final path = xFile.path;
            final name = xFile.name;
            final isImage = StagedAttachment.isImagePath(path);
            notifier.add(
              StagedAttachment(
                path: path,
                type: isImage ? 'image' : 'file',
                name: name,
              ),
            );
          }
        },
        child: body,
      );
    }

    return body;
  }

  Widget _buildAvatar(bool isUser) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        color: isUser
            ? colorScheme.tertiaryContainer
            : colorScheme.primaryContainer,
        child: Icon(
          isUser ? Icons.person : Icons.smart_toy,
          size: 20,
          color: isUser
              ? colorScheme.onTertiaryContainer
              : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildDbMessageWithSeparator(Message msg, Message? olderMsg) {
    // ListView is reverse, so separator for THIS message appears
    // above it visually (which means it's placed AFTER in the Column).
    Widget? separator;
    if (olderMsg != null) {
      separator = _buildSeparatorIfNeeded(msg.createdAt, olderMsg.createdAt);
    }
    final item = _buildDbMessageItem(msg);
    if (separator == null) return item;
    // In reverse ListView: item at bottom, separator above → Column reversed
    return Column(mainAxisSize: MainAxisSize.min, children: [item, separator]);
  }

  Widget? _buildSeparatorIfNeeded(int newerMs, int olderMs) {
    final newer = DateTime.fromMillisecondsSinceEpoch(newerMs);
    final older = DateTime.fromMillisecondsSinceEpoch(olderMs);
    final newerDay = DateTime(newer.year, newer.month, newer.day);
    final olderDay = DateTime(older.year, older.month, older.day);

    if (newerDay != olderDay) {
      // 日期变化 → 显示日期分割
      return _buildSeparatorLabel(_formatSeparatorLabel(newerDay));
    }
    // 同天 + 间隔 ≥10 分钟 → 显示时间分割
    if (newerMs - olderMs >= 10 * 60 * 1000) {
      return _buildSeparatorLabel(
        '${newer.hour.toString().padLeft(2, '0')}:${newer.minute.toString().padLeft(2, '0')}',
      );
    }
    return null;
  }

  String _formatSeparatorLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return context.l10n.today;
    if (day == today.subtract(const Duration(days: 1))) return context.l10n.yesterday;
    if (day.year == now.year) return context.l10n.monthDay(day.month, day.day);
    return '${day.year}/${day.month}/${day.day}';
  }

  Widget _buildSeparatorLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaLine(Message msg, bool isUser) {
    final colorScheme = Theme.of(context).colorScheme;
    final metaColor = colorScheme.onSurface.withOpacity(0.4);
    final time = _formatMessageTime(msg.createdAt);

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: metaColor)),
            const SizedBox(width: 6),
            _buildStatusIcon(msg.status),
          ],
        ),
      );
    }

    // AI 消息：time | model | ⚡ token
    final parts = <String>[];
    parts.add(time);
    if (msg.modelName != null && msg.modelName!.isNotEmpty) {
      parts.add(msg.modelName!);
    }
    if (msg.inputTokens != null && msg.inputTokens! > 0) {
      parts.add('▸ ${_formatTokenCount(msg.inputTokens!)} in · ${_formatTokenCount(msg.outputTokens ?? 0)} out');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 10),
      child: Text(
        parts.join(' │ '),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: metaColor,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['.AppleSystemUIFont', 'Roboto'],
        ),
      ),
    );
  }

  Widget _buildDbMessageItem(Message msg) {
    final isUser = msg.senderId == 'local_user';
    final colorScheme = Theme.of(context).colorScheme;

    // 处理已删除消息
    if (msg.status == 'deleted') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            context.l10n.messageDeleted,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final bubbleColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerLowest;

    return MessageContextMenu(
      message: msg,
      isUser: isUser,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[_buildAvatar(false), const SizedBox(width: 2)],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Thinking 块（如果有）
                    if (!isUser &&
                        msg.thinkingContent != null &&
                        msg.thinkingContent!.isNotEmpty)
                      Container(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width *
                              ((Platform.isIOS || Platform.isAndroid)
                                  ? 0.78
                                  : 0.55),
                        ),
                        child: ThinkingBlockWidget(
                          content: msg.thinkingContent!,
                          isStreaming: false,
                        ),
                      ),
                    // 箭头 + 气泡
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _BubbleArrow(
                              isUser: false,
                              color: bubbleColor,
                            ),
                          ),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width *
                                  ((Platform.isIOS || Platform.isAndroid)
                                      ? 0.78
                                      : 0.55),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 引用消息卡片
                                if (msg.quoteId != null)
                                  _buildQuoteCard(msg.quoteId!),
                                // 消息内容 — 按 type 分发
                                _buildMessageContent(msg, isUser),
                                if (msg.editedAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      context.l10n.edited,
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: isUser
                                            ? colorScheme.onPrimary.withOpacity(
                                                0.7,
                                              )
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (isUser)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _BubbleArrow(
                              isUser: true,
                              color: bubbleColor,
                            ),
                          ),
                      ],
                    ),
                    // 上传进度条（仅发送中的媒体消息）
                    if (isUser && msg.status == 'sending' && (msg.type == 'image' || msg.type == 'file'))
                      Consumer(
                        builder: (context, ref, _) {
                          final progressMap = ref.watch(uploadProgressProvider);
                          final progress = progressMap[msg.messageId];
                          if (progress == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, right: 10),
                            child: SizedBox(
                              width: 160,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 3,
                                      backgroundColor: colorScheme.onSurface.withOpacity(0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(progress * 100).toInt()}%',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    // 时间戳 + token（气泡下方）
                    _buildMetaLine(msg, isUser),
                  ],
                ),
              ),
              if (isUser) ...[const SizedBox(width: 2), _buildAvatar(true)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteCard(String quoteId) {
    final convId = ref.read(selectedConversationIdProvider);
    if (convId == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    final messagesAsync = ref.read(chatMessagesProvider(convId));
    final quotedMsg = messagesAsync.valueOrNull?.cast<Message?>().firstWhere(
      (m) => m?.messageId == quoteId,
      orElse: () => null,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
      ),
      child: Text(
        quotedMsg?.content ?? context.l10n.messageInvisible,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildMessageContent(Message msg, bool isUser) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (msg.type) {
      'image' => _buildImageMessage(msg),
      'file' => _buildFileContent(msg),
      'mixed' => MixedMessageWidget(
        content: msg.content ?? '{}',
        isUser: isUser,
      ),
      'cup_component' => _buildSduiContent(msg),
      _ =>
        isUser
            ? SelectableText(
                msg.content ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onPrimary,
                  height: 1.4,
                ),
              )
            : SelectionArea(
                child: GptMarkdown(
                  _autoLinkUrls(msg.content ?? ''),
                  useDollarSignsForLatex: true,
                  codeBuilder: buildHighlightedCodeBlock,
                  style: TextStyle(color: colorScheme.onSurface),
                  linkBuilder: (context, text, url, style) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        text.toPlainText(),
                        style: const TextStyle(
                          color: Color(0xFF4493F8),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF4493F8),
                        ),
                      ),
                    );
                  },
                  onLinkTap: (url, title) {
                    if (url.startsWith('http://') || url.startsWith('https://')) {
                      launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
                    }
                  },
                ),
              ),
    };
  }

  /// 构建图片消息：解析 JSON 格式的新架构 content，回退到旧 filePath
  Widget _buildImageMessage(Message msg) {
    // 尝试解析 JSON 格式（新架构：含 mediaUrl/thumbUrl/thumbHash）
    final json = _tryParseJson(msg.content);
    if (json != null && (json.containsKey('mediaUrl') || json.containsKey('thumbHash'))) {
      return ImageMessageWidget(
        filePath: json['localPath'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
        thumbUrl: json['thumbUrl'] as String?,
        thumbHash: json['thumbHash'] as String?,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        onCached: (cachedPath) => _updateMessageLocalPath(msg.messageId, msg.content, cachedPath),
      );
    }
    // 旧格式：content 可能是 HTTP URL
    if (msg.content != null && MediaResolver.isMediaUrl(msg.content!)) {
      return ImageMessageWidget(mediaUrl: msg.content);
    }
    // 旧格式：content 是本地文件路径
    return ImageMessageWidget(filePath: msg.content);
  }

  Map<String, dynamic>? _tryParseJson(String? s) {
    if (s == null) return null;
    try {
      return Map<String, dynamic>.from(const JsonDecoder().convert(s) as Map);
    } catch (_) {
      return null;
    }
  }

  Widget _buildSduiContent(Message msg) {
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final json = Map<String, dynamic>.from(
        const JsonDecoder().convert(msg.content ?? '{}') as Map,
      );
      final component = SduiComponentModel.fromJson(json);
      return WidgetFactory.build(component, msg.messageId);
    } catch (_) {
      return SelectableText(
        msg.content ?? '',
        style: TextStyle(color: colorScheme.onSurface),
      );
    }
  }

  Widget _buildFileContent(Message msg) {
    try {
      // content 是 JSON: {"path":"...","name":"...","size":123}
      final json = Map<String, dynamic>.from(
        (msg.content != null) ? _parseJson(msg.content!) : {},
      );
      return FileMessageWidget(
        fileName: json['name'] as String? ?? 'unknown',
        filePath: json['localPath'] as String? ?? json['path'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
        fileSize: json['size'] as int?,
        onCached: (cachedPath) => _updateMessageLocalPath(msg.messageId, msg.content, cachedPath),
      );
    } catch (_) {
      return FileMessageWidget(fileName: msg.content ?? 'unknown');
    }
  }

  /// 下载缓存成功后，将 localPath 写回 DB message content JSON
  void _updateMessageLocalPath(String messageId, String? currentContent, String localPath) {
    try {
      final json = currentContent != null ? _parseJson(currentContent) : <String, dynamic>{};
      json['localPath'] = localPath;
      final updatedContent = jsonEncode(json);
      ref.read(messageDaoProvider).updateContent(messageId, updatedContent);
      debugPrint('[ChatScreen] 缓存路径写回 DB: msgId=$messageId, localPath=$localPath');
    } catch (e) {
      debugPrint('[ChatScreen] 写回 localPath 失败: $e');
    }
  }

  Map<String, dynamic> _parseJson(String s) {
    try {
      return Map<String, dynamic>.from(const JsonDecoder().convert(s) as Map);
    } catch (_) {
      return {};
    }
  }

  Widget _buildStatusIcon(String status) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = colorScheme.onPrimary.withOpacity(0.45);
    return switch (status) {
      'sending' => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: statusColor),
      ),
      'failed' => Icon(Icons.error_outline, size: 14, color: colorScheme.error),
      'sent' => Icon(Icons.check, size: 14, color: statusColor),
      'delivered' => Icon(Icons.done_all, size: 14, color: statusColor),
      'read' => Icon(Icons.done_all, size: 14, color: statusColor),
      _ => const SizedBox.shrink(),
    };
  }

  String _formatMessageTime(int milliseconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (msgDay == today) {
      return time;
    } else if (msgDay == today.subtract(const Duration(days: 1))) {
      return context.l10n.yesterdayTime(time);
    } else if (dt.year == now.year) {
      return '${dt.month}/${dt.day} $time';
    } else {
      return '${dt.year}/${dt.month}/${dt.day} $time';
    }
  }

  /// 格式化 token 数量：1234 → 1234, 12345 → 12.3K, 1234567 → 1.2M
  String _formatTokenCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  /// 构建流式输出区域：thinking 块 + 文本气泡
  Widget _buildStreamingItem(
    TextMessage? streamingMsg,
    ThinkingMessage? streamingThinking,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isThinkingOnly = streamingThinking != null && streamingMsg == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(false),
            const SizedBox(width: 2),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thinking 块（如果有）
                  if (streamingThinking != null)
                    Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width *
                            ((Platform.isIOS || Platform.isAndroid)
                                ? 0.78
                                : 0.55),
                      ),
                      child: ThinkingBlockWidget(
                        content: streamingThinking.content,
                        isStreaming: isThinkingOnly,
                      ),
                    ),
                  // 文本气泡（如果有）
                  if (streamingMsg != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _BubbleArrow(
                            isUser: false,
                            color: colorScheme.surfaceContainerLowest,
                          ),
                        ),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width *
                                  ((Platform.isIOS || Platform.isAndroid)
                                      ? 0.78
                                      : 0.55),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectionArea(
                              child: GptMarkdown(
                                _autoLinkUrls(streamingMsg.content),
                                useDollarSignsForLatex: true,
                                codeBuilder: buildHighlightedCodeBlock,
                                style: Theme.of(context).textTheme.bodyMedium,
                                linkBuilder: (context, text, url, style) {
                                  return MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      text.toPlainText(),
                                      style: const TextStyle(
                                        color: Color(0xFF4493F8),
                                        decoration: TextDecoration.underline,
                                        decorationColor: Color(0xFF4493F8),
                                      ),
                                    ),
                                  );
                                },
                                onLinkTap: (url, title) {
                                  if (url.startsWith('http://') || url.startsWith('https://')) {
                                    launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextBubble(TextMessage message) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerLowest;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[_buildAvatar(false), const SizedBox(width: 2)],
            Flexible(
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // 箭头 + 气泡
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _BubbleArrow(
                            isUser: false,
                            color: bubbleColor,
                          ),
                        ),
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width *
                                ((Platform.isIOS || Platform.isAndroid)
                                    ? 0.78
                                    : 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            message.content,
                            style: TextStyle(
                              color: isUser
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      if (isUser)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _BubbleArrow(isUser: true, color: bubbleColor),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (isUser) ...[const SizedBox(width: 2), _buildAvatar(true)],
          ],
        ),
      ),
    );
  }

  Future<void> _handlePaste() async {
    // 桌面端：尝试从剪贴板粘贴图片
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        final imageBytes = await Pasteboard.image;
        if (imageBytes != null) {
          ref
              .read(stagedAttachmentsProvider.notifier)
              .add(
                StagedAttachment(
                  type: 'image',
                  bytes: imageBytes,
                  name: 'paste_${DateTime.now().millisecondsSinceEpoch}.png',
                ),
              );
          return;
        }
      } catch (_) {}
    }

    // 非图片 → 走系统文本粘贴
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipData?.text != null) {
      final text = clipData!.text!;
      final selection = _controller.selection;
      final before = _controller.text.substring(0, selection.baseOffset);
      final after = _controller.text.substring(selection.extentOffset);
      _controller.text = '$before$text$after';
      _controller.selection = TextSelection.collapsed(
        offset: before.length + text.length,
      );
    }
  }

  Widget _buildInputAreaWithPaste(WsState? state) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV):
            const _PasteIntent(),
      },
      child: Actions(
        actions: {
          _PasteIntent: CallbackAction<_PasteIntent>(
            onInvoke: (_) {
              _handlePaste();
              return null;
            },
          ),
        },
        child: _buildInputArea(state),
      ),
    );
  }

  Widget _buildInputArea(WsState? state) {
    final aiState = ref.watch(aiBackendStateProvider);
    final connected =
        state == WsState.connected && aiState == AiBackendState.connected;
    final replyingTo = ref.watch(replyingToProvider);
    final editingMsg = ref.watch(editingMessageProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 如果进入编辑模式，填充原文到输入框
    if (editingMsg != null && _controller.text.isEmpty) {
      _controller.text = editingMsg.content ?? '';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 回复/编辑预览条
        if (replyingTo != null || editingMsg != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  editingMsg != null ? Icons.edit : Icons.reply,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editingMsg != null
                        ? context.l10n.editMessage
                        : context.l10n.replyTo(replyingTo!.content ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    ref.read(replyingToProvider.notifier).state = null;
                    ref.read(editingMessageProvider.notifier).state = null;
                    _controller.clear();
                  },
                ),
              ],
            ),
          ),
        // 附件预览条
        const StagedAttachmentsPreview(),
        // 输入栏
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              // 附件按钮
              PopupMenuButton<String>(
                icon: const Icon(Icons.attach_file),
                tooltip: context.l10n.sendAttachment,
                onSelected: (value) {
                  switch (value) {
                    case 'image':
                      _pickAndStageImage();
                    case 'file':
                      _pickAndStageFile();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'image',
                    child: Row(
                      children: [
                        const Icon(Icons.image, size: 18),
                        const SizedBox(width: 8),
                        Text(context.l10n.image),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'file',
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, size: 18),
                        const SizedBox(width: 8),
                        Text(context.l10n.file),
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: TextField(
                  focusNode: _focusNode,
                  controller: _controller,
                  enabled: connected,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: connected
                        ? context.l10n.typeMessage
                        : context.l10n.notConnected,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Builder(builder: (context) {
                final convId = ref.watch(selectedConversationIdProvider);
                final rawMsg = ref.watch(streamingMessageProvider);
                final rawThink = ref.watch(streamingThinkingProvider);
                final waiting = ref.watch(waitingForReplyProvider);
                // 只看属于当前会话的流式状态
                final isMyStreaming =
                    (rawMsg != null && (rawMsg.conversationId == null || rawMsg.conversationId == convId)) ||
                    (rawThink != null && (rawThink.conversationId == null || rawThink.conversationId == convId)) ||
                    (waiting != null && waiting == convId);
                return IconButton.filled(
                  onPressed: connected
                      ? (isMyStreaming
                          ? () => ref.read(wsMessageHandlerProvider).sendAbort()
                          : _handleSend)
                      : null,
                  icon: Icon(isMyStreaming ? Icons.stop : Icons.send),
                  style: isMyStreaming
                      ? IconButton.styleFrom(backgroundColor: colorScheme.error)
                      : null,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _BubbleArrow extends StatelessWidget {
  final bool isUser;
  final Color color;
  const _BubbleArrow({required this.isUser, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 12),
      painter: _ArrowPainter(isUser: isUser, color: color),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool isUser;
  final Color color;
  _ArrowPainter({required this.isUser, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isUser) {
      // ▷ 指向右侧头像
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    } else {
      // ◁ 指向左侧头像
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

/// 将裸 URL 自动转为 markdown 链接格式
/// 例: `https://github.com/foo` → `[https://github.com/foo](https://github.com/foo)`
/// 跳过已在 markdown 链接 `[text](url)` 中的 URL（包括 text 和 url 部分）
String _autoLinkUrls(String text) {
  // 1. 先找出所有已有 markdown 链接 [text](url) 的范围
  final mdLinkRe = RegExp(r'\[([^\]]*)\]\([^\)]+\)');
  final protectedRanges = <(int, int)>[];
  for (final m in mdLinkRe.allMatches(text)) {
    protectedRanges.add((m.start, m.end));
  }

  // 2. 先处理 <URL> 角括号自动链接语法：剥离角括号
  var processed = text.replaceAllMapped(
    RegExp(r'<(https?://[^\s>]+)>'),
    (match) => match.group(1)!,
  );

  // 3. 匹配所有 URL，但跳过在 protected 范围内的
  final urlRe = RegExp(r'\b(https?://[^\s\)\]]+)');
  return processed.replaceAllMapped(urlRe, (match) {
    // 检查此 URL 是否在某个 markdown 链接范围内
    for (final (start, end) in protectedRanges) {
      if (match.start >= start && match.end <= end) {
        return match[0]!; // 在 [text](url) 内，不转换
      }
    }
    final url = match[1]!;
    return '[$url]($url)';
  });
}

