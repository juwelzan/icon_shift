#include <flutter_linux/flutter_linux.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include "include/icon_shift/icon_shift_plugin.h"
#include "icon_shift_plugin_private.h"

// Unit tests of the plugin's method handling without a window. Once you have
// built the example app for Linux, run:
// $ build/linux/x64/debug/plugins/icon_shift/icon_shift_test

namespace icon_shift {
namespace test {

static FlValue* lookup(FlValue* map, const char* key) {
  return fl_value_lookup_string(map, key);
}

TEST(IconShiftPlugin, WithoutWindowReportsUnsupported) {
  g_autoptr(IconShiftPlugin) plugin = icon_shift_plugin_new(nullptr);

  g_autoptr(FlMethodResponse) caps =
      icon_shift_plugin_handle(plugin, "getCapabilities", nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(caps));
  FlValue* result =
      fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(caps));
  EXPECT_FALSE(fl_value_get_bool(lookup(lookup(result, "icon"), "supported")));
  EXPECT_STREQ(fl_value_get_string(lookup(lookup(result, "icon"), "scope")),
               "none");

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "key", fl_value_new_string("dark"));
  g_autoptr(FlMethodResponse) icon =
      icon_shift_plugin_handle(plugin, "setIcon", args);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(icon));
  EXPECT_STREQ(
      fl_method_error_response_get_code(FL_METHOD_ERROR_RESPONSE(icon)),
      "unsupported");
}

TEST(IconShiftPlugin, NativeStateDefaultsToDefaultIcon) {
  g_autoptr(IconShiftPlugin) plugin = icon_shift_plugin_new(nullptr);
  g_autoptr(FlMethodResponse) state =
      icon_shift_plugin_handle(plugin, "getNativeState", nullptr);
  FlValue* result =
      fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(state));
  EXPECT_STREQ(fl_value_get_string(lookup(result, "iconKey")), "default");
}

TEST(IconShiftPlugin, UnknownMethodIsNotImplemented) {
  g_autoptr(IconShiftPlugin) plugin = icon_shift_plugin_new(nullptr);
  g_autoptr(FlMethodResponse) response =
      icon_shift_plugin_handle(plugin, "nope", nullptr);
  EXPECT_TRUE(FL_IS_METHOD_NOT_IMPLEMENTED_RESPONSE(response));
}

}  // namespace test
}  // namespace icon_shift
