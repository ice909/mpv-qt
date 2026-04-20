#include "src/app/playerwindow.h"

#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QEvent>
#include <QFileDialog>
#include <QMimeData>
#include <QUrl>

#include "src/player/mpvwindowrenderer.h"

PlayerWindow::PlayerWindow(QWindow *parent)
    : QQuickView(parent),
      m_videoView(nullptr),
      m_videoRenderer(new MpvWindowRenderer(this)),
      m_dropActive(false)
{
    setPersistentGraphics(true);
    setPersistentSceneGraph(true);
    setColor(Qt::black);
}

PlayerWindow::~PlayerWindow() = default;

bool PlayerWindow::dropActive() const
{
    return m_dropActive;
}

void PlayerWindow::openSystemFileDialog()
{
    const QString path = QFileDialog::getOpenFileName(
        nullptr,
        QStringLiteral("选择媒体文件"));

    if (path.isEmpty())
    {
        return;
    }

    emit fileSelected(path);
}

void PlayerWindow::setVideoView(MpvPlayerView *view)
{
    if (m_videoView == view)
    {
        return;
    }

    m_videoView = view;
    m_videoRenderer->setView(view);
    update();
}

void PlayerWindow::clearVideoView(MpvPlayerView *view)
{
    if (m_videoView != view)
    {
        return;
    }

    m_videoView = nullptr;
    m_videoRenderer->setView(nullptr);
    update();
}

bool PlayerWindow::event(QEvent *event)
{
    if (!event)
    {
        return QQuickView::event(event);
    }

    switch (event->type())
    {
    case QEvent::DragEnter:
    case QEvent::DragMove: {
        auto *dragEvent = static_cast<QDragMoveEvent *>(event);
        const QString path = firstDroppedFile(dragEvent->mimeData());
        if (path.isEmpty())
        {
            dragEvent->ignore();
            setDropActive(false);
            return true;
        }

        dragEvent->acceptProposedAction();
        setDropActive(true);
        return true;
    }
    case QEvent::DragLeave: {
        setDropActive(false);
        return QQuickView::event(event);
    }
    case QEvent::Drop: {
        auto *dropEvent = static_cast<QDropEvent *>(event);
        const QString path = firstDroppedFile(dropEvent->mimeData());
        setDropActive(false);

        if (path.isEmpty())
        {
            dropEvent->ignore();
            return true;
        }

        emit fileDropped(path);
        dropEvent->acceptProposedAction();
        return true;
    }
    default:
        break;
    }

    return QQuickView::event(event);
}

QString PlayerWindow::firstDroppedFile(const QMimeData *mimeData) const
{
    if (!mimeData || !mimeData->hasUrls())
    {
        return {};
    }

    const QList<QUrl> urls = mimeData->urls();
    for (const QUrl &url : urls)
    {
        if (url.isLocalFile())
        {
            const QString path = url.toLocalFile().trimmed();
            if (!path.isEmpty())
            {
                return path;
            }
        }
    }

    return {};
}

void PlayerWindow::setDropActive(bool active)
{
    if (m_dropActive == active)
    {
        return;
    }

    m_dropActive = active;
    emit dropActiveChanged();
}
