import 'package:flutter/material.dart';

class UpgradePromptWidget extends StatelessWidget {
  final String unknownWidgetName;
  const UpgradePromptWidget({super.key, required this.unknownWidgetName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        border: Border.all(color: colorScheme.tertiary.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前版本不支持组件：$unknownWidgetName，请升级客户端。',
              style: TextStyle(color: colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
