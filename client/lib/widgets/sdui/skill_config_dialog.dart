import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

class SkillConfigDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;
  final String messageId;

  const SkillConfigDialog({
    super.key,
    required this.props,
    required this.messageId,
  });

  @override
  ConsumerState<SkillConfigDialog> createState() => _SkillConfigDialogState();
}

class _SkillConfigDialogState extends ConsumerState<SkillConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};

  @override
  void initState() {
    super.initState();
    final fields = widget.props['fields'] as List<dynamic>? ?? [];
    for (var f in fields) {
      final field = f as Map<String, dynamic>;
      _formData[field['name']] = field['current_value'] ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.props['title'] as String? ?? '技能配置';
    final fields = widget.props['fields'] as List<dynamic>? ?? [];

    return Container(
      constraints: const BoxConstraints(maxWidth: 450),
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
              Icon(Icons.settings_suggest, color: theme.colorScheme.primary),
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
                  // TODO: Cancel action
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Form(
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
                  final initialValue = f['current_value']?.toString() ?? '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      initialValue: initialValue,
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
                          'action_id': 'save_skill_config',
                          'data': {
                            'skill_id': widget.props['skill_id'],
                            'config_data': _formData,
                          },
                        },
                      });
                    }
                  },
                  child: const Text('保存配置'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
