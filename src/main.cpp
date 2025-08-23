// main.cpp
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <QCommandLineParser>
#include "terminalbackend.h"
#include "settingsmanager.h"


#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif

QString readStringFromResource(const QString& resourcePath) {
    QFile file(resourcePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qDebug() << "Could not open resource file:" << resourcePath;
        return QString();
    }
    QTextStream in(&file);
    return in.readLine().trimmed();
}


int main(int argc, char *argv[]) {
    QApplication app(argc, argv);

    // Application attributes
    app.setOrganizationName("Qmshell");
    app.setApplicationName("qmshell");

    QQmlApplicationEngine engine;

    qmlRegisterSingletonType<SettingsManager>("qmshell.settings", 1, 0, "SettingsManager",
                                              [](QQmlEngine *engine, QJSEngine *scriptEngine) -> QObject * {
                                                  Q_UNUSED(engine)
                                                  Q_UNUSED(scriptEngine)
                                                  return new SettingsManager();
                                              });

    QString baseVersion = readStringFromResource(":/data/version.conf");
    QString buildInfo = readStringFromResource(":/data/build_info.conf");
    engine.rootContext()->setContextProperty("appVersion", baseVersion);
    engine.rootContext()->setContextProperty("appBuildInfo", buildInfo);

    TerminalBackend backend;

    engine.rootContext()->setContextProperty("terminalBackend", &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    QCoreApplication::setApplicationVersion(baseVersion);
    QCommandLineParser parser;
    parser.setApplicationDescription("qmshell Terminal Emulator");
    parser.addHelpOption();
    parser.addVersionOption();   // --version or  and -v
    parser.process(app);

    return app.exec();
}
