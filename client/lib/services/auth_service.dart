import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/core/env_config.dart';
import 'package:client/core/http_util.dart';
import 'package:client/models/user_model.dart';
import 'package:client/models/account_summary.dart';

/// 认证服务 —— 对接 clawke.ai 后端真实 API。
///
/// 所有 HTTP 请求通过 [HttpUtil.doPost] 统一发起，
/// 自动携带 Cookie 鉴权、统一响应解析。
class AuthService {
  static const _kUidKey = 'clawke_auth_uid';
  static const _kSecuritKey = 'clawke_auth_securit';
  static const _kUserJsonKey = 'clawke_auth_user';
  static const _kRelayJsonKey = 'clawke_relay_credentials';
  static const _kLoggedOutKey = 'clawke_logged_out';
  static const _kKnownAccountsKey = 'clawke_known_accounts';

  // ── 本地状态查询 ──

  /// 检查是否已登录（本地有持久化的 uid + securit）。
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_kUidKey);
    final securit = prefs.getString(_kSecuritKey);
    return uid != null && uid.isNotEmpty && securit != null && securit.isNotEmpty;
  }

  /// 获取本地持久化的用户信息。
  static Future<UserVO?> getPersistedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kUserJsonKey);
    if (json == null) return null;
    try {
      return UserVO.fromJson(jsonDecode(json));
    } catch (e) {
      debugPrint('[Auth] Failed to parse persisted user: $e');
      return null;
    }
  }

  /// 获取本地持久化的 Relay 凭证。
  static Future<RelayCredentials?> getPersistedRelay() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kRelayJsonKey);
    if (json == null) return null;
    try {
      return RelayCredentials.fromJson(jsonDecode(json));
    } catch (e) {
      debugPrint('[Auth] Failed to parse persisted relay: $e');
      return null;
    }
  }

  // ── 持久化 ──

  static Future<void> _persistUser(UserVO user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUidKey, user.uid);
    await prefs.setString(_kSecuritKey, user.securit);
    await prefs.setString(_kUserJsonKey, jsonEncode(user.toJson()));
    // 登录成功，清除登出标记
    await prefs.remove(_kLoggedOutKey);
    // 自动记录到已知账号列表
    await _addToKnownAccounts(user);
  }

  static Future<void> _persistRelay(RelayCredentials relay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRelayJsonKey, jsonEncode({
      'token': relay.token,
      'relayUrl': relay.relayUrl,
    }));
  }

  // ── 邮箱登录 ──

  /// 邮箱 + 密码登录。
  ///
  /// API: POST /user/emailLogin.json
  static Future<UserVO> loginWithEmail(String email, String password) async {
    debugPrint('[Auth] Email login: $email');

    final result = await HttpUtil.doPost(
      '/user/emailLogin.json',
      data: {
        'loginId': email,
        'password': password,
        'loginType': 'password',
        'appCode': 'clawke',
      },
    );

    final user = UserVO.fromJson(result['value'] as Map<String, dynamic>);
    await _persistUser(user);
    return user;
  }

  // ── 邮箱注册 ──

  /// 发送注册邮箱验证码。
  ///
  /// API: POST /user/sendVerifyCodeMailApp.json
  static Future<void> sendVerificationCode(String email) async {
    debugPrint('[Auth] Sending verification code to: $email');

    await HttpUtil.doPost(
      '/user/sendVerifyCodeMailApp.json',
      data: {'email': email},
    );

    debugPrint('[Auth] ✅ Verification code sent');
  }

  /// 邮箱注册（需先发送验证码）。
  ///
  /// API: POST /user/emailReg.json
  static Future<UserVO> registerWithEmail(
    String email,
    String code,
    String password,
  ) async {
    debugPrint('[Auth] Email register: $email');

    final result = await HttpUtil.doPost(
      '/user/emailReg.json',
      data: {
        'email': email,
        'emailCode': code,
        'password': password,
        'regType': 'email',
        'appCode': 'clawke',
      },
    );

    final user = UserVO.fromJson(result['value'] as Map<String, dynamic>);
    await _persistUser(user);
    return user;
  }

  // ── Google 登录 ──

  /// Google Sign-In → 后端验证登录。
  ///
  /// API: POST /oauth/user/googleLogin.json
  static Future<UserVO> loginWithGoogle() async {
    debugPrint('[Auth] Google login on ${Platform.operatingSystem}');

    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
      );

      debugPrint('[Auth] Google signIn starting...');
      // 清除上一次残留的登录状态（macOS 上旧 session 可能阻塞新弹窗）
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          debugPrint('[Auth] Google signIn timeout after 120s');
          return null;
        },
      );
      debugPrint('[Auth] Google signIn result: ${googleUser?.email ?? 'null (cancelled)'}');

      if (googleUser == null) {
        throw const ApiException('Google 登录已取消');
      }

      // 获取认证 token（idToken 用于服务端验证）
      final googleAuth = await googleUser.authentication;
      debugPrint('[Auth] Got Google auth, idToken: ${googleAuth.idToken != null ? "OK" : "null"}');

      // 服务端 googleLogin 接口返回 302 + set-cookie（web OAuth 模式），
      // 不走 HttpUtil.doPost，而是直接发请求并从 Cookie 中提取凭证。
      final dio = Dio(BaseOptions(
        followRedirects: false,
        validateStatus: (status) => true,
      ));
      final formData = FormData.fromMap({
        'idToken': googleAuth.idToken ?? '',
        'accessToken': googleAuth.accessToken ?? '',
        'uid': googleUser.id,
        'name': googleUser.displayName ?? '',
        'email': googleUser.email,
        'imageUrl': googleUser.photoUrl ?? '',
        'state': 'clawke',
      });

      final response = await dio.post(
        '${EnvConfig.webBaseUrl}/oauth/user/googleLogin.json',
        data: formData,
      );

      debugPrint('[Auth] Google login response status: ${response.statusCode}');

      // 从 set-cookie 中提取 __UID 和 __SECURIT
      final cookies = response.headers['set-cookie'] ?? [];
      String? uid;
      String? securit;
      for (final cookie in cookies) {
        if (cookie.startsWith('__UID=')) {
          uid = cookie.split(';').first.split('=').sublist(1).join('=');
        } else if (cookie.startsWith('__SECURIT=')) {
          securit = Uri.decodeComponent(
            cookie.split(';').first.split('=').sublist(1).join('='),
          );
        }
      }

      debugPrint('[Auth] Extracted from cookies: uid=$uid, securit=${securit != null ? "OK" : "null"}');

      if (uid == null || uid.isEmpty || securit == null || securit.isEmpty) {
        throw const ApiException('Google 登录失败：服务端未返回认证信息');
      }

      // 先持久化 Cookie 凭证，然后用 checkLogin 获取完整用户信息
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUidKey, uid);
      await prefs.setString(_kSecuritKey, securit);
      await prefs.remove(_kLoggedOutKey);

      debugPrint('[Auth] Credentials saved, calling checkLogin...');
      final user = await checkLogin();
      return user;
    } on ApiException {
      rethrow;
    } catch (e, st) {
      debugPrint('[Auth] Google login failed: $e\n$st');
      throw ApiException('Google 登录失败: $e');
    }
  }

  // ── Apple 登录 ──

  /// Apple Sign-In → 后端验证登录。
  ///
  /// API: POST /user/appleLogin.json
  static Future<UserVO> loginWithApple() async {
    debugPrint('[Auth] Apple login on ${Platform.operatingSystem}');

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Apple 只在首次授权时返回 name，后续为 null
      String name = '';
      if (credential.givenName != null || credential.familyName != null) {
        name =
            '${credential.givenName ?? ''} ${credential.familyName ?? ''}'
                .trim();
      }

      final result = await HttpUtil.doPost(
        '/user/appleLogin.json',
        data: {
          'appleUid': credential.userIdentifier ?? '',
          'name': name,
          'appCode': 'clawke',
          'deviceType': Platform.isIOS ? 'ios' : 'macos',
        },
      );

      final user = UserVO.fromJson(result['value'] as Map<String, dynamic>);
      await _persistUser(user);
      return user;
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('[Auth] Apple login authorization error: ${e.code} - ${e.message}');
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          throw const ApiException('Apple 登录已取消');
        case AuthorizationErrorCode.invalidResponse:
          throw const ApiException('Apple 登录响应无效，请重试');
        case AuthorizationErrorCode.notHandled:
          throw const ApiException('Apple 登录请求未被处理');
        case AuthorizationErrorCode.notInteractive:
          throw const ApiException('Apple 登录需要用户交互');
        default:
          // error 1000 = unknown, 通常是 App ID 未配置 Sign In with Apple 能力
          throw const ApiException(
              'Apple 登录不可用，请确认 Apple Developer 已启用 Sign In with Apple');
      }
    } on ApiException {
      rethrow;
    } catch (e, st) {
      debugPrint('[Auth] Apple login failed: $e\n$st');
      throw ApiException('Apple 登录失败: $e');
    }
  }

  // ── 忘记密码（三步式） ──

  /// 忘记密码 - Step 1: 发送验证码到邮箱。
  ///
  /// API: POST /user/sendForgotPasswordCodeApp.json
  static Future<void> sendForgotPasswordCode(String email) async {
    debugPrint('[Auth] Forgot password - sending code to: $email');

    await HttpUtil.doPost(
      '/user/sendForgotPasswordCodeApp.json',
      data: {'email': email},
    );

    debugPrint('[Auth] ✅ Forgot password code sent');
  }

  /// 忘记密码 - Step 2: 验证验证码。
  ///
  /// API: POST /common/user/verifyForgotPasswordCode.json
  static Future<void> verifyForgotPasswordCode(String email, String code) async {
    debugPrint('[Auth] Forgot password - verifying code for: $email');

    await HttpUtil.doPost(
      '/common/user/verifyForgotPasswordCode.json',
      data: {
        'email': email,
        'verifyCode': code,
      },
    );

    debugPrint('[Auth] ✅ Forgot password code verified');
  }

  /// 忘记密码 - Step 3: 重置密码。
  ///
  /// API: POST /common/user/resetForgotPassword.json
  static Future<void> resetForgotPassword(String email, String newPassword) async {
    debugPrint('[Auth] Forgot password - resetting for: $email');

    await HttpUtil.doPost(
      '/common/user/resetForgotPassword.json',
      data: {
        'email': email,
        'newPassword': newPassword,
      },
    );

    debugPrint('[Auth] ✅ Password reset successful');
  }

  // ── 登录态校验 ──

  /// 修改密码。
  ///
  /// API: POST /user/modPassword.json
  static Future<void> modifyPassword(String oldPassword, String newPassword, String newPassword2) async {
    await HttpUtil.doPost('/user/modPassword.json', data: {
      'passwordOrignal': oldPassword,
      'passwordNew': newPassword,
      'passwordNew2': newPassword2,
    });
  }

  /// 服务端校验登录态是否有效。
  ///
  /// API: POST /user/checkLogin.json（Cookie 鉴权）
  /// 返回最新的 UserVO，如果登录态无效则抛出 ApiException。
  static Future<UserVO> checkLogin() async {
    debugPrint('[Auth] Checking login state with server');

    final result = await HttpUtil.doPost('/user/checkLogin.json');

    final user = UserVO.fromJson(result['value'] as Map<String, dynamic>);
    // 更新本地持久化（服务端可能更新了 name/photo 等）
    await _persistUser(user);
    return user;
  }

  // ── Relay 凭证 ──

  /// 从 Web 服务获取 Relay 凭证。
  ///
  /// API: POST /clawke/relay/credentials.json（Cookie 鉴权）
  /// 返回 token + subdomain + relayServer，拼接为 relayUrl。
  static Future<RelayCredentials> fetchRelayCredentials() async {
    debugPrint('[Auth] Fetching relay credentials');

    final result = await HttpUtil.doPost('/clawke/relay/credentials.json');
    final relay = RelayCredentials.fromJson(result['value'] as Map<String, dynamic>);

    await _persistRelay(relay);
    return relay;
  }

  // ── 登出 ──

  /// 清除所有本地持久化的认证和 Relay 数据。
  static Future<void> logout() async {
    debugPrint('[Auth] Logout');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUidKey);
    await prefs.remove(_kSecuritKey);
    await prefs.remove(_kUserJsonKey);
    await prefs.remove(_kRelayJsonKey);
    // 设置登出标记，让 AuthGate 知道用户主动登出了
    await prefs.setBool(_kLoggedOutKey, true);
  }

  // ── 注销账号 ──

  /// 向服务器请求注销当前登录账户，成功后清除本地数据
  static Future<void> deleteAccount() async {
    debugPrint('[Auth] Delete Account');
    // 发送真实的网络请求删除远端账号
    await HttpUtil.doPost('/user/deleteAccount.json');
    // 远端成功后，清理本地验证信息
    await logout();
  }

  // ── 账号记忆系统 ──

  /// 将用户加入已知账号列表（登录成功时自动调用）
  static Future<void> _addToKnownAccounts(UserVO user) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getKnownAccounts();

    // 更新已有或添加新的
    final idx = accounts.indexWhere((a) => a.uid == user.uid);
    final summary = AccountSummary.fromUser(user);
    if (idx >= 0) {
      accounts[idx] = summary;
    } else {
      accounts.add(summary);
    }

    await prefs.setString(
      _kKnownAccountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    debugPrint('[Auth] Known accounts updated: ${accounts.length} accounts');
  }

  /// 获取所有已知账号
  static Future<List<AccountSummary>> getKnownAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kKnownAccountsKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => AccountSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Auth] Failed to parse known accounts: $e');
      return [];
    }
  }

  /// 从已知账号列表移除
  static Future<void> removeKnownAccount(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getKnownAccounts();
    accounts.removeWhere((a) => a.uid == uid);
    await prefs.setString(
      _kKnownAccountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    debugPrint('[Auth] Removed account $uid from known accounts');
  }

  /// 切换到指定账号：恢复凭证 + checkLogin 验证
  ///
  /// 成功返回 UserVO，失败抛出异常并从已知列表移除。
  static Future<UserVO> switchToAccount(AccountSummary account) async {
    debugPrint('[Auth] Switching to account: ${account.uid} (${account.name})');
    final prefs = await SharedPreferences.getInstance();

    // 恢复凭证
    await prefs.setString(_kUidKey, account.uid);
    await prefs.setString(_kSecuritKey, account.securit);
    await prefs.remove(_kLoggedOutKey);

    try {
      // 服务端验证
      final user = await checkLogin();
      return user;
    } catch (e) {
      debugPrint('[Auth] Switch failed, account expired: $e');
      // 登录态无效，从已知列表移除
      await removeKnownAccount(account.uid);
      // 清除当前无效凭证
      await prefs.remove(_kUidKey);
      await prefs.remove(_kSecuritKey);
      rethrow;
    }
  }
}
