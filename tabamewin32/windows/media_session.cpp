#include <windows.h>

#include <flutter/encodable_value.h>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>

#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

namespace MediaSession
{
    namespace
    {
        std::string WStringToString(const std::wstring &wstr)
        {
            if (wstr.empty())
                return {};

            const int size = WideCharToMultiByte(
                CP_UTF8,
                0,
                wstr.data(),
                static_cast<int>(wstr.size()),
                nullptr,
                0,
                nullptr,
                nullptr);

            std::string result(size, '\0');
            WideCharToMultiByte(
                CP_UTF8,
                0,
                wstr.data(),
                static_cast<int>(wstr.size()),
                result.data(),
                size,
                nullptr,
                nullptr);
            return result;
        }

        std::string HStringToString(const winrt::hstring &hstr)
        {
            return WStringToString(std::wstring(hstr));
        }

        std::string PlaybackStatusToString(
            winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus status)
        {
            using Status = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;

            switch (status)
            {
                case Status::Playing:
                    return "Playing";
                case Status::Paused:
                    return "Paused";
                case Status::Stopped:
                    return "Stopped";
                case Status::Changing:
                    return "Changing";
                case Status::Closed:
                    return "Closed";
                default:
                    return "Unknown";
            }
        }

        std::vector<uint8_t> ReadStreamReference(
            const winrt::Windows::Storage::Streams::IRandomAccessStreamReference &streamRef)
        {
            if (!streamRef)
                return {};

            try
            {
                auto stream = streamRef.OpenReadAsync().get();
                if (!stream)
                    return {};

                const uint64_t size = stream.Size();
                if (size == 0 || size > 10 * 1024 * 1024)
                    return {};

                winrt::Windows::Storage::Streams::DataReader reader(stream);
                reader.LoadAsync(static_cast<uint32_t>(size)).get();

                std::vector<uint8_t> bytes(static_cast<size_t>(size));
                reader.ReadBytes(bytes);
                return bytes;
            }
            catch (...)
            {
                return {};
            }
        }
    } // namespace

    flutter::EncodableValue GetMediaSessions()
    {
        using flutter::EncodableList;
        using flutter::EncodableMap;
        using flutter::EncodableValue;
        using Manager = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;

        EncodableList sessionList;
        EncodableValue currentSessionId;

        try
        {
            auto manager = Manager::RequestAsync().get();
            auto currentSession = manager.GetCurrentSession();

            std::string currentId;
            if (currentSession)
            {
                currentId = HStringToString(currentSession.SourceAppUserModelId());
                currentSessionId = EncodableValue(currentId);
            }

            auto sessions = manager.GetSessions();
            const auto sessionCount = sessions.Size();
            for (uint32_t index = 0; index < sessionCount; ++index)
            {
                auto session = sessions.GetAt(index);
                EncodableMap entry;

                const std::string sessionId = HStringToString(session.SourceAppUserModelId());
                entry[EncodableValue("id")] = EncodableValue(sessionId);
                entry[EncodableValue("isCurrent")] = EncodableValue(sessionId == currentId);

                const auto playbackInfo = session.GetPlaybackInfo();
                const auto controls = playbackInfo.Controls();
                entry[EncodableValue("playbackStatus")] =
                    EncodableValue(PlaybackStatusToString(playbackInfo.PlaybackStatus()));
                entry[EncodableValue("canPlay")] = EncodableValue(controls.IsPlayEnabled());
                entry[EncodableValue("canPause")] = EncodableValue(controls.IsPauseEnabled());
                entry[EncodableValue("canSkipNext")] = EncodableValue(controls.IsNextEnabled());
                entry[EncodableValue("canSkipPrevious")] = EncodableValue(controls.IsPreviousEnabled());

                try
                {
                    const auto props = session.TryGetMediaPropertiesAsync().get();
                    if (props)
                    {
                        entry[EncodableValue("title")] = EncodableValue(HStringToString(props.Title()));
                        entry[EncodableValue("artist")] = EncodableValue(HStringToString(props.Artist()));
                        entry[EncodableValue("albumTitle")] = EncodableValue(HStringToString(props.AlbumTitle()));
                        entry[EncodableValue("albumArtist")] = EncodableValue(HStringToString(props.AlbumArtist()));
                        entry[EncodableValue("trackNumber")] =
                            EncodableValue(static_cast<int>(props.TrackNumber()));

                        const auto thumbnail = ReadStreamReference(props.Thumbnail());
                        if (!thumbnail.empty())
                        {
                            entry[EncodableValue("thumbnail")] = EncodableValue(thumbnail);
                        }
                        else
                        {
                            entry[EncodableValue("thumbnail")] = EncodableValue();
                        }
                    }
                }
                catch (...)
                {
                    entry[EncodableValue("title")] = EncodableValue(std::string{});
                    entry[EncodableValue("artist")] = EncodableValue(std::string{});
                    entry[EncodableValue("albumTitle")] = EncodableValue(std::string{});
                    entry[EncodableValue("albumArtist")] = EncodableValue(std::string{});
                    entry[EncodableValue("trackNumber")] = EncodableValue(0);
                    entry[EncodableValue("thumbnail")] = EncodableValue();
                }

                sessionList.emplace_back(entry);
            }
        }
        catch (const winrt::hresult_error &ex)
        {
            std::ostringstream oss;
            oss << "WinRT error 0x" << std::hex << static_cast<uint32_t>(ex.code().value) << ": "
                << HStringToString(ex.message());
            return EncodableValue(EncodableMap{
                {EncodableValue("error"), EncodableValue(oss.str())},
            });
        }

        return EncodableValue(EncodableMap{
            {EncodableValue("currentSessionId"), currentSessionId},
            {EncodableValue("sessions"), EncodableValue(sessionList)},
        });
    }
} // namespace MediaSession
