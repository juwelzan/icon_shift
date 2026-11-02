//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <icon_shift/icon_shift_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) icon_shift_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "IconShiftPlugin");
  icon_shift_plugin_register_with_registrar(icon_shift_registrar);
}
