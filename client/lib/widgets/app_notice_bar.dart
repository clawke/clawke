import 'package:flutter/material.dart';

enum AppNoticeSeverity { info, warning, error }

class AppNoticeBar extends StatelessWidget {
  final String message;
  final String? detail;
  final AppNoticeSeverity severity;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final String? actionTooltip;
  final bool showProgress;
  final bool edgeToEdge;

  const AppNoticeBar({
    super.key,
    required this.message,
    this.detail,
    required this.severity,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
  });

  const AppNoticeBar.info({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
  }) : severity = AppNoticeSeverity.info;

  const AppNoticeBar.warning({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
  }) : severity = AppNoticeSeverity.warning;

  const AppNoticeBar.error({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
  }) : severity = AppNoticeSeverity.error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = _palette(colorScheme);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isMobile = viewportWidth < 600;
    final maxWidth = isMobile
        ? viewportWidth
        : (viewportWidth * 0.64).clamp(800.0, 1120.0).toDouble();
    final radius = BorderRadius.circular(edgeToEdge ? 0 : 8);
    final border = edgeToEdge
        ? Border(
            top: BorderSide(color: palette.border),
            bottom: BorderSide(color: palette.border),
          )
        : Border.all(color: palette.border);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        key: const ValueKey('app_notice_bar'),
        color: palette.background,
        elevation: 6,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(borderRadius: radius, border: border),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: showProgress
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: palette.foreground,
                        ),
                      )
                    : Icon(palette.icon, size: 22, color: palette.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.foreground,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        SelectableText(
                          detail!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.foreground.withValues(
                                  alpha: 0.82,
                                ),
                                height: 1.35,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: actionTooltip,
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.refresh),
                  color: palette.foreground,
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(width: 4),
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
        background: Color.alphaBlend(
          colorScheme.error.withValues(
            alpha: colorScheme.brightness == Brightness.dark ? 0.18 : 0.1,
          ),
          colorScheme.surfaceContainerHighest,
        ),
        foreground: colorScheme.onSurface,
        border: colorScheme.error.withValues(alpha: 0.55),
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
