#ifndef TABAMEWIN32_AUDIO
#define TABAMEWIN32_AUDIO
#include <windows.h>

#include <ole2.h>
#include <ShellAPI.h>
#include <olectl.h>
#include <mmdeviceapi.h>
#include <Audioclient.h>
#include <propsys.h>
#include <propvarutil.h>
#include <stdio.h>
#include <Functiondiscoverykeys_devpkey.h>
#include <atlstr.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <memory>
#include <sstream>
#include "include/Policyconfig.h"
#include "include/encoding.h"

#pragma warning(push)
#pragma warning(disable : 4201)
#include <endpointvolume.h>

#include <audiopolicy.h>
#include <psapi.h>
#include <TlHelp32.h>

#pragma warning(pop)
#pragma comment(lib, "ole32")
#pragma comment(lib, "propsys")
using namespace std;

bool aDebugging = false;
std::string debFile = "";

void appendDebugFile(const std::string name, const std::string content)
{
    if (aDebugging == false)
        return;
    std::ofstream outfile;
    outfile.open(name, std::ios_base::app);
    outfile << content << endl;
    outfile.close();
}
void setAudioDebugInfo(string debugFi)
{
    aDebugging = true;
    debFile = debugFi;
}

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
struct ProcessVolume
{
    int processId = 0;
    std::string processPath = "";
    float maxVolume = 1.0;
    float peakVolume = 0.0;
};

struct DeviceProps
{
    wstring id = L"00x";
    string name = "Missing";
    string iconInfo = "missing,0";
    bool isActive = false;
};

static HRESULT getDeviceProperty(IMMDevice *pDevice, DeviceProps *output)
{
    HRESULT hr = (HRESULT) false;
    try
    {
        appendDebugFile(debFile, "getDevProp");
        IPropertyStore *pStore = NULL;
        appendDebugFile(debFile, "getDevProp: Store Init");
        hr = pDevice->OpenPropertyStore(STGM_READ, &pStore);
        if (SUCCEEDED(hr))
        {
            PROPVARIANT prop;
            appendDebugFile(debFile, "getDevProp: Get PKEY_Device_FriendlyName");
            PropVariantInit(&prop);
            appendDebugFile(debFile, "getDevProp: Prop Variant");
            hr = pStore->GetValue(PKEY_Device_FriendlyName, &prop);
            if (SUCCEEDED(hr))
            {
                string result;

                result = CW2A((LPCWSTR)prop.pwszVal);
                output->name = result;
            }
            PROPVARIANT prop2;
            appendDebugFile(debFile, "getDevProp: PKEY_DeviceClass_IconPath");
            PropVariantInit(&prop2);
            appendDebugFile(debFile, "getDevProp: Str Prop Variant");
            hr = pStore->GetValue(PKEY_DeviceClass_IconPath, &prop2);
            if (SUCCEEDED(hr))
            {
                string result;

                result = CW2A((LPCWSTR)prop2.pwszVal);
                output->iconInfo = result;
            }
            PropVariantClear(&prop);
            PropVariantClear(&prop2);
            appendDebugFile(debFile, "getDevProp: Release");
            pStore->Release();
        }
    }
    catch (...)
    {
        appendDebugFile(debFile, "Audio: getDevProp Throw exception");
    }
    // delete pStore;
    return hr;
}

std::vector<DeviceProps> EnumAudioDevices(EDataFlow deviceType = eRender)
{
    std::vector<DeviceProps> output;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            LPWSTR activeID;
            pActive->GetId(&activeID);
            wstring activeDevID(activeID);

            pActive->Release();

            IMMDeviceCollection *pCollection = NULL;
            hr = pEnumerator->EnumAudioEndpoints(deviceType, DEVICE_STATE_ACTIVE, &pCollection);
            if (SUCCEEDED(hr))
            {
                UINT cEndpoints = 0;
                hr = pCollection->GetCount(&cEndpoints);
                if (SUCCEEDED(hr))
                {
                    for (UINT n = 0; SUCCEEDED(hr) && n < cEndpoints; ++n)
                    {
                        IMMDevice *pDevice = NULL;
                        hr = pCollection->Item(n, &pDevice);
                        if (SUCCEEDED(hr))
                        {
                            DeviceProps device;
                            getDeviceProperty(pDevice, &device);

                            LPWSTR id;
                            pDevice->GetId(&id);
                            wstring currentID(id);
                            device.id = currentID;

                            if (currentID.compare(activeDevID) == 0)
                                device.isActive = true;
                            else
                                device.isActive = false;
                            output.push_back(device);
                            pDevice->Release();
                        }
                    }
                }
                pCollection->Release();
            }
            pEnumerator->Release();
        }
    }
    CoUninitialize();
    return output;
}

DeviceProps getDefaultDevice(EDataFlow deviceType = eRender)
{
    std::vector<DeviceProps> output;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            DeviceProps activeDevice;
            getDeviceProperty(pActive, &activeDevice);
            LPWSTR aid;
            pActive->GetId(&aid);
            activeDevice.id = aid;
            pEnumerator->Release();
            CoUninitialize();

            return activeDevice;
        }
        pEnumerator->Release();
    }
    CoUninitialize();
    return DeviceProps();
}

static HRESULT setDefaultDevice(LPWSTR devID, bool console, bool multimedia, bool communications)
{
    IPolicyConfigVista *pPolicyConfig = nullptr;

    HRESULT hr = CoCreateInstance(__uuidof(CPolicyConfigVistaClient),
                                  NULL, CLSCTX_ALL, __uuidof(IPolicyConfigVista), (LPVOID *)&pPolicyConfig);
    if (SUCCEEDED(hr))
    {
        if (console)
            hr = pPolicyConfig->SetDefaultEndpoint(devID, eConsole);
        if (multimedia)
            hr = pPolicyConfig->SetDefaultEndpoint(devID, eMultimedia);
        if (communications)
            hr = pPolicyConfig->SetDefaultEndpoint(devID, eCommunications);
        pPolicyConfig->Release();
    }
    return hr;
}

float getVolume(EDataFlow deviceType = eRender)
{
    std::vector<DeviceProps> output;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            LPWSTR aid;
            pActive->GetId(&aid);

            IAudioEndpointVolume *m_spVolumeControl = NULL;
            hr = pActive->Activate(__uuidof(m_spVolumeControl), CLSCTX_INPROC_SERVER, NULL, (void **)&m_spVolumeControl);
            if (SUCCEEDED(hr))
            {
                float volumeLevel = 0.0;
                m_spVolumeControl->GetMasterVolumeLevelScalar(&volumeLevel);

                m_spVolumeControl->Release();
                pActive->Release();
                pEnumerator->Release();
                CoUninitialize();
                return volumeLevel;
            }
        }
    }
    CoUninitialize();
    return 0.0;
}

bool registerNotificationCallback(EDataFlow deviceType = eRender)
{
    std::vector<DeviceProps> output;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            IMMNotificationClient *pNotify = NULL;
            pEnumerator->RegisterEndpointNotificationCallback(pNotify);
            pEnumerator->Release();
        }
    }
    CoUninitialize();
    return 0.0;
}

bool setMuteAudioDevice(bool muteState, EDataFlow deviceType = eRender)
{

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            LPWSTR aid;
            pActive->GetId(&aid);

            IAudioEndpointVolume *m_spVolumeControl = NULL;
            hr = pActive->Activate(__uuidof(m_spVolumeControl), CLSCTX_INPROC_SERVER, NULL, (void **)&m_spVolumeControl);
            if (SUCCEEDED(hr))
            {
                m_spVolumeControl->SetMute(muteState, NULL);
                m_spVolumeControl->Release();
                pActive->Release();
            }
            pEnumerator->Release();
        }
    }
    CoUninitialize();
    return true;
}

bool getMuteAudioDevice(EDataFlow deviceType = eRender)
{
    BOOL muteState = false;

    appendDebugFile(debFile, "Audio: CoIn");
    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);

    if (SUCCEEDED(hr))
    {

        appendDebugFile(debFile, "Audio: EnumDevice");
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            appendDebugFile(debFile, "Audio: GetDefault endpoint");
            hr = pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            if (SUCCEEDED(hr))
            {
                LPWSTR aid;

                appendDebugFile(debFile, "Audio: getID");
                pActive->GetId(&aid);

                IAudioEndpointVolume *m_spVolumeControl = NULL;

                appendDebugFile(debFile, "Audio: Activate");
                hr = pActive->Activate(__uuidof(m_spVolumeControl), CLSCTX_INPROC_SERVER, NULL, (void **)&m_spVolumeControl);
                if (SUCCEEDED(hr))
                {

                    appendDebugFile(debFile, "Audio: GetMute");
                    m_spVolumeControl->GetMute(&muteState);

                    appendDebugFile(debFile, "Audio: Release");
                    m_spVolumeControl->Release();
                    pActive->Release();
                    pEnumerator->Release();
                    return muteState;
                }
            }
            pEnumerator->Release();
        }
    }
    CoUninitialize();
    return muteState;
}

bool canAccessAudio(EDataFlow deviceType = eRender)
{
    BOOL muteState = false;

    appendDebugFile(debFile, "Audio: CanAccessAudio CoInitializeEx");
    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);

    if (!SUCCEEDED(hr))
    {
        CoUninitialize();
        return false;
    }

    appendDebugFile(debFile, "Audio: EnumDevice");
    IMMDeviceEnumerator *pEnumerator = NULL;
    hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
    if (!SUCCEEDED(hr))
        return false;
    IMMDevice *pActive = NULL;

    appendDebugFile(debFile, "Audio: GetDefault endpoint");
    hr = pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
    if (!SUCCEEDED(hr))
        return false;
    LPWSTR aid;

    appendDebugFile(debFile, "Audio: getID");
    hr = pActive->GetId(&aid);
    if (!SUCCEEDED(hr))
        return false;

    IAudioEndpointVolume *m_spVolumeControl = NULL;

    appendDebugFile(debFile, "Audio: Activate");
    hr = pActive->Activate(__uuidof(m_spVolumeControl), CLSCTX_INPROC_SERVER, NULL, (void **)&m_spVolumeControl);
    if (!SUCCEEDED(hr))
        return false;

    appendDebugFile(debFile, "Audio: GetMute");
    m_spVolumeControl->GetMute(&muteState);

    appendDebugFile(debFile, "Audio: Release");
    m_spVolumeControl->Release();
    pActive->Release();
    pEnumerator->Release();
    CoUninitialize();
    return true;
}
bool setVolume(float volumeLevel, EDataFlow deviceType = eRender)
{
    std::vector<DeviceProps> output;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            LPWSTR aid;
            pActive->GetId(&aid);
            IAudioEndpointVolume *m_spVolumeControl = NULL;
            hr = pActive->Activate(__uuidof(m_spVolumeControl), CLSCTX_INPROC_SERVER, NULL, (void **)&m_spVolumeControl);
            if (SUCCEEDED(hr))
            {
                if (volumeLevel > 1)
                    volumeLevel = volumeLevel / 100;
                m_spVolumeControl->SetMasterVolumeLevelScalar((float)volumeLevel, NULL);
                m_spVolumeControl->Release();
                pActive->Release();
                pEnumerator->Release();
            }
        }
    }
    CoUninitialize();
    return true;
}

static bool switchDefaultDevice(EDataFlow deviceType, bool console, bool multimedia, bool communications)
{
    std::vector<DeviceProps> result = EnumAudioDevices(deviceType);
    if (!result.empty())
    {
        std::wstring activateID(L"");
        for (const auto &device : result)
        {
            if (activateID == L"x")
            {
                activateID = device.id;
                break;
            }
            if (device.isActive)
                activateID = L"x";
        }
        if (activateID == L"x" || activateID == L"")
            activateID = result[0].id;
        setDefaultDevice((LPWSTR)activateID.c_str(), console, multimedia, communications);
        return true;
    }
    return false;
}

///? Audio Session

IAudioSessionEnumerator *GetAudioSessionEnumerator()
{
    IMMDeviceEnumerator *deviceEnumerator = nullptr;
    HRESULT x = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IMMDeviceEnumerator), (LPVOID *)&deviceEnumerator);
    if (x)
    {
    }
    IMMDevice *device = nullptr;
    deviceEnumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);

    IAudioSessionManager2 *sessionManager = nullptr;
    device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, (void **)&sessionManager);

    IAudioSessionEnumerator *enumerator = nullptr;
    sessionManager->GetSessionEnumerator(&enumerator);

    deviceEnumerator->Release();
    device->Release();
    sessionManager->Release();

    return enumerator;
}

std::string GetProcessNameFromPid(DWORD pid)
{
    std::string name;

    HANDLE handle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (handle)
    {
        TCHAR buffer[MAX_PATH];
        if (GetModuleFileNameEx(handle, NULL, buffer, sizeof(buffer)))
        {
            CloseHandle(handle);
            wstring test(&buffer[0]); // convert to wstring
            std::string buff(Encoding::WideToUtf8(test));
            return buff;
        }
    }
    CloseHandle(handle);

    return std::move(name);
}

float getSetProcessMasterVolume(IAudioSessionControl *session, float volume = 0.0)
{
    ISimpleAudioVolume *info = nullptr;
    session->QueryInterface(__uuidof(ISimpleAudioVolume), (void **)&info);
    if (volume != 0.00)
    {
        info->SetMasterVolume(volume, NULL);
    }
    float maxVolume;
    info->GetMasterVolume(&maxVolume);
    info->Release();
    info = nullptr;

    return maxVolume;
}

float GetPeakVolumeFromAudioSessionControl(IAudioSessionControl *session)
{
    IAudioMeterInformation *info = nullptr;
    session->QueryInterface(__uuidof(IAudioMeterInformation), (void **)&info);

    float peakVolume;
    info->GetPeakValue(&peakVolume);

    info->Release();
    info = nullptr;

    return peakVolume;
}

std::vector<ProcessVolume> GetProcessVolumes(int pID = 0, float volume = 0.0)
{
    std::vector<ProcessVolume> volumes;

    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (hr)
    {
        IAudioSessionEnumerator *enumerator = GetAudioSessionEnumerator();
        int sessionCount;
        enumerator->GetCount(&sessionCount);
        for (int index = 0; index < sessionCount; index++)
        {
            IAudioSessionControl *session = nullptr;
            IAudioSessionControl2 *session2 = nullptr;
            enumerator->GetSession(index, &session);
            session->QueryInterface(__uuidof(IAudioSessionControl2), (void **)&session2);

            DWORD id = 0;
            session2->GetProcessId(&id);
            std::string processPath = "";
            if ((int)id != 0)
                processPath = GetProcessNameFromPid(id);
            else
            {
                session2->Release();
                session->Release();
                continue;
            }
            if (pID == (int)id && volume != 0.00)
            {
                // getSetProcessMasterVolume(session, volume);
                std::vector<ProcessVolume> volumes2;
                ProcessVolume data;
                data.processPath = processPath;
                data.processId = (int)id;
                data.maxVolume = getSetProcessMasterVolume(session, volume);
                data.peakVolume = 0;
                session2->Release();
                session->Release();
                volumes2.push_back(data);
                CoUninitialize();
                return volumes2;
                break;
            }
            float maxVolume = getSetProcessMasterVolume(session);
            float peakVolume = GetPeakVolumeFromAudioSessionControl(session);

            ProcessVolume data;
            data.processPath = processPath;
            data.processId = (int)id;
            data.maxVolume = maxVolume;
            data.peakVolume = peakVolume;

            volumes.push_back(data);
            session2->Release();
            session->Release();
        }
        enumerator->Release();
        if (volume != 0.00)
        {
            return std::vector<ProcessVolume>{};
        }
        CoUninitialize();
        return volumes;
    }
    CoUninitialize();
    return std::vector<ProcessVolume>{};
}
#endif