#ifndef LZC_PLAYER_MPVOBJECT_H_
#define LZC_PLAYER_MPVOBJECT_H_

#include <QtQuick/QQuickFramebufferObject>

#include <mpv/client.h>
#include <mpv/render_gl.h>

#include "src/common/qthelper.hpp"

class MpvRenderer;

class MpvObject : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(double timePos READ timePos NOTIFY timePosChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double bufferDuration READ bufferDuration NOTIFY bufferDurationChanged)
    Q_PROPERTY(double bufferEnd READ bufferEnd NOTIFY bufferEndChanged)
    Q_PROPERTY(qint64 networkSpeed READ networkSpeed NOTIFY networkSpeedChanged)
    Q_PROPERTY(double playbackSpeed READ playbackSpeed NOTIFY playbackSpeedChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(QString qualityLabel READ qualityLabel NOTIFY qualityLabelChanged)
    Q_PROPERTY(QVariantList videoTracks READ videoTracks NOTIFY videoTracksChanged)
    Q_PROPERTY(int videoId READ videoId NOTIFY videoIdChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY subtitleTracksChanged)
    Q_PROPERTY(int subtitleId READ subtitleId NOTIFY subtitleIdChanged)
    Q_PROPERTY(bool consoleOpen READ consoleOpen NOTIFY consoleOpenChanged)

    friend class MpvRenderer;

public:
    explicit MpvObject(QQuickItem *parent = nullptr);
    ~MpvObject() override;

    Renderer *createRenderer() const override;

    static void on_update(void *ctx);
    static void on_mpv_events(void *ctx);

    bool isPlaying() const;
    double timePos() const;
    double duration() const;
    double bufferDuration() const;
    double bufferEnd() const;
    qint64 networkSpeed() const;
    double playbackSpeed() const;
    double volume() const;
    QString qualityLabel() const;
    QVariantList videoTracks() const;
    int videoId() const;
    QVariantList subtitleTracks() const;
    int subtitleId() const;
    bool consoleOpen() const;

public slots:
    void loadFile(const QString &path);
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
    void onUpdate();
    void playingChanged();
    void timePosChanged();
    void durationChanged();
    void bufferDurationChanged();
    void bufferEndChanged();
    void networkSpeedChanged();
    void playbackSpeedChanged();
    void volumeChanged();
    void qualityLabelChanged();
    void videoTracksChanged();
    void videoIdChanged();
    void subtitleTracksChanged();
    void subtitleIdChanged();
    void consoleOpenChanged();

private slots:
    void doUpdate();
    void loadPendingFile();
    void processMpvEvents();

private:
    void setPaused(bool paused);
    void setTimePos(double seconds);
    void setDuration(double seconds);
    void setBufferDuration(double seconds);
    void setBufferEnd(double seconds);
    void setNetworkSpeed(qint64 bytesPerSecond);
    void setPlaybackSpeedValue(double speed);
    void setVolumeValue(double volume);
    void setQualityLabel(const QString &label);
    void setVideoTracks(const QVariantList &tracks);
    void setVideoIdValue(int id);
    void setSubtitleTracks(const QVariantList &tracks);
    void setSubtitleIdValue(int id);
    void setConsoleOpen(bool open);

    mpv_handle *mpv;
    mpv_render_context *mpv_gl;
    QString pendingFile;
    QString sourceUrl;
    bool m_paused;
    double m_timePos;
    double m_duration;
    double m_bufferDuration;
    double m_bufferEnd;
    qint64 m_networkSpeed;
    double m_playbackSpeed;
    double m_volume;
    QString m_qualityLabel;
    QVariantList m_videoTracks;
    int m_videoId;
    QVariantList m_subtitleTracks;
    int m_subtitleId;
    bool m_consoleOpen;
    bool m_reachedEof;
};

#endif
