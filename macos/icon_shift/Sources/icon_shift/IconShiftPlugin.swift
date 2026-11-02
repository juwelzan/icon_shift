import Cocoa
import FlutterMacOS

/// macOS implementation of IconShift.
///
/// The icon is the running app's Dock icon (`NSApplication.applicationIconImage`),
/// the display name is the main window title. The signed app bundle is never
/// modified, so both changes last only while the app runs; the Dart side
/// re-applies the saved selection on launch.
public class IconShiftPlugin: NSObject, FlutterPlugin {
  static let defaultKey = "default"
  static let selectionKey = "icon_shift.selection"

  private weak var registrar: FlutterPluginRegistrar?
  private var iconKey: String?
  private var originalTitle: String?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "icon_shift", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(IconShiftPlugin(registrar: registrar), channel: channel)
  }

  private var window: NSWindow? {
    registrar?.view?.window ?? NSApp.mainWindow ?? NSApp.windows.first
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getCapabilities":
      result(capabilities())
    case "getNativeState":
      result(["iconKey": iconKey ?? Self.defaultKey, "displayName": window?.title])
    case "setIcon":
      setIcon(key: args["key"] as? String, bytes: args["bytes"] as? FlutterStandardTypedData, result: result)
    case "setDisplayName":
      setDisplayName(args["name"] as? String, result: result)
    case "inspect":
      result([
        "issues": [] as [Any],
        "info": [
          "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
          "sandboxed": ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
          "hasWindow": window != nil,
        ],
      ])
    case "loadSelection":
      result(UserDefaults.standard.dictionary(forKey: Self.selectionKey) as? [String: String] ?? [:])
    case "saveSelection":
      UserDefaults.standard.set(args["selection"] as? [String: String] ?? [:], forKey: Self.selectionKey)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func capabilities() -> [String: Any] {
    [
      "icon": [
        "supported": true,
        "scope": "runningApp",
        "persistsNatively": false,
        "acceptsArbitraryValues": true,
        "limitation": "Changes the Dock icon while the app runs. Finder, Launchpad and the Dock icon of the "
          + "closed app keep the bundle icon (changing the signed bundle would break its code signature).",
      ] as [String: Any],
      "displayName": [
        "supported": true,
        "scope": "windowTitle",
        "persistsNatively": false,
        "acceptsArbitraryValues": true,
        "limitation": "Changes the main window title. The app name in the menu bar, Dock and Finder comes "
          + "from the signed bundle and cannot change at runtime.",
      ] as [String: Any],
      "iconAndNameLinked": false,
      "notes": [] as [String],
    ]
  }

  private func setIcon(key: String?, bytes: FlutterStandardTypedData?, result: FlutterResult) {
    guard let key = key, !key.isEmpty else {
      result(FlutterError(code: "invalid_argument", message: "setIcon needs a variant key.", details: nil))
      return
    }
    if key == (iconKey ?? Self.defaultKey) {
      result(["status": "unchanged"])
      return
    }
    if key == Self.defaultKey {
      NSApp.applicationIconImage = nil  // Restores the bundle icon.
      iconKey = nil
      result(["status": "applied"])
      return
    }
    guard let data = bytes?.data, let image = NSImage(data: data) else {
      result(FlutterError(
        code: "invalid_argument", message: "Icon bytes for \"\(key)\" could not be decoded as an image.",
        details: nil))
      return
    }
    NSApp.applicationIconImage = image
    iconKey = key
    result(["status": "applied"])
  }

  private func setDisplayName(_ name: String?, result: FlutterResult) {
    guard let window = window else {
      result(FlutterError(code: "native_failure", message: "The app has no window to rename.", details: nil))
      return
    }
    if originalTitle == nil { originalTitle = window.title }
    let target = name ?? originalTitle ?? ""
    if window.title == target {
      result(["status": "unchanged"])
      return
    }
    window.title = target
    result(["status": "applied"])
  }
}
