#ifndef LZC_PLAYER_MPVWINDOWRENDERER_H_
#define LZC_PLAYER_MPVWINDOWRENDERER_H_

#include <QObject>
#include <QPointer>
#include <mpv/client.h>
#include <mpv/render.h>

#include <atomic>

class PlayerWindow;
class MpvPlayerView;

class MpvWindowRenderer : public QObject
{
    Q_OBJECT

public:
    explicit MpvWindowRenderer(PlayerWindow *window);
    ~MpvWindowRenderer() override;

    void setView(MpvPlayerView *view);
    void scheduleFrameUpdate();

private slots:
    void render();
    void releaseResources();
    void requestWindowUpdate();
    void reportSwap();

private:
    void ensureRenderContext();
    void markRenderContextReady();

    PlayerWindow *m_window;
    QPointer<MpvPlayerView> m_view;
    mpv_handle *m_mpv;
    mpv_render_context *m_renderContext;
    bool m_renderContextReady;
    std::atomic_bool m_frameUpdateScheduled;
    std::atomic_bool m_frameUpdateDirty;
};

#endif
