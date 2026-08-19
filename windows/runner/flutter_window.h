#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel used by Dart to request a forced repaint, e.g. after the window
  // is shown again following a hide where DWM may have discarded the
  // layered surface (see QuickMenuFunctions.toggleQuickMenu in Dart).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_window_channel_;

  // Windows Explorer cannot enter an elevated OLE drop target from a normal
  // process. This channel forwards the WM_DROPFILES fallback through the
  // desktop_drop package's existing Dart event stream.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      legacy_drop_channel_;
  bool legacy_file_drop_enabled_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
