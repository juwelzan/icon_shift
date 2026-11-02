#ifndef FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_
#define FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace icon_shift {

class IconShiftPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  IconShiftPlugin();

  virtual ~IconShiftPlugin();

  // Disallow copy and assign.
  IconShiftPlugin(const IconShiftPlugin&) = delete;
  IconShiftPlugin& operator=(const IconShiftPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace icon_shift

#endif  // FLUTTER_PLUGIN_ICON_SHIFT_PLUGIN_H_
