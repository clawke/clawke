import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/l10n/l10n.dart';

const _uuid = Uuid();

class NewConversationDialog extends ConsumerStatefulWidget {
  const NewConversationDialog({super.key});

  @override
  ConsumerState<NewConversationDialog> createState() =>
      _NewConversationDialogState();
}

class _NewConversationDialogState extends ConsumerState<NewConversationDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final convId = 'conv_${_uuid.v4().substring(0, 8)}';

    await ref
        .read(conversationRepositoryProvider)
        .ensureConversation(accountId: convId, type: 'dm', name: name);

    if (mounted) {
      ref.read(selectedConversationIdProvider.notifier).state = convId;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;

    return AlertDialog(
      title: Text(t.newConversation),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: t.conversationName,
          hintText: t.conversationNameHint,
        ),
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _create, child: Text(t.create)),
      ],
    );
  }
}
