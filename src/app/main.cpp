#include "src/app/playerwindow.h"
#include "src/player/videoplayerview.h"

#include <clocale>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

#include <QApplication>
#include <QColor>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QLoggingCategory>
#include <QMessageBox>
#include <QMutex>
#include <QMutexLocker>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickView>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTextStream>

namespace {

QFile *g_logFile = nullptr;
QString g_logFilePath;
QMutex g_logMutex;

struct StartupOptions
{
    QString file;
    QVariantList playlist;
    QString start;
    QString cookie;
    QString inputIpcServer;
};

void setApplicationMetadata()
{
    QCoreApplication::setApplicationName(QStringLiteral("lzc-player"));
    QCoreApplication::setApplicationVersion(QString::fromLatin1(LZC_PLAYER_VERSION));
}

void configureQtQuickControlsStyle()
{
    if (!qEnvironmentVariableIsSet("QT_QUICK_CONTROLS_STYLE"))
    {
        qputenv("QT_QUICK_CONTROLS_STYLE", QByteArrayLiteral("Basic"));
    }
}

QString messageTypeName(QtMsgType type)
{
    switch (type)
    {
    case QtDebugMsg:
        return QStringLiteral("DEBUG");
    case QtInfoMsg:
        return QStringLiteral("INFO");
    case QtWarningMsg:
        return QStringLiteral("WARN");
    case QtCriticalMsg:
        return QStringLiteral("ERROR");
    case QtFatalMsg:
        return QStringLiteral("FATAL");
    }

    return QStringLiteral("LOG");
}

void appendLogLine(const QString &line)
{
    QMutexLocker locker(&g_logMutex);

    if (g_logFile && g_logFile->isOpen())
    {
        QTextStream stream(g_logFile);
        stream << line << Qt::endl;
        g_logFile->flush();
    }

    std::fprintf(stderr, "%s\n", line.toLocal8Bit().constData());
    std::fflush(stderr);
}

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    QString line = QStringLiteral("%1 [%2] %3")
                       .arg(QDateTime::currentDateTime().toString(Qt::ISODateWithMs),
                            messageTypeName(type),
                            message);

    if (context.file && *context.file)
    {
        line += QStringLiteral(" (%1:%2)").arg(QString::fromLocal8Bit(context.file)).arg(context.line);
    }

    appendLogLine(line);

    if (type == QtFatalMsg)
    {
        std::abort();
    }
}

void installFileLogging()
{
    QString logDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (logDir.isEmpty())
    {
        logDir = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("logs"));
    }

    QDir().mkpath(logDir);
    g_logFilePath = QDir(logDir).filePath(QStringLiteral("lzc-player.log"));

    if (!g_logFile)
    {
        g_logFile = new QFile(g_logFilePath);
        g_logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    }

    qInstallMessageHandler(messageHandler);
    qInfo().noquote() << "Logging to" << QDir::toNativeSeparators(g_logFilePath);
}

QString startupFailureMessage(const QString &details)
{
    QString message = details.trimmed();
    if (message.isEmpty())
    {
        message = QStringLiteral("程序启动失败。");
    }

    if (!g_logFilePath.isEmpty())
    {
        message += QStringLiteral("\n\n日志文件:\n%1").arg(QDir::toNativeSeparators(g_logFilePath));
    }

    return message;
}

void showStartupFailureDialog(const QString &details)
{
    QMessageBox::critical(nullptr, QStringLiteral("lzc-player"), startupFailureMessage(details));
}

void logQmlErrors(const QList<QQmlError> &errors)
{
    for (const QQmlError &error : errors)
    {
        qCritical().noquote() << error.toString();
    }
}

void configureCommandLineParser(QCommandLineParser &parser)
{
    const QCommandLineOption cookieOption(
        QStringLiteral("cookie"),
        QStringLiteral("HTTP Cookie header value to send with media requests."),
        QStringLiteral("cookie"));
    const QCommandLineOption playlistFileOption(
        QStringLiteral("playlist-file"),
        QStringLiteral("Path to a JSON playlist file."),
        QStringLiteral("file"));
    const QCommandLineOption playlistJsonOption(
        QStringLiteral("playlist-json"),
        QStringLiteral("Inline JSON playlist payload."),
        QStringLiteral("json"));
    const QCommandLineOption startOption(
        QStringLiteral("start"),
        QStringLiteral("Seek to given position on startup. Supports percent, seconds, or timestamps like 12:34 and 01:02:03."),
        QStringLiteral("time"));
    const QCommandLineOption inputIpcServerOption(
        QStringLiteral("input-ipc-server"),
        QStringLiteral("Path to the mpv JSON IPC server socket."),
        QStringLiteral("path"));
    const QCommandLineOption configFileOption(
        QStringList{QStringLiteral("f"), QStringLiteral("config-file")},
        QStringLiteral("Path to a JSON config file. Command line arguments override config values."),
        QStringLiteral("file"));

    parser.setApplicationDescription(
        QStringLiteral("Lzc video player\n"
                       "\n"
                       "Examples:\n"
                       "  lzc-player --start=90 <file>\n"
                       "  lzc-player --start=12:34 <file>\n"
                       "  lzc-player --start=50% <file>\n"
                       "  lzc-player --playlist-file=episodes.json\n"
                       "  lzc-player -f player.json"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption(configFileOption);
    parser.addOption(cookieOption);
    parser.addOption(playlistFileOption);
    parser.addOption(playlistJsonOption);
    parser.addOption(startOption);
    parser.addOption(inputIpcServerOption);
    parser.addPositionalArgument(QStringLiteral("file"), QStringLiteral("Media file or URL to open."));
}

bool hasCommandLineOption(int argc, char **argv, std::initializer_list<const char *> names)
{
    for (int i = 1; i < argc; ++i) {
        const QString argument = QString::fromLocal8Bit(argv[i]);
        for (const char *name : names) {
            if (argument == QString::fromLatin1(name)) {
                return true;
            }
        }
    }

    return false;
}

QString resolveConfigPath(const QString &path, const QString &baseDir)
{
    if (path.isEmpty() || QDir::isAbsolutePath(path) || path.contains(QStringLiteral("://")))
    {
        return path;
    }

    return QDir(baseDir).filePath(path);
}

bool readJsonString(const QJsonObject &object, std::initializer_list<const char *> names, QString *value)
{
    for (const char *name : names)
    {
        const QString key = QString::fromLatin1(name);
        if (!object.contains(key) || object.value(key).isNull())
        {
            continue;
        }

        const QJsonValue jsonValue = object.value(key);
        if (jsonValue.isString())
        {
            *value = jsonValue.toString();
            return true;
        }

        if (jsonValue.isDouble() || jsonValue.isBool())
        {
            *value = jsonValue.toVariant().toString();
            return true;
        }

        qWarning().noquote() << "Ignoring config value with unsupported type:" << key;
        return false;
    }

    return false;
}

QVariantList parsePlaylistPayload(const QByteArray &payload, QString *error)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (document.isNull())
    {
        if (error)
        {
            *error = parseError.errorString();
        }
        return {};
    }

    if (!document.isArray())
    {
        if (error)
        {
            *error = QStringLiteral("playlist payload must be a JSON array");
        }
        return {};
    }

    return document.array().toVariantList();
}

QVariantList parsePlaylistConfigValue(const QJsonValue &value, QString *error)
{
    if (value.isArray())
    {
        return value.toArray().toVariantList();
    }

    if (value.isString())
    {
        return parsePlaylistPayload(value.toString().toUtf8(), error);
    }

    if (error)
    {
        *error = QStringLiteral("playlist config value must be a JSON array or JSON string");
    }
    return {};
}

QVariantList loadPlaylistFromFile(const QString &fileName)
{
    QString error;
    QFile file(fileName);
    if (!file.open(QIODevice::ReadOnly))
    {
        qWarning().noquote() << "Failed to open playlist file:" << file.fileName();
        return {};
    }

    const QVariantList playlist = parsePlaylistPayload(file.readAll(), &error);
    if (!error.isEmpty())
    {
        qWarning().noquote() << "Failed to parse playlist file JSON:" << error;
    }
    return playlist;
}

QVariantList loadPlaylistFromJson(const QString &json)
{
    QString error;
    const QVariantList playlist = parsePlaylistPayload(json.toUtf8(), &error);
    if (!error.isEmpty())
    {
        qWarning().noquote() << "Failed to parse playlist JSON:" << error;
    }
    return playlist;
}

bool loadStartupOptionsFromConfigFile(const QString &fileName, StartupOptions *options)
{
    QFile file(fileName);
    if (!file.open(QIODevice::ReadOnly))
    {
        qCritical().noquote() << "Failed to open config file:" << file.fileName();
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (document.isNull())
    {
        qCritical().noquote() << "Failed to parse config file JSON:" << parseError.errorString();
        return false;
    }

    if (!document.isObject())
    {
        qCritical().noquote() << "Config file JSON must be an object:" << file.fileName();
        return false;
    }

    const QFileInfo configFileInfo(fileName);
    const QString configDir = configFileInfo.absoluteDir().absolutePath();
    const QJsonObject object = document.object();

    QString filePath;
    if (readJsonString(object, {"file"}, &filePath))
    {
        options->file = resolveConfigPath(filePath.trimmed(), configDir);
    }

    readJsonString(object, {"start"}, &options->start);
    readJsonString(object, {"cookie"}, &options->cookie);
    readJsonString(object, {"inputIpcServer", "input-ipc-server"}, &options->inputIpcServer);

    QString playlistFileName;
    if (readJsonString(object, {"playlistFile", "playlist-file"}, &playlistFileName))
    {
        options->playlist = loadPlaylistFromFile(resolveConfigPath(playlistFileName.trimmed(), configDir));
    }

    if (object.contains(QStringLiteral("playlist")))
    {
        QString error;
        const QVariantList playlist = parsePlaylistConfigValue(object.value(QStringLiteral("playlist")), &error);
        if (!error.isEmpty())
        {
            qWarning().noquote() << "Failed to parse config playlist:" << error;
        }
        else
        {
            options->playlist = playlist;
        }
    }

    if (object.contains(QStringLiteral("playlistJson")) || object.contains(QStringLiteral("playlist-json")))
    {
        const QJsonValue value = object.contains(QStringLiteral("playlistJson"))
            ? object.value(QStringLiteral("playlistJson"))
            : object.value(QStringLiteral("playlist-json"));
        QString error;
        const QVariantList playlist = parsePlaylistConfigValue(value, &error);
        if (!error.isEmpty())
        {
            qWarning().noquote() << "Failed to parse config playlistJson:" << error;
        }
        else
        {
            options->playlist = playlist;
        }
    }

    return true;
}

bool loadStartupOptionsFromParser(const QCommandLineParser &parser, StartupOptions *options)
{
    if (parser.isSet(QStringLiteral("config-file")))
    {
        if (!loadStartupOptionsFromConfigFile(parser.value(QStringLiteral("config-file")), options))
        {
            return false;
        }
    }

    if (parser.isSet(QStringLiteral("playlist-file")))
    {
        options->playlist = loadPlaylistFromFile(parser.value(QStringLiteral("playlist-file")));
    }
    else if (parser.isSet(QStringLiteral("playlist-json")))
    {
        options->playlist = loadPlaylistFromJson(parser.value(QStringLiteral("playlist-json")));
    }

    const QStringList positionalArguments = parser.positionalArguments();
    if (!positionalArguments.isEmpty())
    {
        options->file = positionalArguments.first();
    }

    if (parser.isSet(QStringLiteral("start")))
    {
        options->start = parser.value(QStringLiteral("start"));
    }

    if (parser.isSet(QStringLiteral("cookie")))
    {
        options->cookie = parser.value(QStringLiteral("cookie"));
    }

    if (parser.isSet(QStringLiteral("input-ipc-server")))
    {
        options->inputIpcServer = parser.value(QStringLiteral("input-ipc-server"));
    }

    return true;
}

} // namespace

int main(int argc, char **argv)
{
    try
    {
        if (hasCommandLineOption(argc, argv, {"--help", "--help-all", "-h", "-?"})) {
            QCoreApplication app(argc, argv);
            setApplicationMetadata();

            QCommandLineParser parser;
            configureCommandLineParser(parser);
            parser.process(app);
        }

        if (hasCommandLineOption(argc, argv, {"--version", "-v"})) {
            QCoreApplication app(argc, argv);
            setApplicationMetadata();

            QCommandLineParser parser;
            configureCommandLineParser(parser);
            parser.process(app);
        }

        configureQtQuickControlsStyle();
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        QApplication app(argc, argv);
        setApplicationMetadata();
        installFileLogging();
        qInfo().noquote() << "Qt Quick Controls style:"
                          << qEnvironmentVariable("QT_QUICK_CONTROLS_STYLE", QStringLiteral("Basic"));

        QCommandLineParser parser;
        configureCommandLineParser(parser);
        parser.process(app);

        StartupOptions startupOptions;
        if (!loadStartupOptionsFromParser(parser, &startupOptions))
        {
            showStartupFailureDialog(QStringLiteral("配置解析失败。"));
            return 1;
        }

        const QString startupFile = startupOptions.playlist.isEmpty() ? startupOptions.file : QString();
        app.setProperty("lzcPlayerCookie", startupOptions.cookie);
        app.setProperty("lzcPlayerInputIpcServer", startupOptions.inputIpcServer);

        std::setlocale(LC_NUMERIC, "C");

        qmlRegisterType<VideoPlayerView>("LzcPlayer", 1, 0, "VideoPlayerView");

        PlayerWindow view;
        QObject::connect(&view, &QQuickView::statusChanged, &view, [&view](QQuickView::Status status) {
            if (status == QQuickView::Error)
            {
                logQmlErrors(view.errors());
            }
        });
        QObject::connect(&view, &QQuickWindow::sceneGraphError, &view,
                         [](QQuickWindow::SceneGraphError, const QString &message) {
                             qCritical().noquote() << "Scene graph error:" << message;
                         });

        view.setColor(QColor(QStringLiteral("#000000")));
        view.setResizeMode(QQuickView::SizeRootObjectToView);
        view.rootContext()->setContextProperty("playerWindow", &view);
        view.rootContext()->setContextProperty("initialFile", startupFile);
        view.rootContext()->setContextProperty("initialPlaylist", startupOptions.playlist);
        view.rootContext()->setContextProperty("initialStartPosition", startupOptions.start);
        view.setSource(QUrl(QStringLiteral("qrc:/lzc-player/qml/Main.qml")));

        if (view.status() == QQuickView::Error)
        {
            logQmlErrors(view.errors());
            showStartupFailureDialog(QStringLiteral("QML 界面加载失败。"));
            return 1;
        }

        const QSize initialSize = view.initialSize().isValid() ? view.initialSize() : QSize(1280, 720);
        view.resize(initialSize);
        qInfo().noquote() << "Main window initial size:" << initialSize;
        view.show();

        return app.exec();
    }
    catch (const std::exception &error)
    {
        const QString message = QStringLiteral("Unhandled exception: %1").arg(QString::fromLocal8Bit(error.what()));
        appendLogLine(QStringLiteral("%1 [FATAL] %2")
                          .arg(QDateTime::currentDateTime().toString(Qt::ISODateWithMs), message));
        showStartupFailureDialog(message);
        return 1;
    }
    catch (...)
    {
        const QString message = QStringLiteral("Unhandled non-standard exception.");
        appendLogLine(QStringLiteral("%1 [FATAL] %2")
                          .arg(QDateTime::currentDateTime().toString(Qt::ISODateWithMs), message));
        showStartupFailureDialog(message);
        return 1;
    }
}
