import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 确保标题栏和红/黄/绿交通灯按钮可见（App Store 审核要求 Guideline 4）
    self.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible

    // 最小窗口尺寸
    self.minSize = NSSize(width: 800, height: 500)

    // 从 UserDefaults 恢复窗口大小（仅大小，不记位置）
    let defaults = UserDefaults.standard
    let savedWidth = defaults.double(forKey: "ClawkeWindowWidth")
    let savedHeight = defaults.double(forKey: "ClawkeWindowHeight")

    let width: CGFloat = savedWidth >= 800 ? CGFloat(savedWidth) : 1024
    let height: CGFloat = savedHeight >= 500 ? CGFloat(savedHeight) : 768

    let size = NSSize(width: width, height: height)
    self.setContentSize(size)
    self.center()
    NSLog("[Clawke] Window init: saved=(%g, %g) → applied=(%g x %g)", savedWidth, savedHeight, width, height)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 确保窗口在启动时获得焦点（否则 flutter run 时终端保持焦点，
    // macOS 会暂停 Dart 事件循环，导致 WebSocket 连接等 Dart 代码不执行）
    NSApp.activate(ignoringOtherApps: true)
    self.makeKeyAndOrderFront(nil)
  }

  // 关闭窗口时保存大小
  override func close() {
    let defaults = UserDefaults.standard
    defaults.set(Double(self.frame.width), forKey: "ClawkeWindowWidth")
    defaults.set(Double(self.frame.height), forKey: "ClawkeWindowHeight")
    NSLog("[Clawke] Window saved on close: %g x %g", self.frame.width, self.frame.height)
    super.close()
  }
}
