#include "src/player/mpvplayersession.h"

#include <optional>
#include <stdexcept>

#include <QGuiApplication>
#include <QMetaObject>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QStringList>
#include <QTimer>
#include <QtMath>

#include "src/common/qthelper.hpp"
#include "src/player/mpvtrackmapper.h"

namespace
{

Q_LOGGING_CATEGORY(lzcPlayerMpvSessionLog, "lzc-player.mpv-session")

QString normalizedLanguage(QString language)
{
    language = language.trimmed().toLower();
    language.replace(QLatin1Char('_'), QLatin1Char('-'));
    return language;
}

void applyNetworkOptions(mpv_handle *mpv)
{
    const QString headerFields = qEnvironmentVariable("LZC_PLAYER_HTTP_HEADER_FIELDS");
    const QString cookie = qApp->property("lzcPlayerCookie").toString();

    if (!headerFields.isEmpty())
    {
        mpv_set_option_string(mpv, "http-header-fields", headerFields.toUtf8().constData());
    }
    else if (!cookie.isEmpty())
    {
        const QString cookieHeader = QStringLiteral("Cookie: %1").arg(cookie);
        mpv_set_option_string(mpv, "http-header-fields", cookieHeader.toUtf8().constData());
    }
}

void applyIpcServerOption(mpv_handle *mpv)
{
    const QString ipcServer = qApp->property("lzcPlayerInputIpcServer").toString();
    if (!ipcServer.isEmpty())
    {
        const QByteArray ipcServerUtf8 = ipcServer.toUtf8();
        qInfo(lzcPlayerMpvSessionLog) << "Configuring mpv input IPC server:" << ipcServer;

        const int err = mpv_set_option_string(mpv, "input-ipc-server", ipcServerUtf8.constData());
        if (err < 0)
        {
            qWarning(lzcPlayerMpvSessionLog)
                << "Failed to set mpv input-ipc-server to" << ipcServer
                << "error:" << err
                << mpv_error_string(err);
            return;
        }

        qInfo(lzcPlayerMpvSessionLog) << "Configured mpv input-ipc-server:" << ipcServer;
    }
    else
    {
        qInfo(lzcPlayerMpvSessionLog) << "mpv input IPC server is not configured";
    }
}

void scheduleIpcSocketProbe(const QString &ipcServer)
{
    if (ipcServer.isEmpty())
    {
        return;
    }

    QTimer::singleShot(1000, qApp, [ipcServer]() {
        const QFileInfo ipcInfo(ipcServer);
        qInfo(lzcPlayerMpvSessionLog)
            << "Checked mpv IPC socket path:" << ipcServer
            << "exists:" << ipcInfo.exists()
            << "absolute path:" << ipcInfo.absoluteFilePath();
    });
}

std::optional<double> parseTimestampToSeconds(const QString &position)
{
    const QStringList parts = position.split(QLatin1Char(':'), Qt::KeepEmptyParts);
    if (parts.isEmpty() || parts.size() > 3)
    {
        return std::nullopt;
    }

    double totalSeconds = 0.0;
    for (const QString &part : parts)
    {
        bool ok = false;
        const double value = part.toDouble(&ok);
        if (!ok || value < 0.0)
        {
            return std::nullopt;
        }

        totalSeconds = (totalSeconds * 60.0) + value;
    }

    return totalSeconds;
}

} // namespace

MpvPlayerSession::MpvPlayerSession(QObject *parent)
    : QObject(parent),
      mpv(mpv_create()),
      m_paused(true),
      m_timePos(0.0),
      m_duration(0.0),
      m_bufferDuration(0.0),
      m_bufferEnd(0.0),
      m_loading(false),
      m_fileLoading(false),
      m_buffering(false),
      m_seeking(false),
      m_hasMedia(false),
      m_bufferingProgress(0.0),
      m_playbackSpeed(1.0),
      m_volume(100.0),
      m_videoId(0),
      m_subtitleId(0),
      m_consoleOpen(false),
      m_reachedEof(false),
      m_hasSubtitlePreference(false),
      m_preferSubtitlesOff(false),
      m_waitingToApplySubtitlePreference(false)
{
    if (!mpv)
    {
        throw std::runtime_error("could not create mpv context");
    }

    mpv_set_option_string(mpv, "terminal", "yes");
    mpv_set_option_string(mpv, "msg-level", "all=v");
    mpv_set_option_string(mpv, "hwdec", "auto");
    mpv_set_option_string(mpv, "gpu-context", "auto");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "keep-open", "yes");
    mpv_set_option_string(mpv, "video-sync", "display-resample");
    mpv_set_option_string(mpv, "interpolation", "yes");
    applyNetworkOptions(mpv);
    applyIpcServerOption(mpv);

    const int initErr = mpv_initialize(mpv);
    if (initErr < 0)
    {
        qWarning(lzcPlayerMpvSessionLog)
            << "Failed to initialize mpv context:"
            << initErr
            << mpv_error_string(initErr);
        throw std::runtime_error("could not initialize mpv context");
    }

    scheduleIpcSocketProbe(qApp->property("lzcPlayerInputIpcServer").toString());
    observeProperties();
    mpv_set_wakeup_callback(mpv, MpvPlayerSession::onMpvEvents, this);
}

MpvPlayerSession::~MpvPlayerSession()
{
    mpv_terminate_destroy(mpv);
}

mpv_handle *MpvPlayerSession::handle() const
{
    return mpv;
}

bool MpvPlayerSession::isPlaying() const
{
    return !m_paused;
}

double MpvPlayerSession::timePos() const
{
    return m_timePos;
}

double MpvPlayerSession::duration() const
{
    return m_duration;
}

double MpvPlayerSession::bufferDuration() const
{
    return m_bufferDuration;
}

double MpvPlayerSession::bufferEnd() const
{
    return m_bufferEnd;
}

bool MpvPlayerSession::loading() const
{
    return m_loading;
}

bool MpvPlayerSession::buffering() const
{
    return m_buffering;
}

bool MpvPlayerSession::seeking() const
{
    return m_seeking;
}

bool MpvPlayerSession::hasMedia() const
{
    return m_hasMedia;
}

double MpvPlayerSession::bufferingProgress() const
{
    return m_bufferingProgress;
}

double MpvPlayerSession::playbackSpeed() const
{
    return m_playbackSpeed;
}

double MpvPlayerSession::volume() const
{
    return m_volume;
}

QString MpvPlayerSession::qualityLabel() const
{
    return m_qualityLabel;
}

QVariantList MpvPlayerSession::videoTracks() const
{
    return m_videoTracks;
}

int MpvPlayerSession::videoId() const
{
    return m_videoId;
}

QVariantList MpvPlayerSession::subtitleTracks() const
{
    return m_subtitleTracks;
}

int MpvPlayerSession::subtitleId() const
{
    return m_subtitleId;
}

bool MpvPlayerSession::consoleOpen() const
{
    return m_consoleOpen;
}

void MpvPlayerSession::onMpvEvents(void *ctx)
{
    auto *self = static_cast<MpvPlayerSession *>(ctx);
    QMetaObject::invokeMethod(self, &MpvPlayerSession::processMpvEvents, Qt::QueuedConnection);
}

void MpvPlayerSession::loadFile(const QString &path)
{
    if (path.isEmpty())
    {
        return;
    }

    m_reachedEof = false;
    setTimePos(0.0);
    setDuration(0.0);
    setBufferDuration(0.0);
    setBufferEnd(0.0);
    setBuffering(false);
    setSeeking(false);
    setHasMedia(true);
    setBufferingProgress(0.0);
    setFileLoading(true);
    setPaused(false);
    m_waitingToApplySubtitlePreference = false;

    mpv::qt::command_variant(mpv, QVariantList{QStringLiteral("loadfile"), path});
    mpv::qt::set_property_variant(mpv, "pause", false);
}

void MpvPlayerSession::setExternalSubtitles(const QVariantList &subtitles)
{
    m_externalSubtitles = subtitles;
    m_waitingToApplySubtitlePreference = false;
}

void MpvPlayerSession::setStartupPosition(const QString &position)
{
    m_pendingStartupPosition = position.trimmed();
}

void MpvPlayerSession::togglePause()
{
    if (m_reachedEof)
    {
        mpv::qt::command_variant(
            mpv, QVariantList{QStringLiteral("seek"), 0, QStringLiteral("absolute+exact")});
        mpv::qt::set_property_variant(mpv, "pause", false);
        return;
    }

    mpv::qt::set_property_variant(mpv, "pause", !m_paused);
}

void MpvPlayerSession::seekRelative(double seconds)
{
    mpv::qt::command_variant(
        mpv, QVariantList{QStringLiteral("seek"), seconds, QStringLiteral("relative+exact")});
}

void MpvPlayerSession::seekTo(double seconds)
{
    mpv::qt::command_variant(
        mpv, QVariantList{QStringLiteral("seek"), seconds, QStringLiteral("absolute+exact")});
}

void MpvPlayerSession::setPlaybackSpeed(double speed)
{
    mpv::qt::set_property_variant(mpv, "speed", speed);
}

void MpvPlayerSession::setVolume(double volume)
{
    mpv::qt::set_property_variant(mpv, "volume", qBound(0.0, volume, 100.0));
}

void MpvPlayerSession::setVideoId(int id)
{
    if (id <= 0)
    {
        mpv::qt::set_property_variant(mpv, "vid", QStringLiteral("auto"));
    }
    else
    {
        mpv::qt::set_property_variant(mpv, "vid", id);
    }
}

void MpvPlayerSession::setSubtitleId(int id)
{
    selectSubtitleTrack(id, true);
}

void MpvPlayerSession::command(const QVariant &params)
{
    mpv::qt::command_variant(mpv, params);
}

QVariant MpvPlayerSession::getProperty(const QString &name)
{
    return mpv::qt::get_property_variant(mpv, name);
}

void MpvPlayerSession::setProperty(const QString &name, const QVariant &value)
{
    mpv::qt::set_property_variant(mpv, name, value);
}

void MpvPlayerSession::processMpvEvents()
{
    while (true)
    {
        mpv_event *event = mpv_wait_event(mpv, 0);
        if (!event || event->event_id == MPV_EVENT_NONE)
        {
            break;
        }

        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE)
        {
            auto *property = static_cast<mpv_event_property *>(event->data);
            if (!property || !property->name)
            {
                continue;
            }

            handlePropertyChange(*property);
        }
        else if (event->event_id == MPV_EVENT_END_FILE)
        {
            const auto *endFile = static_cast<mpv_event_end_file *>(event->data);
            const bool reachedPlaylistEnd = endFile && endFile->reason == MPV_END_FILE_REASON_EOF;
            m_reachedEof = true;
            if (reachedPlaylistEnd)
            {
                setTimePos(m_duration);
            }
            setBufferDuration(0.0);
            setBufferEnd(0.0);
            setBuffering(false);
            setSeeking(false);
            setBufferingProgress(0.0);
            setFileLoading(false);
            if (reachedPlaylistEnd)
            {
                emit playbackFinished();
            }
            if (!m_fileLoading)
            {
                setPaused(true);
            }
        }
        else if (event->event_id == MPV_EVENT_FILE_LOADED)
        {
            m_reachedEof = false;
            setPaused(false);
            mpv::qt::set_property_variant(mpv, "pause", false);
            applyPendingStartupPosition();
            setFileLoading(false);
            loadExternalSubtitles();
        }
    }
}

void MpvPlayerSession::observeProperties()
{
    mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "demuxer-cache-duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "seeking", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "cache-buffering-state", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "video-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "vid", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "sid", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "user-data/mpv/console/open", MPV_FORMAT_FLAG);
}

void MpvPlayerSession::handlePropertyChange(const mpv_event_property &property)
{
    if (qstrcmp(property.name, "pause") == 0)
    {
        if (property.format == MPV_FORMAT_FLAG && property.data)
        {
            setPaused(*static_cast<int *>(property.data) != 0);
        }
        return;
    }

    if (qstrcmp(property.name, "time-pos") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setTimePos(*static_cast<double *>(property.data));
        }
        else
        {
            setTimePos(0.0);
        }
        return;
    }

    if (qstrcmp(property.name, "duration") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setDuration(*static_cast<double *>(property.data));
        }
        else
        {
            setDuration(0.0);
        }
        return;
    }

    if (qstrcmp(property.name, "demuxer-cache-duration") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setBufferDuration(*static_cast<double *>(property.data));
        }
        else
        {
            setBufferDuration(0.0);
        }
        return;
    }

    if (qstrcmp(property.name, "paused-for-cache") == 0)
    {
        if (property.format == MPV_FORMAT_FLAG && property.data)
        {
            setBuffering(*static_cast<int *>(property.data) != 0);
        }
        else
        {
            setBuffering(false);
        }
        return;
    }

    if (qstrcmp(property.name, "seeking") == 0)
    {
        if (property.format == MPV_FORMAT_FLAG && property.data)
        {
            setSeeking(*static_cast<int *>(property.data) != 0);
        }
        else
        {
            setSeeking(false);
        }
        return;
    }

    if (qstrcmp(property.name, "cache-buffering-state") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setBufferingProgress(*static_cast<double *>(property.data) / 100.0);
        }
        else if (property.format == MPV_FORMAT_INT64 && property.data)
        {
            setBufferingProgress(static_cast<double>(*static_cast<int64_t *>(property.data)) / 100.0);
        }
        else
        {
            setBufferingProgress(0.0);
        }
        return;
    }

    if (qstrcmp(property.name, "speed") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setPlaybackSpeedValue(*static_cast<double *>(property.data));
        }
        return;
    }

    if (qstrcmp(property.name, "volume") == 0)
    {
        if (property.format == MPV_FORMAT_DOUBLE && property.data)
        {
            setVolumeValue(*static_cast<double *>(property.data));
        }
        return;
    }

    if (qstrcmp(property.name, "vid") == 0)
    {
        if (property.format == MPV_FORMAT_INT64 && property.data)
        {
            setVideoIdValue(static_cast<int>(*static_cast<int64_t *>(property.data)));
        }
        else
        {
            setVideoIdValue(0);
        }
        return;
    }

    if (qstrcmp(property.name, "sid") == 0)
    {
        if (property.format == MPV_FORMAT_INT64 && property.data)
        {
            setSubtitleIdValue(static_cast<int>(*static_cast<int64_t *>(property.data)));
        }
        else
        {
            setSubtitleIdValue(0);
        }
        return;
    }

    if (qstrcmp(property.name, "user-data/mpv/console/open") == 0)
    {
        if (property.format == MPV_FORMAT_FLAG && property.data)
        {
            setConsoleOpen(*static_cast<int *>(property.data) != 0);
        }
        else
        {
            setConsoleOpen(false);
        }
        return;
    }

    if (qstrcmp(property.name, "eof-reached") == 0)
    {
        if (property.format == MPV_FORMAT_FLAG && property.data)
        {
            m_reachedEof = *static_cast<int *>(property.data) != 0;
        }
        else
        {
            m_reachedEof = false;
        }
        return;
    }

    if (qstrcmp(property.name, "track-list") == 0)
    {
        handleTrackListChange(property);
    }
}

void MpvPlayerSession::handleTrackListChange(const mpv_event_property &property)
{
    QVariantList trackList;
    if (property.format == MPV_FORMAT_NODE && property.data)
    {
        trackList = mpv::qt::node_to_variant(static_cast<mpv_node *>(property.data)).toList();
    }

    const MpvMappedTracks mapped = MpvTrackMapper::mapTracks(trackList);
    setVideoTracks(mapped.videoTracks);
    if (mapped.selectedVideoId > 0)
    {
        setVideoIdValue(mapped.selectedVideoId);
    }
    setSubtitleTracks(mapped.subtitleTracks);

    if (!m_waitingToApplySubtitlePreference)
    {
        return;
    }

    if (m_externalSubtitles.isEmpty() || subtitleTrackCountBySource(true) >= m_externalSubtitles.size())
    {
        applyStoredSubtitlePreference();
        m_waitingToApplySubtitlePreference = false;
    }
}

void MpvPlayerSession::loadExternalSubtitles()
{
    m_waitingToApplySubtitlePreference = false;

    for (const QVariant &entry : m_externalSubtitles)
    {
        const QVariantMap subtitle = entry.toMap();
        const QString url = subtitle.value(QStringLiteral("url")).toString().trimmed();
        if (url.isEmpty())
        {
            continue;
        }

        const QString name = subtitle.value(QStringLiteral("name")).toString().trimmed();
        const QString lang = normalizedLanguage(subtitle.value(QStringLiteral("lang")).toString());
        mpv::qt::command_variant(
            mpv,
            QVariantList{
                QStringLiteral("sub-add"),
                url,
                QStringLiteral("auto"),
                name,
                lang,
            });
        m_waitingToApplySubtitlePreference = true;
    }

    if (!m_waitingToApplySubtitlePreference)
    {
        applyStoredSubtitlePreference();
    }
}

void MpvPlayerSession::rememberSubtitlePreference(int id)
{
    m_hasSubtitlePreference = true;
    m_preferSubtitlesOff = id <= 0;
    m_preferredSubtitleLang.clear();

    if (id <= 0)
    {
        return;
    }

    for (const QVariant &entry : m_subtitleTracks)
    {
        const QVariantMap track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() != id)
        {
            continue;
        }

        const QString lang = normalizedLanguage(track.value(QStringLiteral("lang")).toString());
        if (!lang.isEmpty())
        {
            m_preferredSubtitleLang = lang;
            return;
        }

        m_hasSubtitlePreference = false;
        return;
    }

    m_hasSubtitlePreference = false;
}

bool MpvPlayerSession::applyStoredSubtitlePreference()
{
    if (m_preferSubtitlesOff)
    {
        selectSubtitleTrack(0, false);
        return true;
    }

    if (m_hasSubtitlePreference)
    {
        const int preferredId = preferredSubtitleTrackId();
        if (preferredId > 0)
        {
            selectSubtitleTrack(preferredId, false);
        }
        return true;
    }

    if (m_subtitleId > 0)
    {
        return true;
    }

    for (const QVariant &entry : m_externalSubtitles)
    {
        const QVariantMap subtitle = entry.toMap();
        if (!subtitle.value(QStringLiteral("default")).toBool())
        {
            continue;
        }

        const QString desiredLang = normalizedLanguage(subtitle.value(QStringLiteral("lang")).toString());
        const QString desiredName = subtitle.value(QStringLiteral("name")).toString().trimmed();
        for (const QVariant &trackEntry : m_subtitleTracks)
        {
            const QVariantMap track = trackEntry.toMap();
            if (!track.value(QStringLiteral("isExternal")).toBool())
            {
                continue;
            }

            const QString trackLang = normalizedLanguage(track.value(QStringLiteral("lang")).toString());
            const QString trackTitle = track.value(QStringLiteral("title")).toString().trimmed();
            if ((!desiredLang.isEmpty() && trackLang == desiredLang)
                || (!desiredName.isEmpty() && trackTitle == desiredName))
            {
                selectSubtitleTrack(track.value(QStringLiteral("id")).toInt(), false);
                return true;
            }
        }
    }

    return true;
}

bool MpvPlayerSession::hasMatchingSubtitleLanguage() const
{
    if (m_preferredSubtitleLang.isEmpty())
    {
        return false;
    }

    for (const QVariant &entry : m_subtitleTracks)
    {
        const QVariantMap track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() <= 0)
        {
            continue;
        }

        if (normalizedLanguage(track.value(QStringLiteral("lang")).toString()) == m_preferredSubtitleLang)
        {
            return true;
        }
    }

    return false;
}

int MpvPlayerSession::subtitleTrackCountBySource(bool external) const
{
    int count = 0;
    for (const QVariant &entry : m_subtitleTracks)
    {
        const QVariantMap track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() <= 0)
        {
            continue;
        }

        if (track.value(QStringLiteral("isExternal")).toBool() == external)
        {
            ++count;
        }
    }

    return count;
}

int MpvPlayerSession::preferredSubtitleTrackId() const
{
    if (!hasMatchingSubtitleLanguage())
    {
        return 0;
    }

    for (const QVariant &entry : m_subtitleTracks)
    {
        const QVariantMap track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() <= 0)
        {
            continue;
        }

        if (normalizedLanguage(track.value(QStringLiteral("lang")).toString()) == m_preferredSubtitleLang)
        {
            return track.value(QStringLiteral("id")).toInt();
        }
    }

    return 0;
}

void MpvPlayerSession::selectSubtitleTrack(int id, bool rememberPreference)
{
    if (rememberPreference)
    {
        rememberSubtitlePreference(id);
    }

    if (id <= 0)
    {
        mpv::qt::set_property_variant(mpv, "sid", QStringLiteral("no"));
        return;
    }

    mpv::qt::set_property_variant(mpv, "sid", id);
}

void MpvPlayerSession::setPaused(bool paused)
{
    if (m_paused == paused)
    {
        return;
    }

    m_paused = paused;
    emit playingChanged();
}

void MpvPlayerSession::setTimePos(double seconds)
{
    const double safeSeconds = qMax(0.0, seconds);
    if (qFuzzyCompare(m_timePos, safeSeconds))
    {
        return;
    }

    const double previousTimePos = m_timePos;
    m_timePos = safeSeconds;
    emit timePosChanged();

    if (qAbs(m_timePos - previousTimePos) <= 1.0)
    {
        setBufferEnd(m_timePos + m_bufferDuration);
    }
}

void MpvPlayerSession::setDuration(double seconds)
{
    if (qFuzzyCompare(m_duration, seconds))
    {
        return;
    }

    m_duration = seconds;
    emit durationChanged();
}

void MpvPlayerSession::setBufferDuration(double seconds)
{
    if (qFuzzyCompare(m_bufferDuration, seconds))
    {
        return;
    }

    m_bufferDuration = qMax(0.0, seconds);
    emit bufferDurationChanged();
    setBufferEnd(m_timePos + m_bufferDuration);
}

void MpvPlayerSession::setBufferEnd(double seconds)
{
    const double safeSeconds = qMax(0.0, seconds);
    if (qFuzzyCompare(m_bufferEnd, safeSeconds))
    {
        return;
    }

    m_bufferEnd = safeSeconds;
    emit bufferEndChanged();
}

void MpvPlayerSession::setLoading(bool loading)
{
    if (m_loading == loading)
    {
        return;
    }

    m_loading = loading;
    emit loadingChanged();
}

void MpvPlayerSession::setFileLoading(bool loading)
{
    if (m_fileLoading == loading)
    {
        return;
    }

    m_fileLoading = loading;
    updateLoadingState();
}

void MpvPlayerSession::setBuffering(bool buffering)
{
    if (m_buffering == buffering)
    {
        return;
    }

    m_buffering = buffering;
    emit bufferingChanged();

    if (!m_buffering)
    {
        setBufferingProgress(0.0);
    }

    updateLoadingState();
}

void MpvPlayerSession::setSeeking(bool seeking)
{
    if (m_seeking == seeking)
    {
        return;
    }

    m_seeking = seeking;
    emit seekingChanged();
    updateLoadingState();
}

void MpvPlayerSession::setHasMedia(bool hasMedia)
{
    if (m_hasMedia == hasMedia)
    {
        return;
    }

    m_hasMedia = hasMedia;
    emit hasMediaChanged();
}

void MpvPlayerSession::setBufferingProgress(double progress)
{
    const double normalizedProgress = qBound(0.0, progress, 1.0);
    if (qFuzzyCompare(m_bufferingProgress, normalizedProgress))
    {
        return;
    }

    m_bufferingProgress = normalizedProgress;
    emit bufferingProgressChanged();
}

void MpvPlayerSession::setPlaybackSpeedValue(double speed)
{
    if (qFuzzyCompare(m_playbackSpeed, speed))
    {
        return;
    }

    m_playbackSpeed = speed;
    emit playbackSpeedChanged();
}

void MpvPlayerSession::setVolumeValue(double volume)
{
    if (qFuzzyCompare(m_volume, volume))
    {
        return;
    }

    m_volume = volume;
    emit volumeChanged();
}

void MpvPlayerSession::setQualityLabel(const QString &label)
{
    if (m_qualityLabel == label)
    {
        return;
    }

    m_qualityLabel = label;
    emit qualityLabelChanged();
}

void MpvPlayerSession::setVideoTracks(const QVariantList &tracks)
{
    if (m_videoTracks == tracks)
    {
        return;
    }

    m_videoTracks = tracks;
    emit videoTracksChanged();
    setQualityLabel(MpvTrackMapper::qualityLabelForVideoId(m_videoTracks, m_videoId));
}

void MpvPlayerSession::setVideoIdValue(int id)
{
    const int normalizedId = id > 0 ? id : 0;
    if (m_videoId == normalizedId)
    {
        return;
    }

    m_videoId = normalizedId;
    setQualityLabel(MpvTrackMapper::qualityLabelForVideoId(m_videoTracks, normalizedId));
    emit videoIdChanged();
}

void MpvPlayerSession::setSubtitleTracks(const QVariantList &tracks)
{
    if (m_subtitleTracks == tracks)
    {
        return;
    }

    m_subtitleTracks = tracks;
    emit subtitleTracksChanged();
}

void MpvPlayerSession::setSubtitleIdValue(int id)
{
    const int normalizedId = id > 0 ? id : 0;
    if (m_subtitleId == normalizedId)
    {
        return;
    }

    m_subtitleId = normalizedId;
    emit subtitleIdChanged();
}

void MpvPlayerSession::setConsoleOpen(bool open)
{
    if (m_consoleOpen == open)
    {
        return;
    }

    m_consoleOpen = open;
    emit consoleOpenChanged();
}

void MpvPlayerSession::updateLoadingState()
{
    setLoading(m_fileLoading || m_buffering || m_seeking);
}

void MpvPlayerSession::applyPendingStartupPosition()
{
    if (m_pendingStartupPosition.isEmpty())
    {
        return;
    }

    const QString position = m_pendingStartupPosition;
    m_pendingStartupPosition.clear();

    if (position.endsWith(QLatin1Char('%')))
    {
        bool ok = false;
        const double percent = position.first(position.size() - 1).toDouble(&ok);
        if (ok)
        {
            setSeeking(true);
            mpv::qt::command_variant(
                mpv, QVariantList{QStringLiteral("seek"), percent, QStringLiteral("absolute-percent+exact")});
            return;
        }
        return;
    }

    if (const std::optional<double> seconds = parseTimestampToSeconds(position))
    {
        setSeeking(true);
        mpv::qt::command_variant(
            mpv, QVariantList{QStringLiteral("seek"), *seconds, QStringLiteral("absolute+exact")});
        return;
    }
}
