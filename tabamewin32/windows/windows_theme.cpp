#include <windows.h>

bool SetDwordValue(HKEY root, const wchar_t* subKey, const wchar_t* name, DWORD value) {
    HKEY hKey = nullptr;

    if (RegCreateKeyExW(root, subKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &hKey, nullptr) != ERROR_SUCCESS)
        return false;

    bool success = (RegSetValueExW(
        hKey,
        name,
        0,
        REG_DWORD,
        reinterpret_cast<const BYTE*>(&value),
        sizeof(value)
    ) == ERROR_SUCCESS);

    RegCloseKey(hKey);
    return success;
}

// type: 0 = dark, 1 = light
bool SetWindowTheme(int type) {
    const wchar_t* key =
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";

    DWORD value = (type == 1) ? 1 : 0;

    bool ok1 = SetDwordValue(HKEY_CURRENT_USER, key, L"AppsUseLightTheme", value);
    bool ok2 = SetDwordValue(HKEY_CURRENT_USER, key, L"SystemUsesLightTheme", value);

    // Notify the system that settings changed
    SendMessageTimeoutW(
        HWND_BROADCAST,
        WM_SETTINGCHANGE,
        0,
        (LPARAM)L"ImmersiveColorSet",
        SMTO_ABORTIFHUNG,
        2000,
        nullptr
    );

    return ok1 && ok2;
}
