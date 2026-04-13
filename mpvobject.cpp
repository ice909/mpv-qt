#include "mpvobject.h"

#include <stdexcept>

#include <QGuiApplication>
#include <QMetaObject>
#include <QOpenGLContext>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>
#include <QtGui/qguiapplication_platform.h>
#include <QtOpenGL/QOpenGLFramebufferObject>

namespace
{

    void on_mpv_redraw(void *ctx)
    {
        MpvObject::on_update(ctx);
    }

    void *get_proc_address_mpv(void *ctx, const char *name)
    {
        Q_UNUSED(ctx)

        QOpenGLContext *glctx = QOpenGLContext::currentContext();
        if (!glctx)
        {
            return nullptr;
        }

        return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
    }

    void applyNetworkOptions(mpv_handle *mpv)
    {
        const QString headerFields = qEnvironmentVariable("MPV_QT_HTTP_HEADER_FIELDS");
        const QString cookie = qEnvironmentVariable("MPV_QT_COOKIE");

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
        const QString ipcServer = qEnvironmentVariable("LZCPLAYER_MPV_IPC");
        if (!ipcServer.isEmpty())
        {
            mpv_set_option_string(mpv, "input-ipc-server", ipcServer.toUtf8().constData());
        }
    }

} // namespace

class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(MpvObject *new_obj)
        : obj(new_obj)
    {
        mpv_set_wakeup_callback(obj->mpv, MpvObject::on_mpv_events, obj);
    }

    ~MpvRenderer() override = default;

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!obj->mpv_gl)
        {
            mpv_opengl_init_params gl_init_params = {get_proc_address_mpv, nullptr};
            mpv_render_param params[5] = {};
            int paramIndex = 0;

            params[paramIndex++] =
                mpv_render_param{MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)};
            params[paramIndex++] =
                mpv_render_param{MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params};

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

            if (mpv_render_context_create(&obj->mpv_gl, obj->mpv, params) < 0)
            {
                throw std::runtime_error("failed to initialize mpv GL context");
            }

            mpv_render_context_set_update_callback(obj->mpv_gl, on_mpv_redraw, obj);
            QMetaObject::invokeMethod(obj, &MpvObject::loadPendingFile, Qt::QueuedConnection);
        }

        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (obj->mpv_gl)
        {
            mpv_render_context_update(obj->mpv_gl);
        }

        obj->window()->beginExternalCommands();
        QQuickOpenGLUtils::resetOpenGLState();

        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpv_fbo = {
            static_cast<int>(fbo->handle()),
            fbo->width(),
            fbo->height(),
            0,
        };
        int flip_y = 0;
        int blockForTargetTime = 0;

        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpv_fbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
            {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &blockForTargetTime},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };

        mpv_render_context_render(obj->mpv_gl, params);
        QQuickOpenGLUtils::resetOpenGLState();
        obj->window()->endExternalCommands();
    }

private:
    MpvObject *obj;
};

MpvObject::MpvObject(QQuickItem *parent)
    : QQuickFramebufferObject(parent), mpv(mpv_create()), mpv_gl(nullptr), sourceUrl(), m_paused(true), m_timePos(0.0), m_duration(0.0), m_playbackSpeed(1.0), m_volume(100.0), m_subtitleId(0), m_reachedEof(false)
{
    if (!mpv)
    {
        throw std::runtime_error("could not create mpv context");
    }

    mpv_set_option_string(mpv, "terminal", "yes");
    mpv_set_option_string(mpv, "msg-level", "all=v");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "keep-open", "yes");
    applyNetworkOptions(mpv);
    applyIpcServerOption(mpv);

    if (mpv_initialize(mpv) < 0)
    {
        throw std::runtime_error("could not initialize mpv context");
    }

    mpv::qt::set_option_variant(mpv, "hwdec", "auto");
    mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "video-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "sid", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG);

    connect(this, &MpvObject::onUpdate, this, &MpvObject::doUpdate, Qt::QueuedConnection);
}

MpvObject::~MpvObject()
{
    if (mpv_gl)
    {
        mpv_render_context_free(mpv_gl);
    }

    mpv_terminate_destroy(mpv);
}

void MpvObject::on_update(void *ctx)
{
    auto *self = static_cast<MpvObject *>(ctx);
    emit self->onUpdate();
}

void MpvObject::on_mpv_events(void *ctx)
{
    auto *self = static_cast<MpvObject *>(ctx);
    QMetaObject::invokeMethod(self, &MpvObject::processMpvEvents, Qt::QueuedConnection);
}

bool MpvObject::isPlaying() const
{
    return !m_paused;
}

double MpvObject::timePos() const
{
    return m_timePos;
}

double MpvObject::duration() const
{
    return m_duration;
}

double MpvObject::playbackSpeed() const
{
    return m_playbackSpeed;
}

double MpvObject::volume() const
{
    return m_volume;
}

QString MpvObject::qualityLabel() const
{
    return m_qualityLabel;
}

QVariantList MpvObject::subtitleTracks() const
{
    return m_subtitleTracks;
}

int MpvObject::subtitleId() const
{
    return m_subtitleId;
}

void MpvObject::doUpdate()
{
    update();
}

void MpvObject::loadFile(const QString &path)
{
    if (path.isEmpty())
    {
        return;
    }

    const QString filePath = path;

    if (!mpv_gl)
    {
        pendingFile = filePath;
        update();
        return;
    }

    pendingFile.clear();
    sourceUrl = filePath;
    m_reachedEof = false;

    mpv::qt::command_variant(mpv, QVariantList{QStringLiteral("loadfile"), filePath});
}

void MpvObject::loadPendingFile()
{
    if (!pendingFile.isEmpty())
    {
        loadFile(pendingFile);
    }
}

void MpvObject::togglePause()
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

void MpvObject::seekRelative(double seconds)
{
    mpv::qt::command_variant(
        mpv, QVariantList{QStringLiteral("seek"), seconds, QStringLiteral("relative+exact")});
}

void MpvObject::seekTo(double seconds)
{
    mpv::qt::command_variant(
        mpv, QVariantList{QStringLiteral("seek"), seconds, QStringLiteral("absolute+exact")});
}

void MpvObject::setPlaybackSpeed(double speed)
{
    mpv::qt::set_property_variant(mpv, "speed", speed);
}

void MpvObject::setVolume(double volume)
{
    mpv::qt::set_property_variant(mpv, "volume", qBound(0.0, volume, 100.0));
}

void MpvObject::setSubtitleId(int id)
{
    if (id <= 0)
    {
        mpv::qt::set_property_variant(mpv, "sid", QStringLiteral("no"));
    }
    else
    {
        mpv::qt::set_property_variant(mpv, "sid", id);
    }
}

void MpvObject::processMpvEvents()
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

            if (qstrcmp(property->name, "pause") == 0)
            {
                if (property->format == MPV_FORMAT_FLAG && property->data)
                {
                    setPaused(*static_cast<int *>(property->data) != 0);
                }
            }
            else if (qstrcmp(property->name, "time-pos") == 0)
            {
                if (property->format == MPV_FORMAT_DOUBLE && property->data)
                {
                    setTimePos(*static_cast<double *>(property->data));
                }
                else
                {
                    setTimePos(0.0);
                }
            }
            else if (qstrcmp(property->name, "duration") == 0)
            {
                if (property->format == MPV_FORMAT_DOUBLE && property->data)
                {
                    setDuration(*static_cast<double *>(property->data));
                }
                else
                {
                    setDuration(0.0);
                }
            }
            else if (qstrcmp(property->name, "speed") == 0)
            {
                if (property->format == MPV_FORMAT_DOUBLE && property->data)
                {
                    setPlaybackSpeedValue(*static_cast<double *>(property->data));
                }
            }
            else if (qstrcmp(property->name, "volume") == 0)
            {
                if (property->format == MPV_FORMAT_DOUBLE && property->data)
                {
                    setVolumeValue(*static_cast<double *>(property->data));
                }
            }
            else if (qstrcmp(property->name, "sid") == 0)
            {
                if (property->format == MPV_FORMAT_INT64 && property->data)
                {
                    setSubtitleIdValue(static_cast<int>(*static_cast<int64_t *>(property->data)));
                }
                else
                {
                    setSubtitleIdValue(0);
                }
            }
            else if (qstrcmp(property->name, "eof-reached") == 0)
            {
                if (property->format == MPV_FORMAT_FLAG && property->data)
                {
                    m_reachedEof = *static_cast<int *>(property->data) != 0;
                }
                else
                {
                    m_reachedEof = false;
                }
            }
            else if (qstrcmp(property->name, "video-params") == 0)
            {
                QString label;
                if (property->format == MPV_FORMAT_NODE && property->data)
                {
                    const auto value =
                        mpv::qt::node_to_variant(static_cast<mpv_node *>(property->data)).toMap();
                    const int width = value.value(QStringLiteral("w")).toInt();
                    const int height = value.value(QStringLiteral("h")).toInt();
                    if (width > 0 && height > 0)
                    {
                        label = QStringLiteral("%1p").arg(height);
                    }
                }
                setQualityLabel(label);
            }
            else if (qstrcmp(property->name, "track-list") == 0)
            {
                QVariantList tracks{QVariantMap{
                    {QStringLiteral("id"), 0},
                    {QStringLiteral("title"), QStringLiteral("无字幕")},
                }};

                if (property->format == MPV_FORMAT_NODE && property->data)
                {
                    const auto list =
                        mpv::qt::node_to_variant(static_cast<mpv_node *>(property->data)).toList();
                    for (const auto &entry : list)
                    {
                        const auto track = entry.toMap();
                        if (track.value(QStringLiteral("type")).toString() != QStringLiteral("sub"))
                        {
                            continue;
                        }

                        const int id = track.value(QStringLiteral("id")).toInt();
                        QString title = track.value(QStringLiteral("title")).toString();
                        if (title.isEmpty())
                        {
                            title = track.value(QStringLiteral("lang")).toString();
                        }
                        if (title.isEmpty())
                        {
                            title = QStringLiteral("字幕 %1").arg(id);
                        }

                        tracks.append(QVariantMap{
                            {QStringLiteral("id"), id},
                            {QStringLiteral("title"), title},
                        });
                    }
                }

                setSubtitleTracks(tracks);
            }
        }
        else if (event->event_id == MPV_EVENT_END_FILE)
        {
            m_reachedEof = true;
            setTimePos(0.0);
            setPaused(true);
        }
        else if (event->event_id == MPV_EVENT_FILE_LOADED)
        {
            m_reachedEof = false;
        }
    }
}

void MpvObject::command(const QVariant &params)
{
    mpv::qt::command_variant(mpv, params);
}

void MpvObject::setProperty(const QString &name, const QVariant &value)
{
    mpv::qt::set_property_variant(mpv, name, value);
}

QQuickFramebufferObject::Renderer *MpvObject::createRenderer() const
{
    window()->setPersistentGraphics(true);
    window()->setPersistentSceneGraph(true);
    return new MpvRenderer(const_cast<MpvObject *>(this));
}

void MpvObject::setPaused(bool paused)
{
    if (m_paused == paused)
    {
        return;
    }

    m_paused = paused;
    emit playingChanged();
}

void MpvObject::setTimePos(double seconds)
{
    if (qFuzzyCompare(m_timePos, seconds))
    {
        return;
    }

    m_timePos = seconds;
    emit timePosChanged();
}

void MpvObject::setDuration(double seconds)
{
    if (qFuzzyCompare(m_duration, seconds))
    {
        return;
    }

    m_duration = seconds;
    emit durationChanged();
}

void MpvObject::setPlaybackSpeedValue(double speed)
{
    if (qFuzzyCompare(m_playbackSpeed, speed))
    {
        return;
    }

    m_playbackSpeed = speed;
    emit playbackSpeedChanged();
}

void MpvObject::setVolumeValue(double volume)
{
    if (qFuzzyCompare(m_volume, volume))
    {
        return;
    }

    m_volume = volume;
    emit volumeChanged();
}

void MpvObject::setQualityLabel(const QString &label)
{
    if (m_qualityLabel == label)
    {
        return;
    }

    m_qualityLabel = label;
    emit qualityLabelChanged();
}

void MpvObject::setSubtitleTracks(const QVariantList &tracks)
{
    if (m_subtitleTracks == tracks)
    {
        return;
    }

    m_subtitleTracks = tracks;
    emit subtitleTracksChanged();
}

void MpvObject::setSubtitleIdValue(int id)
{
    const int normalizedId = id > 0 ? id : 0;
    if (m_subtitleId == normalizedId)
    {
        return;
    }

    m_subtitleId = normalizedId;
    emit subtitleIdChanged();
}
