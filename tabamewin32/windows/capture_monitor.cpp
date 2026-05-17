#include <windows.h>
#define WINRT_LEAN_AND_MEAN

#include <d3d11.h>
#include <dxgi1_2.h>
#include <roapi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <stdint.h>
#include <cstring>
#include <map>
#include <mutex>
#include <vector>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/base.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowsapp.lib")

struct MonitorCaptureResult {
    std::vector<uint8_t> pixels; // BGRA, 4 bytes per pixel
    int width;
    int height;
};

namespace
{
    using winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame;
    using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
    using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
    using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
    using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
    using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
    using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface;

    template <typename T>
    void ReleaseIfSet(T*& ptr)
    {
        if (ptr)
        {
            ptr->Release();
            ptr = nullptr;
        }
    }

    bool IsRgbBlackFrame(const std::vector<uint8_t>& pixels, int width, int height)
    {
        if (pixels.empty() || width <= 0 || height <= 0) return true;
        const int stepX = width / 8;
        const int stepY = height / 8;
        if (stepX <= 0 || stepY <= 0) return false;
        for (int gy = 0; gy < 8; gy++)
        for (int gx = 0; gx < 8; gx++)
        {
            int idx = ((gy * stepY) * width + (gx * stepX)) * 4;
            if (pixels[idx] != 0 || pixels[idx + 1] != 0 || pixels[idx + 2] != 0)
                return false;
        }
        return true;
    }

    bool EnsureWinRtInitialized()
    {
        static std::once_flag initOnce;
        static HRESULT initResult = E_FAIL;

        std::call_once(initOnce, []()
        {
            initResult = RoInitialize(RO_INIT_MULTITHREADED);
            if (initResult == RPC_E_CHANGED_MODE)
                initResult = S_OK;
        });

        return SUCCEEDED(initResult);
    }

    bool CreateD3D11Device(
        ID3D11Device** device,
        ID3D11DeviceContext** context)
    {
        static const D3D_FEATURE_LEVEL kFeatureLevels[] = {
            D3D_FEATURE_LEVEL_11_1,
            D3D_FEATURE_LEVEL_11_0,
            D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL_10_0,
        };

        HRESULT hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            kFeatureLevels,
            static_cast<UINT>(sizeof(kFeatureLevels) / sizeof(kFeatureLevels[0])),
            D3D11_SDK_VERSION,
            device,
            nullptr,
            context);
        if (SUCCEEDED(hr))
            return true;

        hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            kFeatureLevels,
            static_cast<UINT>(sizeof(kFeatureLevels) / sizeof(kFeatureLevels[0])),
            D3D11_SDK_VERSION,
            device,
            nullptr,
            context);
        return SUCCEEDED(hr);
    }

    bool CopyTextureToPixels(
        ID3D11Device* device,
        ID3D11DeviceContext* context,
        ID3D11Texture2D* sourceTexture,
        MonitorCaptureResult& result)
    {
        if (device == nullptr || context == nullptr || sourceTexture == nullptr)
            return false;

        ID3D11Texture2D* stagingTexture = nullptr;
        D3D11_TEXTURE2D_DESC desc = {};
        D3D11_TEXTURE2D_DESC stagingDesc = {};
        D3D11_MAPPED_SUBRESOURCE mapped = {};

        sourceTexture->GetDesc(&desc);
        if (desc.Width == 0 || desc.Height == 0)
            return false;

        stagingDesc = desc;
        stagingDesc.Usage = D3D11_USAGE_STAGING;
        stagingDesc.BindFlags = 0;
        stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        stagingDesc.MiscFlags = 0;

        HRESULT hr = device->CreateTexture2D(&stagingDesc, nullptr, &stagingTexture);
        if (FAILED(hr))
            goto fail;

        context->CopyResource(stagingTexture, sourceTexture);

        hr = context->Map(stagingTexture, 0, D3D11_MAP_READ, 0, &mapped);
        if (FAILED(hr))
            goto fail;

        result.width = static_cast<int>(desc.Width);
        result.height = static_cast<int>(desc.Height);
        result.pixels.resize(static_cast<size_t>(result.width) * result.height * 4);

        for (int y = 0; y < result.height; ++y)
        {
            memcpy(
                result.pixels.data() + static_cast<size_t>(y) * result.width * 4,
                static_cast<uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
                static_cast<size_t>(result.width) * 4);
        }

        context->Unmap(stagingTexture, 0);
        ReleaseIfSet(stagingTexture);
        return true;

    fail:
        if (stagingTexture != nullptr && mapped.pData != nullptr)
            context->Unmap(stagingTexture, 0);
        ReleaseIfSet(stagingTexture);
        result.pixels.clear();
        result.width = 0;
        result.height = 0;
        return false;
    }

    bool CopyCaptureFrameToPixels(
        ID3D11Device* device,
        ID3D11DeviceContext* context,
        const Direct3D11CaptureFrame& frame,
        MonitorCaptureResult& result)
    {
        if (!frame)
            return false;

        IDirect3DSurface surface = frame.Surface();
        if (!surface)
            return false;

        winrt::com_ptr<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess> access =
            surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        winrt::com_ptr<ID3D11Texture2D> sourceTexture;
        HRESULT hr = access->GetInterface(
            __uuidof(ID3D11Texture2D),
            sourceTexture.put_void());
        if (FAILED(hr))
            return false;

        return CopyTextureToPixels(device, context, sourceTexture.get(), result);
    }

    bool TryCaptureMonitorWithGraphicsCapture(
        HMONITOR monitor,
        MonitorCaptureResult& result)
    {
        if (monitor == nullptr)
            return false;
        if (!EnsureWinRtInitialized())
            return false;
        if (!GraphicsCaptureSession::IsSupported())
            return false;

        ID3D11Device* device = nullptr;
        ID3D11DeviceContext* context = nullptr;
        HANDLE frameEvent = nullptr;
        bool success = false;

        try
        {
            if (!CreateD3D11Device(&device, &context))
                return false;

            winrt::com_ptr<IDXGIDevice> dxgiDevice;
            HRESULT hr = device->QueryInterface(__uuidof(IDXGIDevice), dxgiDevice.put_void());
            if (FAILED(hr))
                return false;

            winrt::com_ptr<::IInspectable> inspectableDevice;
            hr = CreateDirect3D11DeviceFromDXGIDevice(
                dxgiDevice.get(),
                inspectableDevice.put());
            if (FAILED(hr))
                return false;

            IDirect3DDevice direct3dDevice = inspectableDevice.as<IDirect3DDevice>();

            auto interop = winrt::get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
            GraphicsCaptureItem item{ nullptr };
            hr = interop->CreateForMonitor(
                monitor,
                winrt::guid_of<winrt::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
                winrt::put_abi(item));
            if (FAILED(hr) || !item)
                return false;

            const auto size = item.Size();
            if (size.Width <= 0 || size.Height <= 0)
                return false;

            Direct3D11CaptureFramePool framePool =
                Direct3D11CaptureFramePool::CreateFreeThreaded(
                    direct3dDevice,
                    DirectXPixelFormat::B8G8R8A8UIntNormalized,
                    1,
                    size);
            GraphicsCaptureSession session = framePool.CreateCaptureSession(item);
            session.IsCursorCaptureEnabled(false);

            frameEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
            if (frameEvent == nullptr)
                return false;

            auto token = framePool.FrameArrived([&](auto const&, auto const&)
            {
                SetEvent(frameEvent);
            });

            session.StartCapture();

            for (int attempt = 0; attempt < 8; ++attempt)
            {
                const DWORD waitResult = WaitForSingleObject(frameEvent, 200);
                if (waitResult != WAIT_OBJECT_0)
                    continue;

                Direct3D11CaptureFrame frame = framePool.TryGetNextFrame();
                if (!frame)
                    continue;

                MonitorCaptureResult candidate;
                if (!CopyCaptureFrameToPixels(device, context, frame, candidate))
                    continue;
                if (IsRgbBlackFrame(candidate.pixels, candidate.width, candidate.height))
                    continue;

                result = std::move(candidate);
                success = true;
                break;
            }

            framePool.FrameArrived(token);
            session.Close();
            framePool.Close();
        }
        catch (...)
        {
            success = false;
        }

        if (frameEvent != nullptr)
            CloseHandle(frameEvent);
        ReleaseIfSet(context);
        ReleaseIfSet(device);
        return success;
    }

    struct MonitorCaptureSession
    {
        ID3D11Device* device = nullptr;
        ID3D11DeviceContext* context = nullptr;
        IDXGIOutputDuplication* duplication = nullptr;
        ID3D11Texture2D* stagingTexture = nullptr;
        D3D11_TEXTURE2D_DESC stagingDesc = {};
        int width = 0;
        int height = 0;
        std::vector<uint8_t> cachedPixels;

        ~MonitorCaptureSession()
        {
            Reset();
        }

        void Reset()
        {
            ReleaseIfSet(stagingTexture);
            ReleaseIfSet(duplication);
            ReleaseIfSet(context);
            ReleaseIfSet(device);
            cachedPixels.clear();
            width = 0;
            height = 0;
        }

        bool Initialize(int monitorIndex)
        {
            if (duplication)
                return true;

            IDXGIDevice* dxgiDevice = nullptr;
            IDXGIAdapter* adapter = nullptr;
            IDXGIOutput* output = nullptr;
            IDXGIOutput1* output1 = nullptr;
            DXGI_OUTPUT_DESC outputDesc = {};

            HRESULT hr = D3D11CreateDevice(
                nullptr,
                D3D_DRIVER_TYPE_HARDWARE,
                nullptr,
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                nullptr,
                0,
                D3D11_SDK_VERSION,
                &device,
                nullptr,
                &context);
            if (FAILED(hr))
                goto fail;

            hr = device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDevice));
            if (FAILED(hr))
                goto fail;

            hr = dxgiDevice->GetAdapter(&adapter);
            if (FAILED(hr))
                goto fail;

            hr = adapter->EnumOutputs(static_cast<UINT>(monitorIndex), &output);
            if (FAILED(hr))
                goto fail;

            output->GetDesc(&outputDesc);
            width = outputDesc.DesktopCoordinates.right - outputDesc.DesktopCoordinates.left;
            height = outputDesc.DesktopCoordinates.bottom - outputDesc.DesktopCoordinates.top;
            cachedPixels.reserve(static_cast<size_t>(width) * height * 4);

            hr = output->QueryInterface(__uuidof(IDXGIOutput1), reinterpret_cast<void**>(&output1));
            if (FAILED(hr))
                goto fail;

            hr = output1->DuplicateOutput(device, &duplication);
            if (FAILED(hr))
                goto fail;

            ReleaseIfSet(output1);
            ReleaseIfSet(output);
            ReleaseIfSet(adapter);
            ReleaseIfSet(dxgiDevice);
            return true;

        fail:
            ReleaseIfSet(output1);
            ReleaseIfSet(output);
            ReleaseIfSet(adapter);
            ReleaseIfSet(dxgiDevice);
            Reset();
            return false;
        }

        bool CopyFrameToCache(IDXGIResource* desktopResource)
        {
            ID3D11Texture2D* gpuTexture = nullptr;
            D3D11_MAPPED_SUBRESOURCE mapped = {};
            D3D11_TEXTURE2D_DESC desc = {};
            std::vector<uint8_t> framePixels;

            HRESULT hr = desktopResource->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&gpuTexture));
            if (FAILED(hr))
                goto fail;

            gpuTexture->GetDesc(&desc);

            if (!stagingTexture || stagingDesc.Width != desc.Width || stagingDesc.Height != desc.Height)
            {
                ReleaseIfSet(stagingTexture);
                stagingDesc = desc;
                stagingDesc.Usage = D3D11_USAGE_STAGING;
                stagingDesc.BindFlags = 0;
                stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                stagingDesc.MiscFlags = 0;

                hr = device->CreateTexture2D(&stagingDesc, nullptr, &stagingTexture);
                if (FAILED(hr))
                    goto fail;
            }

            context->CopyResource(stagingTexture, gpuTexture);

            hr = context->Map(stagingTexture, 0, D3D11_MAP_READ, 0, &mapped);
            if (FAILED(hr))
                goto fail;

            framePixels.resize(static_cast<size_t>(width) * height * 4);
            for (int y = 0; y < height; y++)
            {
                memcpy(
                    framePixels.data() + static_cast<size_t>(y) * width * 4,
                    static_cast<uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
                    static_cast<size_t>(width) * 4);
            }

            context->Unmap(stagingTexture, 0);
            mapped.pData = nullptr;
            if (IsRgbBlackFrame(framePixels, width, height))
            {
                ReleaseIfSet(gpuTexture);
                return false;
            }

            cachedPixels = std::move(framePixels);
            ReleaseIfSet(gpuTexture);
            return true;

        fail:
            if (stagingTexture && mapped.pData)
                context->Unmap(stagingTexture, 0);
            ReleaseIfSet(gpuTexture);
            return false;
        }

        bool Capture(MonitorCaptureResult& result)
        {
            if (!duplication)
                return false;

            bool gotFrame = false;

            for (int attempt = 0; attempt < 8; attempt++)
            {
                DXGI_OUTDUPL_FRAME_INFO frameInfo = {};
                IDXGIResource* desktopResource = nullptr;
                HRESULT hr = duplication->AcquireNextFrame(16, &frameInfo, &desktopResource);

                if (hr == DXGI_ERROR_WAIT_TIMEOUT)
                    break;

                if (hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_INVALID_CALL)
                {
                    Reset();
                    return false;
                }

                if (FAILED(hr))
                    break;

                gotFrame = CopyFrameToCache(desktopResource);
                ReleaseIfSet(desktopResource);
                duplication->ReleaseFrame();

                if (gotFrame)
                    break;
            }

            if (cachedPixels.empty())
                return false;

            result.pixels = std::move(cachedPixels);
            cachedPixels.clear();
            result.width = width;
            result.height = height;
            return true;
        }
    };

    std::map<int, MonitorCaptureSession> gCaptureSessions;
}

bool ExcludeWindowFromCapture(HWND hwnd)
{
#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif
    return SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) != FALSE;
}

bool IncludeWindowFromCapture(HWND hwnd)
{
    return SetWindowDisplayAffinity(hwnd, WDA_NONE) != FALSE;
}

bool CaptureMonitor(int monitorIndex, MonitorCaptureResult& result)
{
    MonitorCaptureSession& session = gCaptureSessions[monitorIndex];
    if (!session.Initialize(monitorIndex))
        return false;

    if (session.Capture(result))
        return true;

    // Recreate once after access loss, mode changes, or stale duplication state.
    session.Reset();
    if (!session.Initialize(monitorIndex))
        return false;

    return session.Capture(result);
}

bool CaptureMonitorBitmapAlternative(int64_t monitorHandle, MonitorCaptureResult& result)
{
    return TryCaptureMonitorWithGraphicsCapture(
        reinterpret_cast<HMONITOR>(static_cast<LONG_PTR>(monitorHandle)),
        result);
}
