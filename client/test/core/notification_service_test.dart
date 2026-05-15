import 'package:client/core/notification_event.dart';
import 'package:client/core/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const badgeChannel = MethodChannel('clawke/app_badge');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badgeChannel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badgeChannel, null);
  });

  test('setApplicationBadgeCount sends count to platform channel', () async {
    await NotificationService.setApplicationBadgeCount(7);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setBadgeCount');
    expect(calls.single.arguments, {'count': 7});
  });

  test('setApplicationBadgeCount clamps negative count to zero', () async {
    await NotificationService.setApplicationBadgeCount(-3);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setBadgeCount');
    expect(calls.single.arguments, {'count': 0});
  });

  test('openNotificationSettings sends request to platform channel', () async {
    await NotificationService.openNotificationSettings();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openNotificationSettings');
    expect(calls.single.arguments, isNull);
  });

  test('canShowSystemNotifications only requires notification switch', () {
    expect(
      const AppNotificationPermissions(
        isEnabled: true,
        isAlertEnabled: false,
        isBadgeEnabled: false,
        isSoundEnabled: false,
      ).canShowSystemNotifications,
      isTrue,
    );
    expect(
      const AppNotificationPermissions(
        isEnabled: false,
        isAlertEnabled: false,
        isBadgeEnabled: true,
        isSoundEnabled: false,
      ).canShowSystemNotifications,
      isFalse,
    );
  });

  test('notification payload round-trips routing fields', () {
    const payload = NotificationPayload(
      conversationId: 'conv_1',
      messageId: 'msg_1',
      gatewayId: 'gateway_1',
      seq: 42,
      source: NotificationEventSource.localWs,
    );

    final decoded = NotificationPayload.decode(payload.encode());

    expect(decoded?.conversationId, 'conv_1');
    expect(decoded?.messageId, 'msg_1');
    expect(decoded?.gatewayId, 'gateway_1');
    expect(decoded?.seq, 42);
    expect(decoded?.source, NotificationEventSource.localWs);
  });

  test('notification payload returns null for invalid payload', () {
    expect(NotificationPayload.decode(''), isNull);
    expect(NotificationPayload.decode('{"message_id":"msg_1"}'), isNull);
  });

  test('init skips unsupported Windows local notification plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await NotificationService.init();
    await NotificationService.showMessageNotification(
      title: 'title',
      body: 'body',
    );

    expect(calls, isEmpty);
  });
}
