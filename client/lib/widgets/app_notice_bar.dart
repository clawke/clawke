import 'package:flutter/material.dart';

enum AppNoticeSeverity { info, warning, error }

class AppNoticeBar extends StatelessWidget {
  final String message;
  final AppNoticeSeverity severity;
  final VoidCallback onDismiss;

  const AppNoticeBar({
    super.key,
    required this.message,
    required this.severity,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = _palette(colorScheme);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Material(
        key: const ValueKey('app_notice_bar'),
        color: palette.background,
        elevation: 6,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(palette.icon, size: 22, color: palette.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.foreground,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('app_notice_close'),
                tooltip: '关闭',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
                color: palette.foreground,
                iconSize: 20,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  _NoticePalette _palette(ColorScheme colorScheme) {
    return switch (severity) {
      AppNoticeSeverity.info => _NoticePalette(
        background: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
        border: colorScheme.secondary.withValues(alpha: 0.35),
        icon: Icons.info_outline,
      ),
      AppNoticeSeverity.warning => _NoticePalette(
        background: Color.alphaBlend(
          colorScheme.tertiary.withValues(alpha: 0.16),
          colorScheme.surfaceContainerHigh,
        ),
        foreground: colorScheme.onSurface,
        border: colorScheme.tertiary.withValues(alpha: 0.5),
        icon: Icons.warning_amber_rounded,
      ),
      AppNoticeSeverity.error => _NoticePalette(
        background: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
        border: colorScheme.error.withValues(alpha: 0.35),
        icon: Icons.error_outline,
      ),
    };
  }
}

class _NoticePalette {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _NoticePalette({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });
}
