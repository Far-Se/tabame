#include <windows.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <algorithm>

struct FolderState {
    std::wstring path;
    FILETIME lastWriteTime;
};

static std::vector<FolderState> g_watchlist;

// Get current last write time for a folder
FILETIME GetFolderLastWriteTime(const std::wstring& path) {
    WIN32_FILE_ATTRIBUTE_DATA attr;
    if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attr)) {
        return attr.ftLastWriteTime;
    }
    return { 0, 0 };
}

// Pass in your cached states, get back only the ones that changed
// This version uses the internal watchlist
std::vector<std::wstring> GetChangedFolders() {
    std::vector<std::wstring> changed;

    for (auto& state : g_watchlist) {
        FILETIME currentWriteTime = GetFolderLastWriteTime(state.path);
        
        // If it was accessible before but not now, or vice versa, or time changed
        if (CompareFileTime(&currentWriteTime, &state.lastWriteTime) != 0) {
            changed.push_back(state.path);
            state.lastWriteTime = currentWriteTime; // update cache
        }
    }

    return changed;
}

void AddFoldersToWatchlist(const std::vector<std::wstring>& paths) {
    for (const auto& path : paths) {
        // Avoid duplicates
        auto it = std::find_if(g_watchlist.begin(), g_watchlist.end(), [&](const FolderState& s) {
            return s.path == path;
        });
        
        if (it == g_watchlist.end()) {
            g_watchlist.push_back({ path, GetFolderLastWriteTime(path) });
        }
    }
}

void RemoveFoldersFromWatchlist(const std::vector<std::wstring>& paths) {
    for (const auto& path : paths) {
        g_watchlist.erase(std::remove_if(g_watchlist.begin(), g_watchlist.end(), [&](const FolderState& s) {
            return s.path == path;
        }), g_watchlist.end());
    }
}
