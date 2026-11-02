#include "icon_shift_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <memory>
#include <vector>

namespace icon_shift {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr char kDefaultKey[] = "default";

std::wstring Utf8ToWide(const std::string &utf8) {
  if (utf8.empty()) return std::wstring();
  int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring wide(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                        static_cast<int>(utf8.size()), wide.data(), length);
  return wide;
}

std::string WideToUtf8(const std::wstring &wide) {
  if (wide.empty()) return std::string();
  int length = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                     static_cast<int>(wide.size()), nullptr, 0,
                                     nullptr, nullptr);
  if (length <= 0) return std::string();
  std::string utf8(length, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        utf8.data(), length, nullptr, nullptr);
  return utf8;
}

std::wstring WindowTitle(HWND window) {
  int length = ::GetWindowTextLengthW(window);
  std::wstring title(static_cast<size_t>(length) + 1, L'\0');
  int copied = ::GetWindowTextW(window, title.data(), length + 1);
  title.resize(copied > 0 ? copied : 0);
  return title;
}

const EncodableValue *Lookup(const EncodableMap &map, const char *key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<std::string> StringArg(const EncodableMap &map, const char *key) {
  const EncodableValue *value = Lookup(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto *s = std::get_if<std::string>(value)) return *s;
  return std::nullopt;
}

// Scoped COM initialization; tolerates COM already being initialized by the
// runner (S_FALSE) or with another threading model (RPC_E_CHANGED_MODE).
class ScopedCom {
 public:
  ScopedCom() {
    HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    initialized_ = SUCCEEDED(hr);
  }
  ~ScopedCom() {
    if (initialized_) ::CoUninitialize();
  }

 private:
  bool initialized_ = false;
};

// Decodes |bytes| (PNG, JPEG, BMP, ICO, …) with the Windows Imaging Component
// and creates a |size|x|size| 32-bit icon with alpha. Returns nullptr on
// failure and sets |error|.
HICON CreateIconFromImageBytes(const std::vector<uint8_t> &bytes, int size,
                               std::string &error) {
  ScopedCom com;
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  ComPtr<IWICBitmapScaler> scaler;
  ComPtr<IWICFormatConverter> converter;

  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory))) ||
      FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromMemory(
          const_cast<BYTE *>(bytes.data()), static_cast<DWORD>(bytes.size())))) {
    error = "Could not initialize the Windows Imaging Component.";
    return nullptr;
  }
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame))) {
    error = "Icon bytes could not be decoded as an image.";
    return nullptr;
  }
  if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
      FAILED(scaler->Initialize(frame.Get(), size, size,
                                WICBitmapInterpolationModeFant)) ||
      FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(scaler.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    error = "Icon image could not be scaled or converted.";
    return nullptr;
  }

  BITMAPV5HEADER header = {};
  header.bV5Size = sizeof(header);
  header.bV5Width = size;
  header.bV5Height = -size;  // Top-down rows, matching WIC's output.
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;

  void *pixels = nullptr;
  HDC screen = ::GetDC(nullptr);
  HBITMAP color = ::CreateDIBSection(
      screen, reinterpret_cast<BITMAPINFO *>(&header), DIB_RGB_COLORS, &pixels,
      nullptr, 0);
  ::ReleaseDC(nullptr, screen);
  if (color == nullptr || pixels == nullptr) {
    error = "Could not allocate the icon bitmap.";
    return nullptr;
  }
  const UINT stride = static_cast<UINT>(size) * 4;
  if (FAILED(converter->CopyPixels(nullptr, stride, stride * size,
                                   static_cast<BYTE *>(pixels)))) {
    ::DeleteObject(color);
    error = "Could not read the decoded icon pixels.";
    return nullptr;
  }

  // Monochrome mask rows are WORD-aligned; all zero so alpha decides.
  std::vector<uint8_t> mask_bits(((size + 15) / 16) * 2 * size, 0);
  HBITMAP mask = ::CreateBitmap(size, size, 1, 1, mask_bits.data());

  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmMask = mask;
  info.hbmColor = color;
  HICON icon = ::CreateIconIndirect(&info);
  ::DeleteObject(color);
  ::DeleteObject(mask);
  if (icon == nullptr) error = "CreateIconIndirect failed.";
  return icon;
}

// Selection persistence: HKCU\Software\IconShift\<executable name>.
std::wstring SelectionRegistryKey() {
  wchar_t path[MAX_PATH] = {};
  DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring stem = L"app";
  if (length > 0 && length < MAX_PATH) {
    stem = std::filesystem::path(path).stem().wstring();
  }
  return L"Software\\IconShift\\" + stem;
}

EncodableMap LoadSelection() {
  EncodableMap selection;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, SelectionRegistryKey().c_str(), 0,
                      KEY_READ, &key) != ERROR_SUCCESS) {
    return selection;
  }
  for (DWORD index = 0;; ++index) {
    wchar_t name[256];
    DWORD name_length = 256;
    DWORD type = 0;
    DWORD data_size = 0;
    LONG status = ::RegEnumValueW(key, index, name, &name_length, nullptr,
                                  &type, nullptr, &data_size);
    if (status != ERROR_SUCCESS) break;
    if (type != REG_SZ) continue;
    std::wstring data(data_size / sizeof(wchar_t) + 1, L'\0');
    DWORD read_size = static_cast<DWORD>(data.size() * sizeof(wchar_t));
    if (::RegQueryValueExW(key, name, nullptr, nullptr,
                           reinterpret_cast<BYTE *>(data.data()),
                           &read_size) == ERROR_SUCCESS) {
      data.resize(wcsnlen(data.c_str(), data.size()));
      selection[EncodableValue(WideToUtf8(name))] =
          EncodableValue(WideToUtf8(data));
    }
  }
  ::RegCloseKey(key);
  return selection;
}

bool SaveSelection(const EncodableMap &selection, std::string &error) {
  const std::wstring path = SelectionRegistryKey();
  LONG status = ::RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
  if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
    error = "Could not clear the saved selection.";
    return false;
  }
  if (selection.empty()) return true;

  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    error = "Could not create the registry key for the saved selection.";
    return false;
  }
  bool ok = true;
  for (const auto &[k, v] : selection) {
    const auto *name = std::get_if<std::string>(&k);
    const auto *value = std::get_if<std::string>(&v);
    if (name == nullptr || value == nullptr) continue;
    std::wstring wide = Utf8ToWide(*value);
    if (::RegSetValueExW(key, Utf8ToWide(*name).c_str(), 0, REG_SZ,
                         reinterpret_cast<const BYTE *>(wide.c_str()),
                         static_cast<DWORD>((wide.size() + 1) *
                                            sizeof(wchar_t))) != ERROR_SUCCESS) {
      ok = false;
    }
  }
  ::RegCloseKey(key);
  if (!ok) error = "Could not write the saved selection.";
  return ok;
}

EncodableMap Status(const char *status) {
  return EncodableMap{{EncodableValue("status"), EncodableValue(status)}};
}

}  // namespace

// static
void IconShiftPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "icon_shift",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<IconShiftPlugin>([registrar]() -> HWND {
    flutter::FlutterView *view = registrar->GetView();
    if (view == nullptr) return nullptr;
    HWND child = view->GetNativeWindow();
    return child == nullptr ? nullptr : ::GetAncestor(child, GA_ROOT);
  });

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

IconShiftPlugin::IconShiftPlugin(std::function<HWND()> window_provider)
    : window_provider_(std::move(window_provider)) {}

IconShiftPlugin::~IconShiftPlugin() {
  // The window may outlive the plugin; give it back its original icons
  // before destroying ours.
  HWND window = window_provider_ ? window_provider_() : nullptr;
  if (window != nullptr && captured_icons_) {
    ::SendMessageW(window, WM_SETICON, ICON_BIG,
                   reinterpret_cast<LPARAM>(original_big_icon_));
    ::SendMessageW(window, WM_SETICON, ICON_SMALL,
                   reinterpret_cast<LPARAM>(original_small_icon_));
  }
  if (big_icon_ != nullptr) ::DestroyIcon(big_icon_);
  if (small_icon_ != nullptr) ::DestroyIcon(small_icon_);
}

void IconShiftPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static const EncodableMap kNoArgs;
  const auto *args_value = method_call.arguments();
  const EncodableMap *maybe_args =
      args_value ? std::get_if<EncodableMap>(args_value) : nullptr;
  const EncodableMap &args = maybe_args ? *maybe_args : kNoArgs;
  const std::string &method = method_call.method_name();
  HWND window = window_provider_ ? window_provider_() : nullptr;

  if (method == "getCapabilities") {
    result->Success(EncodableValue(Capabilities(window)));
  } else if (method == "getNativeState") {
    EncodableMap state{
        {EncodableValue("iconKey"),
         EncodableValue(icon_key_.value_or(kDefaultKey))}};
    if (window != nullptr) {
      state[EncodableValue("displayName")] =
          EncodableValue(WideToUtf8(WindowTitle(window)));
    }
    result->Success(EncodableValue(state));
  } else if (method == "setIcon") {
    SetIcon(window, args, *result);
  } else if (method == "setDisplayName") {
    SetDisplayName(window, args, *result);
  } else if (method == "inspect") {
    EncodableMap info{
        {EncodableValue("hasWindow"), EncodableValue(window != nullptr)},
        {EncodableValue("iconSize"),
         EncodableValue(::GetSystemMetrics(SM_CXICON))},
    };
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("issues"), EncodableValue(EncodableList())},
        {EncodableValue("info"), EncodableValue(info)},
    }));
  } else if (method == "loadSelection") {
    result->Success(EncodableValue(LoadSelection()));
  } else if (method == "saveSelection") {
    const EncodableValue *selection = Lookup(args, "selection");
    const auto *map = selection ? std::get_if<EncodableMap>(selection) : nullptr;
    std::string error;
    if (SaveSelection(map ? *map : EncodableMap(), error)) {
      result->Success();
    } else {
      result->Error("native_failure", error);
    }
  } else {
    result->NotImplemented();
  }
}

EncodableMap IconShiftPlugin::Capabilities(HWND window) const {
  const bool has_window = window != nullptr;
  auto capability = [has_window](const char *scope, const char *limitation) {
    return EncodableValue(EncodableMap{
        {EncodableValue("supported"), EncodableValue(has_window)},
        {EncodableValue("scope"), EncodableValue(has_window ? scope : "none")},
        {EncodableValue("persistsNatively"), EncodableValue(false)},
        {EncodableValue("acceptsArbitraryValues"), EncodableValue(true)},
        {EncodableValue("limitation"),
         EncodableValue(has_window ? limitation
                                   : "The Flutter engine has no window.")},
    });
  };
  return EncodableMap{
      {EncodableValue("icon"),
       capability("runningApp",
                  "Changes the title-bar, Alt-Tab and taskbar-button icon of "
                  "the running window. Pinned taskbar entries, shortcuts and "
                  "the .exe icon are not changed.")},
      {EncodableValue("displayName"),
       capability("windowTitle",
                  "Changes the window title. Shortcut names, the Start menu "
                  "entry and MSIX display name are not changed.")},
      {EncodableValue("iconAndNameLinked"), EncodableValue(false)},
      {EncodableValue("notes"), EncodableValue(EncodableList())},
  };
}

void IconShiftPlugin::SetIcon(
    HWND window, const EncodableMap &args,
    flutter::MethodResult<flutter::EncodableValue> &result) {
  std::optional<std::string> key = StringArg(args, "key");
  if (!key || key->empty()) {
    result.Error("invalid_argument", "setIcon needs a variant key.");
    return;
  }
  if (window == nullptr) {
    result.Error("unsupported", "The Flutter engine has no window.");
    return;
  }
  if (*key == icon_key_.value_or(kDefaultKey)) {
    result.Success(EncodableValue(Status("unchanged")));
    return;
  }
  if (!captured_icons_) {
    original_big_icon_ = reinterpret_cast<HICON>(
        ::SendMessageW(window, WM_GETICON, ICON_BIG, 0));
    original_small_icon_ = reinterpret_cast<HICON>(
        ::SendMessageW(window, WM_GETICON, ICON_SMALL, 0));
    captured_icons_ = true;
  }

  if (*key == kDefaultKey) {
    ReplaceIcons(window, nullptr, nullptr);
    icon_key_.reset();
    result.Success(EncodableValue(Status("applied")));
    return;
  }

  const EncodableValue *bytes_value = Lookup(args, "bytes");
  const auto *bytes =
      bytes_value ? std::get_if<std::vector<uint8_t>>(bytes_value) : nullptr;
  if (bytes == nullptr || bytes->empty()) {
    result.Error("invalid_argument", "setIcon needs image bytes.");
    return;
  }
  std::string error;
  HICON big = CreateIconFromImageBytes(*bytes, ::GetSystemMetrics(SM_CXICON),
                                       error);
  HICON small_icon =
      big ? CreateIconFromImageBytes(*bytes, ::GetSystemMetrics(SM_CXSMICON),
                                     error)
          : nullptr;
  if (big == nullptr || small_icon == nullptr) {
    if (big != nullptr) ::DestroyIcon(big);
    result.Error("invalid_argument", error);
    return;
  }
  ReplaceIcons(window, big, small_icon);
  icon_key_ = *key;
  result.Success(EncodableValue(Status("applied")));
}

void IconShiftPlugin::ReplaceIcons(HWND window, HICON big, HICON small_icon) {
  // nullptr means "restore the original icons".
  ::SendMessageW(window, WM_SETICON, ICON_BIG,
                 reinterpret_cast<LPARAM>(big ? big : original_big_icon_));
  ::SendMessageW(
      window, WM_SETICON, ICON_SMALL,
      reinterpret_cast<LPARAM>(small_icon ? small_icon : original_small_icon_));
  if (big_icon_ != nullptr) ::DestroyIcon(big_icon_);
  if (small_icon_ != nullptr) ::DestroyIcon(small_icon_);
  big_icon_ = big;
  small_icon_ = small_icon;
}

void IconShiftPlugin::SetDisplayName(
    HWND window, const EncodableMap &args,
    flutter::MethodResult<flutter::EncodableValue> &result) {
  if (window == nullptr) {
    result.Error("unsupported", "The Flutter engine has no window.");
    return;
  }
  std::wstring current = WindowTitle(window);
  if (!original_title_) original_title_ = current;
  std::optional<std::string> name = StringArg(args, "name");
  std::wstring target = name ? Utf8ToWide(*name) : *original_title_;
  if (target == current) {
    result.Success(EncodableValue(Status("unchanged")));
    return;
  }
  if (!::SetWindowTextW(window, target.c_str())) {
    result.Error("native_failure", "SetWindowTextW failed.");
    return;
  }
  result.Success(EncodableValue(Status("applied")));
}

}  // namespace icon_shift
