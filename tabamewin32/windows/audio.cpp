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
#include <endpointvolume.h>
#include "include/Policyconfig.h"
#include "include/encoding.h"
#include <winstring.h>
#include <psapi.h>


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
const IID IID_IAudioEndpointVolume = __uuidof(IAudioEndpointVolume);
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
        if (FAILED(hr) || pStore == NULL)
        {
            pDevice->Release();
            CoUninitialize();
            return hr;
        }
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
    // append debugFile("CoInitializeEx");
    appendDebugFile(debFile, "EnumAudioDevices CoInitializeEx");
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        appendDebugFile(debFile, "EnumAudioDevices CoCreateInstance");
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;

            hr = pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            if (FAILED(hr) || pActive == NULL)
            {
                pEnumerator->Release();
                CoUninitialize();
                return output;
            }
            appendDebugFile(debFile, "EnumAudioDevices GetDefaultAudioEndpoint");

            LPWSTR activeID = nullptr;
            pActive->GetId(&activeID);
            wstring activeDevID(activeID);
            CoTaskMemFree(activeID);

            pActive->Release();

            IMMDeviceCollection *pCollection = NULL;
            hr = pEnumerator->EnumAudioEndpoints(deviceType, DEVICE_STATE_ACTIVE, &pCollection);
            appendDebugFile(debFile, "EnumAudioDevices EnumAudioEndpoints");
            // check if pcollection is empty

            if (pCollection == NULL)
            {
                pEnumerator->Release();
                CoUninitialize();
                return output;
            }

            if (SUCCEEDED(hr))
            {
                UINT cEndpoints = 0;
                hr = pCollection->GetCount(&cEndpoints);
                appendDebugFile(debFile, "EnumAudioDevices GetCount");
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

                            LPWSTR id = nullptr;
                            pDevice->GetId(&id);
                            wstring currentID(id);
                            CoTaskMemFree(id);
                            device.id = currentID;

                            device.isActive = (currentID.compare(activeDevID) == 0);
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
    HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr))
    {
        IMMDeviceEnumerator *pEnumerator = NULL;
        hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_IMMDeviceEnumerator, reinterpret_cast<void **>(&pEnumerator));
        if (SUCCEEDED(hr))
        {
            IMMDevice *pActive = NULL;
            HRESULT epHr = pEnumerator->GetDefaultAudioEndpoint(deviceType, eMultimedia, &pActive);
            if (FAILED(epHr) || pActive == NULL)
            {
                pEnumerator->Release();
                CoUninitialize();
                return DeviceProps();
            }
            DeviceProps activeDevice;
            getDeviceProperty(pActive, &activeDevice);
            LPWSTR aid = nullptr;
            pActive->GetId(&aid);
            activeDevice.id = aid;
            CoTaskMemFree(aid);
            pActive->Release();
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

// registerNotificationCallback was removed — it registered a null callback
// and returned 0.0 for a bool. Notification callbacks should be implemented
// properly if needed in the future.

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
IAudioSessionEnumerator *GetAudioSessionEnumerator(ERole eRole = eMultimedia)
{
    IMMDeviceEnumerator *deviceEnumerator = nullptr;
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IMMDeviceEnumerator), (LPVOID *)&deviceEnumerator);
    if (FAILED(hr) || !deviceEnumerator) return nullptr;

    IMMDevice *device = nullptr;
    hr = deviceEnumerator->GetDefaultAudioEndpoint(eRender, eRole, &device);
    if (FAILED(hr) || !device)
    {
        deviceEnumerator->Release();
        return nullptr;
    }

    IAudioSessionManager2 *sessionManager = nullptr;
    hr = device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr, (void **)&sessionManager);
    if (FAILED(hr) || !sessionManager)
    {
        device->Release();
        deviceEnumerator->Release();
        return nullptr;
    }

    IAudioSessionEnumerator *enumerator = nullptr;
    hr = sessionManager->GetSessionEnumerator(&enumerator);

    sessionManager->Release();
    device->Release();
    deviceEnumerator->Release();

    return SUCCEEDED(hr) ? enumerator : nullptr;
}

std::string GetProcessNameFromPid(DWORD pid)
{
    std::string path;
    // PROCESS_QUERY_LIMITED_INFORMATION is preferred for QueryFullProcessImageName 
    // and works on elevated processes where PROCESS_QUERY_INFORMATION might fail.
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProcess) hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);

    if (hProcess)
    {
        TCHAR buffer[MAX_PATH];
        DWORD size = MAX_PATH;
        if (QueryFullProcessImageName(hProcess, 0, buffer, &size))
        {
            path = Encoding::WideToUtf8(buffer);
        }
        else if (GetModuleFileNameEx(hProcess, 0, buffer, MAX_PATH))
        {
            path = Encoding::WideToUtf8(buffer);
        }
        CloseHandle(hProcess);
    }
    return path;
}


float getSetProcessMasterVolume(IAudioSessionControl *session, float volume = 0.0)
{
    ISimpleAudioVolume *info = nullptr;
    if (FAILED(session->QueryInterface(__uuidof(ISimpleAudioVolume), (void **)&info)) || !info)
        return 0.0f;

    if (volume != 0.00f)
    {
        info->SetMasterVolume(volume, NULL);
    }
    float maxVolume = 0.0f;
    info->GetMasterVolume(&maxVolume);
    info->Release();
    info = nullptr;

    return maxVolume;
}

float GetPeakVolumeFromAudioSessionControl(IAudioSessionControl *session)
{
    IAudioMeterInformation *info = nullptr;
    if (FAILED(session->QueryInterface(__uuidof(IAudioMeterInformation), (void **)&info)) || !info)
        return 0.0f;

    float peakVolume = 0.0f;
    info->GetPeakValue(&peakVolume);

    info->Release();
    info = nullptr;

    return peakVolume;
}

std::vector<ProcessVolume> GetProcessVolumes(int pID = 0, float volume = 0.0f)
{
    std::vector<ProcessVolume> volumes;

    HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit) && hrInit != RPC_E_CHANGED_MODE)
    {
        // COM not available on this thread
        return volumes;
    }

    IAudioSessionEnumerator *enumerator = GetAudioSessionEnumerator();
    if (!enumerator)
    {
        if (SUCCEEDED(hrInit))
            CoUninitialize();
        return volumes;
    }

    int sessionCount = 0;
    HRESULT hr = enumerator->GetCount(&sessionCount);
    if (FAILED(hr))
    {
        enumerator->Release();
        if (SUCCEEDED(hrInit))
            CoUninitialize();
        return volumes;
    }

    for (int index = 0; index < sessionCount; ++index)
    {
        IAudioSessionControl *session = nullptr;
        hr = enumerator->GetSession(index, &session);
        if (FAILED(hr) || !session)
            continue;

        // Skip inactive/expired sessions
        AudioSessionState state = AudioSessionStateInactive;
        if (SUCCEEDED(session->GetState(&state)))
        {
            if (state != AudioSessionStateActive)
            {
                session->Release();
                continue;
            }
        }

        IAudioSessionControl2 *session2 = nullptr;
        hr = session->QueryInterface(__uuidof(IAudioSessionControl2), (void **)&session2);
        if (FAILED(hr) || !session2)
        {
            session->Release();
            continue;
        }

        // Skip system sounds session if you only want app audio
        hr = session2->IsSystemSoundsSession(); // S_OK = system sounds, S_FALSE = not
        if (hr == S_OK)
        {
            session2->Release();
            session->Release();
            continue;
        }

        DWORD id = 0;
        hr = session2->GetProcessId(&id);
        if (FAILED(hr) || id == 0)
        {
            session2->Release();
            session->Release();
            continue;
        }

        std::string processPath = GetProcessNameFromPid(id);

        // Get peak value for this session
        float peakVolume = 0.0f;
        IAudioMeterInformation *meter = nullptr;
        hr = session->QueryInterface(__uuidof(IAudioMeterInformation), (void **)&meter);
        if (SUCCEEDED(hr) && meter)
        {
            float peak = 0.0f;
            if (SUCCEEDED(meter->GetPeakValue(&peak)))
            {
                // Peak is in [0.0, 1.0] representing the last device period.
                peakVolume = peak;
            }
            meter->Release();
        }

        if (pID == static_cast<int>(id) && volume != 0.0f)
        {
            ProcessVolume data;
            data.processPath = processPath;
            data.processId = static_cast<int>(id);
            data.maxVolume = getSetProcessMasterVolume(session, volume);
            data.peakVolume = peakVolume;

            session2->Release();
            session->Release();
            enumerator->Release();

            if (SUCCEEDED(hrInit))
                CoUninitialize();
            return std::vector<ProcessVolume>{data};
        }

        float maxVolume = getSetProcessMasterVolume(session);

        ProcessVolume data;
        data.processPath = processPath;
        data.processId = static_cast<int>(id);
        data.maxVolume = maxVolume;
        data.peakVolume = peakVolume;

        volumes.push_back(data);

        session2->Release();
        session->Release();
    }

    enumerator->Release();
    if (volume != 0.0f)
    {
        // caller asked to modify a specific PID but it was not found
        if (SUCCEEDED(hrInit))
            CoUninitialize();
        return std::vector<ProcessVolume>{};
    }

    if (SUCCEEDED(hrInit))
        CoUninitialize();
    return volumes;
}

bool setAudioDeviceVolume(float volumeLevel, LPWSTR devID)
{
    HRESULT hr = CoInitialize(NULL);  // Initialize COM library
    if (FAILED(hr)) {
        return false;  // COM initialization failed
    }

    // Create a device enumerator to get access to audio devices
    IMMDeviceEnumerator* pEnumerator = nullptr;
    hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_PPV_ARGS(&pEnumerator));
    if (FAILED(hr)) {
        CoUninitialize();
        return false;  // Failed to create device enumerator
    }

    IMMDevice* pDevice = nullptr;
    hr = pEnumerator->GetDevice(devID, &pDevice);
    if (FAILED(hr)) {
        pEnumerator->Release();
        CoUninitialize();
        return false;  // Failed to get the device by devID
    }

    IAudioEndpointVolume* pAudioVolume = nullptr;
    hr = pDevice->Activate(IID_IAudioEndpointVolume, CLSCTX_ALL, NULL, (void**)&pAudioVolume);
    if (FAILED(hr)) {
        pDevice->Release();
        pEnumerator->Release();
        CoUninitialize();
        return false;  // Failed to activate the audio endpoint volume
    }

    // Set the volume
    hr = pAudioVolume->SetMasterVolumeLevelScalar(volumeLevel, NULL);
    if (FAILED(hr)) {
        pAudioVolume->Release();
        pDevice->Release();
        pEnumerator->Release();
        CoUninitialize();
        return false;  // Failed to set the volume
    }

    // Cleanup
    pAudioVolume->Release();
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();

    return true;
}

bool SetProcessVolumeByPath(ERole eRole, std::string path, float volume)
{
    HRESULT hrInit = CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit) && hrInit != RPC_E_CHANGED_MODE) return false;

    IAudioSessionEnumerator *enumerator = GetAudioSessionEnumerator(eRole);
    if (enumerator)
    {
        int sessionCount = 0;
        if (SUCCEEDED(enumerator->GetCount(&sessionCount)))
        {
            for (int index = 0; index < sessionCount; index++)
            {
                IAudioSessionControl *session = nullptr;
                IAudioSessionControl2 *session2 = nullptr;
                if (FAILED(enumerator->GetSession(index, &session)) || !session) continue;

                if (FAILED(session->QueryInterface(__uuidof(IAudioSessionControl2), (void **)&session2)) || !session2)
                {
                    session->Release();
                    continue;
                }

                DWORD id = 0;
                session2->GetProcessId(&id);
                std::string processPath = "";
                if (id != 0)
                    processPath = GetProcessNameFromPid(id);

                if (id != 0 && path == processPath)
                {
                    getSetProcessMasterVolume(session, volume);
                }

                session2->Release();
                session->Release();
            }
        }
        enumerator->Release();
    }
    
    if (SUCCEEDED(hrInit)) CoUninitialize();
    return true;
}


float getAudioDeviceVolume(LPWSTR devID)
{
    float volumeLevel = 0.0f;
    HRESULT hr = CoInitialize(NULL);
    if (FAILED(hr)) return volumeLevel;

    IMMDeviceEnumerator* pEnumerator = nullptr;
    hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, IID_PPV_ARGS(&pEnumerator));
    if (FAILED(hr)) { CoUninitialize(); return volumeLevel; }

    IMMDevice* pDevice = nullptr;
    hr = pEnumerator->GetDevice(devID, &pDevice);
    if (FAILED(hr)) { pEnumerator->Release(); CoUninitialize(); return volumeLevel; }

    IAudioEndpointVolume* pAudioVolume = nullptr;
    hr = pDevice->Activate(IID_IAudioEndpointVolume, CLSCTX_ALL, NULL, (void**)&pAudioVolume);
    if (FAILED(hr)) {
        pDevice->Release();
        pEnumerator->Release();
        CoUninitialize();
        return volumeLevel;
    }

    pAudioVolume->GetMasterVolumeLevelScalar(&volumeLevel);

    pAudioVolume->Release();
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();

    return volumeLevel;
}
#endif