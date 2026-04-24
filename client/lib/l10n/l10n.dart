import 'package:flutter/widgets.dart';
import 'package:client/l10n/app_localizations.dart';

/// BuildContext 扩展，简化国际化调用。
/// 用法：context.l10n.reply（替代 AppLocalizations.of(context)!.reply）
extension LocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
