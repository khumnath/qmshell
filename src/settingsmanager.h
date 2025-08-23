#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>
#include <QRect>
#include <QVariantMap>

class SettingsManager : public QObject
{
    Q_OBJECT
public:
    explicit SettingsManager(QObject *parent = nullptr);
    Q_INVOKABLE void saveWindowGeometry(const QRect &geometry);
    Q_INVOKABLE QRect loadWindowGeometry();
    Q_INVOKABLE void saveTerminalSettings(const QVariantMap &settings);
    Q_INVOKABLE QVariantMap loadTerminalSettings();
    Q_INVOKABLE void saveColorSchemePath(const QString &path);
    Q_INVOKABLE QString loadColorSchemePath();


private:
    QSettings m_settings;
};

#endif // SETTINGSMANAGER_H
