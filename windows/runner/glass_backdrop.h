#ifndef RUNNER_GLASS_BACKDROP_H_
#define RUNNER_GLASS_BACKDROP_H_

#include <windows.h>
#include <flutter/encodable_value.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <memory>
#include <string>
#include <vector>

// Tightly sized, region-clipped siblings below the Flutter HWND. Each connected
// surface gets its own HWND so DWM cannot fill the canvas padding or panel gaps.
// Keeping the backdrop separate preserves popups and resize hit areas.
class GlassBackdrop {
 public:
  explicit GlassBackdrop(HWND host);
  ~GlassBackdrop();
  bool Update(const flutter::EncodableMap& arguments);
  void Sync();
  void RefreshTheme();

 private:
  struct Pane {
    explicit Pane(GlassBackdrop* backdrop) : owner(backdrop) {}
    ~Pane();
    GlassBackdrop* owner;
    HWND window = nullptr;
    RECT bounds{};  // Physical pixels relative to the Flutter client origin.
    bool solid_fallback = true;
    bool host_active = false;
  };

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  bool EnsureWindow(Pane& pane);
  void ApplyMaterial(Pane& pane);

  HWND host_ = nullptr;
  std::vector<std::unique_ptr<Pane>> panes_;
  std::string effect_ = "none";
  COLORREF tint_ = RGB(24, 24, 24);
  bool custom_acrylic_tint_ = false;
  BYTE acrylic_tint_alpha_ = 153;
  bool mica_alt_ = false;
  bool syncing_ = false;
  Microsoft::WRL::ComPtr<IVirtualDesktopManager> desktops_;
};

#endif  // RUNNER_GLASS_BACKDROP_H_
