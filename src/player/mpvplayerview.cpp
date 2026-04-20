#include "src/player/mpvplayerview.h"

#include <QQuickWindow>

#include "src/app/playerwindow.h"
#include "src/player/mpvplayersession.h"

MpvPlayerView::MpvPlayerView(QQuickItem *parent)
    : QQuickItem(parent),
      m_session(new MpvPlayerSession(this)),
      m_registeredWindow(nullptr),
      m_renderContextReady(false),
      m_playlistIndex(-1)
{
    setFlag(QQuickItem::ItemHasContents, false);

    connect(this, &QQuickItem::windowChanged, this, &MpvPlayerView::handleWindowChanged);
    connect(m_session, &MpvPlayerSession::playbackFinished, this, &MpvPlayerView::handlePlaybackFinished);
    connect(m_session, &MpvPlayerSession::playingChanged, this, &MpvPlayerView::playingChanged);
    connect(m_session, &MpvPlayerSession::timePosChanged, this, &MpvPlayerView::timePosChanged);
    connect(m_session, &MpvPlayerSession::durationChanged, this, &MpvPlayerView::durationChanged);
    connect(m_session, &MpvPlayerSession::bufferDurationChanged, this, &MpvPlayerView::bufferDurationChanged);
    connect(m_session, &MpvPlayerSession::bufferEndChanged, this, &MpvPlayerView::bufferEndChanged);
    connect(m_session, &MpvPlayerSession::networkSpeedChanged, this, &MpvPlayerView::networkSpeedChanged);
    connect(m_session, &MpvPlayerSession::loadingChanged, this, &MpvPlayerView::loadingChanged);
    connect(m_session, &MpvPlayerSession::bufferingChanged, this, &MpvPlayerView::bufferingChanged);
    connect(m_session, &MpvPlayerSession::seekingChanged, this, &MpvPlayerView::seekingChanged);
    connect(m_session, &MpvPlayerSession::hasMediaChanged, this, &MpvPlayerView::hasMediaChanged);
    connect(m_session, &MpvPlayerSession::bufferingProgressChanged, this, &MpvPlayerView::bufferingProgressChanged);
    connect(m_session, &MpvPlayerSession::playbackSpeedChanged, this, &MpvPlayerView::playbackSpeedChanged);
    connect(m_session, &MpvPlayerSession::volumeChanged, this, &MpvPlayerView::volumeChanged);
    connect(m_session, &MpvPlayerSession::qualityLabelChanged, this, &MpvPlayerView::qualityLabelChanged);
    connect(m_session, &MpvPlayerSession::videoTracksChanged, this, &MpvPlayerView::videoTracksChanged);
    connect(m_session, &MpvPlayerSession::videoIdChanged, this, &MpvPlayerView::videoIdChanged);
    connect(m_session, &MpvPlayerSession::subtitleTracksChanged, this, &MpvPlayerView::subtitleTracksChanged);
    connect(m_session, &MpvPlayerSession::subtitleIdChanged, this, &MpvPlayerView::subtitleIdChanged);
    connect(m_session, &MpvPlayerSession::consoleOpenChanged, this, &MpvPlayerView::consoleOpenChanged);
}

MpvPlayerView::~MpvPlayerView()
{
    detachFromWindow();
}

bool MpvPlayerView::isPlaying() const
{
    return m_session->isPlaying();
}

double MpvPlayerView::timePos() const
{
    return m_session->timePos();
}

double MpvPlayerView::duration() const
{
    return m_session->duration();
}

double MpvPlayerView::bufferDuration() const
{
    return m_session->bufferDuration();
}

double MpvPlayerView::bufferEnd() const
{
    return m_session->bufferEnd();
}

qint64 MpvPlayerView::networkSpeed() const
{
    return m_session->networkSpeed();
}

bool MpvPlayerView::loading() const
{
    return m_session->loading();
}

bool MpvPlayerView::buffering() const
{
    return m_session->buffering();
}

bool MpvPlayerView::seeking() const
{
    return m_session->seeking();
}

bool MpvPlayerView::hasMedia() const
{
    return m_session->hasMedia();
}

double MpvPlayerView::bufferingProgress() const
{
    return m_session->bufferingProgress();
}

double MpvPlayerView::playbackSpeed() const
{
    return m_session->playbackSpeed();
}

double MpvPlayerView::volume() const
{
    return m_session->volume();
}

QString MpvPlayerView::qualityLabel() const
{
    return m_session->qualityLabel();
}

QVariantList MpvPlayerView::videoTracks() const
{
    return m_session->videoTracks();
}

int MpvPlayerView::videoId() const
{
    return m_session->videoId();
}

QVariantList MpvPlayerView::subtitleTracks() const
{
    return m_session->subtitleTracks();
}

int MpvPlayerView::subtitleId() const
{
    return m_session->subtitleId();
}

bool MpvPlayerView::consoleOpen() const
{
    return m_session->consoleOpen();
}

QVariantList MpvPlayerView::playlistItems() const
{
    return m_playlistItems;
}

int MpvPlayerView::playlistIndex() const
{
    return m_playlistIndex;
}

int MpvPlayerView::playlistCount() const
{
    return m_playlistItems.size();
}

bool MpvPlayerView::hasPlaylist() const
{
    return !m_playlistItems.isEmpty();
}

void MpvPlayerView::loadFile(const QString &path)
{
    if (path.isEmpty())
    {
        return;
    }

    loadMedia(path, QVariantList{});
}

void MpvPlayerView::loadMedia(const QString &path, const QVariantList &externalSubtitles)
{
    if (!m_renderContextReady)
    {
        m_pendingFile = path;
        m_pendingExternalSubtitles = externalSubtitles;
        if (QQuickWindow *targetWindow = window())
        {
            targetWindow->update();
        }
        return;
    }

    m_pendingFile.clear();
    m_pendingExternalSubtitles.clear();
    m_session->setExternalSubtitles(externalSubtitles);
    m_session->loadFile(path);
}

void MpvPlayerView::setPlaylistItems(const QVariantList &items)
{
    if (m_playlistItems == items)
    {
        return;
    }

    const int previousCount = m_playlistItems.size();
    m_playlistItems = items;
    emit playlistItemsChanged();

    if (previousCount != m_playlistItems.size())
    {
        emit playlistCountChanged();
    }

    const int nextIndex = m_playlistItems.isEmpty() ? -1 : qBound(0, m_playlistIndex, m_playlistItems.size() - 1);
    setPlaylistIndexInternal(nextIndex);
}

void MpvPlayerView::playEpisode(int index)
{
    loadEpisodeAtIndex(index);
}

void MpvPlayerView::playNextEpisode()
{
    if (m_playlistItems.isEmpty())
    {
        return;
    }

    loadEpisodeAtIndex(m_playlistIndex + 1);
}

void MpvPlayerView::playPrevEpisode()
{
    if (m_playlistItems.isEmpty())
    {
        return;
    }

    loadEpisodeAtIndex(m_playlistIndex - 1);
}

void MpvPlayerView::setStartupPosition(const QString &position)
{
    m_session->setStartupPosition(position);
}

void MpvPlayerView::togglePause()
{
    m_session->togglePause();
}

void MpvPlayerView::seekRelative(double seconds)
{
    m_session->seekRelative(seconds);
}

void MpvPlayerView::seekTo(double seconds)
{
    m_session->seekTo(seconds);
}

void MpvPlayerView::setPlaybackSpeed(double speed)
{
    m_session->setPlaybackSpeed(speed);
}

void MpvPlayerView::setVolume(double volume)
{
    m_session->setVolume(volume);
}

void MpvPlayerView::setVideoId(int id)
{
    m_session->setVideoId(id);
}

void MpvPlayerView::setSubtitleId(int id)
{
    m_session->setSubtitleId(id);
}

void MpvPlayerView::command(const QVariant &params)
{
    m_session->command(params);
}

QVariant MpvPlayerView::getProperty(const QString &name)
{
    return m_session->getProperty(name);
}

void MpvPlayerView::setProperty(const QString &name, const QVariant &value)
{
    m_session->setProperty(name, value);
}

void MpvPlayerView::handleWindowChanged(QQuickWindow *window)
{
    if (window == m_registeredWindow)
    {
        return;
    }

    detachFromWindow();
    attachToWindow(qobject_cast<PlayerWindow *>(window));
}

void MpvPlayerView::markRenderContextReady()
{
    if (m_renderContextReady)
    {
        return;
    }

    m_renderContextReady = true;
    loadPendingFile();
}

void MpvPlayerView::loadPendingFile()
{
    if (!m_renderContextReady || m_pendingFile.isEmpty())
    {
        return;
    }

    const QString pendingFile = m_pendingFile;
    m_pendingFile.clear();
    const QVariantList pendingExternalSubtitles = m_pendingExternalSubtitles;
    m_pendingExternalSubtitles.clear();
    m_session->setExternalSubtitles(pendingExternalSubtitles);
    m_session->loadFile(pendingFile);
}

void MpvPlayerView::handlePlaybackFinished()
{
    if (m_playlistItems.isEmpty())
    {
        return;
    }

    playNextEpisode();
}

QVariantMap MpvPlayerView::playlistItemAt(int index) const
{
    if (index < 0 || index >= m_playlistItems.size())
    {
        return {};
    }

    return m_playlistItems.at(index).toMap();
}

QVariantList MpvPlayerView::normalizedSubtitles(const QVariantList &subtitles) const
{
    QVariantList normalized;
    for (const QVariant &entry : subtitles)
    {
        const QVariantMap subtitle = entry.toMap();
        const QString url = subtitle.value(QStringLiteral("url")).toString().trimmed();
        const QString id = subtitle.value(QStringLiteral("id")).toString().trimmed();
        if (url.isEmpty() || id.isEmpty())
        {
            continue;
        }

        QVariantMap item = subtitle;
        item.insert(QStringLiteral("url"), url);
        item.insert(QStringLiteral("id"), id);
        item.insert(QStringLiteral("name"), subtitle.value(QStringLiteral("name")).toString().trimmed());
        item.insert(QStringLiteral("lang"), subtitle.value(QStringLiteral("lang")).toString().trimmed());
        item.insert(QStringLiteral("format"), subtitle.value(QStringLiteral("format")).toString().trimmed());
        item.insert(QStringLiteral("default"), subtitle.value(QStringLiteral("default")).toBool());
        normalized.append(item);
    }

    return normalized;
}

void MpvPlayerView::setPlaylistIndexInternal(int index)
{
    const int normalizedIndex = (index >= 0 && index < m_playlistItems.size()) ? index : -1;
    if (m_playlistIndex == normalizedIndex)
    {
        return;
    }

    m_playlistIndex = normalizedIndex;
    emit playlistIndexChanged();
}

void MpvPlayerView::loadEpisodeAtIndex(int index)
{
    const QVariantMap item = playlistItemAt(index);
    const QString path = item.value(QStringLiteral("url")).toString().trimmed();
    if (path.isEmpty())
    {
        return;
    }

    setPlaylistIndexInternal(index);
    loadMedia(path, normalizedSubtitles(item.value(QStringLiteral("subtitles")).toList()));
}

mpv_handle *MpvPlayerView::mpvHandle() const
{
    return m_session->handle();
}

void MpvPlayerView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);

    if (newGeometry == oldGeometry)
    {
        return;
    }

    if (QQuickWindow *targetWindow = window())
    {
        targetWindow->update();
    }
}

void MpvPlayerView::attachToWindow(PlayerWindow *window)
{
    if (!window)
    {
        return;
    }

    m_registeredWindow = window;
    m_registeredWindow->setVideoView(this);
}

void MpvPlayerView::detachFromWindow()
{
    if (!m_registeredWindow)
    {
        return;
    }

    PlayerWindow *window = m_registeredWindow;
    m_registeredWindow = nullptr;
    m_renderContextReady = false;
    window->clearVideoView(this);
}
