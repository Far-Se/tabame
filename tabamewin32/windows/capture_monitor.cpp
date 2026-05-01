#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdint.h>
#include <cstring>
#include <map>
#include <vector>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

struct MonitorCaptureResult {
    std::vector<uint8_t> pixels; // BGRA, 4 bytes per pixel
    int width;
    int height;
};

namespace
{
    template <typename T>
    void ReleaseIfSet(T*& ptr)
    {
        if (ptr)
        {
            ptr->Release();
            ptr = nullptr;
        }
    }

    bool IsRgbBlackFrame(const std::vector<uint8_t>& pixels)
    {
        for (size_t i = 0; i + 2 < pixels.size(); i += 4)
        {
            if (pixels[i] != 0 || pixels[i + 1] != 0 || pixels[i + 2] != 0)
                return false;
        }
        return !pixels.empty();
    }

    struct MonitorCaptureSession
    {
        ID3D11Device* device = nullptr;
        ID3D11DeviceContext* context = nullptr;
        IDXGIOutputDuplication* duplication = nullptr;
        int width = 0;
        int height = 0;
        std::vector<uint8_t> cachedPixels;

        ~MonitorCaptureSession()
        {
            Reset();
        }

        void Reset()
        {
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
            ID3D11Texture2D* stagingTexture = nullptr;
            D3D11_MAPPED_SUBRESOURCE mapped = {};
            D3D11_TEXTURE2D_DESC desc = {};
            D3D11_TEXTURE2D_DESC stagingDesc = {};
            std::vector<uint8_t> framePixels;

            HRESULT hr = desktopResource->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&gpuTexture));
            if (FAILED(hr))
                goto fail;

            gpuTexture->GetDesc(&desc);

            stagingDesc = desc;
            stagingDesc.Usage = D3D11_USAGE_STAGING;
            stagingDesc.BindFlags = 0;
            stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            stagingDesc.MiscFlags = 0;

            hr = device->CreateTexture2D(&stagingDesc, nullptr, &stagingTexture);
            if (FAILED(hr))
                goto fail;

            context->CopyResource(stagingTexture, gpuTexture);

            hr = context->Map(stagingTexture, 0, D3D11_MAP_READ, 0, &mapped);
            if (FAILED(hr))
                goto fail;

            framePixels.resize(width * height * 4);
            for (int y = 0; y < height; y++)
            {
                memcpy(
                    framePixels.data() + y * width * 4,
                    static_cast<uint8_t*>(mapped.pData) + y * mapped.RowPitch,
                    width * 4);
            }

            context->Unmap(stagingTexture, 0);
            mapped.pData = nullptr;
            if (IsRgbBlackFrame(framePixels))
            {
                ReleaseIfSet(stagingTexture);
                ReleaseIfSet(gpuTexture);
                return false;
            }

            cachedPixels = std::move(framePixels);
            ReleaseIfSet(stagingTexture);
            ReleaseIfSet(gpuTexture);
            return true;

        fail:
            if (stagingTexture && mapped.pData)
                context->Unmap(stagingTexture, 0);
            ReleaseIfSet(stagingTexture);
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

            result.pixels = cachedPixels;
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
