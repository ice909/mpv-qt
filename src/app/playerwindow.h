#ifndef LZC_PLAYER_PLAYERWINDOW_H_
#define LZC_PLAYER_PLAYERWINDOW_H_

#include <QQuickView>

class MpvPlayerView;
class MpvWindowRenderer;
class QDragEnterEvent;
class QDragLeaveEvent;
class QDragMoveEvent;
class QDropEvent;
class QEvent;
class QMimeData;

class PlayerWindow : public QQuickView
{
    Q_OBJECT
    Q_PROPERTY(bool dropActive READ dropActive NOTIFY dropActiveChanged)

public:
    explicit PlayerWindow(QWindow *parent = nullptr);
    ~PlayerWindow() override;

    bool dropActive() const;
    Q_INVOKABLE void openSystemFileDialog();
    void setVideoView(MpvPlayerView *view);
    void clearVideoView(MpvPlayerView *view);

signals:
    void dropActiveChanged();
    void fileDropped(const QString &path);
    void fileSelected(const QString &path);

protected:
    bool event(QEvent *event) override;

private:
    QString firstDroppedFile(const QMimeData *mimeData) const;
    void setDropActive(bool active);

    MpvPlayerView *m_videoView;
    MpvWindowRenderer *m_videoRenderer;
    bool m_dropActive;
};

#endif
