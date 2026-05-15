import Cocoa
import FlutterMacOS
import Security
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private static let stablePushDeviceIdService = "ai.clawke.app.push-device-id"
  private static let stablePushDeviceIdAccount = "clawke_push_device_id"
  private var pushChannel: FlutterMethodChannel?
  private var pendingPushTokenResult: FlutterResult?
  private var pendingRemotePushPayloads: [[String: Any]] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    enqueueLaunchNotificationPayload(notification.userInfo)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func setupPushChannel(binaryMessenger: FlutterBinaryMessenger) {
    pushChannel = FlutterMethodChannel(
      name: "clawke/push",
      binaryMessenger: binaryMessenger
    )
    pushChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "registerForRemoteNotifications":
        self.pendingPushTokenResult = result
        DispatchQueue.main.async {
          NSApplication.shared.registerForRemoteNotifications(matching: [.alert, .badge])
        }
      case "readStableDeviceId":
        result(self.readStablePushDeviceId())
      case "takeRemotePushPayloads":
        result(self.pendingRemotePushPayloads)
        self.pendingRemotePushPayloads.removeAll()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    NSLog("[Clawke] Remote push token registered")
    pendingPushTokenResult?(["token": token, "platform": "macos"])
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: NSApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pendingPushTokenResult?(
      FlutterError(
        code: "apns_registration_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: NSApplication,
    didReceiveRemoteNotification userInfo: [String: Any]
  ) {
    NSLog("[Clawke] Remote push delivered to app")
    enqueueRemotePushPayload(userInfo, eventType: "delivery")
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSLog("[Clawke] Notification tapped")
    enqueueRemotePushPayload(
      response.notification.request.content.userInfo,
      eventType: "notification_tap"
    )
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    NSLog("[Clawke] Notification will present: id=\(notification.request.identifier)")
    enqueueRemotePushPayload(
      notification.request.content.userInfo,
      eventType: "delivery"
    )
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .badge])
    } else {
      completionHandler([.alert, .badge])
    }
  }

  private func enqueueRemotePushPayload(_ userInfo: [AnyHashable: Any], eventType: String) {
    let payload = normalizeRemotePushPayload(userInfo, eventType: eventType)
    if payload.isEmpty {
      return
    }
    NSLog("[Clawke] Remote push received")
    pendingRemotePushPayloads.append(payload)
    pushChannel?.invokeMethod("remotePushReceived", arguments: payload)
  }

  private func enqueueLaunchNotificationPayload(_ launchUserInfo: [AnyHashable: Any]?) {
    guard let launchValue = launchUserInfo?[NSApplication.launchUserNotificationUserInfoKey] else {
      return
    }

    if let response = launchValue as? UNNotificationResponse {
      enqueueRemotePushPayload(
        response.notification.request.content.userInfo,
        eventType: "notification_tap"
      )
      return
    }

    if let notification = launchValue as? UNNotification {
      enqueueRemotePushPayload(
        notification.request.content.userInfo,
        eventType: "notification_tap"
      )
      return
    }

    if let notification = launchValue as? NSUserNotification,
       let userInfo = notification.userInfo {
      enqueueRemotePushPayload(userInfo, eventType: "notification_tap")
      return
    }

    if let userInfo = launchValue as? [AnyHashable: Any] {
      enqueueRemotePushPayload(userInfo, eventType: "notification_tap")
      return
    }

    if let userInfo = launchValue as? [String: Any] {
      let normalized = userInfo.reduce(into: [AnyHashable: Any]()) { result, item in
        result[AnyHashable(item.key)] = item.value
      }
      enqueueRemotePushPayload(normalized, eventType: "notification_tap")
    }
  }

  private func normalizeRemotePushPayload(_ userInfo: [AnyHashable: Any], eventType: String) -> [String: Any] {
    if eventType == "notification_tap",
       let localPayload = userInfo["payload"] as? String,
       let decodedPayload = normalizeLocalNotificationPayload(localPayload, eventType: eventType) {
      return decodedPayload
    }

    var payload: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String else { continue }
      if key == "conversation_id" || key == "message_id" || key == "gateway_id" {
        payload[key] = "\(value)"
      } else if key == "seq" {
        if let number = value as? NSNumber {
          payload[key] = number.intValue
        } else {
          payload[key] = Int("\(value)") ?? 0
        }
      }
    }
    if !payload.isEmpty {
      payload["event_type"] = eventType
    }
    return payload
  }

  private func readStablePushDeviceId() -> String {
    if let existing = readKeychainString(
      service: Self.stablePushDeviceIdService,
      account: Self.stablePushDeviceIdAccount
    ), !existing.isEmpty {
      return existing
    }

    let generated = UUID().uuidString
    saveKeychainString(
      generated,
      service: Self.stablePushDeviceIdService,
      account: Self.stablePushDeviceIdAccount
    )
    return generated
  }

  private func readKeychainString(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func saveKeychainString(_ value: String, service: String, account: String) {
    guard let data = value.data(using: .utf8) else {
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      SecItemAdd(item as CFDictionary, nil)
    }
  }

  private func normalizeLocalNotificationPayload(_ rawPayload: String, eventType: String) -> [String: Any]? {
    guard let data = rawPayload.data(using: .utf8),
          let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    var payload: [String: Any] = [:]
    for key in ["conversation_id", "message_id", "gateway_id"] {
      if let value = decoded[key] {
        payload[key] = "\(value)"
      }
    }

    if let number = decoded["seq"] as? NSNumber {
      payload["seq"] = number.intValue
    } else if let value = decoded["seq"] {
      payload["seq"] = Int("\(value)") ?? 0
    }

    if !payload.isEmpty {
      payload["event_type"] = eventType
    }
    return payload.isEmpty ? nil : payload
  }
}
