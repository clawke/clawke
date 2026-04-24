import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/http_util.dart';
import 'package:client/services/auth_service.dart';

/// Auth API 集成测试 —— 对 local.clawke.ai 真实后端发起请求。
///
/// 验证：
/// 1. API 连通性和响应格式（7 个 endpoint）
/// 2. 错误处理（无效凭证、无效参数）
/// 3. AuthService 层的正确封装
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock SharedPreferences（测试环境无 platform channel）
    SharedPreferences.setMockInitialValues({});
  });

  group('Integration: HttpUtil API connectivity', () {
    test('emailLogin with invalid credentials returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/user/emailLogin.json', data: {
          'loginId': 'nonexist@test.com',
          'password': 'wrongpassword',
          'loginType': 'password',
          'appCode': 'clawke',
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('sendVerifyCodeMailApp with invalid email returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/user/sendVerifyCodeMailApp.json', data: {
          'email': 'not_an_email',
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('sendForgotPasswordCodeApp with invalid email returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/user/sendForgotPasswordCodeApp.json', data: {
          'email': 'bad_email',
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('checkLogin without credentials returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/user/checkLogin.json'),
        throwsA(isA<ApiException>()),
      );
    });

    test('emailReg without verification code returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/user/emailReg.json', data: {
          'email': 'test@example.com',
          'emailCode': '',
          'password': 'testpass123',
          'regType': 'email',
          'appCode': 'clawke',
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('verifyForgotPasswordCode with wrong code returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/common/user/verifyForgotPasswordCode.json', data: {
          'email': 'test@example.com',
          'verifyCode': '000000',
        }),
        throwsA(isA<ApiException>()),
      );
    });

    test('relay credentials without login returns ApiException', () async {
      expect(
        () => HttpUtil.doPost('/clawke/relay/credentials.json'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('Integration: AuthService error handling', () {
    test('loginWithEmail with wrong password throws ApiException', () async {
      expect(
        () => AuthService.loginWithEmail('nonexist@test.com', 'wrongpass'),
        throwsA(isA<ApiException>()),
      );
    });

    test('sendVerificationCode with invalid email throws ApiException', () async {
      expect(
        () => AuthService.sendVerificationCode('not_valid'),
        throwsA(isA<ApiException>()),
      );
    });

    test('registerWithEmail without valid code throws ApiException', () async {
      expect(
        () => AuthService.registerWithEmail('test@test.com', '', 'pass123'),
        throwsA(isA<ApiException>()),
      );
    });

    test('sendForgotPasswordCode with invalid email throws ApiException', () async {
      expect(
        () => AuthService.sendForgotPasswordCode('bad_email'),
        throwsA(isA<ApiException>()),
      );
    });

    test('verifyForgotPasswordCode with wrong code throws ApiException', () async {
      expect(
        () => AuthService.verifyForgotPasswordCode('test@test.com', '000000'),
        throwsA(isA<ApiException>()),
      );
    });

    test('checkLogin without session throws ApiException', () async {
      expect(
        () => AuthService.checkLogin(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchRelayCredentials without session throws ApiException', () async {
      expect(
        () => AuthService.fetchRelayCredentials(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
