#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "icon_shift_plugin.h"

namespace icon_shift {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

struct Reply {
  bool success = false;
  EncodableValue value;
  std::string error_code;
};

Reply Call(IconShiftPlugin &plugin, const std::string &method,
           EncodableMap args = {}) {
  Reply reply;
  plugin.HandleMethodCall(
      MethodCall(method, std::make_unique<EncodableValue>(args)),
      std::make_unique<MethodResultFunctions<>>(
          [&reply](const EncodableValue *result) {
            reply.success = true;
            if (result) reply.value = *result;
          },
          [&reply](const std::string &code, const std::string &,
                   const EncodableValue *) { reply.error_code = code; },
          nullptr));
  return reply;
}

const EncodableValue &At(const EncodableValue &map, const char *key) {
  return std::get<EncodableMap>(map).at(EncodableValue(key));
}

}  // namespace

TEST(IconShiftPlugin, WithoutWindowReportsUnsupported) {
  IconShiftPlugin plugin([]() -> HWND { return nullptr; });
  Reply caps = Call(plugin, "getCapabilities");
  ASSERT_TRUE(caps.success);
  EXPECT_FALSE(std::get<bool>(At(At(caps.value, "icon"), "supported")));
  EXPECT_FALSE(std::get<bool>(At(caps.value, "iconAndNameLinked")));

  Reply icon = Call(plugin, "setIcon",
                    {{EncodableValue("key"), EncodableValue("dark")}});
  EXPECT_EQ(icon.error_code, "unsupported");
  Reply name = Call(plugin, "setDisplayName",
                    {{EncodableValue("name"), EncodableValue("X")}});
  EXPECT_EQ(name.error_code, "unsupported");
}

TEST(IconShiftPlugin, ChangesAndRestoresWindowTitleAndIcon) {
  HWND window = ::CreateWindowW(L"STATIC", L"Original", WS_OVERLAPPEDWINDOW, 0,
                                0, 100, 100, nullptr, nullptr, nullptr, nullptr);
  ASSERT_NE(window, nullptr);
  {
    IconShiftPlugin plugin([window]() { return window; });

    Reply caps = Call(plugin, "getCapabilities");
    EXPECT_EQ(std::get<std::string>(At(At(caps.value, "icon"), "scope")),
              "runningApp");

    Reply renamed = Call(plugin, "setDisplayName",
                         {{EncodableValue("name"), EncodableValue("Renamed")}});
    EXPECT_EQ(std::get<std::string>(At(renamed.value, "status")), "applied");
    wchar_t title[64];
    ::GetWindowTextW(window, title, 64);
    EXPECT_EQ(std::wstring(title), L"Renamed");

    Reply restored = Call(plugin, "setDisplayName",
                          {{EncodableValue("name"), EncodableValue()}});
    EXPECT_TRUE(restored.success);
    ::GetWindowTextW(window, title, 64);
    EXPECT_EQ(std::wstring(title), L"Original");

    Reply bad = Call(plugin, "setIcon",
                     {{EncodableValue("key"), EncodableValue("dark")},
                      {EncodableValue("bytes"),
                       EncodableValue(std::vector<uint8_t>{1, 2, 3})}});
    EXPECT_EQ(bad.error_code, "invalid_argument");

    Reply unchanged = Call(plugin, "setIcon",
                           {{EncodableValue("key"), EncodableValue("default")}});
    EXPECT_EQ(std::get<std::string>(At(unchanged.value, "status")),
              "unchanged");
  }
  ::DestroyWindow(window);
}

}  // namespace test
}  // namespace icon_shift
