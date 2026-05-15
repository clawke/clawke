import 'package:client/core/env_config.dart';
import 'package:client/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple sign-in is enabled on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    expect(AuthService.supportsAppleSignIn, isTrue);
  });

  test('Apple sign-in on macOS follows the distribution build flag', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    expect(AuthService.supportsAppleSignIn, EnvConfig.macOSAppleSignInEnabled);
  });
}
