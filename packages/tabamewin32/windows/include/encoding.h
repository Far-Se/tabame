#include <windows.h>
#include <string>
namespace Encoding
{
    std::string WideToUtf8(const std::wstring &wstr)
    {
        int count = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), static_cast<int>(wstr.length()), nullptr, 0, nullptr, nullptr);
        std::string str(count, 0);
        WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], count, nullptr, nullptr);
        return str;
    }

    std::wstring Utf8ToWide(const std::string &str)
    {
        int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), nullptr, 0);
        std::wstring wstr(count, 0);
        MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), &wstr[0], count);
        return wstr;
    }

    std::string WideToAnsi(const std::wstring &wstr)
    {
        int count = WideCharToMultiByte(CP_ACP, 0, wstr.c_str(), static_cast<int>(wstr.length()), nullptr, 0, nullptr, nullptr);
        std::string str(count, 0);
        WideCharToMultiByte(CP_ACP, 0, wstr.c_str(), -1, &str[0], count, nullptr, nullptr);
        return str;
    }

    std::wstring AnsiToWide(const std::string &str)
    {
        int count = MultiByteToWideChar(CP_ACP, 0, str.c_str(), static_cast<int>(str.length()), nullptr, 0);
        std::wstring wstr(count, 0);
        MultiByteToWideChar(CP_ACP, 0, str.c_str(), static_cast<int>(str.length()), &wstr[0], count);
        return wstr;
    }
}
