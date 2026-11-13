#include "flutter_window.h"

#include <commctrl.h>

#include <optional>

#include <window/window_plugin_runner.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kDisableAccessibilitySubclassId = 1;

// Bypass Flutter's WM_GETOBJECT handler to prevent AccessibilityBridge activation.
LRESULT CALLBACK FlutterViewSubclassProc(HWND hwnd,
                                         UINT const message,
                                         WPARAM const wparam,
                                         LPARAM const lparam,
                                         UINT_PTR const subclass_id,
                                         DWORD_PTR) noexcept {
  if (message == WM_GETOBJECT) {
    return ::DefWindowProc(hwnd, message, wparam, lparam);
  }
  if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, FlutterViewSubclassProc, subclass_id);
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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
  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view);
  if (::SetWindowSubclass(flutter_view, FlutterViewSubclassProc,
                          kDisableAccessibilitySubclassId, 0)) {
    flutter_view_ = flutter_view;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {

  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_view_) {
    if (::IsWindow(flutter_view_)) {
      ::RemoveWindowSubclass(flutter_view_, FlutterViewSubclassProc,
                             kDisableAccessibilitySubclassId);
    }
    flutter_view_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_GETOBJECT) {
    return ::DefWindowProc(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    WindowPluginForwardVisibility(*flutter_controller_, message, wparam,
                                  lparam);
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
