import 'dart:async';

import 'package:flutter/material.dart';
import 'package:client/core/http_util.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/l10n/l10n.dart';

/// 忘记密码页面 —— 三步式流程。
///
/// Step 1: 输入邮箱 → 发送验证码 → 60s 倒计时
/// Step 2: 输入 6 位验证码 → 验证
/// Step 3: 输入新密码（6-20字符）→ 重置成功 → 返回登录页
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // 当前步骤：0=输入邮箱, 1=输入验证码, 2=设置新密码
  int _step = 0;
  bool _isLoading = false;
  String? _error;
  String? _success;

  // Controllers
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // 倒计时
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.forgotPasswordTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 步骤指示器
                _buildStepIndicator(colorScheme, textTheme),
                const SizedBox(height: 32),

                // 步骤内容
                if (_step == 0) _buildStep1(colorScheme, textTheme),
                if (_step == 1) _buildStep2(colorScheme, textTheme),
                if (_step == 2) _buildStep3(colorScheme, textTheme),

                // 错误信息
                if (_error != null) ...[
                  const SizedBox(height: 16),
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
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: textTheme.bodySmall!.fontSize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 成功信息
                if (_success != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _success!,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: textTheme.bodySmall!.fontSize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 步骤指示器 ──

  Widget _buildStepIndicator(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        _stepDot(0, context.l10n.stepEmail, colorScheme, textTheme),
        Expanded(child: Container(height: 2, color: _step >= 1 ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3))),
        _stepDot(1, context.l10n.stepVerify, colorScheme, textTheme),
        Expanded(child: Container(height: 2, color: _step >= 2 ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3))),
        _stepDot(2, context.l10n.stepReset, colorScheme, textTheme),
      ],
    );
  }

  Widget _stepDot(int step, String label, ColorScheme colorScheme, TextTheme textTheme) {
    final isActive = _step >= step;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? colorScheme.primary : colorScheme.surfaceContainerLow,
          ),
          child: Center(
            child: _step > step
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                      fontSize: textTheme.bodySmall!.fontSize,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: textTheme.labelSmall!.fontSize,
          ),
        ),
      ],
    );
  }

  // ── Step 1: 输入邮箱 ──

  Widget _buildStep1(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.enterRegisteredEmail,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.willSendCodeToReset,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: context.l10n.emailAddress,
            hintText: context.l10n.enterRegisteredEmailHint,
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
          onSubmitted: (_) => _handleSendCode(),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleSendCode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.l10n.sendVerificationCode, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Step 2: 输入验证码 ──

  Widget _buildStep2(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.enterEmailCode,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.codeSentTo(_emailController.text),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: context.l10n.verificationCode,
            hintText: context.l10n.enterSixDigitCode,
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
            counterText: '',
          ),
          onSubmitted: (_) => _handleVerifyCode(),
        ),
        const SizedBox(height: 12),

        // 重新发送
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _countdown > 0 || _isLoading ? null : _handleResendCode,
              child: Text(
                _countdown > 0 ? context.l10n.resendCountdown(_countdown) : context.l10n.resend,
                style: TextStyle(fontSize: textTheme.bodySmall!.fontSize),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleVerifyCode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.l10n.verifyButton, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Step 3: 设置新密码 ──

  Widget _buildStep3(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.setNewPasswordTitle,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.enter6to20Password,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: context.l10n.newPassword,
            hintText: context.l10n.enterNewPassword,
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
        const SizedBox(height: 16),

        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: context.l10n.confirmPasswordLabel,
            hintText: context.l10n.reenterNewPassword,
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
          onSubmitted: (_) => _handleResetPassword(),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(context.l10n.resetPasswordButton, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── 事件处理 ──

  /// Step 1: 发送验证码
  Future<void> _handleSendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() { _error = context.l10n.enterEmailFirst; _success = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      await AuthService.sendForgotPasswordCode(email);
      _startCountdown();
      setState(() {
        _step = 1;
        _success = context.l10n.codeSentCheckEmail;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.sendFailed(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Step 2: 验证验证码
  Future<void> _handleVerifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() { _error = context.l10n.enterSixDigitCode; _success = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      await AuthService.verifyForgotPasswordCode(_emailController.text.trim(), code);
      setState(() {
        _step = 2;
        _success = context.l10n.verifySuccess;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.verifyFailed(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 重新发送验证码
  Future<void> _handleResendCode() async {
    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      await AuthService.sendForgotPasswordCode(_emailController.text.trim());
      _startCountdown();
      setState(() => _success = context.l10n.codeResent);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.sendFailed(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Step 3: 重置密码
  Future<void> _handleResetPassword() async {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (password.isEmpty) {
      setState(() { _error = context.l10n.enterNewPassword; _success = null; });
      return;
    }
    if (password.length < 6 || password.length > 20) {
      setState(() { _error = context.l10n.passwordLengthError; _success = null; });
      return;
    }
    if (password != confirm) {
      setState(() { _error = context.l10n.passwordMismatch; _success = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      await AuthService.resetForgotPassword(_emailController.text.trim(), password);

      if (mounted) {
        // 弹出成功提示并返回登录页
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.passwordResetSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.resetFailed(e.toString()));
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
