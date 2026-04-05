import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/http_util.dart';
import 'package:client/models/user_model.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/screens/forgot_password_screen.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/services/media_resolver.dart';

/// Login and registration screen with email, Google, and Apple sign-in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _error;

  // Login fields
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Register fields
  final _regEmailController = TextEditingController();
  final _regCodeController = TextEditingController();
  final _regPasswordController = TextEditingController();
  bool _codeSent = false;

  // 验证码倒计时
  int _countdown = 0;
  Timer? _timer;
  bool _obscureLoginPassword = true;
  bool _obscureRegPassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _regEmailController.dispose();
    _regCodeController.dispose();
    _regPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.loginTabLogin),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                // Tab bar: Login / Register
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: colorScheme.primary,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
                    dividerHeight: 0,
                    tabs: [
                      Tab(text: t.loginTabLogin),
                      Tab(text: t.loginTabRegister),
                    ],
                    onTap: (_) => setState(() => _error = null),
                  ),
                ),

                const SizedBox(height: 32),

                // Tab content
                SizedBox(
                  height: 360,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLoginForm(colorScheme),
                      _buildRegisterForm(colorScheme),
                    ],
                  ),
                ),

                // Error message
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: colorScheme.error, fontSize: Theme.of(context).textTheme.bodySmall!.fontSize),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: colorScheme.outline.withValues(alpha: 0.3))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '或',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: colorScheme.outline.withValues(alpha: 0.3))),
                  ],
                ),

                const SizedBox(height: 24),

                // Social login buttons
                _buildSocialButtons(colorScheme),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(ColorScheme colorScheme) {
    return Column(
      children: [
        // Email
        TextField(
          controller: _loginEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '邮箱地址',
            hintText: '请输入邮箱地址',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            prefixIcon: const Icon(Icons.email_outlined),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
        ),
        const SizedBox(height: 16),

        // Password
        TextField(
          controller: _loginPasswordController,
          obscureText: _obscureLoginPassword,
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '请输入密码',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscureLoginPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
          onSubmitted: (_) => _handleLogin(),
        ),

        // 忘记密码链接
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              );
            },
            child: Text(
              '忘记密码？',
              style: TextStyle(
                fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Login button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('登录', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(ColorScheme colorScheme) {
    return Column(
      children: [
        // Email
        TextField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: '邮箱地址',
            hintText: '请输入邮箱地址',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            prefixIcon: const Icon(Icons.email_outlined),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
        ),
        const SizedBox(height: 16),

        // Verification code
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _regCodeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '验证码',
                  hintText: '请输入邮箱验证码',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: const Icon(Icons.verified_outlined),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.error, width: 2),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: TextButton(
                onPressed: (_isLoading || _countdown > 0) ? null : _handleSendCode,
                child: Text(
                  _countdown > 0 ? '${_countdown}s' : (_codeSent ? '重新发送' : '获取验证码'),
                  style: TextStyle(color: _countdown > 0 ? colorScheme.onSurface.withValues(alpha: 0.4) : colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Password
        TextField(
          controller: _regPasswordController,
          obscureText: _obscureRegPassword,
          decoration: InputDecoration(
            labelText: '设置密码',
            hintText: '请设置一个登录密码',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscureRegPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureRegPassword = !_obscureRegPassword),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
        ),
        const SizedBox(height: 24),

        // Register button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('register_submit_button'),
            onPressed: _isLoading ? null : _handleRegister,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('注册', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButtons(ColorScheme colorScheme) {
    return Column(
      children: [
        // Google Sign-In
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _handleGoogleLogin,
            icon: Text('G', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            label: Text('Google 登录', style: Theme.of(context).textTheme.bodyMedium),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
            ),
          ),
        ),

        // Apple Sign-In (iOS only)
        if (Platform.isIOS || Platform.isMacOS) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleAppleLogin,
              icon: const Icon(Icons.apple, size: 24),
              label: Text('Apple 登录', style: Theme.of(context).textTheme.bodyMedium),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Handlers ──

  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写邮箱和密码');
      return;
    }
    await _doLogin(() => AuthService.loginWithEmail(email, password));
  }

  Future<void> _handleSendCode() async {
    final email = _regEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请先输入邮箱地址');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      await AuthService.sendVerificationCode(email);
      setState(() => _codeSent = true);
      _startCountdown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '发送验证码失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    final email = _regEmailController.text.trim();
    final code = _regCodeController.text.trim();
    final password = _regPasswordController.text;
    if (email.isEmpty || code.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写所有字段');
      return;
    }
    await _doLogin(() => AuthService.registerWithEmail(email, code, password));
  }

  Future<void> _handleGoogleLogin() async {
    try {
      await _doLogin(() => AuthService.loginWithGoogle());
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Google 登录暂不可用，请使用邮箱登录');
      }
    }
  }

  Future<void> _handleAppleLogin() async {
    try {
      await _doLogin(() => AuthService.loginWithApple());
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Apple 登录暂不可用，请使用邮箱登录');
      }
    }
  }

  /// Shared login flow: call auth → fetch relay → navigate to main.
  Future<void> _doLogin(Future<UserVO> Function() loginFn) async {
    setState(() { _isLoading = true; _error = null; });
    try {
      debugPrint('[Login] Step 1: Calling login API...');
      final user = await loginFn();
      debugPrint('[Login] Step 1 OK: uid=${user.uid}');
      ref.read(authUserProvider.notifier).state = user;

      debugPrint('[Login] Step 2: Fetching relay credentials...');
      final relay = await AuthService.fetchRelayCredentials();
      debugPrint('[Login] Step 2 OK: relayUrl=${relay.relayUrl}, token=${relay.token.substring(0, 4)}...');
      ref.read(relayCredentialsProvider.notifier).state = relay;

      debugPrint('[Login] Step 3: Setting server address...');
      // 等待 provider 构造函数中的 _load() 先完成，
      // 避免 _load() 异步读到旧值后覆盖我们即将设置的新值（竞态条件）。
      await ref.read(serverConfigProvider.notifier).ensureLoaded();
      await ref.read(serverConfigProvider.notifier).setServerAddress(relay.relayUrl);
      debugPrint('[Login] Step 3 OK');

      debugPrint('[Login] Step 4: Setting token...');
      await ref.read(serverConfigProvider.notifier).setToken(relay.token);
      debugPrint('[Login] Step 4 OK');

      // Step 5: 直接同步更新 WsService / MediaResolver 的 static 状态，
      // 避免 MainLayout 被复用时 initState 不再执行导致用旧 token 连接。
      final updatedConfig = ref.read(serverConfigProvider);
      WsService.setUrl(updatedConfig.wsUrl);
      WsService.setToken(updatedConfig.token);
      MediaResolver.setBaseUrl(updatedConfig.httpUrl);
      MediaResolver.setToken(updatedConfig.token);
      debugPrint('[Login] Step 5: WsService/MediaResolver synced with new credentials');

      if (mounted) {
        debugPrint('[Login] Step 6: Navigating to /main...');
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('[Login] ❌ Error: $e\n$st');
      setState(() => _error = '登录失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 启动 60s 倒计时
  void _startCountdown() {
    _timer?.cancel();
    _countdown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }
}
