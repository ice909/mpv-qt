#ifndef LZC_PLAYER_MPVPLAYERVIEW_H_
#define LZC_PLAYER_MPVPLAYERVIEW_H_

#include <QtQuick/QQuickItem>
#include <mpv/client.h>

#include <QString>
#include <QStringList>
#include <QVariant>

class MpvPlayerSession;
class PlayerWindow;
class QQuickWindow;

class MpvPlayerView : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(double timePos READ timePos NOTIFY timePosChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double bufferDuration READ bufferDuration NOTIFY bufferDurationChanged)
    Q_PROPERTY(double bufferEnd READ bufferEnd NOTIFY bufferEndChanged)
    Q_PROPERTY(qint64 networkSpeed READ networkSpeed NOTIFY networkSpeedChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(bool seeking READ seeking NOTIFY seekingChanged)
    Q_PROPERTY(bool hasMedia READ hasMedia NOTIFY hasMediaChanged)
    Q_PROPERTY(double bufferingProgress READ bufferingProgress NOTIFY bufferingProgressChanged)
    Q_PROPERTY(double playbackSpeed READ playbackSpeed NOTIFY playbackSpeedChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(QString qualityLabel READ qualityLabel NOTIFY qualityLabelChanged)
    Q_PROPERTY(QVariantList videoTracks READ videoTracks NOTIFY videoTracksChanged)
    Q_PROPERTY(int videoId READ videoId NOTIFY videoIdChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY subtitleTracksChanged)
    Q_PROPERTY(int subtitleId READ subtitleId NOTIFY subtitleIdChanged)
    Q_PROPERTY(bool consoleOpen READ consoleOpen NOTIFY consoleOpenChanged)
    Q_PROPERTY(QVariantList playlistItems READ playlistItems NOTIFY playlistItemsChanged)
    Q_PROPERTY(int playlistIndex READ playlistIndex NOTIFY playlistIndexChanged)
    Q_PROPERTY(int playlistCount READ playlistCount NOTIFY playlistCountChanged)
    Q_PROPERTY(bool hasPlaylist READ hasPlaylist NOTIFY playlistItemsChanged)

public:
    explicit MpvPlayerView(QQuickItem *parent = nullptr);
    ~MpvPlayerView() override;

    mpv_handle *mpvHandle() const;
    void markRenderContextReady();

    bool isPlaying() const;
    double timePos() const;
    double duration() const;
    double bufferDuration() const;
    double bufferEnd() const;
    qint64 networkSpeed() const;
    bool loading() const;
    bool buffering() const;
    bool seeking() const;
    bool hasMedia() const;
    double bufferingProgress() const;
    double playbackSpeed() const;
    double volume() const;
    QString qualityLabel() const;
    QVariantList videoTracks() const;
    int videoId() const;
    QVariantList subtitleTracks() const;
    int subtitleId() const;
    bool consoleOpen() const;
    QVariantList playlistItems() const;
    int playlistIndex() const;
    int playlistCount() const;
    bool hasPlaylist() const;

public slots:
    void loadFile(const QString &path);
    void setPlaylistItems(const QVariantList &items);
    void playEpisode(int index);
    void playNextEpisode();
    void playPrevEpisode();
    void setStartupPosition(const QString &position);
    void togglePause();
    void seekRelative(double seconds);
    void seekTo(double seconds);
    void setPlaybackSpeed(double speed);
    void setVolume(double volume);
    void setVideoId(int id);
    void setSubtitleId(int id);
    void command(const QVariant &params);
    QVariant getProperty(const QString &name);
    void setProperty(const QString &name, const QVariant &value);

signals:
    void playingChanged();
    void timePosChanged();
    void durationChanged();
    void bufferDurationChanged();
    void bufferEndChanged();
    void networkSpeedChanged();
    void loadingChanged();
    void bufferingChanged();
    void seekingChanged();
    void hasMediaChanged();
    void bufferingProgressChanged();
    void playbackSpeedChanged();
    void volumeChanged();
    void qualityLabelChanged();
    void videoTracksChanged();
    void videoIdChanged();
    void subtitleTracksChanged();
    void subtitleIdChanged();
    void consoleOpenChanged();
    void playlistItemsChanged();
    void playlistIndexChanged();
    void playlistCountChanged();

private slots:
    void handleWindowChanged(QQuickWindow *window);
    void loadPendingFile();
    void handlePlaybackFinished();

private:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void loadMedia(const QString &path, const QVariantList &externalSubtitles);
    QVariantMap playlistItemAt(int index) const;
    QVariantList normalizedSubtitles(const QVariantList &subtitles) const;
    void setPlaylistIndexInternal(int index);
    void loadEpisodeAtIndex(int index);
    void attachToWindow(PlayerWindow *window);
    void detachFromWindow();

    MpvPlayerSession *m_session;
    PlayerWindow *m_registeredWindow;
    QString m_pendingFile;
    QVariantList m_pendingExternalSubtitles;
    bool m_renderContextReady;
    QVariantList m_playlistItems;
    int m_playlistIndex;
};

#endif
