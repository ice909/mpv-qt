#include "mpvobject.h"

#include <clocale>

#include <QGuiApplication>
#include <QColor>
#include <QQmlContext>
#include <QQuickView>
#include <QQuickWindow>

int main(int argc, char **argv)
{
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QGuiApplication app(argc, argv);
    const QString startupFile = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QString();

    std::setlocale(LC_NUMERIC, "C");

    qmlRegisterType<MpvObject>("mpvtest", 1, 0, "MpvObject");

    QQuickView view;
    view.setColor(QColor(QStringLiteral("#000000")));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty("initialFile", startupFile);
    view.setSource(QUrl("qrc:/mpvqt/Main.qml"));
    view.show();

    return app.exec();
}
