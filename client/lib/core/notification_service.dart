import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:client/core/notification_event.dart';

typedef NotificationTapHandler = void Function(NotificationPayload payload);

class AppNotificationPermissions {
  final bool isEnabled;
  final bool isAlertEnabled;
  final bool isBadgeEnabled;
  final bool isSoundEnabled;

  const AppNotificationPermissions({
    required this.isEnabled,
    required this.isAlertEnabled,
    required this.isBadgeEnabled,
    required this.isSoundEnabled,
  });

  bool get canShowSystemNotifications => isEnabled;
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _badgeChannel = MethodChannel('clawke/app_badge');
  static bool _initialized = false;
  static NotificationTapHandler? _tapHandler;
  static NotificationPayload? _launchPayload;

  static Future<void> init() async {
    if (_initialized) return;
    if (!_supportsLocalNotificationPlugin()) {
      debugPrint(
        '[NotificationService] 🔕 local notifications unsupported on ${defaultTargetPlatform.name}',
      );
      return;
    }

    // Do NOT request permissions here — requesting on macOS during init
    // can block the main thread before the window renders, causing a black screen.
    // Call requestPermissions() separately after the UI is visible.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(
      macOS: darwinSettings,
      iOS: darwinSettings,
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchPayload = NotificationPayload.decode(
        launchDetails?.notificationResponse?.payload,
      );
    }
    _initialized = true;
  }

  static bool _supportsLocalNotificationPlugin() {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  static void setTapHandler(NotificationTapHandler? handler) {
    _tapHandler = handler;
    final payload = _launchPayload;
    if (payload == null || handler == null) return;
    _launchPayload = null;
    handler(payload);
  }

  static NotificationPayload? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    if (payload == null) return;
    final handler = _tapHandler;
    if (handler == null) {
      _launchPayload = payload;
      return;
    }
    handler(payload);
  }

  /// Request notification permissions after the UI is fully rendered.
  /// Call this from the main screen's initState, not from main().
  static Future<AppNotificationPermissions?> requestPermissions() async {
    if (!_initialized) return null;
    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    return checkNotificationPermissions();
  }

  static Future<AppNotificationPermissions?>
  checkNotificationPermissions() async {
    if (Platform.isMacOS) {
      final macOSNotifications = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final macOSPermissions = await macOSNotifications?.checkPermissions();
      if (macOSPermissions == null) return null;
      return _fromDarwinPermissions('macOS', macOSPermissions);
    }

    if (Platform.isIOS) {
      final iOSNotifications = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iOSPermissions = await iOSNotifications?.checkPermissions();
      if (iOSPermissions == null) return null;
      await _logAppleNotificationSettingsDetails('iOS');
      return _fromDarwinPermissions('iOS', iOSPermissions);
    }

    if (Platform.isAndroid) {
      final androidNotifications = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await androidNotifications?.areNotificationsEnabled();
      if (enabled == null) return null;
      final permissions = AppNotificationPermissions(
        isEnabled: enabled,
        isAlertEnabled: enabled,
        isBadgeEnabled: enabled,
        isSoundEnabled: enabled,
      );
      _logPermissions('Android', permissions);
      return permissions;
    }

    if (Platform.isWindows) {
      final enabled = await _checkPlatformNotificationsEnabled();
      final permissions = AppNotificationPermissions(
        isEnabled: enabled,
        isAlertEnabled: enabled,
        isBadgeEnabled: false,
        isSoundEnabled: enabled,
      );
      _logPermissions('Windows', permissions);
      return permissions;
    }

    return null;
  }

  static Future<AppNotificationPermissions?> checkMacOSPermissions() {
    return checkNotificationPermissions();
  }

  static AppNotificationPermissions _fromDarwinPermissions(
    String platform,
    NotificationsEnabledOptions source,
  ) {
    final permissions = AppNotificationPermissions(
      isEnabled: source.isEnabled,
      isAlertEnabled: source.isAlertEnabled,
      isBadgeEnabled: source.isBadgeEnabled,
      isSoundEnabled: source.isSoundEnabled,
    );
    _logPermissions(platform, permissions);
    return permissions;
  }

  static void _logPermissions(
    String platform,
    AppNotificationPermissions permissions,
  ) {
    debugPrint(
      '[NotificationService] 🔔 $platform permissions: '
      'enabled=${permissions.isEnabled}, '
      'alert=${permissions.isAlertEnabled}, '
      'badge=${permissions.isBadgeEnabled}, '
      'sound=${permissions.isSoundEnabled}',
    );
  }

  static Future<void> _logAppleNotificationSettingsDetails(
    String platform,
  ) async {
    try {
      final details = await _badgeChannel.invokeMapMethod<String, dynamic>(
        'checkNotificationSettingsDetails',
      );
      if (details == null) return;
      debugPrint(
        '[NotificationService] 🔔 $platform notification settings details: '
        'authorization=${details['authorization']}, '
        'alert=${details['alert']}, '
        'badge=${details['badge']}, '
        'sound=${details['sound']}, '
        'lockScreen=${details['lockScreen']}, '
        'notificationCenter=${details['notificationCenter']}',
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint(
        '[NotificationService] ⚠️ check notification details failed: ${e.message}',
      );
    }
  }

  static Future<bool> _checkPlatformNotificationsEnabled() async {
    try {
      return await _badgeChannel.invokeMethod<bool>(
            'checkNotificationsEnabled',
          ) ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (e) {
      debugPrint(
        '[NotificationService] ⚠️ check notification settings failed: ${e.message}',
      );
      return true;
    }
  }

  static Future<void> setApplicationBadgeCount(int count) async {
    final safeCount = count < 0 ? 0 : count;

    try {
      await _badgeChannel.invokeMethod<void>('setBadgeCount', {
        'count': safeCount,
      });
      debugPrint('[NotificationService] 🔢 app badge count: $safeCount');
    } on MissingPluginException catch (e) {
      debugPrint('[NotificationService] ⚠️ app badge channel unavailable: $e');
    } on PlatformException catch (e) {
      debugPrint('[NotificationService] ⚠️ set badge failed: ${e.message}');
    }
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _badgeChannel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException catch (e) {
      debugPrint(
        '[NotificationService] ⚠️ notification settings channel unavailable: $e',
      );
    } on PlatformException catch (e) {
      debugPrint(
        '[NotificationService] ⚠️ open notification settings failed: ${e.message}',
      );
    }
  }

  static Future<void> showMessageNotification({
    required String title,
    required String body,
    String? accountId,
    String? conversationId,
    String? messageId,
    NotificationPayload? payload,
    bool playSound = true,
  }) async {
    if (!_initialized) return;

    final resolvedPayload =
        payload ??
        ((conversationId != null && messageId != null)
            ? NotificationPayload(
                conversationId: conversationId,
                messageId: messageId,
                gatewayId: accountId ?? conversationId,
                seq: 0,
                source: NotificationEventSource.localWs,
              )
            : null);

    final details = NotificationDetails(
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
      android: const AndroidNotificationDetails(
        'clawke_messages',
        'Messages',
        channelDescription: 'Clawke message notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
      payload: resolvedPayload?.encode(),
    );
    debugPrint(
      '[NotificationService] 🔔 message notification shown: '
      'conv=${resolvedPayload?.conversationId ?? ''}, '
      'msg=${resolvedPayload?.messageId ?? ''}',
    );
  }
}
