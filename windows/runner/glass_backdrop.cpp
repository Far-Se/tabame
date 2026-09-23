#include "glass_backdrop.h"

#include <dwmapi.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <type_traits>
#include <utility>
#include <vector>

namespace {
constexpr wchar_t kClassName[] = L"TABAME_GLASS_BACKDROP";
constexpr DWORD kSystemBackdrop = 38;
constexpr DWORD kImmersiveDarkMode = 20;
constexpr DWORD kWindowCornerPreference = 33;
constexpr DWORD kBorderColor = 34;

struct RegionDeleter {
  void operator()(HRGN region) const { DeleteObject(region); }
};
using Region = std::unique_ptr<std::remove_pointer_t<HRGN>, RegionDeleter>;

struct ScopedSync {
  explicit ScopedSync(bool& flag) : flag_(flag), previous_(flag) { flag_ = true; }
  ~ScopedSync() { flag_ = previous_; }
  bool& flag_;
  const bool previous_;
};

struct AccentPolicy {
  int state;
  DWORD flags;
  DWORD color;
  DWORD animation;
};
struct CompositionAttributeData {
  int attribute;
  void* data;
  SIZE_T size;
};
using SetCompositionAttribute = BOOL(WINAPI*)(HWND, CompositionAttributeData*);

bool SetCompositionData(HWND window, int attribute, void* value, SIZE_T size) {
  static const auto set_attribute = reinterpret_cast<SetCompositionAttribute>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"),
                     "SetWindowCompositionAttribute"));
  if (!set_attribute) return false;
  CompositionAttributeData data{attribute, value, size};
  return set_attribute(window, &data) != FALSE;
}

bool SetAccent(HWND window, int state, COLORREF tint, BYTE tint_alpha = 153) {
  // COLORREF is already BBGGRR. A nonzero alpha is required by legacy acrylic.
  AccentPolicy accent{state, 2,
      state == 4 ? ((static_cast<DWORD>(tint_alpha) << 24) | tint) : 0, 0};
  return SetCompositionData(window, 19, &accent, sizeof(accent));
}

bool TransparencyAllowed() {
  HIGHCONTRASTW high_contrast{sizeof(HIGHCONTRASTW), 0, nullptr};
  if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(high_contrast),
                            &high_contrast, 0) &&
      (high_contrast.dwFlags & HCF_HIGHCONTRASTON)) {
    return false;
  }
  DWORD enabled = 1;
  DWORD size = sizeof(enabled);
  RegGetValueW(HKEY_CURRENT_USER,
               L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
               L"EnableTransparency", RRF_RT_REG_DWORD, nullptr, &enabled, &size);
  BOOL composition = FALSE;
  return enabled != 0 && SUCCEEDED(DwmIsCompositionEnabled(&composition)) &&
         composition;
}

const flutter::EncodableValue* Get(const flutter::EncodableMap& map,
                                   const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

bool ReadBool(const flutter::EncodableMap& map, const char* key, bool* value) {
  const auto* raw = Get(map, key);
  if (!raw) return true;  // Older Dart callers retain the original appearance.
  const auto* boolean = std::get_if<bool>(raw);
  if (!boolean) return false;
  *value = *boolean;
  return true;
}

bool ReadOpacity(const flutter::EncodableMap& map, const char* key, double* value) {
  const auto* raw = Get(map, key);
  if (!raw) return true;
  if (const auto* number = std::get_if<double>(raw)) {
    *value = *number;
  } else if (const auto* integer = std::get_if<int32_t>(raw)) {
    *value = *integer;
  } else if (const auto* wide_integer = std::get_if<int64_t>(raw)) {
    *value = static_cast<double>(*wide_integer);
  } else {
    return false;
  }
  if (!std::isfinite(*value)) return false;
  *value = std::clamp(*value, 0.01, 1.0);
  return true;
}

Region ReadRegion(const flutter::EncodableList& surfaces) {
  Region combined(CreateRectRgn(0, 0, 0, 0));
  if (!combined) return {};
  for (const auto& surface : surfaces) {
    const auto* map = std::get_if<flutter::EncodableMap>(&surface);
    const auto* raw_contours = map ? Get(*map, "contours") : nullptr;
    const auto* contours = raw_contours
        ? std::get_if<flutter::EncodableList>(raw_contours) : nullptr;
    if (!contours) return {};
    const auto* raw_even_odd = Get(*map, "evenOdd");
    const auto* even_odd = raw_even_odd ? std::get_if<bool>(raw_even_odd) : nullptr;
    std::vector<POINT> points;
    std::vector<int> counts;
    for (const auto& contour : *contours) {
      const auto* values = std::get_if<std::vector<int32_t>>(&contour);
      if (!values || values->size() < 6 || values->size() % 2 != 0 ||
          points.size() + values->size() / 2 > 65536) {
        return {};
      }
      counts.push_back(static_cast<int>(values->size() / 2));
      for (size_t i = 0; i < values->size(); i += 2) {
        points.push_back(POINT{(*values)[i], (*values)[i + 1]});
      }
    }
    if (counts.empty()) continue;
    Region region(CreatePolyPolygonRgn(points.data(), counts.data(),
        static_cast<int>(counts.size()), even_odd && *even_odd ? ALTERNATE : WINDING));
    if (!region || CombineRgn(combined.get(), combined.get(), region.get(), RGN_OR) == ERROR) {
      return {};
    }
  }
  return combined;
}

size_t FindRoot(std::vector<size_t>& parents, size_t index) {
  while (parents[index] != index) {
    parents[index] = parents[parents[index]];
    index = parents[index];
  }
  return index;
}

// Split the already-unioned region, not its input contours: holes must stay
// empty and overlapping Flutter surfaces must never get two layers of blur.
bool SplitRegion(Region combined, std::vector<Region>& regions) {
  RECT bounds{};
  const int kind = GetRgnBox(combined.get(), &bounds);
  if (kind == ERROR) return false;
  if (kind == NULLREGION) return true;
  if (kind == SIMPLEREGION) {
    regions.push_back(std::move(combined));
    return true;
  }

  const DWORD bytes = GetRegionData(combined.get(), 0, nullptr);
  if (!bytes) return false;
  // DWORD storage supplies the alignment required by RGNDATA and RECT.
  std::vector<DWORD> storage((bytes + sizeof(DWORD) - 1) / sizeof(DWORD));
  auto* data = reinterpret_cast<RGNDATA*>(storage.data());
  if (!GetRegionData(combined.get(), bytes, data)) return false;
  const auto* rectangles = reinterpret_cast<const RECT*>(data->Buffer);
  const size_t count = data->rdh.nCount;
  std::vector<size_t> parents(count);
  for (size_t i = 0; i < count; ++i) parents[i] = i;

  // GDI supplies non-overlapping rectangles sorted top-to-bottom, left-to-right.
  // Only rectangles still touching the current scanline can connect to it.
  std::vector<size_t> active;
  for (size_t i = 0; i < count; ++i) {
    const RECT& current = rectangles[i];
    active.erase(std::remove_if(active.begin(), active.end(), [&](size_t index) {
      return rectangles[index].bottom < current.top;
    }), active.end());
    for (const size_t index : active) {
      const RECT& previous = rectangles[index];
      if (previous.left <= current.right && current.left <= previous.right) {
        parents[FindRoot(parents, i)] = FindRoot(parents, index);
      }
    }
    active.push_back(i);
  }

  size_t component_count = 0;
  for (size_t i = 0; i < count; ++i) {
    if (parents[i] == i) ++component_count;
  }
  if (component_count == 1) {
    regions.push_back(std::move(combined));
    return true;
  }

  std::vector<std::vector<RECT>> components(count);
  for (size_t i = 0; i < count; ++i) {
    components[FindRoot(parents, i)].push_back(rectangles[i]);
  }
  for (const auto& component : components) {
    if (component.empty()) continue;
    const DWORD rectangle_bytes = static_cast<DWORD>(component.size() * sizeof(RECT));
    const DWORD region_bytes = static_cast<DWORD>(sizeof(RGNDATAHEADER)) + rectangle_bytes;
    std::vector<DWORD> component_storage((region_bytes + sizeof(DWORD) - 1) / sizeof(DWORD));
    auto* component_data = reinterpret_cast<RGNDATA*>(component_storage.data());
    RECT component_bounds = component.front();
    for (const RECT& rectangle : component) {
      UnionRect(&component_bounds, &component_bounds, &rectangle);
    }
    component_data->rdh = {sizeof(RGNDATAHEADER), RDH_RECTANGLES,
        static_cast<DWORD>(component.size()), rectangle_bytes, component_bounds};
    std::memcpy(component_data->Buffer, component.data(), rectangle_bytes);
    Region region(ExtCreateRegion(nullptr, region_bytes, component_data));
    if (!region) return false;
    regions.push_back(std::move(region));
  }
  return true;
}
}  // namespace

GlassBackdrop::GlassBackdrop(HWND host) : host_(host) {
  CoCreateInstance(CLSID_VirtualDesktopManager, nullptr, CLSCTX_INPROC_SERVER,
                    IID_PPV_ARGS(desktops_.GetAddressOf()));
}

GlassBackdrop::~GlassBackdrop() {
  const ScopedSync guard(syncing_);
  panes_.clear();
}

GlassBackdrop::Pane::~Pane() {
  if (window) DestroyWindow(window);
}

bool GlassBackdrop::EnsureWindow(Pane& pane) {
  if (pane.window) return true;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kClassName;
  if (!RegisterClassW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  // Intentionally unowned: an owned popup must sit ABOVE its owner. This window
  // must sit BELOW Flutter so it cannot obscure its content. No taskbar entry,
  // activation, mouse input or independent lifetime is exposed to the user.
  pane.window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
      kClassName, L"", WS_POPUP | WS_DISABLED, 0, 0, 0, 0,
      nullptr, nullptr, window_class.hInstance, &pane);
  if (!pane.window) return false;
  const BOOL no_transitions = TRUE;
  DwmSetWindowAttribute(pane.window, DWMWA_TRANSITIONS_FORCEDISABLED,
                        &no_transitions, sizeof(no_transitions));
  const int corners = 1;  // DWMWCP_DONOTROUND: Flutter supplies the exact path.
  DwmSetWindowAttribute(pane.window, kWindowCornerPreference, &corners, sizeof(corners));
  const COLORREF border = 0xFFFFFFFE;  // DWMWA_COLOR_NONE
  DwmSetWindowAttribute(pane.window, kBorderColor, &border, sizeof(border));
  return true;
}

bool GlassBackdrop::Update(const flutter::EncodableMap& arguments) {
  const auto* raw_effect = Get(arguments, "effect");
  const auto* effect = raw_effect ? std::get_if<std::string>(raw_effect) : nullptr;
  const auto* raw_tint = Get(arguments, "tint");
  const auto* raw_regions = Get(arguments, "regions");
  const auto* regions = raw_regions
      ? std::get_if<flutter::EncodableList>(raw_regions) : nullptr;
  if (!effect || !raw_tint || !regions ||
      (*effect != "none" && *effect != "blur" && *effect != "acrylic" && *effect != "mica")) {
    return false;
  }
  uint32_t argb = 0;
  if (const auto* value = std::get_if<int32_t>(raw_tint)) {
    argb = static_cast<uint32_t>(*value);
  } else if (const auto* wide_value = std::get_if<int64_t>(raw_tint)) {
    argb = static_cast<uint32_t>(*wide_value);
  } else {
    return false;
  }
  if (*effect == "none" || regions->empty()) {
    const ScopedSync guard(syncing_);
    effect_ = *effect;
    panes_.clear();
    return true;
  }
  bool custom_tint = false;
  bool mica_alt = false;
  double tint_opacity = 0.6;
  if (!ReadBool(arguments, "customAcrylicTint", &custom_tint) ||
      !ReadBool(arguments, "micaAlt", &mica_alt) ||
      !ReadOpacity(arguments, "acrylicTintOpacity", &tint_opacity)) {
    return false;
  }
  custom_tint = *effect == "acrylic" && custom_tint;
  mica_alt = *effect == "mica" && mica_alt;
  const BYTE tint_alpha = static_cast<BYTE>(std::lround(tint_opacity * 255));
  Region region = ReadRegion(*regions);
  if (!region) return false;
  RECT client{};
  if (!GetClientRect(host_, &client)) return false;
  Region client_region(CreateRectRgnIndirect(&client));
  if (!client_region ||
      CombineRgn(region.get(), region.get(), client_region.get(), RGN_AND) == ERROR) {
    return false;
  }
  std::vector<Region> shapes;
  if (!SplitRegion(std::move(region), shapes)) return false;

  const COLORREF tint = RGB((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff);
  {
    // Native sizing/material calls can send synchronous window messages. Only
    // expose the panes after both their actual rectangles and masks are ready.
    const ScopedSync guard(syncing_);
    const bool material_changed = effect_ != *effect || tint_ != tint ||
        custom_acrylic_tint_ != custom_tint || mica_alt_ != mica_alt ||
        (custom_tint && acrylic_tint_alpha_ != tint_alpha);
    effect_ = *effect;
    tint_ = tint;
    custom_acrylic_tint_ = custom_tint;
    acrylic_tint_alpha_ = tint_alpha;
    mica_alt_ = mica_alt;
    if (panes_.size() > shapes.size()) panes_.resize(shapes.size());
    for (size_t i = 0; i < shapes.size(); ++i) {
      const bool creating = i == panes_.size();
      if (creating) panes_.push_back(std::make_unique<Pane>(this));
      Pane& pane = *panes_[i];
      RECT bounds{};
      if (GetRgnBox(shapes[i].get(), &bounds) <= NULLREGION ||
          OffsetRgn(shapes[i].get(), -bounds.left, -bounds.top) == ERROR ||
          !EnsureWindow(pane)) {
        panes_.clear();
        return false;
      }
      const bool moved = !EqualRect(&pane.bounds, &bounds);
      if (moved || material_changed) ShowWindow(pane.window, SW_HIDE);
      pane.bounds = bounds;
      // DWM materials can extend across the HWND's entire bounds, regardless of
      // the Flutter canvas or a smaller HRGN. Physically crop the HWND as well.
      if (!SetWindowPos(pane.window, nullptr, 0, 0,
                        bounds.right - bounds.left, bounds.bottom - bounds.top,
                        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
        panes_.clear();
        return false;
      }
      if (creating || material_changed) ApplyMaterial(pane);
      // The path is now local to the tightly sized HWND. Apply it AFTER sizing
      // and material changes; Windows owns it only when SetWindowRgn succeeds.
      if (!SetWindowRgn(pane.window, shapes[i].get(), TRUE)) {
        panes_.clear();
        return false;
      }
      shapes[i].release();
      if (creating && i == 0) {
        // One guard for all panes catches layered alpha / desktop cloaking,
        // which do not reliably produce host window-position messages.
        SetTimer(pane.window, 1, 50, nullptr);
      }
    }
  }
  Sync();
  return true;
}

void GlassBackdrop::ApplyMaterial(Pane& pane) {
  SetAccent(pane.window, 0, tint_);
  int backdrop = 1;  // DWMSBT_NONE, including reset when switching effects.
  DwmSetWindowAttribute(pane.window, kSystemBackdrop, &backdrop, sizeof(backdrop));
  const MARGINS reset{0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(pane.window, &reset);
  pane.solid_fallback = true;
  if (TransparencyAllowed()) {
    const BOOL dark = (GetRValue(tint_) * 299 + GetGValue(tint_) * 587 +
                      GetBValue(tint_) * 114) < 128000;
    DwmSetWindowAttribute(pane.window, kImmersiveDarkMode, &dark, sizeof(dark));
    const MARGINS full{-1, -1, -1, -1};
    DwmExtendFrameIntoClientArea(pane.window, &full);
    if (effect_ == "acrylic" && custom_acrylic_tint_) {
      // DWMSBT_TRANSIENTWINDOW has no tint/opacity parameters. An explicit
      // custom tint uses the adjustable accent policy; System keeps DWM's recipe.
      pane.solid_fallback = !SetAccent(pane.window, 4, tint_, acrylic_tint_alpha_);
    } else if (effect_ == "mica" || effect_ == "acrylic") {
      // Documented system backdrops are available on Windows 11 22H2+.
      // Mica uses wallpaper material; Acrylic uses the transient blur material.
      backdrop = effect_ == "mica" ? (mica_alt_ ? 4 : 2) : 3;
      pane.solid_fallback = FAILED(DwmSetWindowAttribute(
          pane.window, kSystemBackdrop, &backdrop, sizeof(backdrop)));
      // Older Windows versions fall back to acrylic, then blur, then solid.
      if (pane.solid_fallback) pane.solid_fallback = !SetAccent(pane.window, 4, tint_);
    }
    if (effect_ == "blur" || pane.solid_fallback) {
      pane.solid_fallback = !SetAccent(pane.window, 3, tint_);
    }
  }
  if (pane.solid_fallback) DwmExtendFrameIntoClientArea(pane.window, &reset);
  InvalidateRect(pane.window, nullptr, TRUE);
}

void GlassBackdrop::RefreshTheme() {
  if (syncing_) return;
  {
    const ScopedSync guard(syncing_);
    for (const auto& pane : panes_) {
      Region region(CreateRectRgn(0, 0, 0, 0));
      if (!region || GetWindowRgn(pane->window, region.get()) == ERROR) {
        panes_.clear();
        return;
      }
      ShowWindow(pane->window, SW_HIDE);
      ApplyMaterial(*pane);
      if (!SetWindowRgn(pane->window, region.get(), TRUE)) {
        panes_.clear();
        return;
      }
      region.release();
    }
  }
  Sync();
}

void GlassBackdrop::Sync() {
  if (panes_.empty() || syncing_) return;
  const ScopedSync guard(syncing_);
  BYTE alpha = 255;
  DWORD flags = 0;
  COLORREF key = 0;
  GetLayeredWindowAttributes(host_, &key, &alpha, &flags);
  DWORD cloaked = 0;
  DwmGetWindowAttribute(host_, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
  RECT client{};
  POINT origin{};
  const bool visible = IsWindowVisible(host_) && !IsIconic(host_) &&
      !cloaked && (!(flags & LWA_ALPHA) || alpha == 255) &&
      GetClientRect(host_, &client) && ClientToScreen(host_, &origin);
  const HWND foreground = GetForegroundWindow();
  const bool active = foreground == host_ || GetAncestor(foreground, GA_ROOTOWNER) == host_;
  HWND previous = host_;
  for (const auto& pane : panes_) {
    // A host resize can arrive before Flutter sends its next path. Clamp that
    // interval too, so no backdrop can escape the current Flutter client area.
    const int width = std::min(pane->bounds.right, client.right) - pane->bounds.left;
    const int height = std::min(pane->bounds.bottom, client.bottom) - pane->bounds.top;
    if (!visible || width <= 0 || height <= 0) {
      if (IsWindowVisible(pane->window)) ShowWindow(pane->window, SW_HIDE);
      continue;
    }
    DWORD backdrop_cloaked = 0;
    DwmGetWindowAttribute(pane->window, DWMWA_CLOAKED, &backdrop_cloaked, sizeof(backdrop_cloaked));
    if (backdrop_cloaked && desktops_) {
      GUID desktop{};
      if (SUCCEEDED(desktops_->GetWindowDesktopId(host_, &desktop))) {
        desktops_->MoveWindowToDesktop(pane->window, desktop);
      }
    }
    if (active != pane->host_active) {
      pane->host_active = active;
      BOOL appearance = active;
      // The backdrop never takes focus. Mirror the host's active appearance so
      // Mica doesn't stay in its inactive solid state beneath a focused launcher.
      SetCompositionData(pane->window, 15, &appearance, sizeof(appearance));
    }
    const int left = origin.x + pane->bounds.left;
    const int top = origin.y + pane->bounds.top;
    // Keep the entire group immediately below Flutter in its z-order band,
    // including always-on-top changes, without activating any backdrop pane.
    RECT current{};
    GetWindowRect(pane->window, &current);
    if (!IsWindowVisible(pane->window) || current.left != left || current.top != top ||
        current.right - current.left != width || current.bottom - current.top != height ||
        GetWindow(pane->window, GW_HWNDPREV) != previous) {
      if (!SetWindowPos(pane->window, previous, left, top, width, height,
                        SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW)) {
        ShowWindow(pane->window, SW_HIDE);
        continue;
      }
    }
    previous = pane->window;
  }
}

LRESULT CALLBACK GlassBackdrop::WindowProc(HWND window, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* pane = reinterpret_cast<Pane*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  switch (message) {
    case WM_TIMER:
      if (pane) pane->owner->Sync();
      return 0;
    case WM_NCHITTEST: return HTTRANSPARENT;
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      // Black is the transparent glass surface when the full DWM frame is
      // extended. A theme-colored brush supplies the accessible solid fallback.
      HBRUSH brush = CreateSolidBrush(pane && pane->solid_fallback ? pane->owner->tint_ : RGB(0, 0, 0));
      FillRect(dc, &paint.rcPaint, brush);
      DeleteObject(brush);
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
