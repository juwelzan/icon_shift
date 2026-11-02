#include <flutter_linux/flutter_linux.h>

#include "include/icon_shift/icon_shift_plugin.h"

// This file exposes some plugin internals for unit testing. See
// https://github.com/flutter/flutter/issues/88724 for current limitations
// in the unit-testable API.

G_DEFINE_AUTOPTR_CLEANUP_FUNC(IconShiftPlugin, g_object_unref)

// Creates a plugin. |registrar| may be NULL (no window), as in tests.
IconShiftPlugin* icon_shift_plugin_new(FlPluginRegistrar* registrar);

// Handles |method| with |args| (a map or NULL) and returns the response.
FlMethodResponse* icon_shift_plugin_handle(IconShiftPlugin* self,
                                           const gchar* method, FlValue* args);
