#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

namespace {

constexpr wchar_t kWindowTitle[] = L"leyli";
constexpr wchar_t kAuthScheme[] = L"io.supabase.flutter";

bool RegisterAuthUrlProtocol() {
  wchar_t executable_path[MAX_PATH];
  const DWORD path_length =
      GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length >= MAX_PATH) {
    return false;
  }

  const std::wstring protocol_key =
      std::wstring(L"Software\\Classes\\") + kAuthScheme;
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, protocol_key.c_str(), 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }

  const wchar_t description[] = L"URL:Supabase authentication callback";
  const wchar_t empty_value[] = L"";
  const std::wstring command_key = protocol_key + L"\\shell\\open\\command";
  HKEY command = nullptr;
  bool registered =
      RegSetValueExW(key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(description),
                     sizeof(description)) == ERROR_SUCCESS &&
      RegSetValueExW(key, L"URL Protocol", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(empty_value),
                     sizeof(empty_value)) == ERROR_SUCCESS &&
      RegCreateKeyExW(HKEY_CURRENT_USER, command_key.c_str(), 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &command,
                      nullptr) == ERROR_SUCCESS;

  if (registered) {
    const std::wstring launch_command = std::wstring(L"\"") + executable_path +
                                        L"\" \"%1\"";
    registered = RegSetValueExW(
                     command, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(launch_command.c_str()),
                     static_cast<DWORD>((launch_command.size() + 1) *
                                        sizeof(wchar_t))) == ERROR_SUCCESS;
  }

  if (command != nullptr) RegCloseKey(command);
  RegCloseKey(key);
  return registered;
}

bool SendAppLinkToInstance() {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (hwnd == nullptr) return false;

  SendAppLink(hwnd);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterAuthUrlProtocol();
  if (SendAppLinkToInstance()) return EXIT_SUCCESS;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
