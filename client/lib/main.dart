import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/l10n/app_localizations.dart';
import 'package:client/screens/main_layout.dart';
import 'package:client/screens/welcome_screen.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/font_scale_provider.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/core/notification_service.dart';
import 'package:client/providers/debug_log_provider.dart';

import 'package:client/core/http_util.dart';
import 'package:client/core/file_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 覆盖 debugPrint：同时输出到控制台、Debug Log Panel、文件日志
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    originalDebugPrint(message, wrapWidth: wrapWidth);
    if (message != null && message.isNotEmpty) {
      DebugLogNotifier.instance.addLog(message);
      FileLogger.instance.log(message);
    }
  };

  await NotificationService.init();

  // 初始化文件日志（路径会打印到 debug console）
  debugPrint('[main] FileLogger initializing...');
  try {
    await FileLogger.instance.init();
    FileLogger.instance.log('[APP] Clawke client started');
    debugPrint('[main] FileLogger OK: ${await FileLogger.instance.logPath}');
  } catch (e) {
    debugPrint('[main] FileLogger FAILED: $e');
  }

  runApp(const ProviderScope(child: ClawkeApp()));
}

/// 根据缩放系数生成 TextTheme。
///
/// 基准字体：bodyMedium = 16sp（Clawke 规范）。
/// 其他样式基于此按比例放大/缩小，具体参见 docs/font-spec.md。
TextTheme _scaledTextTheme(double scale) {
  return TextTheme(
    displayLarge: TextStyle(fontSize: 65 * scale),
    displayMedium: TextStyle(fontSize: 51 * scale),
    displaySmall: TextStyle(fontSize: 41 * scale),
    headlineLarge: TextStyle(fontSize: 37 * scale),
    headlineMedium: TextStyle(fontSize: 32 * scale),
    headlineSmall: TextStyle(fontSize: 27 * scale),
    titleLarge: TextStyle(fontSize: 25 * scale),
    titleMedium: TextStyle(fontSize: 18 * scale),
    titleSmall: TextStyle(fontSize: 16 * scale),
    bodyLarge: TextStyle(fontSize: 18 * scale),
    bodyMedium: TextStyle(fontSize: 16 * scale),
    bodySmall: TextStyle(fontSize: 14 * scale),
    labelLarge: TextStyle(fontSize: 16 * scale),
    labelMedium: TextStyle(fontSize: 14 * scale),
    labelSmall: TextStyle(fontSize: 13 * scale),
  );
}

class ClawkeApp extends ConsumerWidget {
  const ClawkeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final scaledText = _scaledTextTheme(fontScale);

    return MaterialApp(
      title: 'Clawke',
      debugShowCheckedModeBanner: false,
      // i18n
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.light,
          surface: const Color(0xFFF0F0F0),
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: const Color(0xFFFAFAFA),
          surfaceContainerLow: const Color(0xFFE8E8EA),
          surfaceContainer: const Color(0xFFDCDCE0),
        ),
        textTheme: scaledText,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          actionsPadding: const EdgeInsets.only(right: 8),
          foregroundColor: Colors.black87,
          titleTextStyle: scaledText.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        extensions: [
          GptMarkdownThemeData(
            brightness: Brightness.light,
            linkColor: const Color(0xFF1A73E8),
            linkHoverColor: const Color(0xFF1558B0),
          ),
        ],
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
          surface: const Color(0xFF161616),
          surfaceTint: Colors.transparent,
          onSurface: const Color(0xFFE4E4E7),
          surfaceContainerLowest: const Color(0xFF1C1C1C),
          surfaceContainerLow: const Color(0xFF232323),
          surfaceContainer: const Color(0xFF2C2C2C),
          surfaceContainerHigh: const Color(0xFF333333),
          surfaceContainerHighest: const Color(0xFF3A3A3A),
          outlineVariant: const Color(0xFF3A3A3A),
          primary: const Color(0xFF10B981),
          secondary: const Color(0xFF34D399),
          error: const Color(0xFFF87171),
        ),
        textTheme: scaledText,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          actionsPadding: const EdgeInsets.only(right: 8),
          foregroundColor: const Color(0xFFE4E4E7),
          titleTextStyle: scaledText.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE4E4E7),
          ),
        ),
        extensions: [
          GptMarkdownThemeData(
            brightness: Brightness.dark,
            linkColor: const Color(0xFF4493F8),
            linkHoverColor: const Color(0xFF6CB6FF),
          ),
        ],
      ),
      // Named routes for navigation from login/welcome screens
      routes: {'/main': (_) => const MainLayout()},
      home: const AuthGate(),
    );
  }
}

/// Determines the initial screen based on auth state.
///
/// - If server URL is configured + login state valid → MainLayout
/// - If first launch or login state invalid → WelcomeScreen
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: _initAndCheck(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Loading — show blank screen briefly
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!) {
          return const MainLayout();
        }
        return const WelcomeScreen();
      },
    );
  }

  /// Check config and validate login state with server.
  Future<bool> _initAndCheck(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();

    // 如果用户主动登出过，直接显示欢迎页
    final loggedOut = prefs.getBool('clawke_logged_out') ?? false;
    if (loggedOut) return false;

    final httpUrl = prefs.getString('clawke_http_url');
    final hasConfig =
        httpUrl != null &&
        httpUrl.isNotEmpty &&
        httpUrl != 'http://127.0.0.1:8780';

    if (!hasConfig) return false;

    // 有本地配置，检查是否有登录态
    final isLoggedIn = await AuthService.isLoggedIn();
    if (!isLoggedIn) {
      // 有连接配置但没有登录态（可能是 QR 扫码直连模式）
      final user = await AuthService.getPersistedUser();
      if (user != null) {
        ref.read(authUserProvider.notifier).state = user;
      }
      final relay = await AuthService.getPersistedRelay();
      if (relay != null) {
        ref.read(relayCredentialsProvider.notifier).state = relay;
      }
      return true;
    }

    // 有登录态，向服务端验证是否有效
    try {
      final user = await AuthService.checkLogin();
      ref.read(authUserProvider.notifier).state = user;

      // 同时恢复 Relay 凭证
      final relay = await AuthService.getPersistedRelay();
      if (relay != null) {
        ref.read(relayCredentialsProvider.notifier).state = relay;
      }

      return true;
    } on ApiException catch (e) {
      // 网络超时不应该触发 logout — 只有服务端明确拒绝才清除凭证
      if (e.message.contains('超时') || e.message.contains('网络异常')) {
        debugPrint('[AuthGate] checkLogin timeout, using local data');
        final user = await AuthService.getPersistedUser();
        if (user != null) {
          ref.read(authUserProvider.notifier).state = user;
        }
        final relay = await AuthService.getPersistedRelay();
        if (relay != null) {
          ref.read(relayCredentialsProvider.notifier).state = relay;
        }
        return true;
      }
      // 登录态无效（服务端返回 success=false），清除本地凭证
      debugPrint('[AuthGate] Login state invalid, clearing credentials');
      await AuthService.logout();
      return false;
    } catch (e) {
      // 其他异常，仍然用本地数据（离线容错）
      debugPrint(
        '[AuthGate] checkLogin failed (network?): $e, using local data',
      );
      final user = await AuthService.getPersistedUser();
      if (user != null) {
        ref.read(authUserProvider.notifier).state = user;
      }
      final relay = await AuthService.getPersistedRelay();
      if (relay != null) {
        ref.read(relayCredentialsProvider.notifier).state = relay;
      }
      return true;
    }
  }
}
