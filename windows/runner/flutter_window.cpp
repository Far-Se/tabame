#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

#include "utils.h"

namespace {

constexpr UINT kWmCopyGlobalData = 0x0049;

bool IsCurrentProcessElevated() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation = {};
  DWORD size = 0;
  const bool elevated =
      ::GetTokenInformation(token, TokenElevation, &elevation,
                            sizeof(elevation), &size) != FALSE &&
      elevation.TokenIsElevated != 0;
  ::CloseHandle(token);
  return elevated;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // OLE drag/drop is blocked when Explorer runs normally and Tabame runs as
  // administrator. WM_DROPFILES is the Windows-supported compatibility path.
  // Keep desktop_drop as the primary implementation on every platform.
  legacy_file_drop_enabled_ = IsCurrentProcessElevated();
  if (legacy_file_drop_enabled_) {
    ::DragAcceptFiles(GetHandle(), TRUE);
    ::ChangeWindowMessageFilterEx(GetHandle(), WM_DROPFILES, MSGFLT_ALLOW,
                                  nullptr);
    ::ChangeWindowMessageFilterEx(GetHandle(), WM_COPYDATA, MSGFLT_ALLOW,
                                  nullptr);
    ::ChangeWindowMessageFilterEx(GetHandle(), kWmCopyGlobalData, MSGFLT_ALLOW,
                                  nullptr);
  }
  //TODO: Implement multiplatform fallback if native desktop_drop support is
  // unavailable on Linux or macOS.

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  if (legacy_file_drop_enabled_) {
    // desktop_drop registers an OLE target on the Flutter child window. Lower
    // integrity Explorer processes cannot enter it, so remove it while the
    // elevated-only WM_DROPFILES bridge owns file drops.
    ::RevokeDragDrop(flutter_controller_->view()->GetNativeWindow());
  }

  native_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "tabame/native_window",
          &flutter::StandardMethodCodec::GetInstance());
  native_window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue> &call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "forceRedraw") {
          if (flutter_controller_) {
            flutter_controller_->ForceRedraw();
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  legacy_drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "desktop_drop",
          &flutter::StandardMethodCodec::GetInstance());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (legacy_file_drop_enabled_) {
    ::DragAcceptFiles(GetHandle(), FALSE);
  }
  legacy_drop_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DROPFILES) {
    const HDROP drop = reinterpret_cast<HDROP>(wparam);
    POINT point = {};
    ::DragQueryPoint(drop, &point);

    flutter::EncodableList paths;
    const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    paths.reserve(count);
    for (UINT index = 0; index < count; ++index) {
      const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      if (::DragQueryFileW(drop, index, path.data(), length + 1) == 0) {
        continue;
      }
      path.resize(length);
      paths.emplace_back(Utf8FromUtf16(path.c_str()));
    }
    ::DragFinish(drop);

    if (legacy_drop_channel_ && !paths.empty()) {
      legacy_drop_channel_->InvokeMethod(
          "entered", std::make_unique<flutter::EncodableValue>(
                         flutter::EncodableList{
                             flutter::EncodableValue(double(point.x)),
                             flutter::EncodableValue(double(point.y))}));
      legacy_drop_channel_->InvokeMethod(
          "performOperation",
          std::make_unique<flutter::EncodableValue>(std::move(paths)));
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SETFOCUS:
      if (GetKeyState(VK_MENU) < 0) {
        // ALT is stuck down, simulate release
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
      }
      break;
    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == SC_KEYMENU) {
        return 0; // suppress Alt-triggered system/menu activation
      }
      break;
    

    case WM_SYSCHAR:
    case WM_SYSDEADCHAR:
    case WM_SYSKEYUP:
    case WM_SYSKEYDOWN:
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
