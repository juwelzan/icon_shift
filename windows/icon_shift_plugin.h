#ifndef FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_
#define FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>

namespace icon_shift {

// Windows implementation of IconShift.
//
// The icon is the running window's title-bar / taskbar-button / Alt-Tab icon
// (WM_SETICON) and the display name is the window title. The executable,
// its resources and shortcuts are never modified; the Dart side re-applies
// the saved selection on launch.
class IconShiftPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  // |window_provider| returns the app's top-level window, or nullptr when
  // there is none (headless engines, tests).
  explicit IconShiftPlugin(std::function<HWND()> window_provider);

  virtual ~IconShiftPlugin();

  // Disallow copy and assign.
  IconShiftPlugin(const IconShiftPlugin &) = delete;
  IconShiftPlugin &operator=(const IconShiftPlugin &) = delete;

  // Called when a method call is received from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  flutter::EncodableMap Capabilities(HWND window) const;
  void SetIcon(HWND window, const flutter::EncodableMap &args,
               flutter::MethodResult<flutter::EncodableValue> &result);
  void SetDisplayName(HWND window, const flutter::EncodableMap &args,
                      flutter::MethodResult<flutter::EncodableValue> &result);
  void ReplaceIcons(HWND window, HICON big, HICON small_icon);

  std::function<HWND()> window_provider_;
  std::optional<std::string> icon_key_;

  // Icons created by this plugin; destroyed when replaced.
  HICON big_icon_ = nullptr;
  HICON small_icon_ = nullptr;

  // Window state before the first change, restored for the default.
  bool captured_icons_ = false;
  HICON original_big_icon_ = nullptr;
  HICON original_small_icon_ = nullptr;
  std::optional<std::wstring> original_title_;
};

}  // namespace icon_shift

#endif  // FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_
