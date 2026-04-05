import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

class ChannelConnectDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;
  final String messageId;

  const ChannelConnectDialog({
    super.key,
    required this.props,
    required this.messageId,
  });

  @override
  ConsumerState<ChannelConnectDialog> createState() =>
      _ChannelConnectDialogState();
}

class _ChannelConnectDialogState extends ConsumerState<ChannelConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _formData = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForm = widget.props['content_type'] == 'form';
    final title = widget.props['title'] as String? ?? '连接渠道';
    final hint = widget.props['hint'] as String?;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.add_link, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  // TODO: 这里可以发个关闭事件给 Server，告知用户取消了操作
                },
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 16),
            Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: isForm ? TextAlign.start : TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          if (isForm) _buildFormContent(theme) else _buildQrContent(theme),
        ],
      ),
    );
  }

  Widget _buildFormContent(ThemeData theme) {
    final fields = widget.props['fields'] as List<dynamic>? ?? [];

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...fields.map((fieldData) {
            final f = fieldData as Map<String, dynamic>;
            final name = f['name'] as String;
            final label = f['label'] as String? ?? name;
            final isPassword = f['type'] == 'password';
            final hintText = f['hint'] as String?;
            final required = f['required'] == true;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                obscureText: isPassword,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  if (required && (value == null || value.isEmpty)) {
                    return '请输入 $label';
                  }
                  return null;
                },
                onSaved: (value) {
                  _formData[name] = value ?? '';
                },
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              if (_formKey.currentState?.validate() ?? false) {
                _formKey.currentState?.save();
                ref.read(wsServiceProvider).sendJson({
                  'event_type': 'user_action',
                  'context': {'client_msg_id': widget.messageId},
                  'action': {
                    'action_id': 'submit_channel_form',
                    'data': {
                      'channel_type': widget.props['channel_type'],
                      'form_data': _formData,
                    },
                  },
                });
              }
            },
            child: const Text('验证并连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent(ThemeData theme) {
    final base64String = widget.props['qr_data_base64'] as String?;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (base64String != null && base64String.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Image.memory(
              base64Decode(base64String),
              width: 200,
              height: 200,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 64, color: Colors.grey),
            ),
          )
        else
          Container(
            width: 200,
            height: 200,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CircularProgressIndicator(),
          ),
        const SizedBox(height: 24),
        Text(
          '正在等待扫描...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
