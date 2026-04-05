import 'package:flutter/material.dart';

class ToolRunInfo {
  final String toolName;
  final String status; // 'running', 'completed', 'error'
  final int? durationMs;
  final String? summary;

  ToolRunInfo({
    required this.toolName,
    required this.status,
    this.durationMs,
    this.summary,
  });
}

class ToolStatusWidget extends StatelessWidget {
  final List<ToolRunInfo> tools;

  const ToolStatusWidget({super.key, required this.tools});

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tools.map((tool) {
          final isRunning = tool.status == 'running';
          final isError = tool.status == 'error';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRunning
                      ? Icons.autorenew
                      : (isError ? Icons.error : Icons.check_circle),
                  size: 14,
                  color: isRunning
                      ? colorScheme.primary
                      : (isError ? colorScheme.error : colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  '${tool.toolName}${tool.durationMs != null ? ' (${tool.durationMs}ms)' : ''}',
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (tool.summary != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    tool.summary!,
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
