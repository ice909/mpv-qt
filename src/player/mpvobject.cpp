#include "src/player/mpvobject.h"

#include <algorithm>
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

    QString formatSubtitleTitle(QString title, const QString &lang)
    {
        title = title.trimmed();
        if (title.isEmpty())
        {
            return title;
        }

        title.remove(QStringLiteral("HDMV_PGS_SUBTITLE"));
        title.remove(QStringLiteral("PGS"));
        title.remove(QStringLiteral("SUP"));
        title.remove(QChar('/'));
        title = title.simplified();

        const QString upperLang = lang.trimmed().toUpper();
        if (!upperLang.isEmpty())
        {
            title.remove(upperLang, Qt::CaseInsensitive);
            title = title.simplified();
        }

        if (title.isEmpty())
        {
            if (upperLang == QStringLiteral("CHS"))
            {
                return QStringLiteral("简体中文");
            }
            if (upperLang == QStringLiteral("CHT"))
            {
                return QStringLiteral("繁体中文");
            }
            if (upperLang == QStringLiteral("CHS/ENG"))
            {
                return QStringLiteral("简英字幕");
            }
            if (upperLang == QStringLiteral("CHT/ENG"))
            {
                return QStringLiteral("繁英字幕");
            }
        }

        return title;
    }

    QString formatSubtitleCodec(const QString &codec)
    {
        const QString upper = codec.trimmed().toUpper();
        if (upper.contains(QStringLiteral("PGS")) || upper.contains(QStringLiteral("HDMV_PGS")))
        {
            return QStringLiteral("SUP");
        }
        if (upper.contains(QStringLiteral("SUBRIP")) || upper == QStringLiteral("SRT"))
        {
            return QStringLiteral("SRT");
        }
        if (upper.contains(QStringLiteral("ASS")))
        {
            return QStringLiteral("ASS");
        }
        if (upper.contains(QStringLiteral("SSA")))
        {
            return QStringLiteral("SSA");
        }
        if (upper.contains(QStringLiteral("WEBVTT")) || upper == QStringLiteral("VTT"))
        {
            return QStringLiteral("VTT");
        }
        return upper;
    }

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
        const QString headerFields = qEnvironmentVariable("LZC_PLAYER_HTTP_HEADER_FIELDS");
        const QString cookie = qApp->property("lzcPlayerCookie").toString();

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
    : QQuickFramebufferObject(parent), mpv(mpv_create()), mpv_gl(nullptr), sourceUrl(), m_paused(true), m_timePos(0.0), m_duration(0.0), m_bufferDuration(0.0), m_bufferEnd(0.0), m_networkSpeed(0), m_playbackSpeed(1.0), m_volume(100.0), m_videoId(0), m_subtitleId(0), m_consoleOpen(false), m_reachedEof(false)
{
    if (!mpv)
    {
        throw std::runtime_error("could not create mpv context");
    }

    mpv_set_option_string(mpv, "terminal", "yes");
    mpv_set_option_string(mpv, "msg-level", "all=v");
    mpv_set_option_string(mpv, "hwdec", "auto");
    mpv_set_option_string(mpv, "gpu-context", "auto");
    mpv_set_option_string(mpv, "vo", "libmpv");
    mpv_set_option_string(mpv, "keep-open", "yes");
    applyNetworkOptions(mpv);
    applyIpcServerOption(mpv);

    if (mpv_initialize(mpv) < 0)
    {
        throw std::runtime_error("could not initialize mpv context");
    }

    mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "demuxer-cache-duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "cache-speed", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, 0, "video-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(mpv, 0, "vid", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "sid", MPV_FORMAT_INT64);
    mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv, 0, "user-data/mpv/console/open", MPV_FORMAT_FLAG);

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

double MpvObject::bufferDuration() const
{
    return m_bufferDuration;
}

double MpvObject::bufferEnd() const
{
    return m_bufferEnd;
}

qint64 MpvObject::networkSpeed() const
{
    return m_networkSpeed;
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

QVariantList MpvObject::videoTracks() const
{
    return m_videoTracks;
}

int MpvObject::videoId() const
{
    return m_videoId;
}

QVariantList MpvObject::subtitleTracks() const
{
    return m_subtitleTracks;
}

int MpvObject::subtitleId() const
{
    return m_subtitleId;
}

bool MpvObject::consoleOpen() const
{
    return m_consoleOpen;
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
    setTimePos(0.0);
    setDuration(0.0);
    setBufferDuration(0.0);
    setBufferEnd(0.0);

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

void MpvObject::setVideoId(int id)
{
    if (id <= 0)
    {
        mpv::qt::set_property_variant(mpv, "vid", QStringLiteral("auto"));
    }
    else
    {
        mpv::qt::set_property_variant(mpv, "vid", id);
    }
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
            else if (qstrcmp(property->name, "demuxer-cache-duration") == 0)
            {
                if (property->format == MPV_FORMAT_DOUBLE && property->data)
                {
                    setBufferDuration(*static_cast<double *>(property->data));
                }
                else
                {
                    setBufferDuration(0.0);
                }
            }
            else if (qstrcmp(property->name, "cache-speed") == 0)
            {
                if (property->format == MPV_FORMAT_INT64 && property->data)
                {
                    setNetworkSpeed(static_cast<qint64>(*static_cast<int64_t *>(property->data)));
                }
                else
                {
                    setNetworkSpeed(0);
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
            else if (qstrcmp(property->name, "vid") == 0)
            {
                if (property->format == MPV_FORMAT_INT64 && property->data)
                {
                    setVideoIdValue(static_cast<int>(*static_cast<int64_t *>(property->data)));
                }
                else
                {
                    setVideoIdValue(0);
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
            else if (qstrcmp(property->name, "user-data/mpv/console/open") == 0)
            {
                if (property->format == MPV_FORMAT_FLAG && property->data)
                {
                    setConsoleOpen(*static_cast<int *>(property->data) != 0);
                }
                else
                {
                    setConsoleOpen(false);
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
                // video-params describes the decoded output size, not a user-facing
                // quality selection. Keep the quality button tied to track choices.
            }
            else if (qstrcmp(property->name, "track-list") == 0)
            {
                QVariantList videoTracks;
                int selectedVideoId = 0;
                QVariantList tracks{QVariantMap{
                    {QStringLiteral("id"), 0},
                    {QStringLiteral("title"), QStringLiteral("关闭")},
                    {QStringLiteral("detail"), QString()},
                    {QStringLiteral("isDefault"), false},
                }};

                if (property->format == MPV_FORMAT_NODE && property->data)
                {
                    const auto list =
                        mpv::qt::node_to_variant(static_cast<mpv_node *>(property->data)).toList();
                    for (const auto &entry : list)
                    {
                        const auto track = entry.toMap();
                        const QString type = track.value(QStringLiteral("type")).toString();
                        if (type == QStringLiteral("video"))
                        {
                            const int id = track.value(QStringLiteral("id")).toInt();
                            const int width = track.value(QStringLiteral("demux-w")).toInt();
                            const int height = track.value(QStringLiteral("demux-h")).toInt();
                            const qint64 bitrate = track.value(QStringLiteral("demux-bitrate")).toLongLong();
                            const qint64 hlsBitrate = track.value(QStringLiteral("hls-bitrate")).toLongLong();
                            const qint64 effectiveBitrate = bitrate > 0 ? bitrate : hlsBitrate;
                            if (track.value(QStringLiteral("selected")).toBool())
                            {
                                selectedVideoId = id;
                            }

                            QString label;
                            if (height >= 2160 || width >= 3840)
                            {
                                label = QStringLiteral("4K");
                            }
                            else if (height > 0)
                            {
                                label = QStringLiteral("%1P").arg(height);
                            }
                            else
                            {
                                label = QStringLiteral("原画质");
                            }

                            QString detail = label;
                            if (effectiveBitrate > 0)
                            {
                                detail += QStringLiteral(" %1Mbps").arg(
                                    QString::number(double(effectiveBitrate) / 1000000.0, 'f', 0));
                            }

                            videoTracks.append(QVariantMap{
                                {QStringLiteral("id"), id},
                                {QStringLiteral("label"), label},
                                {QStringLiteral("detail"), detail},
                                {QStringLiteral("width"), width},
                                {QStringLiteral("height"), height},
                                {QStringLiteral("bitrate"), effectiveBitrate},
                            });
                            continue;
                        }

                        if (type != QStringLiteral("sub"))
                        {
                            continue;
                        }

                        const int id = track.value(QStringLiteral("id")).toInt();
                        const QString lang = track.value(QStringLiteral("lang")).toString();
                        const QString codec = formatSubtitleCodec(track.value(QStringLiteral("codec")).toString());
                        const bool isDefault = track.value(QStringLiteral("default")).toBool();
                        QString title = formatSubtitleTitle(track.value(QStringLiteral("title")).toString(), lang);
                        if (title.isEmpty())
                        {
                            title = QStringLiteral("字幕 %1").arg(id);
                        }

                        QString detail = codec;
                        if (!lang.isEmpty())
                        {
                            detail += detail.isEmpty() ? lang.toUpper() : QStringLiteral(" %1").arg(lang.toUpper());
                        }

                        tracks.append(QVariantMap{
                            {QStringLiteral("id"), id},
                            {QStringLiteral("title"), title},
                            {QStringLiteral("detail"), detail},
                            {QStringLiteral("isDefault"), isDefault},
                        });
                    }
                }

                std::sort(videoTracks.begin(), videoTracks.end(), [](const QVariant &lhs, const QVariant &rhs) {
                    const auto left = lhs.toMap();
                    const auto right = rhs.toMap();

                    const qint64 leftBitrate = left.value(QStringLiteral("bitrate")).toLongLong();
                    const qint64 rightBitrate = right.value(QStringLiteral("bitrate")).toLongLong();
                    if (leftBitrate != rightBitrate)
                    {
                        return leftBitrate > rightBitrate;
                    }

                    const int leftHeight = left.value(QStringLiteral("height")).toInt();
                    const int rightHeight = right.value(QStringLiteral("height")).toInt();
                    if (leftHeight != rightHeight)
                    {
                        return leftHeight > rightHeight;
                    }

                    return left.value(QStringLiteral("width")).toInt()
                        > right.value(QStringLiteral("width")).toInt();
                });

                if (!videoTracks.isEmpty())
                {
                    auto first = videoTracks.first().toMap();
                    first.insert(QStringLiteral("label"), QStringLiteral("原画质"));
                    videoTracks[0] = first;
                }

                setVideoTracks(videoTracks);
                if (selectedVideoId > 0)
                {
                    setVideoIdValue(selectedVideoId);
                }
                setSubtitleTracks(tracks);
            }
        }
        else if (event->event_id == MPV_EVENT_END_FILE)
        {
            m_reachedEof = true;
            setTimePos(0.0);
            setBufferDuration(0.0);
            setBufferEnd(0.0);
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

QVariant MpvObject::getProperty(const QString &name)
{
    return mpv::qt::get_property_variant(mpv, name);
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
    const double safeSeconds = qMax(0.0, seconds);
    if (qFuzzyCompare(m_timePos, safeSeconds))
    {
        return;
    }

    const double previousTimePos = m_timePos;
    m_timePos = safeSeconds;
    emit timePosChanged();

    // Keep the buffered endpoint moving during normal playback, but avoid
    // reusing the previous cache window after a large seek jump.
    if (qAbs(m_timePos - previousTimePos) <= 1.0)
    {
        setBufferEnd(m_timePos + m_bufferDuration);
    }
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

void MpvObject::setBufferDuration(double seconds)
{
    if (qFuzzyCompare(m_bufferDuration, seconds))
    {
        return;
    }

    m_bufferDuration = qMax(0.0, seconds);
    emit bufferDurationChanged();
    setBufferEnd(m_timePos + m_bufferDuration);
}

void MpvObject::setBufferEnd(double seconds)
{
    const double safeSeconds = qMax(0.0, seconds);
    if (qFuzzyCompare(m_bufferEnd, safeSeconds))
    {
        return;
    }

    m_bufferEnd = safeSeconds;
    emit bufferEndChanged();
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

void MpvObject::setNetworkSpeed(qint64 bytesPerSecond)
{
    if (m_networkSpeed == bytesPerSecond)
    {
        return;
    }

    m_networkSpeed = qMax<qint64>(0, bytesPerSecond);
    emit networkSpeedChanged();
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

void MpvObject::setVideoTracks(const QVariantList &tracks)
{
    if (m_videoTracks == tracks)
    {
        return;
    }

    m_videoTracks = tracks;
    emit videoTracksChanged();

    QString label = QStringLiteral("原画质");
    for (const auto &entry : m_videoTracks)
    {
        const auto track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() == m_videoId)
        {
            label = track.value(QStringLiteral("label")).toString();
            break;
        }
    }
    setQualityLabel(label);
}

void MpvObject::setVideoIdValue(int id)
{
    const int normalizedId = id > 0 ? id : 0;
    if (m_videoId == normalizedId)
    {
        return;
    }

    m_videoId = normalizedId;

    QString label = QStringLiteral("原画质");
    for (const auto &entry : m_videoTracks)
    {
        const auto track = entry.toMap();
        if (track.value(QStringLiteral("id")).toInt() == normalizedId)
        {
            label = track.value(QStringLiteral("label")).toString();
            break;
        }
    }
    setQualityLabel(label);
    emit videoIdChanged();
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

void MpvObject::setConsoleOpen(bool open)
{
    if (m_consoleOpen == open)
    {
        return;
    }

    m_consoleOpen = open;
    emit consoleOpenChanged();
}
