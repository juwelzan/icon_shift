#include "include/icon_shift/icon_shift_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "icon_shift_plugin.h"

void IconShiftPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  icon_shift::IconShiftPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
