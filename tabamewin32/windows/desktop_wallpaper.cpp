#include <windows.h>
#include <shobjidl.h>
#include <string>
#include <stdexcept>

enum class WallpaperFillMode {
    Center,
    Tile,
    Stretch,
    Fit,
    Fill,
    Span
};

DESKTOP_WALLPAPER_POSITION ToDesktopPosition(WallpaperFillMode mode) {
    switch (mode) {
        case WallpaperFillMode::Center:  return DWPOS_CENTER;
        case WallpaperFillMode::Tile:    return DWPOS_TILE;
        case WallpaperFillMode::Stretch: return DWPOS_STRETCH;
        case WallpaperFillMode::Fit:     return DWPOS_FIT;
        case WallpaperFillMode::Fill:    return DWPOS_FILL;
        case WallpaperFillMode::Span:    return DWPOS_SPAN;
        default:                         return DWPOS_FILL;
    }
}

void ChangeWallpaperForMonitor(
    const std::wstring& imagePath,
    int monitorIndex,
    WallpaperFillMode fillMode = WallpaperFillMode::Fill
) {
    HRESULT hr = CoInitialize(nullptr);
    bool comInitialized = SUCCEEDED(hr);

    IDesktopWallpaper* wallpaper = nullptr;
    hr = CoCreateInstance(
        CLSID_DesktopWallpaper,
        nullptr,
        CLSCTX_ALL,
        IID_PPV_ARGS(&wallpaper)
    );

    if (FAILED(hr) || wallpaper == nullptr) {
        if (comInitialized) CoUninitialize();
        throw std::runtime_error("Failed to create IDesktopWallpaper.");
    }

    UINT monitorCount = 0;
    hr = wallpaper->GetMonitorDevicePathCount(&monitorCount);
    if (FAILED(hr)) {
        wallpaper->Release();
        if (comInitialized) CoUninitialize();
        throw std::runtime_error("Failed to get monitor count.");
    }

    if (monitorIndex < 0 || static_cast<UINT>(monitorIndex) >= monitorCount) {
        wallpaper->Release();
        if (comInitialized) CoUninitialize();
        throw std::out_of_range("Invalid monitor index.");
    }

    LPWSTR monitorId = nullptr;
    hr = wallpaper->GetMonitorDevicePathAt(static_cast<UINT>(monitorIndex), &monitorId);
    if (FAILED(hr) || monitorId == nullptr) {
        wallpaper->Release();
        if (comInitialized) CoUninitialize();
        throw std::runtime_error("Failed to get monitor ID.");
    }

    hr = wallpaper->SetPosition(ToDesktopPosition(fillMode));
    if (FAILED(hr)) {
        CoTaskMemFree(monitorId);
        wallpaper->Release();
        if (comInitialized) CoUninitialize();
        throw std::runtime_error("Failed to set wallpaper position.");
    }

    hr = wallpaper->SetWallpaper(monitorId, imagePath.c_str());
    CoTaskMemFree(monitorId);
    wallpaper->Release();

    if (comInitialized) CoUninitialize();

    if (FAILED(hr)) {
        throw std::runtime_error("Failed to set wallpaper for the specified monitor.");
    }
}