#ifndef LZC_PLAYER_MPVPLAYERVIEW_H_
#define LZC_PLAYER_MPVPLAYERVIEW_H_

#include <QtQuick/QQuickFramebufferObject>
#include <mpv/client.h>
#include <mpv/render_gl.h>

#include <QString>
#include <QVariant>

class MpvPlayerSession;

class MpvPlayerView : public QQuickFramebufferObject
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

public:
    explicit MpvPlayerView(QQuickItem *parent = nullptr);
    ~MpvPlayerView() override;

    Renderer *createRenderer() const override;
    mpv_handle *mpvHandle() const;
    void ensureRenderContext();
    void renderFrame(QOpenGLFramebufferObject *fbo);

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
    void frameUpdateRequested();
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
    void requestFrameUpdate();
    void markRenderContextReady();
    void loadPendingFile();

private:
    MpvPlayerSession *m_session;
    QString m_pendingFile;
    bool m_renderContextReady;
    mpv_render_context *m_renderContext;
};

#endif
