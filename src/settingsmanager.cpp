#include "settingsmanager.h"
#include <QGuiApplication>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings(QSettings::IniFormat, QSettings::UserScope, "qmshell", "qmshell")
{
}

void SettingsManager::saveWindowGeometry(const QRect &geometry)
{
    m_settings.setValue("windowGeometry", geometry);
}

QRect SettingsManager::loadWindowGeometry()
{
    return m_settings.value("windowGeometry", QRect(298, 40, 600, 653)).toRect();
}

void SettingsManager::saveTerminalSettings(const QVariantMap &settings)
{
    m_settings.beginGroup("Terminal");
    m_settings.setValue("fontSize", settings.value("fontSize"));
    m_settings.setValue("background", settings.value("background"));
    m_settings.endGroup();
}

QVariantMap SettingsManager::loadTerminalSettings()
{
    QVariantMap settings;
    m_settings.beginGroup("Terminal");
    settings["fontSize"] = m_settings.value("fontSize", 14);
    settings["background"] = m_settings.value("background", 0);
    m_settings.endGroup();
    return settings;
}

void SettingsManager::saveColorSchemePath(const QString &path)
{
    m_settings.beginGroup("Terminal");
    m_settings.setValue("colorSchemePath", path);
    m_settings.endGroup();
}

QString SettingsManager::loadColorSchemePath()
{
    m_settings.beginGroup("Terminal");
    QString path = m_settings.value("colorSchemePath").toString();

    if (path.isEmpty()) {
        path = ":/data/color_schemes/DarkPastels.schema";
        m_settings.setValue("colorSchemePath", path);
    }

    m_settings.endGroup();
    return path;
}
