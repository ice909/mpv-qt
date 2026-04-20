#include "src/player/mpvwindowrenderer.h"

#include <stdexcept>

#include <QGuiApplication>
#include <QMetaObject>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>
#include <QtGui/qguiapplication_platform.h>

#include <mpv/render_gl.h>

#include "src/app/playerwindow.h"
#include "src/player/mpvplayerview.h"

namespace
{

void *getProcAddressMpv(void *ctx, const char *name)
{
    Q_UNUSED(ctx)

    QOpenGLContext *glctx = QOpenGLContext::currentContext();
    if (!glctx)
    {
        return nullptr;
    }

    return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
}

void onMpvRenderUpdate(void *ctx)
{
    auto *renderer = static_cast<MpvWindowRenderer *>(ctx);
    renderer->scheduleFrameUpdate();
}

} // namespace

MpvWindowRenderer::MpvWindowRenderer(PlayerWindow *window)
    : QObject(window),
      m_window(window),
      m_view(nullptr),
      m_mpv(nullptr),
      m_renderContext(nullptr),
      m_renderContextReady(false),
      m_frameUpdateScheduled(false),
      m_frameUpdateDirty(false)
{
    connect(m_window, &QQuickWindow::beforeRenderPassRecording, this, &MpvWindowRenderer::render,
            Qt::DirectConnection);
    connect(m_window, &QQuickWindow::sceneGraphInvalidated, this, &MpvWindowRenderer::releaseResources,
            Qt::DirectConnection);
    connect(m_window, &QQuickWindow::frameSwapped, this, &MpvWindowRenderer::reportSwap, Qt::DirectConnection);
}

MpvWindowRenderer::~MpvWindowRenderer()
{
    releaseResources();
}

void MpvWindowRenderer::setView(MpvPlayerView *view)
{
    if (m_view == view)
    {
        return;
    }

    if (m_renderContext && m_view != view)
    {
        releaseResources();
    }

    m_view = view;
    m_mpv = view ? view->mpvHandle() : nullptr;
    m_renderContextReady = false;
    m_frameUpdateDirty.store(false, std::memory_order_release);
    m_frameUpdateScheduled.store(false, std::memory_order_release);
}

void MpvWindowRenderer::scheduleFrameUpdate()
{
    m_frameUpdateDirty.store(true, std::memory_order_release);

    bool expected = false;
    if (!m_frameUpdateScheduled.compare_exchange_strong(
            expected, true, std::memory_order_acq_rel, std::memory_order_acquire))
    {
        return;
    }

    QMetaObject::invokeMethod(this, &MpvWindowRenderer::requestWindowUpdate, Qt::QueuedConnection);
}

void MpvWindowRenderer::render()
{
    if (!m_window || !m_view || !m_mpv)
    {
        return;
    }

    ensureRenderContext();
    if (!m_renderContext)
    {
        return;
    }

    const qreal dpr = m_window->effectiveDevicePixelRatio();
    const int surfaceWidth = qMax(1, qRound(m_window->width() * dpr));
    const int surfaceHeight = qMax(1, qRound(m_window->height() * dpr));

    m_frameUpdateDirty.store(false, std::memory_order_release);
    mpv_render_context_update(m_renderContext);

    m_window->beginExternalCommands();
    QQuickOpenGLUtils::resetOpenGLState();

    if (QOpenGLContext *glContext = QOpenGLContext::currentContext())
    {
        glContext->functions()->glViewport(0, 0, surfaceWidth, surfaceHeight);
    }

    mpv_opengl_fbo mpvFbo = {0, surfaceWidth, surfaceHeight, 0};
    int flipY = 1;
    int blockForTargetTime = 0;

    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &mpvFbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flipY},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &blockForTargetTime},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };

    mpv_render_context_render(m_renderContext, params);
    QQuickOpenGLUtils::resetOpenGLState();
    m_window->endExternalCommands();

    m_frameUpdateScheduled.store(false, std::memory_order_release);
    if (m_frameUpdateDirty.exchange(false, std::memory_order_acq_rel))
    {
        scheduleFrameUpdate();
    }
}

void MpvWindowRenderer::releaseResources()
{
    mpv_render_context *renderContext = takeRenderContext();
    if (!renderContext)
    {
        return;
    }

    destroyRenderContext(renderContext);
}

void MpvWindowRenderer::requestWindowUpdate()
{
    if (!m_window || !m_view)
    {
        m_frameUpdateDirty.store(false, std::memory_order_release);
        m_frameUpdateScheduled.store(false, std::memory_order_release);
        return;
    }

    m_window->update();
}

void MpvWindowRenderer::reportSwap()
{
    if (!m_renderContext || !m_view || !m_view->hasMedia())
    {
        return;
    }

    mpv_render_context_report_swap(m_renderContext);
}

void MpvWindowRenderer::ensureRenderContext()
{
    if (m_renderContext || !m_mpv)
    {
        return;
    }

    mpv_opengl_init_params glInitParams = {getProcAddressMpv, nullptr};
    mpv_render_param params[5] = {};
    int paramIndex = 0;

    params[paramIndex++] =
        mpv_render_param{MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)};
    params[paramIndex++] =
        mpv_render_param{MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInitParams};

#if QT_CONFIG(wayland)
    if (auto *waylandApp = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
    {
        params[paramIndex++] = mpv_render_param{MPV_RENDER_PARAM_WL_DISPLAY, waylandApp->display()};
    }
#endif

#if QT_CONFIG(xcb)
    if (auto *x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>())
    {
        params[paramIndex++] = mpv_render_param{MPV_RENDER_PARAM_X11_DISPLAY, x11App->display()};
    }
#endif

    params[paramIndex] = mpv_render_param{MPV_RENDER_PARAM_INVALID, nullptr};

    if (mpv_render_context_create(&m_renderContext, m_mpv, params) < 0)
    {
        throw std::runtime_error("failed to initialize mpv GL context");
    }

    mpv_render_context_set_update_callback(m_renderContext, onMpvRenderUpdate, this);
    markRenderContextReady();
}

void MpvWindowRenderer::markRenderContextReady()
{
    if (m_renderContextReady || !m_view)
    {
        return;
    }

    m_renderContextReady = true;
    QMetaObject::invokeMethod(m_view, &MpvPlayerView::markRenderContextReady, Qt::QueuedConnection);
}

mpv_render_context *MpvWindowRenderer::takeRenderContext()
{
    mpv_render_context *renderContext = m_renderContext;
    m_renderContext = nullptr;
    m_renderContextReady = false;
    m_frameUpdateDirty.store(false, std::memory_order_release);
    m_frameUpdateScheduled.store(false, std::memory_order_release);

    if (renderContext)
    {
        mpv_render_context_set_update_callback(renderContext, nullptr, nullptr);
    }

    return renderContext;
}

void MpvWindowRenderer::destroyRenderContext(mpv_render_context *renderContext)
{
    if (!renderContext)
    {
        return;
    }

    mpv_render_context_free(renderContext);
}
