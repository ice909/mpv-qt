#include "src/player/mpvplayerview.h"

#include <clocale>
#include <initializer_list>

#include <QColor>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QQuickWindow>

namespace {

void setApplicationMetadata()
{
    QCoreApplication::setApplicationName(QStringLiteral("lzc-player"));
    QCoreApplication::setApplicationVersion(QString::fromLatin1(LZC_PLAYER_VERSION));
}

void configureCommandLineParser(QCommandLineParser &parser)
{
    const QCommandLineOption cookieOption(
        QStringLiteral("cookie"),
        QStringLiteral("HTTP Cookie header value to send with media requests."),
        QStringLiteral("cookie"));
    const QCommandLineOption startOption(
        QStringLiteral("start"),
        QStringLiteral("Seek to given position on startup. Supports percent, seconds, or timestamps like 12:34 and 01:02:03."),
        QStringLiteral("time"));

    parser.setApplicationDescription(
        QStringLiteral("Lzc video player\n"
                       "\n"
                       "Examples:\n"
                       "  lzc-player --start=90 <file>\n"
                       "  lzc-player --start=12:34 <file>\n"
                       "  lzc-player --start=50% <file>"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption(cookieOption);
    parser.addOption(startOption);
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

} // namespace

int main(int argc, char **argv)
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

    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QGuiApplication app(argc, argv);
    setApplicationMetadata();

    QCommandLineParser parser;
    configureCommandLineParser(parser);
    parser.process(app);

    const QStringList positionalArguments = parser.positionalArguments();
    const QString startupFile = positionalArguments.isEmpty() ? QString() : positionalArguments.first();
    const QString startupPosition = parser.value(QStringLiteral("start"));
    app.setProperty("lzcPlayerCookie", parser.value(QStringLiteral("cookie")));

    std::setlocale(LC_NUMERIC, "C");

    qmlRegisterType<MpvPlayerView>("mpvtest", 1, 0, "MpvPlayerView");

    QQuickView view;
    view.setColor(QColor(QStringLiteral("#000000")));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("initialFile", startupFile);
    view.rootContext()->setContextProperty("initialStartPosition", startupPosition);
    view.setSource(QUrl("qrc:/lzc-player/qml/Main.qml"));
    view.show();

    return app.exec();
}
