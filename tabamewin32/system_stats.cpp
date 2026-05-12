// Windows only
// Requires:
//   pdh.lib
//   wbemuuid.lib
//
// Build:
//   cl /EHsc monitor.cpp pdh.lib wbemuuid.lib

#include <windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <wbemidl.h>
#include <comdef.h>

#include <iostream>
#include <string>
#include <vector>

#pragma comment(lib, "pdh.lib")
#pragma comment(lib, "wbemuuid.lib")

struct SystemStats
{
    double cpuUsage;
    double gpuUsage;
    double cpuTemp;
    double gpuTemp;
};

class HardwareMonitor
{
private:
    PDH_HQUERY cpuQuery = nullptr;
    PDH_HCOUNTER cpuTotal = nullptr;

    PDH_HQUERY gpuQuery = nullptr;
    std::vector<PDH_HCOUNTER> gpuCounters;

public:
    HardwareMonitor()
    {
        InitCPU();
        InitGPU();
    }

    ~HardwareMonitor()
    {
        if (cpuQuery)
            PdhCloseQuery(cpuQuery);

        if (gpuQuery)
            PdhCloseQuery(gpuQuery);
    }

    bool InitCPU()
    {
        if (PdhOpenQuery(NULL, NULL, &cpuQuery) != ERROR_SUCCESS)
            return false;

        if (PdhAddEnglishCounter(
                cpuQuery,
                L"\\Processor(_Total)\\% Processor Time",
                NULL,
                &cpuTotal) != ERROR_SUCCESS)
            return false;

        PdhCollectQueryData(cpuQuery);

        return true;
    }

    bool InitGPU()
    {
        if (PdhOpenQuery(NULL, NULL, &gpuQuery) != ERROR_SUCCESS)
            return false;

        DWORD bufferSize = 0;
        DWORD itemCount = 0;

        PDH_STATUS status = PdhEnumObjectItems(
            NULL,
            NULL,
            L"GPU Engine",
            NULL,
            &bufferSize,
            NULL,
            &itemCount,
            PERF_DETAIL_WIZARD,
            0);

        if (status != PDH_MORE_DATA)
            return false;

        std::vector<wchar_t> buffer(bufferSize);

        status = PdhEnumObjectItems(
            NULL,
            NULL,
            L"GPU Engine",
            buffer.data(),
            &bufferSize,
            NULL,
            &itemCount,
            PERF_DETAIL_WIZARD,
            0);

        if (status != ERROR_SUCCESS)
            return false;

        wchar_t* ptr = buffer.data();

        while (*ptr)
        {
            std::wstring instance = ptr;

            if (instance.find(L"engtype_3D") != std::wstring::npos)
            {
                std::wstring path =
                    L"\\GPU Engine(" + instance + L")\\Utilization Percentage";

                PDH_HCOUNTER counter;

                if (PdhAddEnglishCounter(
                        gpuQuery,
                        path.c_str(),
                        NULL,
                        &counter) == ERROR_SUCCESS)
                {
                    gpuCounters.push_back(counter);
                }
            }

            ptr += instance.size() + 1;
        }

        PdhCollectQueryData(gpuQuery);

        return true;
    }

    double GetCPUUsage()
    {
        PDH_FMT_COUNTERVALUE counterVal;

        PdhCollectQueryData(cpuQuery);

        if (PdhGetFormattedCounterValue(
                cpuTotal,
                PDH_FMT_DOUBLE,
                NULL,
                &counterVal) != ERROR_SUCCESS)
        {
            return -1.0;
        }

        return counterVal.doubleValue;
    }

    double GetGPUUsage()
    {
        PdhCollectQueryData(gpuQuery);

        double total = 0.0;

        for (auto& counter : gpuCounters)
        {
            PDH_FMT_COUNTERVALUE value;

            if (PdhGetFormattedCounterValue(
                    counter,
                    PDH_FMT_DOUBLE,
                    NULL,
                    &value) == ERROR_SUCCESS)
            {
                total += value.doubleValue;
            }
        }

        return total;
    }

    double ReadWMITemperature(const wchar_t* sensorName)
    {
        HRESULT hres;

        hres = CoInitializeEx(0, COINIT_MULTITHREADED);

        if (FAILED(hres) && hres != RPC_E_CHANGED_MODE)
            return -1.0;

        hres = CoInitializeSecurity(
            NULL,
            -1,
            NULL,
            NULL,
            RPC_C_AUTHN_LEVEL_DEFAULT,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            NULL,
            EOAC_NONE,
            NULL);

        IWbemLocator* pLoc = NULL;

        hres = CoCreateInstance(
            CLSID_WbemLocator,
            0,
            CLSCTX_INPROC_SERVER,
            IID_IWbemLocator,
            (LPVOID*)&pLoc);

        if (FAILED(hres))
            return -1.0;

        IWbemServices* pSvc = NULL;

        hres = pLoc->ConnectServer(
            _bstr_t(L"ROOT\\WMI"),
            NULL,
            NULL,
            0,
            NULL,
            0,
            0,
            &pSvc);

        if (FAILED(hres))
        {
            pLoc->Release();
            return -1.0;
        }

        hres = CoSetProxyBlanket(
            pSvc,
            RPC_C_AUTHN_WINNT,
            RPC_C_AUTHZ_NONE,
            NULL,
            RPC_C_AUTHN_LEVEL_CALL,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            NULL,
            EOAC_NONE);

        IEnumWbemClassObject* pEnumerator = NULL;

        hres = pSvc->ExecQuery(
            bstr_t("WQL"),
            bstr_t("SELECT * FROM MSAcpi_ThermalZoneTemperature"),
            WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
            NULL,
            &pEnumerator);

        if (FAILED(hres))
        {
            pSvc->Release();
            pLoc->Release();
            return -1.0;
        }

        IWbemClassObject* pclsObj = NULL;
        ULONG uReturn = 0;

        double temperature = -1.0;

        while (pEnumerator)
        {
            HRESULT hr = pEnumerator->Next(
                WBEM_INFINITE,
                1,
                &pclsObj,
                &uReturn);

            if (0 == uReturn)
                break;

            VARIANT vtProp;

            hr = pclsObj->Get(L"CurrentTemperature", 0, &vtProp, 0, 0);

            if (SUCCEEDED(hr))
            {
                temperature =
                    ((double)vtProp.uintVal / 10.0) - 273.15;

                VariantClear(&vtProp);
                pclsObj->Release();
                break;
            }

            pclsObj->Release();
        }

        pSvc->Release();
        pLoc->Release();
        pEnumerator->Release();

        return temperature;
    }

    double GetCPUTemp()
    {
        return ReadWMITemperature(L"CPU");
    }

    double GetGPUTemp()
    {
        return ReadWMITemperature(L"GPU");
    }

    SystemStats GetStats(bool onlyUsage)
    {
        SystemStats stats;

        stats.cpuUsage = GetCPUUsage();
        stats.gpuUsage = GetGPUUsage();
        if(onlyUsage)
        {
            stats.cpuTemp = 0;
            stats.gpuTemp = 0;
            return stats;
        }
        stats.cpuTemp = GetCPUTemp();
        stats.gpuTemp = GetGPUTemp();
        return stats;
    }
};

// int main()
// {
//     HardwareMonitor monitor;

//     Sleep(1000);

//     SystemStats stats = monitor.GetStats();

//     std::cout << "CPU Usage: " << stats.cpuUsage << "%\n";
//     std::cout << "GPU Usage: " << stats.gpuUsage << "%\n";
//     std::cout << "CPU Temp : " << stats.cpuTemp << " C\n";
//     std::cout << "GPU Temp : " << stats.gpuTemp << " C\n";

//     return 0;
// }
