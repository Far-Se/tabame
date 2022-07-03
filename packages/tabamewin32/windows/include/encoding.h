#include <windows.h>
#include <string>
namespace Encoding {
    /**
     * @brief Converts a wide string to UTF-8.
     * 
     * @param wstr 
     * @return std::string 
     */
    std::string WideToUtf8(const std::wstring& wstr)
    {
        int count = WideCharToMultiByte(
            CP_UTF8, 
            0, 
            wstr.c_str(), 
            static_cast<int>(wstr.length()), 
            nullptr, 
            0, 
            nullptr, 
            nullptr);
        std::string str(count, 0);
        WideCharToMultiByte(
            CP_UTF8, 
            0, 
            wstr.c_str(), 
            -1, 
            &str[0], 
            count, 
            nullptr, 
            nullptr);
        return str;
    }

    /**
     * @brief Converts an UTF-8 string to a wide string.
     * 
     * @param str 
     * @return std::wstring 
     */
    std::wstring Utf8ToWide(const std::string& str)
    {
        int count = MultiByteToWideChar(
            CP_UTF8, 
            0, 
            str.c_str(), 
            static_cast<int>(str.length()), 
            nullptr, 
            0);
        std::wstring wstr(count, 0);
        MultiByteToWideChar(
            CP_UTF8, 
            0, 
            str.c_str(), 
            static_cast<int>(str.length()), 
            &wstr[0], 
            count);
        return wstr;
    }

    /**
     * @brief Converts a wide string to ANSI.
     * 
     * @param wstr 
     * @return std::string 
     */
    std::string WideToAnsi(const std::wstring& wstr)
    {
        int count = WideCharToMultiByte(
            CP_ACP, 
            0,
            wstr.c_str(),
            static_cast<int>(wstr.length()),
            nullptr,
            0,
            nullptr,
            nullptr);
        std::string str(count, 0);
        WideCharToMultiByte(CP_ACP,
            0,
            wstr.c_str(),
            -1,
            &str[0],
            count,
            nullptr,
            nullptr);
        return str;
    }

    /**
     * @brief Converts an ANSI string to a wide string.
     * 
     * @param str 
     * @return std::wstring 
     */
    std::wstring AnsiToWide(const std::string& str)
    {
        int count = MultiByteToWideChar(
            CP_ACP,
            0,
            str.c_str(),
            static_cast<int>(str.length()),
            nullptr,
            0);
        std::wstring wstr(count, 0);
        MultiByteToWideChar(
            CP_ACP,
            0,
            str.c_str(),
            static_cast<int>(str.length()),
            &wstr[0],
            count);
        return wstr;
    }
}
