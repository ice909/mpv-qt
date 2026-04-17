#include "src/player/mpvplayerview.h"

#include <stdexcept>

#include <QGuiApplication>
#include <QMetaObject>
#include <QOpenGLContext>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>
#include <QtGui/qguiapplication_platform.h>
#include <QtOpenGL/QOpenGLFramebufferObject>

#include <mpv/render_gl.h>

#include "src/player/mpvplayersession.h"

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
    auto *view = static_cast<MpvPlayerView *>(ctx);
    emit view->frameUpdateRequested();
}

class MpvRenderContext
{
public:
    static bool isReady(mpv_render_context *context)
    {
        return context != nullptr;
    }

    static void ensureCreated(mpv_render_context **context, mpv_handle *mpv, MpvPlayerView *view)
    {
        if (*context)
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
            params[paramIndex++] =
                mpv_render_param{MPV_RENDER_PARAM_WL_DISPLAY, waylandApp->display()};
        }
#endif

#if QT_CONFIG(xcb)
        if (auto *x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>())
        {
            params[paramIndex++] =
                mpv_render_param{MPV_RENDER_PARAM_X11_DISPLAY, x11App->display()};
        }
#endif

        params[paramIndex] = mpv_render_param{MPV_RENDER_PARAM_INVALID, nullptr};

        if (mpv_render_context_create(context, mpv, params) < 0)
        {
            throw std::runtime_error("failed to initialize mpv GL context");
        }

        mpv_render_context_set_update_callback(*context, onMpvRenderUpdate, view);
    }

    static void free(mpv_render_context **context)
    {
        if (!*context)
        {
            return;
        }

        mpv_render_context_set_update_callback(*context, nullptr, nullptr);
        mpv_render_context_free(*context);
        *context = nullptr;
    }

    static void render(mpv_render_context *context, QQuickWindow *window, QOpenGLFramebufferObject *fbo)
    {
        if (!context || !window || !fbo)
        {
            return;
        }

        mpv_render_context_update(context);

        window->beginExternalCommands();
        QQuickOpenGLUtils::resetOpenGLState();

        mpv_opengl_fbo mpvFbo = {
            static_cast<int>(fbo->handle()),
            fbo->width(),
            fbo->height(),
            0,
        };
        int flipY = 0;
        int blockForTargetTime = 0;

        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpvFbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &blockForTargetTime},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };

        mpv_render_context_render(context, params);
        QQuickOpenGLUtils::resetOpenGLState();
        window->endExternalCommands();
    }
};

class MpvPlayerViewRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvPlayerViewRenderer(MpvPlayerView *view)
        : view_(view)
    {
    }

    ~MpvPlayerViewRenderer() override = default;

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        Q_UNUSED(size)
        view_->ensureRenderContext();
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        view_->renderFrame(framebufferObject());
    }

private:
    MpvPlayerView *view_;
};

} // namespace

MpvPlayerView::MpvPlayerView(QQuickItem *parent)
    : QQuickFramebufferObject(parent),
      m_session(new MpvPlayerSession(this)),
      m_renderContextReady(false),
      m_renderContext(nullptr)
{
    connect(this, &MpvPlayerView::frameUpdateRequested, this, &MpvPlayerView::requestFrameUpdate, Qt::QueuedConnection);
    connect(m_session, &MpvPlayerSession::playingChanged, this, &MpvPlayerView::playingChanged);
    connect(m_session, &MpvPlayerSession::timePosChanged, this, &MpvPlayerView::timePosChanged);
    connect(m_session, &MpvPlayerSession::durationChanged, this, &MpvPlayerView::durationChanged);
    connect(m_session, &MpvPlayerSession::bufferDurationChanged, this, &MpvPlayerView::bufferDurationChanged);
    connect(m_session, &MpvPlayerSession::bufferEndChanged, this, &MpvPlayerView::bufferEndChanged);
    connect(m_session, &MpvPlayerSession::networkSpeedChanged, this, &MpvPlayerView::networkSpeedChanged);
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
    MpvRenderContext::free(&m_renderContext);
}

QQuickFramebufferObject::Renderer *MpvPlayerView::createRenderer() const
{
    window()->setPersistentGraphics(true);
    window()->setPersistentSceneGraph(true);
    return new MpvPlayerViewRenderer(const_cast<MpvPlayerView *>(this));
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

void MpvPlayerView::loadFile(const QString &path)
{
    if (path.isEmpty())
    {
        return;
    }

    if (!m_renderContextReady)
    {
        m_pendingFile = path;
        update();
        return;
    }

    m_pendingFile.clear();
    m_session->loadFile(path);
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

void MpvPlayerView::requestFrameUpdate()
{
    update();
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
    m_session->loadFile(pendingFile);
}

mpv_handle *MpvPlayerView::mpvHandle() const
{
    return m_session->handle();
}

void MpvPlayerView::ensureRenderContext()
{
    MpvRenderContext::ensureCreated(&m_renderContext, mpvHandle(), this);
    QMetaObject::invokeMethod(this, &MpvPlayerView::markRenderContextReady, Qt::QueuedConnection);
}

void MpvPlayerView::renderFrame(QOpenGLFramebufferObject *fbo)
{
    MpvRenderContext::render(m_renderContext, window(), fbo);
}
