#include "tabame_linux_platform.h"

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <gdk/gdk.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

struct _TabameLinuxPlatform {
  FlMethodChannel* method_channel = nullptr;
  FlEventChannel* event_channel = nullptr;
  bool event_listening = false;

  GdkDisplay* display = nullptr;
  Display* xdisplay = nullptr;
  Window root = None;

  guint clipboard_source = 0;
  bool clipboard_monitoring = false;
  bool clipboard_seen = false;
  std::string last_clipboard_text;
  unsigned long long clipboard_change_count = 0;

  bool hotkey_registered = false;
  bool hotkey_filter_installed = false;
  KeyCode hotkey_keycode = 0;
  unsigned int hotkey_mask = 0;
  std::vector<unsigned int> hotkey_grab_masks;
  std::string hotkey_name;
};

namespace {

constexpr const char* kSecretService = "org.freedesktop.secrets";
constexpr const char* kSecretPath = "/org/freedesktop/secrets";
constexpr const char* kSecretInterface = "org.freedesktop.Secret.Service";
constexpr const char* kCollectionPath = "/org/freedesktop/secrets/collection/login";
constexpr const char* kSecretApplication = "Tabame";
constexpr const char* kMasterKeyPurpose = "master-key";
constexpr const char* kPortalService = "org.freedesktop.portal.Desktop";
constexpr const char* kPortalPath = "/org/freedesktop/portal/desktop";
constexpr const char* kPortalIntrospectionInterface = "org.freedesktop.DBus.Introspectable";
constexpr const char* kPortalScreenCast = "org.freedesktop.portal.ScreenCast";
constexpr const char* kPortalScreenshot = "org.freedesktop.portal.Screenshot";
constexpr const char* kPortalFileChooser = "org.freedesktop.portal.FileChooser";
constexpr const char* kPortalGlobalShortcuts = "org.freedesktop.portal.GlobalShortcuts";
constexpr const char* kPortalRemoteDesktop = "org.freedesktop.portal.RemoteDesktop";

FlValue* map_lookup(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(map, key);
}

std::string value_string(FlValue* value) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return {};
  const gchar* text = fl_value_get_string(value);
  return text == nullptr ? std::string() : std::string(text);
}

std::string map_string(FlValue* map, const gchar* key) {
  return value_string(map_lookup(map, key));
}

double value_double(FlValue* value, double fallback = 0.0) {
  if (value == nullptr) return fallback;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_INT:
      return static_cast<double>(fl_value_get_int(value));
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(value);
    default:
      return fallback;
  }
}

double map_double(FlValue* map, const gchar* key, double fallback = 0.0) {
  return value_double(map_lookup(map, key), fallback);
}

void map_set_string(FlValue* map, const gchar* key, const std::string& value) {
  fl_value_set_string_take(map, key, fl_value_new_string(value.c_str()));
}

void map_set_bool(FlValue* map, const gchar* key, bool value) {
  fl_value_set_string_take(map, key, fl_value_new_bool(value));
}

void map_set_int(FlValue* map, const gchar* key, int64_t value) {
  fl_value_set_string_take(map, key, fl_value_new_int(value));
}

void map_set_double(FlValue* map, const gchar* key, double value) {
  fl_value_set_string_take(map, key, fl_value_new_float(value));
}

void respond_success(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlValue) result = value;
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(call, response, nullptr);
}

void respond_null(FlMethodCall* call) {
  respond_success(call, fl_value_new_null());
}

void respond_not_implemented(FlMethodCall* call) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(call, response, nullptr);
}

void emit_event(TabameLinuxPlatform* platform, const char* type, const std::string& text,
                unsigned long long change_count = 0) {
  if (platform == nullptr || platform->event_channel == nullptr || !platform->event_listening) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_string(event, "type", type);
  if (g_strcmp0(type, "clipboardChanged") == 0) {
    map_set_string(event, "text", text);
  } else if (!text.empty()) {
    map_set_string(event, "name", text);
  }
  if (change_count != 0) map_set_int(event, "changeCount", static_cast<int64_t>(change_count));
  map_set_int(event, "timestamp", static_cast<int64_t>(g_get_real_time() / 1000));
  g_autoptr(GError) error = nullptr;
  fl_event_channel_send(platform->event_channel, event, nullptr, &error);
}

bool session_declares_wayland() {
  const gchar* session = g_getenv("XDG_SESSION_TYPE");
  if (session != nullptr && session[0] != '\0') {
    return g_ascii_strcasecmp(session, "wayland") == 0;
  }

  // XDG_SESSION_TYPE is not guaranteed to be set in nested sessions or when
  // the compositor launches the application directly. A live Wayland socket
  // is still an authority boundary even when GTK is using an XWayland display.
  const gchar* wayland_display = g_getenv("WAYLAND_DISPLAY");
  return wayland_display != nullptr && wayland_display[0] != '\0';
}

bool gdk_uses_x11(TabameLinuxPlatform* platform) {
  return platform != nullptr && platform->display != nullptr && GDK_IS_X11_DISPLAY(platform->display);
}

bool is_x11_display(TabameLinuxPlatform* platform) {
  // A GDK X11 display inside a Wayland session is XWayland. It is deliberately
  // not treated as an X11 authority for global or foreign-window operations.
  if (platform == nullptr || platform->display == nullptr || session_declares_wayland()) return false;
  return gdk_uses_x11(platform);
}

bool is_xwayland_display(TabameLinuxPlatform* platform) {
  return session_declares_wayland() && gdk_uses_x11(platform);
}

std::string display_server(TabameLinuxPlatform* platform) {
  if (session_declares_wayland()) return "wayland";
  if (platform != nullptr && platform->display != nullptr && GDK_IS_WAYLAND_DISPLAY(platform->display)) {
    return "wayland";
  }
  if (gdk_uses_x11(platform)) return "x11";
  if (session_declares_wayland()) return "wayland";
  return "unknown";
}

std::string session_desktop_name() {
  const char* names[] = {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION"};
  for (const char* name : names) {
    const gchar* value = g_getenv(name);
    if (value != nullptr && value[0] != '\0') return value;
  }
  return {};
}

std::string wayland_compositor(TabameLinuxPlatform* platform) {
  if (display_server(platform) != "wayland") return "not-wayland";
  std::string desktop = session_desktop_name();
  std::transform(desktop.begin(), desktop.end(), desktop.begin(), [](unsigned char value) {
    return static_cast<char>(std::tolower(value));
  });
  // Desktop variables are only an advisory label. They never grant access to
  // a compositor-specific protocol or change the X11 authority decision.
  if (desktop.find("gnome") != std::string::npos) return "mutter";
  if (desktop.find("kde") != std::string::npos || desktop.find("plasma") != std::string::npos) return "kwin";
  if (desktop.find("sway") != std::string::npos) return "sway";
  if (desktop.find("hyprland") != std::string::npos) return "hyprland";
  return "unknown";
}

GDBusConnection* open_session_bus() {
  g_autoptr(GError) error = nullptr;
  GDBusConnection* connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  return connection;
}

bool bus_has_service(GDBusConnection* connection, const char* service) {
  if (connection == nullptr) return false;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", service),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, &error);
  if (reply == nullptr) return false;
  gboolean owned = FALSE;
  g_variant_get(reply, "(b)", &owned);
  return owned != FALSE;
}

struct PortalCapabilityProbe {
  bool desktop = false;
  bool screen_cast = false;
  bool screenshot = false;
  bool file_chooser = false;
  bool global_shortcuts = false;
  bool remote_desktop = false;
};

bool portal_xml_has_interface(const std::string& xml, const char* interface_name) {
  const std::string needle = std::string("<interface name=\"") + interface_name + "\"";
  return xml.find(needle) != std::string::npos;
}

PortalCapabilityProbe probe_portals(GDBusConnection* connection) {
  PortalCapabilityProbe result;
  if (connection == nullptr || !bus_has_service(connection, kPortalService)) return result;
  result.desktop = true;

  // Introspection is a read-only D-Bus operation. It does not create a portal
  // session, show a consent dialog, or grant access to a screen or input.
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, kPortalService, kPortalPath, kPortalIntrospectionInterface, "Introspect",
      nullptr, G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, &error);
  if (reply == nullptr) return result;

  const gchar* xml = nullptr;
  g_variant_get(reply, "(&s)", &xml);
  if (xml == nullptr) return result;
  const std::string description(xml);
  result.screen_cast = portal_xml_has_interface(description, kPortalScreenCast);
  result.screenshot = portal_xml_has_interface(description, kPortalScreenshot);
  result.file_chooser = portal_xml_has_interface(description, kPortalFileChooser);
  result.global_shortcuts = portal_xml_has_interface(description, kPortalGlobalShortcuts);
  result.remote_desktop = portal_xml_has_interface(description, kPortalRemoteDesktop);
  return result;
}

bool pipewire_runtime_socket_present() {
  // The default per-user PipeWire remote is a socket in XDG_RUNTIME_DIR. This
  // is only an observation; Tabame does not connect to it or claim capture
  // access without a portal-mediated, user-approved session.
  const gchar* runtime = g_get_user_runtime_dir();
  if (runtime == nullptr || runtime[0] == '\0') return false;
  const gchar* remote = g_getenv("PIPEWIRE_REMOTE");
  std::string path;
  if (remote != nullptr && remote[0] == '/') {
    path = remote;
  } else {
    path = std::string(runtime) + "/" +
           ((remote != nullptr && remote[0] != '\0') ? remote : "pipewire-0");
  }
  struct stat metadata {};
  return stat(path.c_str(), &metadata) == 0 && S_ISSOCK(metadata.st_mode);
}

// ---------------------------------------------------------------------------
// X11 display, windows, focus, and monitor helpers.
// ---------------------------------------------------------------------------

int x11_ignore_error_handler(Display*, XErrorEvent*) {
  // Windows can disappear between EWMH enumeration and activation. Xlib's
  // default handler exits the process for that normal race, which is not an
  // acceptable failure mode for the portable shell.
  return 0;
}

Atom x11_atom(Display* display, const char* name) {
  return display == nullptr ? None : XInternAtom(display, name, False);
}

bool x11_read_property(Display* display, Window window, Atom property, Atom requested_type,
                       std::vector<unsigned char>* bytes, Atom* actual_type = nullptr,
                       int* actual_format = nullptr) {
  if (display == nullptr || property == None || bytes == nullptr) return false;
  Atom type = None;
  int format = 0;
  unsigned long item_count = 0;
  unsigned long bytes_after = 0;
  unsigned char* data = nullptr;
  const long length = 0x7fffffff;
  const int result = XGetWindowProperty(display, window, property, 0, length, False,
                                        requested_type, &type, &format, &item_count,
                                        &bytes_after, &data);
  if (result != Success || data == nullptr || type == None) {
    if (data != nullptr) XFree(data);
    return false;
  }
  const size_t element_size = format == 32 ? sizeof(unsigned long) :
                              format == 16 ? sizeof(unsigned short) : sizeof(unsigned char);
  bytes->assign(data, data + item_count * element_size);
  XFree(data);
  if (actual_type != nullptr) *actual_type = type;
  if (actual_format != nullptr) *actual_format = format;
  return true;
}

std::string x11_text_property(Display* display, Window window, Atom property) {
  std::vector<unsigned char> bytes;
  Atom type = None;
  int format = 0;
  if (!x11_read_property(display, window, property, AnyPropertyType, &bytes, &type, &format)) return {};
  if (format != 8 || bytes.empty()) return {};
  return std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size());
}

std::vector<Atom> x11_atom_property(Display* display, Window window, Atom property) {
  std::vector<unsigned char> bytes;
  Atom type = None;
  int format = 0;
  if (!x11_read_property(display, window, property, XA_ATOM, &bytes, &type, &format) ||
      format != 32 || bytes.size() % sizeof(unsigned long) != 0) {
    return {};
  }
  const size_t count = bytes.size() / sizeof(unsigned long);
  const unsigned long* values = reinterpret_cast<const unsigned long*>(bytes.data());
  std::vector<Atom> atoms;
  atoms.reserve(count);
  for (size_t index = 0; index < count; index++) atoms.push_back(static_cast<Atom>(values[index]));
  return atoms;
}

long x11_cardinal_property(Display* display, Window window, Atom property) {
  std::vector<unsigned char> bytes;
  Atom type = None;
  int format = 0;
  if (!x11_read_property(display, window, property, AnyPropertyType, &bytes, &type, &format) ||
      format != 32 || bytes.size() < sizeof(unsigned long)) {
    return 0;
  }
  return static_cast<long>(*reinterpret_cast<const unsigned long*>(bytes.data()));
}

bool contains_atom(const std::vector<Atom>& values, Atom target) {
  return target != None && std::find(values.begin(), values.end(), target) != values.end();
}

std::vector<Window> x11_client_windows(TabameLinuxPlatform* platform) {
  std::vector<Window> windows;
  if (!is_x11_display(platform)) return windows;

  Display* display = platform->xdisplay;
  const Atom stacking = x11_atom(display, "_NET_CLIENT_LIST_STACKING");
  const Atom client_list = x11_atom(display, "_NET_CLIENT_LIST");
  std::vector<unsigned char> bytes;
  Atom used = None;
  int format = 0;
  if (x11_read_property(display, platform->root, stacking, XA_WINDOW, &bytes, &used, &format) &&
      format == 32 && bytes.size() % sizeof(unsigned long) == 0) {
    const unsigned long* values = reinterpret_cast<const unsigned long*>(bytes.data());
    for (size_t index = 0; index < bytes.size() / sizeof(unsigned long); index++) {
      windows.push_back(static_cast<Window>(values[index]));
    }
    return windows;
  }
  if (x11_read_property(display, platform->root, client_list, XA_WINDOW, &bytes, &used, &format) &&
      format == 32 && bytes.size() % sizeof(unsigned long) == 0) {
    const unsigned long* values = reinterpret_cast<const unsigned long*>(bytes.data());
    for (size_t index = 0; index < bytes.size() / sizeof(unsigned long); index++) {
      windows.push_back(static_cast<Window>(values[index]));
    }
    return windows;
  }

  Window root = None;
  Window parent = None;
  Window* children = nullptr;
  unsigned int count = 0;
  if (XQueryTree(display, platform->root, &root, &parent, &children, &count) != 0) {
    for (unsigned int index = 0; index < count; index++) windows.push_back(children[index]);
    if (children != nullptr) XFree(children);
  }
  return windows;
}

std::string proc_text(pid_t pid, const char* name) {
  if (pid <= 0) return {};
  std::ifstream file(std::string("/proc/") + std::to_string(pid) + "/" + name,
                     std::ios::in | std::ios::binary);
  if (!file) return {};
  std::string value((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
  while (!value.empty() && (value.back() == '\n' || value.back() == '\r' || value.back() == '\0')) value.pop_back();
  const size_t nul = value.find('\0');
  if (nul != std::string::npos) value.resize(nul);
  return value;
}

std::string proc_executable(pid_t pid) {
  if (pid <= 0) return {};
  std::array<char, 4096> buffer{};
  const ssize_t length = readlink((std::string("/proc/") + std::to_string(pid) + "/exe").c_str(),
                                 buffer.data(), buffer.size() - 1);
  if (length <= 0) return {};
  buffer[static_cast<size_t>(length)] = '\0';
  return std::string(buffer.data());
}

std::string x11_window_class(Display* display, Window window) {
  XClassHint hint{};
  if (XGetClassHint(display, window, &hint) == 0) return {};
  std::string result = hint.res_class == nullptr ? "" : hint.res_class;
  if (hint.res_name != nullptr) XFree(hint.res_name);
  if (hint.res_class != nullptr) XFree(hint.res_class);
  return result;
}

pid_t x11_window_pid(Display* display, Window window) {
  const long pid = x11_cardinal_property(display, window, x11_atom(display, "_NET_WM_PID"));
  return pid > 0 ? static_cast<pid_t>(pid) : static_cast<pid_t>(0);
}

bool x11_window_exists(Display* display, Window window) {
  if (display == nullptr || window == None) return false;
  XWindowAttributes attributes{};
  return XGetWindowAttributes(display, window, &attributes) != 0;
}

FlValue* list_windows(TabameLinuxPlatform* platform) {
  FlValue* result = fl_value_new_list();
  if (!is_x11_display(platform)) return result;

  Display* display = platform->xdisplay;
  XErrorHandler previous_error_handler = XSetErrorHandler(x11_ignore_error_handler);
  const Atom state_atom = x11_atom(display, "_NET_WM_STATE");
  const Atom type_atom = x11_atom(display, "_NET_WM_WINDOW_TYPE");
  const Atom hidden_atom = x11_atom(display, "_NET_WM_STATE_HIDDEN");
  const Atom above_atom = x11_atom(display, "_NET_WM_STATE_ABOVE");
  const Atom below_atom = x11_atom(display, "_NET_WM_STATE_BELOW");
  const Atom skip_taskbar_atom = x11_atom(display, "_NET_WM_STATE_SKIP_TASKBAR");
  const Atom dock_atom = x11_atom(display, "_NET_WM_WINDOW_TYPE_DOCK");
  const Atom desktop_atom = x11_atom(display, "_NET_WM_WINDOW_TYPE_DESKTOP");
  const Atom notification_atom = x11_atom(display, "_NET_WM_WINDOW_TYPE_NOTIFICATION");
  const Atom tooltip_atom = x11_atom(display, "_NET_WM_WINDOW_TYPE_TOOLTIP");

  const pid_t own_pid = getpid();

  for (const Window window : x11_client_windows(platform)) {
    if (window == None) continue;
    const pid_t pid = x11_window_pid(display, window);
    if (pid <= 0 || pid == own_pid) continue;

    const std::vector<Atom> types = x11_atom_property(display, window, type_atom);
    if (contains_atom(types, dock_atom) || contains_atom(types, desktop_atom) ||
        contains_atom(types, notification_atom) || contains_atom(types, tooltip_atom)) {
      continue;
    }
    const std::vector<Atom> states = x11_atom_property(display, window, state_atom);
    if (contains_atom(states, skip_taskbar_atom)) continue;

    XWindowAttributes attributes{};
    if (XGetWindowAttributes(display, window, &attributes) == 0) continue;
    int root_x = 0;
    int root_y = 0;
    Window child = None;
    XTranslateCoordinates(display, window, platform->root, 0, 0, &root_x, &root_y, &child);

    std::string title = x11_text_property(display, window, x11_atom(display, "_NET_WM_NAME"));
    if (title.empty()) title = x11_text_property(display, window, x11_atom(display, "WM_NAME"));
    std::string application = x11_window_class(display, window);
    if (application.empty()) application = proc_text(pid, "comm");
    if (application.empty()) application = proc_executable(pid);
    if (title.empty() && application.empty()) continue;

    const bool minimized = attributes.map_state != IsViewable || contains_atom(states, hidden_atom);
    int layer = 0;
    if (contains_atom(states, above_atom)) layer = 1;
    if (contains_atom(states, below_atom)) layer = -1;

    FlValue* item = fl_value_new_map();
    map_set_string(item, "nativeId", std::to_string(static_cast<unsigned long>(window)));
    map_set_string(item, "title", title);
    map_set_string(item, "applicationName", application);
    map_set_string(item, "bundleIdentifier", "linux:" + application);
    map_set_int(item, "processId", static_cast<int64_t>(pid));
    map_set_int(item, "x", root_x);
    map_set_int(item, "y", root_y);
    map_set_int(item, "width", attributes.width);
    map_set_int(item, "height", attributes.height);
    map_set_bool(item, "isOnScreen", !minimized);
    map_set_bool(item, "isMinimized", minimized);
    map_set_int(item, "layer", layer);
    fl_value_append_take(result, item);
  }
  XSync(display, False);
  XSetErrorHandler(previous_error_handler);
  return result;
}

bool activate_window(TabameLinuxPlatform* platform, const std::string& native_id) {
  if (!is_x11_display(platform) || native_id.empty()) return false;
  char* end = nullptr;
  errno = 0;
  const unsigned long raw = std::strtoul(native_id.c_str(), &end, 10);
  if (errno != 0 || end == native_id.c_str() || *end != '\0' || raw == 0) return false;
  const Window window = static_cast<Window>(raw);
  Display* display = platform->xdisplay;
  XErrorHandler previous_error_handler = XSetErrorHandler(x11_ignore_error_handler);
  if (!x11_window_exists(display, window)) {
    XSync(display, False);
    XSetErrorHandler(previous_error_handler);
    return false;
  }

  const long current_active = x11_cardinal_property(
      display, platform->root, x11_atom(display, "_NET_ACTIVE_WINDOW"));
  XMapRaised(display, window);
  XEvent event{};
  event.xclient.type = ClientMessage;
  event.xclient.window = window;
  event.xclient.message_type = x11_atom(display, "_NET_ACTIVE_WINDOW");
  event.xclient.format = 32;
  event.xclient.data.l[0] = 1;  // application request
  event.xclient.data.l[1] = CurrentTime;
  event.xclient.data.l[2] = current_active > 0 ? current_active : 0;
  event.xclient.data.l[3] = 0;
  event.xclient.data.l[4] = 0;
  const Status sent = XSendEvent(display, platform->root, False,
                                  SubstructureRedirectMask | SubstructureNotifyMask, &event);

  XWindowAttributes attributes{};
  bool focus_requested = false;
  if (XGetWindowAttributes(display, window, &attributes) != 0 && attributes.map_state == IsViewable) {
    XSetInputFocus(display, window, RevertToPointerRoot, CurrentTime);
    focus_requested = true;
  }
  XFlush(display);
  XSync(display, False);
  XSetErrorHandler(previous_error_handler);
  return sent != 0 || focus_requested;
}

std::string active_window_id(TabameLinuxPlatform* platform) {
  if (!is_x11_display(platform)) return {};
  const long active = x11_cardinal_property(platform->xdisplay, platform->root,
                                            x11_atom(platform->xdisplay, "_NET_ACTIVE_WINDOW"));
  Window window = active > 0 ? static_cast<Window>(active) : None;
  if (window == None) {
    int revert = RevertToNone;
    XGetInputFocus(platform->xdisplay, &window, &revert);
  }
  if (window == None || x11_window_pid(platform->xdisplay, window) == getpid()) return {};
  return std::to_string(static_cast<unsigned long>(window));
}

FlValue* monitor_value(TabameLinuxPlatform* platform, GdkMonitor* monitor, int index) {
  GdkRectangle geometry{};
  GdkRectangle workarea{};
  gdk_monitor_get_geometry(monitor, &geometry);
  gdk_monitor_get_workarea(monitor, &workarea);
  const int scale = std::max(1, gdk_monitor_get_scale_factor(monitor));
  const GdkMonitor* primary = gdk_display_get_primary_monitor(platform->display);

  FlValue* value = fl_value_new_map();
  map_set_string(value, "nativeId", "monitor:" + std::to_string(index));
  map_set_int(value, "x", geometry.x);
  map_set_int(value, "y", geometry.y);
  map_set_int(value, "width", geometry.width);
  map_set_int(value, "height", geometry.height);
  map_set_int(value, "visibleX", workarea.x);
  map_set_int(value, "visibleY", workarea.y);
  map_set_int(value, "visibleWidth", workarea.width);
  map_set_int(value, "visibleHeight", workarea.height);
  map_set_int(value, "scaleFactor", scale);
  map_set_bool(value, "isPrimary", monitor == primary);
  return value;
}

GdkMonitor* monitor_for_id(TabameLinuxPlatform* platform, const std::string& id, int* index_out) {
  if (platform == nullptr || platform->display == nullptr) return nullptr;
  if (id.rfind("monitor:", 0) != 0) return nullptr;
  char* end = nullptr;
  const long index = std::strtol(id.c_str() + 8, &end, 10);
  const int count = gdk_display_get_n_monitors(platform->display);
  if (end == id.c_str() + 8 || *end != '\0' || index < 0 || index >= count) return nullptr;
  if (index_out != nullptr) *index_out = static_cast<int>(index);
  return gdk_display_get_monitor(platform->display, static_cast<int>(index));
}

GdkMonitor* cursor_monitor(TabameLinuxPlatform* platform, int* index_out) {
  if (platform == nullptr || platform->display == nullptr) return nullptr;
  GdkSeat* seat = gdk_display_get_default_seat(platform->display);
  GdkDevice* pointer = seat == nullptr ? nullptr : gdk_seat_get_pointer(seat);
  int cursor_x = 0;
  int cursor_y = 0;
  if (pointer != nullptr) gdk_device_get_position(pointer, nullptr, &cursor_x, &cursor_y);

  const int count = gdk_display_get_n_monitors(platform->display);
  for (int index = 0; index < count; index++) {
    GdkMonitor* monitor = gdk_display_get_monitor(platform->display, index);
    GdkRectangle geometry{};
    gdk_monitor_get_geometry(monitor, &geometry);
    if (cursor_x >= geometry.x && cursor_x < geometry.x + geometry.width &&
        cursor_y >= geometry.y && cursor_y < geometry.y + geometry.height) {
      if (index_out != nullptr) *index_out = index;
      return monitor;
    }
  }

  GdkMonitor* primary = gdk_display_get_primary_monitor(platform->display);
  if (primary == nullptr && count > 0) primary = gdk_display_get_monitor(platform->display, 0);
  if (index_out != nullptr) {
    *index_out = 0;
    for (int index = 0; index < count; index++) {
      if (gdk_display_get_monitor(platform->display, index) == primary) *index_out = index;
    }
  }
  return primary;
}

FlValue* list_monitors(TabameLinuxPlatform* platform) {
  FlValue* result = fl_value_new_list();
  if (!is_x11_display(platform)) return result;
  const int count = gdk_display_get_n_monitors(platform->display);
  for (int index = 0; index < count; index++) {
    fl_value_append_take(result, monitor_value(platform, gdk_display_get_monitor(platform->display, index), index));
  }
  return result;
}

FlValue* cursor_monitor_value(TabameLinuxPlatform* platform) {
  if (!is_x11_display(platform)) return nullptr;
  int index = 0;
  GdkMonitor* monitor = cursor_monitor(platform, &index);
  return monitor == nullptr ? nullptr : monitor_value(platform, monitor, index);
}

FlValue* place_popup(TabameLinuxPlatform* platform, FlValue* args) {
  if (!is_x11_display(platform)) return nullptr;
  const double width = map_double(args, "width");
  const double height = map_double(args, "height");
  const double margin = std::max(0.0, map_double(args, "margin", 8.0));
  if (width <= 0 || height <= 0) return nullptr;

  int index = 0;
  GdkMonitor* monitor = monitor_for_id(platform, map_string(args, "monitorId"), &index);
  if (monitor == nullptr) monitor = cursor_monitor(platform, &index);
  if (monitor == nullptr) return nullptr;

  GdkRectangle workarea{};
  gdk_monitor_get_workarea(monitor, &workarea);
  const double left = workarea.x + margin;
  const double top = workarea.y + margin;
  const double right = std::max(left, workarea.x + workarea.width - margin);
  const double bottom = std::max(top, workarea.y + workarea.height - margin);
  const double x = std::min(std::max((left + right - width) / 2.0, left), std::max(left, right - width));
  const double y = std::min(std::max((top + bottom - height) / 2.0, top), std::max(top, bottom - height));

  FlValue* result = fl_value_new_map();
  map_set_double(result, "x", x);
  map_set_double(result, "y", y);
  map_set_double(result, "width", width);
  map_set_double(result, "height", height);
  map_set_string(result, "monitorId", "monitor:" + std::to_string(index));
  return result;
}

// ---------------------------------------------------------------------------
// X11 global hotkeys.
// ---------------------------------------------------------------------------

int g_x11_grab_error = 0;

int x11_grab_error_handler(Display*, XErrorEvent* error) {
  if (error != nullptr && error->error_code == BadAccess) g_x11_grab_error = BadAccess;
  return 0;
}

std::string uppercase(std::string value) {
  for (char& character : value) character = static_cast<char>(std::toupper(static_cast<unsigned char>(character)));
  return value;
}

KeySym key_symbol(const std::string& raw_key) {
  const std::string key = uppercase(raw_key);
  if (key == "SPACE") return XK_space;
  if (key == "ESC" || key == "ESCAPE") return XK_Escape;
  if (key == "ENTER" || key == "RETURN") return XK_Return;
  if (key == "TAB") return XK_Tab;
  if (key == "BACKSPACE") return XK_BackSpace;
  if (key == "DELETE") return XK_Delete;
  if (key == "LEFT") return XK_Left;
  if (key == "RIGHT") return XK_Right;
  if (key == "UP") return XK_Up;
  if (key == "DOWN") return XK_Down;
  if (key == "HOME") return XK_Home;
  if (key == "END") return XK_End;
  KeySym symbol = XStringToKeysym(raw_key.c_str());
  if (symbol == NoSymbol) symbol = XStringToKeysym(key.c_str());
  return symbol;
}

unsigned int modifier_mask(const std::string& raw_modifier) {
  const std::string modifier = uppercase(raw_modifier);
  if (modifier == "CTRL" || modifier == "CONTROL") return ControlMask;
  if (modifier == "ALT" || modifier == "OPTION") return Mod1Mask;
  if (modifier == "SHIFT") return ShiftMask;
  if (modifier == "SUPER" || modifier == "WIN" || modifier == "META" || modifier == "COMMAND") return Mod4Mask;
  return 0;
}

std::vector<unsigned int> lock_masks(Display* display) {
  std::vector<unsigned int> masks{0, LockMask};
  unsigned int num_lock_mask = 0;
  XModifierKeymap* modifier_map = XGetModifierMapping(display);
  const KeyCode num_lock = XKeysymToKeycode(display, XK_Num_Lock);
  if (modifier_map != nullptr) {
    for (int modifier = 0; modifier < 8; modifier++) {
      for (int key = 0; key < modifier_map->max_keypermod; key++) {
        if (modifier_map->modifiermap[modifier * modifier_map->max_keypermod + key] == num_lock) {
          num_lock_mask = 1u << modifier;
        }
      }
    }
    XFreeModifiermap(modifier_map);
  }
  if (num_lock_mask != 0) {
    masks.push_back(num_lock_mask);
    masks.push_back(num_lock_mask | LockMask);
  }
  std::sort(masks.begin(), masks.end());
  masks.erase(std::unique(masks.begin(), masks.end()), masks.end());
  return masks;
}

GdkFilterReturn x11_filter(GdkXEvent* raw_event, GdkEvent*, gpointer user_data) {
  TabameLinuxPlatform* platform = static_cast<TabameLinuxPlatform*>(user_data);
  if (platform == nullptr || !platform->hotkey_registered || raw_event == nullptr) {
    return GDK_FILTER_CONTINUE;
  }
  XEvent* event = reinterpret_cast<XEvent*>(raw_event);
  if (event->type != KeyPress || event->xkey.keycode != platform->hotkey_keycode) {
    return GDK_FILTER_CONTINUE;
  }
  if ((event->xkey.state & platform->hotkey_mask) != platform->hotkey_mask) {
    return GDK_FILTER_CONTINUE;
  }
  emit_event(platform, "hotkey", platform->hotkey_name);
  return GDK_FILTER_REMOVE;
}

void unregister_hotkey(TabameLinuxPlatform* platform) {
  if (platform == nullptr || platform->xdisplay == nullptr) return;
  if (platform->hotkey_filter_installed) {
    gdk_window_remove_filter(nullptr, x11_filter, platform);
    platform->hotkey_filter_installed = false;
  }
  if (platform->hotkey_registered) {
    for (const unsigned int mask : platform->hotkey_grab_masks) {
      XUngrabKey(platform->xdisplay, platform->hotkey_keycode, mask, platform->root);
    }
    XFlush(platform->xdisplay);
  }
  platform->hotkey_registered = false;
  platform->hotkey_grab_masks.clear();
  platform->hotkey_keycode = 0;
  platform->hotkey_mask = 0;
  platform->hotkey_name.clear();
}

FlValue* register_hotkey(TabameLinuxPlatform* platform, FlValue* args) {
  FlValue* result = fl_value_new_map();
  if (!is_x11_display(platform)) {
    map_set_bool(result, "registered", false);
    map_set_bool(result, "permissionRequired", false);
    map_set_string(result, "reason", "Global X11 hotkeys are unavailable in a Wayland or non-X11 session.");
    return result;
  }

  unregister_hotkey(platform);
  const KeySym symbol = key_symbol(map_string(args, "key"));
  const KeyCode keycode = XKeysymToKeycode(platform->xdisplay, symbol);
  unsigned int base_mask = 0;
  FlValue* modifiers = map_lookup(args, "modifiers");
  if (modifiers != nullptr && fl_value_get_type(modifiers) == FL_VALUE_TYPE_LIST) {
    const size_t count = fl_value_get_length(modifiers);
    for (size_t index = 0; index < count; index++) {
      base_mask |= modifier_mask(value_string(fl_value_get_list_value(modifiers, index)));
    }
  }
  if (symbol == NoSymbol || keycode == 0) {
    map_set_bool(result, "registered", false);
    map_set_bool(result, "permissionRequired", false);
    map_set_string(result, "reason", "The requested key is not supported by the Linux X11 adapter.");
    return result;
  }

  g_x11_grab_error = 0;
  XErrorHandler previous_handler = XSetErrorHandler(x11_grab_error_handler);
  const std::vector<unsigned int> locks = lock_masks(platform->xdisplay);
  for (const unsigned int lock : locks) {
    const unsigned int mask = base_mask | lock;
    // Deliver the grabbed press to Tabame rather than the focused client so
    // the GTK event filter can turn it into a summon event.
    XGrabKey(platform->xdisplay, keycode, mask, platform->root, False,
             GrabModeAsync, GrabModeAsync);
    platform->hotkey_grab_masks.push_back(mask);
  }
  XSync(platform->xdisplay, False);
  XSetErrorHandler(previous_handler);
  if (g_x11_grab_error != 0) {
    unregister_hotkey(platform);
    map_set_bool(result, "registered", false);
    map_set_bool(result, "permissionRequired", false);
    map_set_string(result, "reason", "Another X11 client already owns the requested global shortcut.");
    return result;
  }

  platform->hotkey_keycode = keycode;
  platform->hotkey_mask = base_mask;
  platform->hotkey_name = map_string(args, "name");
  if (platform->hotkey_name.empty()) platform->hotkey_name = "summon";
  platform->hotkey_registered = true;
  gdk_window_add_filter(nullptr, x11_filter, platform);
  platform->hotkey_filter_installed = true;
  map_set_bool(result, "registered", true);
  map_set_bool(result, "permissionRequired", false);
  map_set_string(result, "reason", "");
  return result;
}

// ---------------------------------------------------------------------------
// Clipboard polling.
// ---------------------------------------------------------------------------

gchar* clipboard_text(TabameLinuxPlatform* platform) {
  if (!is_x11_display(platform)) return nullptr;
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  return clipboard == nullptr ? nullptr : gtk_clipboard_wait_for_text(clipboard);
}

gboolean clipboard_tick(gpointer user_data) {
  TabameLinuxPlatform* platform = static_cast<TabameLinuxPlatform*>(user_data);
  if (platform == nullptr || !platform->clipboard_monitoring) return G_SOURCE_REMOVE;
  gchar* raw_text = clipboard_text(platform);
  const std::string text = raw_text == nullptr ? std::string() : std::string(raw_text);
  if (raw_text != nullptr) g_free(raw_text);

  if (!platform->clipboard_seen) {
    platform->last_clipboard_text = text;
    platform->clipboard_seen = true;
    return G_SOURCE_CONTINUE;
  }
  if (text == platform->last_clipboard_text) return G_SOURCE_CONTINUE;

  platform->last_clipboard_text = text;
  platform->clipboard_change_count++;
  emit_event(platform, "clipboardChanged", text, platform->clipboard_change_count);
  return G_SOURCE_CONTINUE;
}

bool start_clipboard_monitoring(TabameLinuxPlatform* platform) {
  if (!is_x11_display(platform)) return false;
  if (platform->clipboard_source != 0) return true;
  platform->clipboard_monitoring = true;
  platform->clipboard_seen = false;
  platform->clipboard_source = g_timeout_add(300, clipboard_tick, platform);
  if (platform->clipboard_source == 0) {
    platform->clipboard_monitoring = false;
    return false;
  }
  return true;
}

void stop_clipboard_monitoring(TabameLinuxPlatform* platform) {
  if (platform == nullptr) return;
  platform->clipboard_monitoring = false;
  if (platform->clipboard_source != 0) {
    g_source_remove(platform->clipboard_source);
    platform->clipboard_source = 0;
  }
  platform->clipboard_seen = false;
  platform->last_clipboard_text.clear();
}

bool write_clipboard_text(TabameLinuxPlatform* platform, const std::string& text) {
  if (!is_x11_display(platform)) return false;
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (clipboard == nullptr) return false;
  gtk_clipboard_set_text(clipboard, text.c_str(), static_cast<gint>(text.size()));
  gtk_clipboard_store(clipboard);
  platform->last_clipboard_text = text;
  platform->clipboard_seen = true;
  return true;
}

// ---------------------------------------------------------------------------
// Secret Service.
// ---------------------------------------------------------------------------

struct SecretSession {
  GDBusConnection* connection = nullptr;
  std::string path;
};

void close_secret_session(SecretSession* session) {
  if (session == nullptr || session->connection == nullptr) return;
  g_dbus_connection_call_sync(
      session->connection, kSecretService, kSecretPath, kSecretInterface, "Close",
      g_variant_new("(o)", session->path.c_str()), nullptr, G_DBUS_CALL_FLAGS_NONE,
      1000, nullptr, nullptr);
  g_object_unref(session->connection);
  session->connection = nullptr;
  session->path.clear();
}

bool open_secret_session(SecretSession* output) {
  if (output == nullptr) return false;
  GDBusConnection* connection = open_session_bus();
  if (connection == nullptr || !bus_has_service(connection, kSecretService)) {
    if (connection != nullptr) g_object_unref(connection);
    return false;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, kSecretService, kSecretPath, kSecretInterface, "OpenSession",
      g_variant_new("(sv)", "plain", g_variant_new_string("")),
      G_VARIANT_TYPE("(vo)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  if (reply == nullptr) {
    g_object_unref(connection);
    return false;
  }

  GVariant* output_variant = nullptr;
  gchar* path = nullptr;
  g_variant_get(reply, "(vo)", &output_variant, &path);
  if (output_variant != nullptr) g_variant_unref(output_variant);
  if (path == nullptr || path[0] == '\0') {
    if (path != nullptr) g_free(path);
    g_object_unref(connection);
    return false;
  }
  output->connection = connection;
  output->path = path;
  g_free(path);
  return true;
}

GVariant* secret_value(const SecretSession& session, const std::vector<unsigned char>& value) {
  GVariant* parameters = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, nullptr, 0, sizeof(guchar));
  GVariant* bytes = g_variant_new_fixed_array(
      G_VARIANT_TYPE_BYTE, value.empty() ? nullptr : value.data(), value.size(), sizeof(guchar));
  return g_variant_new("(o@ay@ays)", session.path.c_str(), parameters, bytes, "text/plain");
}

bool item_secret(const SecretSession& session, const std::string& item_path,
                 std::vector<unsigned char>* value) {
  if (value == nullptr) return false;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      session.connection, kSecretService, item_path.c_str(), "org.freedesktop.Secret.Item",
      "GetSecret", g_variant_new("(o)", session.path.c_str()),
      G_VARIANT_TYPE("(oayays)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  if (reply == nullptr) return false;

  gchar* session_path = nullptr;
  GVariant* parameters = nullptr;
  GVariant* bytes = nullptr;
  gchar* content_type = nullptr;
  g_variant_get(reply, "(o@ay@ays)", &session_path, &parameters, &bytes, &content_type);
  gsize length = 0;
  const guint8* data = bytes == nullptr ? nullptr :
      static_cast<const guint8*>(g_variant_get_fixed_array(bytes, &length, sizeof(guint8)));
  if (data != nullptr) value->assign(data, data + length);
  if (session_path != nullptr) g_free(session_path);
  if (parameters != nullptr) g_variant_unref(parameters);
  if (bytes != nullptr) g_variant_unref(bytes);
  if (content_type != nullptr) g_free(content_type);
  return data != nullptr || length == 0;
}


std::string first_object_path(GVariant* array) {
  if (array == nullptr || g_variant_n_children(array) == 0) return {};
  g_autoptr(GVariant) child = g_variant_get_child_value(array, 0);
  const gchar* value = g_variant_get_string(child, nullptr);
  return value == nullptr ? std::string() : std::string(value);
}

std::string find_secret_item(const SecretSession& session,
                             const std::vector<std::pair<std::string, std::string>>& attributes) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{ss}"));
  for (const auto& attribute : attributes) {
    g_variant_builder_add(&builder, "{ss}", attribute.first.c_str(), attribute.second.c_str());
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      session.connection, kSecretService, kSecretPath, kSecretInterface, "SearchItems",
      g_variant_new("(@a{ss})", g_variant_builder_end(&builder)),
      G_VARIANT_TYPE("(aoao)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  if (reply == nullptr) return {};

  GVariant* unlocked = nullptr;
  GVariant* locked = nullptr;
  g_variant_get(reply, "(@ao@ao)", &unlocked, &locked);
  std::string result = first_object_path(unlocked);
  // Keep a locked match visible to the caller. Attempting to create a second
  // key for a locked collection would produce duplicate machine identities.
  if (result.empty()) result = first_object_path(locked);
  if (unlocked != nullptr) g_variant_unref(unlocked);
  if (locked != nullptr) g_variant_unref(locked);
  return result;
}

std::string default_collection_path(const SecretSession& session) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      session.connection, kSecretService, kSecretPath, kSecretInterface, "ReadAlias",
      g_variant_new("(s)", "default"), G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE,
      1000, nullptr, &error);
  if (reply == nullptr) return kCollectionPath;
  gchar* path = nullptr;
  g_variant_get(reply, "(o)", &path);
  const std::string result = path == nullptr || path[0] == '\0' || std::strcmp(path, "/") == 0
      ? kCollectionPath
      : std::string(path);
  if (path != nullptr) g_free(path);
  return result;
}

std::string create_secret_item(const SecretSession& session, const std::string& label,
                               const std::vector<std::pair<std::string, std::string>>& attributes,
                               const std::vector<unsigned char>& value) {
  GVariantBuilder attribute_builder;
  g_variant_builder_init(&attribute_builder, G_VARIANT_TYPE("a{ss}"));
  for (const auto& attribute : attributes) {
    g_variant_builder_add(&attribute_builder, "{ss}", attribute.first.c_str(), attribute.second.c_str());
  }
  GVariant* attribute_value = g_variant_builder_end(&attribute_builder);

  GVariantBuilder properties;
  g_variant_builder_init(&properties, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&properties, "{sv}", "org.freedesktop.Secret.Item.Label",
                        g_variant_new_string(label.c_str()));
  g_variant_builder_add(&properties, "{sv}", "org.freedesktop.Secret.Item.Attributes", attribute_value);

  const std::string collection_path = default_collection_path(session);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      session.connection, kSecretService, collection_path.c_str(),
      "org.freedesktop.Secret.Collection", "CreateItem",
      g_variant_new("(@a{sv}@(oayays)b)", g_variant_builder_end(&properties),
                    secret_value(session, value), TRUE),
      G_VARIANT_TYPE("(oo)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
  if (reply == nullptr) return {};

  gchar* item = nullptr;
  gchar* prompt = nullptr;
  g_variant_get(reply, "(oo)", &item, &prompt);
  const std::string path = item == nullptr ? std::string() : std::string(item);
  const bool has_prompt = prompt != nullptr && prompt[0] != '\0' && std::strcmp(prompt, "/") != 0;
  if (item != nullptr) g_free(item);
  if (prompt != nullptr) g_free(prompt);
  return has_prompt ? std::string() : path;
}

bool random_bytes(std::vector<unsigned char>* value, size_t length) {
  if (value == nullptr) return false;
  std::ifstream random("/dev/urandom", std::ios::in | std::ios::binary);
  if (!random) return false;
  value->resize(length);
  random.read(reinterpret_cast<char*>(value->data()), static_cast<std::streamsize>(length));
  return random.good() || random.gcount() == static_cast<std::streamsize>(length);
}

std::string ensure_secret_service_key() {
  SecretSession session;
  if (!open_secret_session(&session)) return {};
  const std::vector<std::pair<std::string, std::string>> attributes = {
      {"application", kSecretApplication}, {"purpose", kMasterKeyPurpose}};
  const std::string existing_item = find_secret_item(session, attributes);
  std::vector<unsigned char> value;
  if (!existing_item.empty()) {
    if (!item_secret(session, existing_item, &value) || value.size() != 32) {
      close_secret_session(&session);
      return {};
    }
  } else {
    if (!random_bytes(&value, 32)) {
      close_secret_session(&session);
      return {};
    }
    if (create_secret_item(session, "Tabame machine key", attributes, value).empty()) {
      close_secret_session(&session);
      return {};
    }
  }

  gchar* encoded = g_base64_encode(value.data(), value.size());
  const std::string result = encoded == nullptr ? std::string() : std::string(encoded);
  if (encoded != nullptr) g_free(encoded);
  close_secret_session(&session);
  return result;
}

bool show_notification(const std::string& title, const std::string& body) {
  g_autoptr(GDBusConnection) connection = open_session_bus();
  if (!bus_has_service(connection, "org.freedesktop.Notifications")) return false;
  GVariant* actions = g_variant_new_strv(nullptr, 0);
  GVariant* hints = g_variant_new_array(G_VARIANT_TYPE("{sv}"), nullptr, 0);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify",
      g_variant_new("(susss@as@a{sv}i)", "Tabame", 0u, "", title.c_str(), body.c_str(),
                    actions, hints, -1),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  return reply != nullptr;
}

FlValue* capabilities(TabameLinuxPlatform* platform) {
  const std::string server = display_server(platform);
  const bool x11 = is_x11_display(platform);
  const bool xwayland = is_xwayland_display(platform);
  const bool wayland = server == "wayland";
  g_autoptr(GDBusConnection) connection = open_session_bus();
  const bool notifications = bus_has_service(connection, "org.freedesktop.Notifications");
  const bool secret_service = bus_has_service(connection, kSecretService);
  const PortalCapabilityProbe portals = probe_portals(connection);
  const bool pipewire = pipewire_runtime_socket_present();

  FlValue* result = fl_value_new_map();
  map_set_string(result, "displayServer", server);
  map_set_string(result, "waylandCompositor", wayland_compositor(platform));
  map_set_bool(result, "x11", x11);
  map_set_bool(result, "xWayland", xwayland);
  map_set_bool(result, "wayland", wayland);
  map_set_bool(result, "windowEnumeration", x11);
  map_set_bool(result, "windowActivation", x11);
  map_set_bool(result, "monitorGeometry", x11);
  map_set_bool(result, "globalHotkeys", x11);
  map_set_bool(result, "clipboardMonitoring", x11);
  map_set_bool(result, "inputInjection", false);
  map_set_bool(result, "screenCapture", false);
  map_set_bool(result, "screenRecording", false);
  map_set_bool(result, "filesystemWatching", true);
  map_set_bool(result, "notifications", notifications);
  map_set_bool(result, "secretService", secret_service);
  map_set_bool(result, "desktopFileDiscovery", true);
  map_set_bool(result, "portalDesktop", portals.desktop);
  map_set_bool(result, "screenCastPortal", portals.screen_cast);
  map_set_bool(result, "screenshotPortal", portals.screenshot);
  map_set_bool(result, "fileChooserPortal", portals.file_chooser);
  map_set_bool(result, "globalShortcutsPortal", portals.global_shortcuts);
  map_set_bool(result, "remoteDesktopPortal", portals.remote_desktop);
  map_set_bool(result, "pipeWire", pipewire);

  const std::string x11_boundary_reason =
      xwayland ? "The active display is XWayland inside a Wayland session; X11 global and foreign-window APIs are not used as a permission boundary."
               : "No X11 display is available.";
  if (!x11) {
    map_set_string(result, "windowEnumerationReason",
                   wayland ? "No standard Wayland protocol or portal exposes other applications' windows to this adapter."
                           : x11_boundary_reason);
    map_set_string(result, "windowActivationReason",
                   wayland ? "Window activation of other applications is compositor-controlled and is not implemented through an undocumented protocol."
                           : x11_boundary_reason);
    map_set_string(result, "monitorGeometryReason",
                   wayland ? "Wayland output information may be readable, but compositor-owned global popup placement is not implemented; the X11 monitor adapter remains disabled."
                           : x11_boundary_reason);
    map_set_string(result, "globalHotkeysReason",
                   wayland && portals.global_shortcuts
                       ? "The GlobalShortcuts portal is present, but this build only implements X11 passive grabs and does not register a portal shortcut."
                       : wayland ? "No universal Wayland global-hotkey API is used by this adapter; use the visible Tabame window instead."
                                 : x11_boundary_reason);
    map_set_string(result, "clipboardMonitoringReason",
                   wayland ? "Passive clipboard history requires a compositor data-control protocol that this adapter does not use; the X11 selection monitor is disabled."
                           : x11_boundary_reason);
  }
  if (!portals.desktop) {
    map_set_string(result, "portalDesktopReason", "The xdg-desktop-portal D-Bus service is not present.");
  }
  if (!portals.screen_cast || !pipewire) {
    map_set_string(result, "screenCaptureReason",
                   !portals.screen_cast
                       ? "Screen capture is unavailable: the ScreenCast portal interface is not advertised."
                       : "Screen capture is unavailable: the ScreenCast portal is present but the default PipeWire runtime socket was not detected.");
    map_set_string(result, "screenRecordingReason", "Screen recording is unavailable until a portal-approved PipeWire capture adapter is implemented.");
  } else {
    map_set_string(result, "screenCaptureReason",
                   "ScreenCast portal and PipeWire were detected, but Tabame does not implement capture in this build and will not request permission at startup.");
    map_set_string(result, "screenRecordingReason",
                   "Screen recording requires a portal-approved PipeWire stream; no recording adapter is implemented in this build.");
  }
  map_set_string(result, "inputInjectionReason",
                 portals.remote_desktop
                     ? "The RemoteDesktop portal is present, but no input-injection session is requested or implemented."
                     : "Input injection is unavailable; no standard Wayland input-injection permission has been granted.");
  if (!notifications) {
    map_set_string(result, "notificationsReason", "No org.freedesktop.Notifications owner is present.");
  }
  if (!secret_service) {
    map_set_string(result, "secretServiceReason", "No org.freedesktop.secrets owner is present on the session bus.");
  }
  return result;
}

// ---------------------------------------------------------------------------
// Flutter channel handlers.
// ---------------------------------------------------------------------------

void method_call_cb(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  TabameLinuxPlatform* platform = static_cast<TabameLinuxPlatform*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (g_strcmp0(method, "capabilities") == 0) {
    respond_success(call, capabilities(platform));
  } else if (g_strcmp0(method, "listWindows") == 0) {
    respond_success(call, list_windows(platform));
  } else if (g_strcmp0(method, "activateWindow") == 0) {
    respond_success(call, fl_value_new_bool(activate_window(platform, map_string(args, "nativeId"))));
  } else if (g_strcmp0(method, "listMonitors") == 0) {
    respond_success(call, list_monitors(platform));
  } else if (g_strcmp0(method, "cursorMonitor") == 0) {
    FlValue* monitor = cursor_monitor_value(platform);
    if (monitor == nullptr) respond_null(call);
    else respond_success(call, monitor);
  } else if (g_strcmp0(method, "placePopup") == 0) {
    FlValue* placement = place_popup(platform, args);
    if (placement == nullptr) respond_null(call);
    else respond_success(call, placement);
  } else if (g_strcmp0(method, "captureFocus") == 0) {
    const std::string focus = active_window_id(platform);
    if (focus.empty()) respond_null(call);
    else respond_success(call, fl_value_new_string(focus.c_str()));
  } else if (g_strcmp0(method, "restoreFocus") == 0) {
    respond_success(call, fl_value_new_bool(activate_window(platform, map_string(args, "token"))));
  } else if (g_strcmp0(method, "registerGlobalHotkey") == 0) {
    respond_success(call, register_hotkey(platform, args));
  } else if (g_strcmp0(method, "unregisterGlobalHotkey") == 0) {
    unregister_hotkey(platform);
    respond_success(call, fl_value_new_null());
  } else if (g_strcmp0(method, "startClipboardMonitoring") == 0) {
    respond_success(call, fl_value_new_bool(start_clipboard_monitoring(platform)));
  } else if (g_strcmp0(method, "stopClipboardMonitoring") == 0) {
    stop_clipboard_monitoring(platform);
    respond_success(call, fl_value_new_null());
  } else if (g_strcmp0(method, "readClipboardText") == 0) {
    gchar* text = clipboard_text(platform);
    if (text == nullptr) respond_null(call);
    else {
      respond_success(call, fl_value_new_string(text));
      g_free(text);
    }
  } else if (g_strcmp0(method, "writeClipboardText") == 0) {
    respond_success(call, fl_value_new_bool(write_clipboard_text(platform, map_string(args, "text"))));
  } else if (g_strcmp0(method, "showNotification") == 0) {
    respond_success(call, fl_value_new_bool(show_notification(map_string(args, "title"), map_string(args, "body"))));
  } else if (g_strcmp0(method, "ensureSecretServiceKey") == 0) {
    const std::string key = ensure_secret_service_key();
    if (key.empty()) respond_null(call);
    else respond_success(call, fl_value_new_string(key.c_str()));
  } else {
    respond_not_implemented(call);
  }
}

FlMethodErrorResponse* event_listen_cb(FlEventChannel*, FlValue*, gpointer user_data) {
  TabameLinuxPlatform* platform = static_cast<TabameLinuxPlatform*>(user_data);
  if (platform != nullptr) platform->event_listening = true;
  return nullptr;
}

FlMethodErrorResponse* event_cancel_cb(FlEventChannel*, FlValue*, gpointer user_data) {
  TabameLinuxPlatform* platform = static_cast<TabameLinuxPlatform*>(user_data);
  if (platform != nullptr) platform->event_listening = false;
  return nullptr;
}

}  // namespace

extern "C" TabameLinuxPlatform* tabame_linux_platform_new(FlView* view) {
  if (view == nullptr) return nullptr;
  auto* platform = new TabameLinuxPlatform();
  platform->display = gdk_display_get_default();
  if (is_x11_display(platform)) {
    platform->xdisplay = gdk_x11_display_get_xdisplay(platform->display);
    platform->root = DefaultRootWindow(platform->xdisplay);
  }

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  platform->method_channel = fl_method_channel_new(
      messenger, "tabame/linux/core", FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(platform->method_channel, method_call_cb, platform, nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  platform->event_channel = fl_event_channel_new(
      messenger, "tabame/linux/events", FL_METHOD_CODEC(event_codec));
  fl_event_channel_set_stream_handlers(platform->event_channel, event_listen_cb, event_cancel_cb,
                                       platform, nullptr);
  return platform;
}

extern "C" void tabame_linux_platform_free(TabameLinuxPlatform* platform) {
  if (platform == nullptr) return;
  stop_clipboard_monitoring(platform);
  unregister_hotkey(platform);
  platform->event_listening = false;
  if (platform->event_channel != nullptr) g_object_unref(platform->event_channel);
  if (platform->method_channel != nullptr) g_object_unref(platform->method_channel);
  delete platform;
}
