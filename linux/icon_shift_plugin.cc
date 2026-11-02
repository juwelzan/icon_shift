#include "include/icon_shift/icon_shift_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include <glib/gstdio.h>

#include <cstring>

#include "icon_shift_plugin_private.h"

// Linux implementation of IconShift.
//
// The icon is the GTK window icon (honoured on X11 only; Wayland takes window
// icons from the installed .desktop file) and the display name is the window
// / header bar title. Installed .desktop files are never modified.

#define ICON_SHIFT_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), icon_shift_plugin_get_type(), \
                              IconShiftPlugin))

static const gchar kDefaultKey[] = "default";
static const gchar kSelectionGroup[] = "selection";

struct _IconShiftPlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;
  gchar* icon_key;

  // Window state before the first change, restored for the default.
  gboolean captured_icon;
  GdkPixbuf* original_icon;
  gboolean captured_title;
  gchar* original_title;
};

G_DEFINE_TYPE(IconShiftPlugin, icon_shift_plugin, g_object_get_type())

static GtkWindow* get_window(IconShiftPlugin* self) {
  if (self->registrar == nullptr) return nullptr;
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) return nullptr;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  return GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : nullptr;
}

static gboolean is_wayland() {
#ifdef GDK_WINDOWING_WAYLAND
  GdkDisplay* display = gdk_display_get_default();
  return display != nullptr && GDK_IS_WAYLAND_DISPLAY(display);
#else
  return FALSE;
#endif
}

static GtkHeaderBar* get_header_bar(GtkWindow* window) {
  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  return titlebar != nullptr && GTK_IS_HEADER_BAR(titlebar)
             ? GTK_HEADER_BAR(titlebar)
             : nullptr;
}

static const gchar* get_title(GtkWindow* window) {
  GtkHeaderBar* header_bar = get_header_bar(window);
  const gchar* title = header_bar != nullptr
                           ? gtk_header_bar_get_title(header_bar)
                           : gtk_window_get_title(window);
  return title != nullptr ? title : "";
}

static FlMethodResponse* success(FlValue* value) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

static FlMethodResponse* error(const gchar* code, const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static FlMethodResponse* status(const gchar* value) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string(value));
  return success(map);
}

static const gchar* string_arg(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

static FlValue* capability(gboolean supported, const gchar* scope,
                           const gchar* limitation) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "supported", fl_value_new_bool(supported));
  fl_value_set_string_take(map, "scope",
                           fl_value_new_string(supported ? scope : "none"));
  fl_value_set_string_take(map, "persistsNatively", fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "acceptsArbitraryValues",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(map, "limitation", fl_value_new_string(limitation));
  return map;
}

static FlMethodResponse* get_capabilities(IconShiftPlugin* self) {
  gboolean has_window = get_window(self) != nullptr;
  gboolean wayland = is_wayland();
  const gchar* no_window = "The Flutter engine has no window.";

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(
      map, "icon",
      capability(
          has_window && !wayland, "runningApp",
          !has_window ? no_window
          : wayland
              ? "Wayland has no window-icon protocol; the compositor shows "
                "the icon of the installed .desktop file."
              : "Changes the window/taskbar icon of the running window on "
                "X11. Installed .desktop launchers are not changed."));
  fl_value_set_string_take(
      map, "displayName",
      capability(has_window, "windowTitle",
                 has_window ? "Changes the window and header bar title. The "
                              "launcher name in the .desktop file is not "
                              "changed."
                            : no_window));
  fl_value_set_string_take(map, "iconAndNameLinked", fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "notes", fl_value_new_list());
  return success(map);
}

static FlMethodResponse* get_native_state(IconShiftPlugin* self) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(
      map, "iconKey",
      fl_value_new_string(self->icon_key != nullptr ? self->icon_key
                                                    : kDefaultKey));
  GtkWindow* window = get_window(self);
  if (window != nullptr) {
    fl_value_set_string_take(map, "displayName",
                             fl_value_new_string(get_title(window)));
  }
  return success(map);
}

static FlMethodResponse* set_icon(IconShiftPlugin* self, FlValue* args) {
  const gchar* key = string_arg(args, "key");
  if (key == nullptr || key[0] == '\0') {
    return error("invalid_argument", "setIcon needs a variant key.");
  }
  GtkWindow* window = get_window(self);
  if (window == nullptr) {
    return error("unsupported", "The Flutter engine has no window.");
  }
  if (is_wayland()) {
    return error("unsupported",
                 "Wayland has no window-icon protocol; the compositor shows "
                 "the icon of the installed .desktop file.");
  }
  const gchar* current = self->icon_key != nullptr ? self->icon_key : kDefaultKey;
  if (strcmp(key, current) == 0) return status("unchanged");

  if (!self->captured_icon) {
    GdkPixbuf* original = gtk_window_get_icon(window);
    self->original_icon =
        original != nullptr ? GDK_PIXBUF(g_object_ref(original)) : nullptr;
    self->captured_icon = TRUE;
  }

  if (strcmp(key, kDefaultKey) == 0) {
    gtk_window_set_icon(window, self->original_icon);
    g_clear_pointer(&self->icon_key, g_free);
    return status("applied");
  }

  FlValue* bytes = fl_value_lookup_string(args, "bytes");
  if (bytes == nullptr ||
      fl_value_get_type(bytes) != FL_VALUE_TYPE_UINT8_LIST ||
      fl_value_get_length(bytes) == 0) {
    return error("invalid_argument", "setIcon needs image bytes.");
  }
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  g_autoptr(GError) load_error = nullptr;
  if (!gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(bytes),
                               fl_value_get_length(bytes), &load_error) ||
      !gdk_pixbuf_loader_close(loader, &load_error)) {
    g_autofree gchar* message = g_strdup_printf(
        "Icon bytes could not be decoded: %s", load_error->message);
    return error("invalid_argument", message);
  }
  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
  if (pixbuf == nullptr) {
    return error("invalid_argument", "Icon bytes could not be decoded.");
  }
  gtk_window_set_icon(window, pixbuf);  // Takes its own reference.
  g_free(self->icon_key);
  self->icon_key = g_strdup(key);
  return status("applied");
}

static FlMethodResponse* set_display_name(IconShiftPlugin* self,
                                          FlValue* args) {
  GtkWindow* window = get_window(self);
  if (window == nullptr) {
    return error("unsupported", "The Flutter engine has no window.");
  }
  if (!self->captured_title) {
    self->original_title = g_strdup(get_title(window));
    self->captured_title = TRUE;
  }
  const gchar* name = string_arg(args, "name");
  const gchar* target = name != nullptr ? name : self->original_title;
  if (strcmp(target, get_title(window)) == 0) return status("unchanged");

  gtk_window_set_title(window, target);
  GtkHeaderBar* header_bar = get_header_bar(window);
  if (header_bar != nullptr) gtk_header_bar_set_title(header_bar, target);
  return status("applied");
}

static FlMethodResponse* inspect(IconShiftPlugin* self) {
  g_autoptr(FlValue) info = fl_value_new_map();
  fl_value_set_string_take(
      info, "displayServer",
      fl_value_new_string(is_wayland() ? "wayland" : "x11-or-other"));
  fl_value_set_string_take(info, "hasWindow",
                           fl_value_new_bool(get_window(self) != nullptr));
  fl_value_set_string_take(
      info, "sandbox",
      fl_value_new_string(g_getenv("FLATPAK_ID") != nullptr ? "flatpak"
                          : g_getenv("SNAP") != nullptr     ? "snap"
                          : g_getenv("APPIMAGE") != nullptr ? "appimage"
                                                            : "none"));

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "issues", fl_value_new_list());
  fl_value_set(map, fl_value_new_string("info"), info);
  return success(map);
}

// How the app is installed, from the environment the sandbox/packaging
// tools set and the executable's location.
static const gchar* installation_type(const gchar* exe) {
  if (g_getenv("FLATPAK_ID") != nullptr) return "flatpak";
  if (g_getenv("SNAP") != nullptr) return "snap";
  if (g_getenv("APPIMAGE") != nullptr) return "appImage";
  if (exe != nullptr &&
      (g_str_has_prefix(exe, "/usr/") || g_str_has_prefix(exe, "/opt/"))) {
    return "standard";
  }
  return "unpackaged";
}

static FlMethodResponse* get_application_info(IconShiftPlugin* self) {
  g_autoptr(FlValue) map = fl_value_new_map();
  GApplication* app = g_application_get_default();
  const gchar* app_id =
      app != nullptr ? g_application_get_application_id(app) : nullptr;
  if (app_id != nullptr) {
    fl_value_set_string_take(map, "applicationId", fl_value_new_string(app_id));
  }
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* name = g_path_get_basename(exe);
    fl_value_set_string_take(map, "executableName", fl_value_new_string(name));
  }
  fl_value_set_string_take(map, "installationType",
                           fl_value_new_string(installation_type(exe)));
  GtkWindow* window = get_window(self);
  if (window != nullptr) {
    fl_value_set_string_take(map, "windowTitle",
                             fl_value_new_string(get_title(window)));
  }
#if GLIB_CHECK_VERSION(2, 64, 0)
  g_autofree gchar* os = g_get_os_info(G_OS_INFO_KEY_PRETTY_NAME);
  if (os != nullptr) {
    fl_value_set_string_take(map, "osVersion", fl_value_new_string(os));
  }
#endif
  // The display name lives in the installed .desktop file, which the app
  // cannot reliably locate; the version is read by the Dart side from
  // version.json. Neither is guessed here.
  return success(map);
}

// Selection persistence: $XDG_CONFIG_HOME/icon_shift/<program name>.ini
static gchar* selection_path() {
  g_autofree gchar* name = g_strdup(g_get_prgname() != nullptr ? g_get_prgname()
                                                               : "app");
  g_strdelimit(name, "/\\", '_');
  g_autofree gchar* file = g_strconcat(name, ".ini", nullptr);
  return g_build_filename(g_get_user_config_dir(), "icon_shift", file, nullptr);
}

static FlMethodResponse* load_selection() {
  g_autoptr(FlValue) map = fl_value_new_map();
  g_autofree gchar* path = selection_path();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    gsize length = 0;
    g_auto(GStrv) keys =
        g_key_file_get_keys(file, kSelectionGroup, &length, nullptr);
    for (gsize i = 0; keys != nullptr && i < length; i++) {
      g_autofree gchar* value =
          g_key_file_get_string(file, kSelectionGroup, keys[i], nullptr);
      if (value != nullptr) {
        fl_value_set_string_take(map, keys[i], fl_value_new_string(value));
      }
    }
  }
  return success(map);
}

static FlMethodResponse* save_selection(FlValue* args) {
  FlValue* selection = args != nullptr && fl_value_get_type(args) ==
                                              FL_VALUE_TYPE_MAP
                           ? fl_value_lookup_string(args, "selection")
                           : nullptr;
  g_autofree gchar* path = selection_path();
  if (selection == nullptr ||
      fl_value_get_type(selection) != FL_VALUE_TYPE_MAP ||
      fl_value_get_length(selection) == 0) {
    g_remove(path);
    return success(nullptr);
  }

  g_autoptr(GKeyFile) file = g_key_file_new();
  for (size_t i = 0; i < fl_value_get_length(selection); i++) {
    FlValue* k = fl_value_get_map_key(selection, i);
    FlValue* v = fl_value_get_map_value(selection, i);
    if (fl_value_get_type(k) == FL_VALUE_TYPE_STRING &&
        fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
      g_key_file_set_string(file, kSelectionGroup, fl_value_get_string(k),
                            fl_value_get_string(v));
    }
  }
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_autoptr(GError) save_error = nullptr;
  if (g_mkdir_with_parents(dir, 0700) != 0 ||
      !g_key_file_save_to_file(file, path, &save_error)) {
    g_autofree gchar* message = g_strdup_printf(
        "Could not save the selection to %s: %s", path,
        save_error != nullptr ? save_error->message : "cannot create folder");
    return error("native_failure", message);
  }
  return success(nullptr);
}

FlMethodResponse* icon_shift_plugin_handle(IconShiftPlugin* self,
                                           const gchar* method, FlValue* args) {
  if (strcmp(method, "getCapabilities") == 0) return get_capabilities(self);
  if (strcmp(method, "getNativeState") == 0) return get_native_state(self);
  if (strcmp(method, "setIcon") == 0) return set_icon(self, args);
  if (strcmp(method, "setDisplayName") == 0) return set_display_name(self, args);
  if (strcmp(method, "inspect") == 0) return inspect(self);
  if (strcmp(method, "getApplicationInfo") == 0) {
    return get_application_info(self);
  }
  if (strcmp(method, "loadSelection") == 0) return load_selection();
  if (strcmp(method, "saveSelection") == 0) return save_selection(args);
  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

static void icon_shift_plugin_dispose(GObject* object) {
  IconShiftPlugin* self = ICON_SHIFT_PLUGIN(object);
  g_clear_object(&self->registrar);
  g_clear_object(&self->original_icon);
  g_clear_pointer(&self->icon_key, g_free);
  g_clear_pointer(&self->original_title, g_free);
  G_OBJECT_CLASS(icon_shift_plugin_parent_class)->dispose(object);
}

static void icon_shift_plugin_class_init(IconShiftPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = icon_shift_plugin_dispose;
}

static void icon_shift_plugin_init(IconShiftPlugin* self) {}

IconShiftPlugin* icon_shift_plugin_new(FlPluginRegistrar* registrar) {
  IconShiftPlugin* self = ICON_SHIFT_PLUGIN(
      g_object_new(icon_shift_plugin_get_type(), nullptr));
  self->registrar =
      registrar != nullptr ? FL_PLUGIN_REGISTRAR(g_object_ref(registrar))
                           : nullptr;
  return self;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  IconShiftPlugin* self = ICON_SHIFT_PLUGIN(user_data);
  g_autoptr(FlMethodResponse) response = icon_shift_plugin_handle(
      self, fl_method_call_get_name(method_call),
      fl_method_call_get_args(method_call));
  fl_method_call_respond(method_call, response, nullptr);
}

void icon_shift_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  IconShiftPlugin* plugin = icon_shift_plugin_new(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "icon_shift", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
