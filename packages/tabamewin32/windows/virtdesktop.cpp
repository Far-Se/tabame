#include <windows.h>
#include <strsafe.h>
#include <assert.h>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <iterator>
#include <functional>
#include <utility>
#include <sstream>

#include <inttypes.h>

#include "virtdesktop.h"

#include <iostream>

using namespace std;

struct scope_guard
{
private:
    std::function<void()> run;
    bool active;

public:
    scope_guard(std::function<void()> &&fn)
        : run(std::move(fn)), active(true)
    {
    }

    void Dismiss()
    {
        active = false;
    }

    ~scope_guard()
    {
        if (active)
        {
            auto r = std::move(run);
            r();
        }
    }
};

namespace std
{
    template <>
    struct hash<GUID>
    {
        size_t operator()(const GUID &guid) const noexcept
        {
            const std::uint64_t *p = reinterpret_cast<const std::uint64_t *>(&guid);
            std::hash<std::uint64_t> hash;
            return hash(p[0]) ^ hash(p[1]);
        }
    };
}

namespace
{

    IServiceProvider *pServiceProvider = NULL;
    IApplicationViewCollection *viewCollection = NULL;
    IVirtualDesktopManager2 *pDesktopManager = NULL;
    IVirtualDesktopManagerInternal *pDesktopManagerInternal = NULL;

    HINSTANCE mHInstance;
}

void MoveToCurrent(HWND hWin);

size_t WrapIdx(size_t curIdx, size_t max, int dir)
{
    int idx = ((int)curIdx) + dir;
    while (idx < 0)
    {
        idx += (int)max;
    }
    while (idx >= max)
    {
        idx -= (int)max;
    }
    return (size_t)idx;
}

void MoveDesktop(int dir)
{

    IVirtualDesktop *current = nullptr;
    if (!SUCCEEDED(pDesktopManagerInternal->GetCurrentDesktop(&current)))
        return;
    GUID currentId{0};
    if (!SUCCEEDED(current->GetID(&currentId)))
        return;

    IObjectArray *pObjectArray = nullptr;
    if (!SUCCEEDED(pDesktopManagerInternal->GetDesktops(&pObjectArray)))
        return;
    UINT count = 0;
    if (!SUCCEEDED(pObjectArray->GetCount(&count)))
        return;

    std::vector<IVirtualDesktop *> desktops;

    IVirtualDesktop *pCur = nullptr;
    UINT curIdx = 0;

    for (UINT i = 0; i < count; i++)
    {
        if (FAILED(pObjectArray->GetAt(i, __uuidof(IVirtualDesktop), (void **)&pCur)))
            continue;
        GUID id = {0};
        if (FAILED(pCur->GetID(&id)))
            continue;

        desktops.push_back(pCur);
        if (id == currentId)
        {
            curIdx = i;
        }
    }

    IVirtualDesktop *pTarget = NULL;

    pTarget = desktops[WrapIdx(curIdx, desktops.size(), dir)];

    pDesktopManagerInternal->SwitchDesktop(pTarget);
}

void NextDesktop()
{
    MoveDesktop(1);
}

void PrevDesktop()
{
    MoveDesktop(-1);
}

void MoveWinToDesktop(HWND hWin, IVirtualDesktop *pTarget)
{
    IApplicationView *app = NULL;
    if (!SUCCEEDED(viewCollection->GetViewForHwnd(hWin, &app)))
        return;
    if (!SUCCEEDED(pDesktopManagerInternal->MoveViewToDesktop(app, pTarget)))
        return;
}

void MoveToCurrent(HWND hWin)
{
    BOOL onDesk = FALSE;
    if (!SUCCEEDED(pDesktopManager->IsWindowOnCurrentVirtualDesktop(hWin, &onDesk)))
        return;
    if (onDesk)
        return;

    IVirtualDesktop *current = nullptr;
    if (!SUCCEEDED(pDesktopManagerInternal->GetCurrentDesktop(&current)))
        return;
    GUID currentId{0};
    if (!SUCCEEDED(current->GetID(&currentId)))
        return;

    IApplicationView *app = NULL;
    if (!SUCCEEDED(viewCollection->GetViewForHwnd(hWin, &app)))
        return;
    if (!SUCCEEDED(pDesktopManagerInternal->MoveViewToDesktop(app, current)))
        return;
}

void DestoryScratchDesktop()
{
    if (pDesktopManagerInternal)
    {
        pDesktopManagerInternal->Release();
        pDesktopManagerInternal = NULL;
    }
    if (pDesktopManager)
    {
        pDesktopManager->Release();
        pDesktopManager = NULL;
    }
    if (viewCollection)
    {
        viewCollection->Release();
        viewCollection = NULL;
    }
    if (pServiceProvider)
    {
        pServiceProvider->Release();
        pServiceProvider = NULL;
    }
    CoUninitialize();
}

bool CreateScratchDesktop()
{
    HRESULT hr;

    hr = ::CoInitialize(NULL);
    if (!SUCCEEDED(hr))
    {
        return false;
    }

    scope_guard guard([]()
                      { DestoryScratchDesktop(); });

    if (!SUCCEEDED(::CoCreateInstance(CLSID_ImmersiveShell, NULL, CLSCTX_LOCAL_SERVER, __uuidof(IServiceProvider), (PVOID *)&pServiceProvider)))
    {
        return false;
    }

    if (!SUCCEEDED(pServiceProvider->QueryService(__uuidof(IApplicationViewCollection), &viewCollection)))
    {
        return false;
    }

    if (!SUCCEEDED(pServiceProvider->QueryService(__uuidof(IVirtualDesktopManager2), &pDesktopManager)))
    {
        return false;
    }

    if (!SUCCEEDED(pServiceProvider->QueryService(CLSID_VirtualDesktopManagerInternal, __uuidof(IVirtualDesktopManagerInternal), (PVOID *)&pDesktopManagerInternal)))
    {
        return false;
    }

    // if (hr != S_OK)
    // {
    //     return false;
    // }

    guard.Dismiss();

    return true;
}
