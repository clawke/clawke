import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/url_utils.dart';
import 'package:client/screens/login_screen.dart';
import 'package:client/screens/manual_config_screen.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/app_version_provider.dart';
import 'package:client/l10n/app_localizations.dart';

/// Welcome screen shown on first app launch.
///
/// Offers two paths:
///   1. Login to Clawke account → auto-fetch Relay credentials
///   2. Manual server config → existing settings flow
class WelcomeScreen extends ConsumerWidget {
  static const double _horizontalPadding = 32;
  static const double _maxContentWidth = 400;
  static const double _footerReserveHeight = 72;
  static const double _footerBottomPadding = 24;

  final bool showBackButton;

  const WelcomeScreen({super.key, this.showBackButton = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final currentLang =
        locale?.languageCode ?? Localizations.localeOf(context).languageCode;
    final t = AppLocalizations.of(context)!;
    final appVersion = ref
        .watch(appVersionProvider)
        .maybeWhen(data: (info) => info.fullVersion, orElse: () => '...');

    return Scaffold(
      appBar: showBackButton
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentMinHeight =
                (constraints.maxHeight - _footerReserveHeight).clamp(
                  0.0,
                  double.infinity,
                );

            return Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      _horizontalPadding,
                      0,
                      _horizontalPadding,
                      _footerReserveHeight,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: contentMinHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _maxContentWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 60),

                              // Logo
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),

                              const SizedBox(height: 24),

                              // App name
                              Text(
                                'Clawke',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                              ),

                              const SizedBox(height: 8),

                              // Tagline
                              Text(
                                'Your AI workspace, anywhere.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                              ),

                              const SizedBox(height: 48),

                              // Login button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton(
                                  onPressed: () => _navigateToLogin(context),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    t.welcomeLogin,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Manual config button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _navigateToManualConfig(context),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: colorScheme.outline.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    t.welcomeManualConfig,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.8),
                                        ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Language selector
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.language,
                                    size: 18,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'zh',
                                        label: Text('中文'),
                                      ),
                                      ButtonSegment(
                                        value: 'en',
                                        label: Text('English'),
                                      ),
                                    ],
                                    selected: {currentLang},
                                    onSelectionChanged: (codes) {
                                      ref
                                          .read(localeProvider.notifier)
                                          .setLocale(Locale(codes.first));
                                    },
                                    style: const ButtonStyle(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 32),

                              // Legal Footer
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _LegalLink(
                                    label: t.termsOfService,
                                    onTap: () => openTermsOfService(context),
                                  ),
                                  Text(
                                    ' · ',
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  _LegalLink(
                                    label: t.privacyPolicy,
                                    onTap: () => openPrivacyPolicy(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _footerBottomPadding,
                  child: Text(
                    'Clawke v$appVersion',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _navigateToLogin(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _navigateToManualConfig(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualConfigScreen()));
  }
}

class _LegalLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LegalLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
