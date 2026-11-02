import Flutter
import UIKit

/// iOS implementation of IconShift, built on
/// `UIApplication.setAlternateIconName(_:completionHandler:)`.
///
/// Variant ids are alternate icon names. The display name cannot change at
/// runtime on iOS and is reported as unsupported.
public class IconShiftPlugin: NSObject, FlutterPlugin {
  static let defaultKey = "default"
  static let selectionKey = "icon_shift.selection"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "icon_shift", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(IconShiftPlugin(), channel: channel)
  }

  private var app: UIApplication { UIApplication.shared }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getCapabilities":
      result(capabilities())
    case "getNativeState":
      result([
        "iconKey": app.alternateIconName ?? Self.defaultKey,
        "displayName": Self.bundleDisplayName,
      ])
    case "setIcon":
      setIcon(key: args["key"] as? String, result: result)
    case "setDisplayName":
      result(FlutterError(
        code: "unsupported",
        message: "iOS has no API to change an app's display name at runtime.",
        details: nil))
    case "inspect":
      result(inspect(variants: args["variants"] as? [[String: Any]] ?? []))
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
    let supported = app.supportsAlternateIcons
    return [
      "icon": [
        "supported": supported,
        "scope": supported ? "launcher" : "none",
        "persistsNatively": true,
        "requiresPreconfiguredResources": true,
        "acceptsArbitraryValues": false,
        "limitation": supported
          ? "Only alternate icons compiled into the app can be used. iOS shows a confirmation alert after each change."
          : "supportsAlternateIcons is false on this device or build.",
      ] as [String: Any],
      "displayName": [
        "supported": false,
        "scope": "none",
        "limitation": "iOS has no API to change an app's display name at runtime.",
      ] as [String: Any],
      "iconAndNameLinked": false,
      "notes": ["The system alert shown after an icon change cannot be suppressed with public API."],
    ]
  }

  private func setIcon(key: String?, result: @escaping FlutterResult) {
    guard let key = key, !key.isEmpty else {
      result(FlutterError(code: "invalid_argument", message: "setIcon needs a variant key.", details: nil))
      return
    }
    guard app.supportsAlternateIcons else {
      result(FlutterError(code: "unsupported", message: "supportsAlternateIcons is false.", details: nil))
      return
    }
    let name: String? = key == Self.defaultKey ? nil : key
    if name == app.alternateIconName {
      // Re-applying would show the system alert for no change.
      result(["status": "unchanged"])
      return
    }
    if let name = name, !Self.alternateIconNames.contains(name) {
      result(FlutterError(
        code: "missing_resource",
        message: "No alternate icon named \"\(name)\" in this build. Add an app icon set named \"\(name)\" and set "
          + "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES (or list it in CFBundleAlternateIcons).",
        details: nil))
      return
    }
    if app.applicationState == .background {
      result(FlutterError(
        code: "not_active", message: "iOS only changes the icon while the app is in the foreground.", details: nil))
      return
    }
    app.setAlternateIconName(name) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "native_failure", message: error.localizedDescription, details: nil))
        } else {
          result(["status": "applied"])
        }
      }
    }
  }

  private func inspect(variants: [[String: Any]]) -> [String: Any] {
    var issues: [[String: Any?]] = []
    let names = Self.alternateIconNames
    if !app.supportsAlternateIcons {
      issues.append([
        "severity": "error", "code": "alternate_icons_unsupported",
        "message": "supportsAlternateIcons is false; no icon can be switched.", "variantId": nil,
      ])
    }
    var configured = Set<String>()
    for spec in variants {
      guard let id = spec["id"] as? String else { continue }
      configured.insert(id)
      if id != Self.defaultKey, spec["hasOwnIcon"] as? Bool == true, !names.contains(id) {
        issues.append([
          "severity": "error", "code": "missing_alternate_icon",
          "message": "No alternate icon named \"\(id)\" in this build. Add an app icon set named \"\(id)\" "
            + "(icon_shift_generator creates it) and set ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES.",
          "variantId": id,
        ])
      }
    }
    for name in names.subtracting(configured).sorted() {
      issues.append([
        "severity": "info", "code": "unconfigured_alternate_icon",
        "message": "Alternate icon \"\(name)\" is bundled but not in the IconShift configuration.",
        "variantId": nil,
      ])
    }
    return [
      "issues": issues,
      "info": [
        "systemVersion": UIDevice.current.systemVersion,
        "supportsAlternateIcons": app.supportsAlternateIcons,
        "alternateIconNames": names.sorted().joined(separator: ", "),
      ],
    ]
  }

  /// Alternate icon names from the compiled Info.plist (asset-catalog
  /// alternate icons are written there by actool).
  static var alternateIconNames: Set<String> {
    var names = Set<String>()
    for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
      if let icons = Bundle.main.object(forInfoDictionaryKey: key) as? [String: Any],
        let alternates = icons["CFBundleAlternateIcons"] as? [String: Any]
      {
        names.formUnion(alternates.keys)
      }
    }
    return names
  }

  static var bundleDisplayName: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
  }
}
