#ifndef TERMINALBACKEND_H
#define TERMINALBACKEND_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QMap>
#include <QColor>

class TerminalBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList availableColorSchemes READ availableColorSchemes NOTIFY availableColorSchemesChanged)

public:
    explicit TerminalBackend(QObject *parent = nullptr, const QString &startDir = "");
    ~TerminalBackend();
    QVariantList availableColorSchemes() const;

public slots:
    void sendCommand(const QString &command);
    void sendKeyData(const QByteArray &keyData);
    void paste();
    void copyToClipboard(const QString &text);
    void openLink(const QString &url);
    void discoverColorSchemes(const QString &directory);
    void applyColorScheme(const QString &filePath, bool isLiveChange = true);
    Q_INVOKABLE void startTerminal();
    void recallHistoryCommand(const QString &command);
    Q_INVOKABLE void recallPreviousHistory();
    Q_INVOKABLE void recallNextHistory();

signals:
    void availableColorSchemesChanged();
    void themeColorsReady(const QVariantMap &colors);
    void newData(const QString &htmlData);
    void clipboardTextReady(const QString &text);
    void passwordModeChanged(bool active);
    void forceClear();
    void historyCommandRecalled(const QString &command);

private:
    void processTerminalOutput(const QByteArray &data);
    QString parseAnsiToHtml(const QString &text);
    QString getColorFromScheme(int ansiCode);

    // NOTE: Some ANSI SGR features (e.g., blink, alternate font, framed, encircled, etc.)
    //are not supported in Qt/QML rich text and will be ignored or simulated as best as possible.
    //Blink is not natively supported and would require custom animation logic.

    QVariantList m_availableColorSchemes;
    QMap<QString, QColor> m_colorScheme;

    int m_masterFd = -1;
    pid_t m_childPid = -1;
    QString m_startDir;
    bool m_isFirstData = true;

    // ANSI state variables
    QString m_foregroundColor;
    QString m_backgroundColor;
    bool m_isBold = false;
    bool m_isItalic = false;
    bool m_isUnderlined = false;
    bool m_isDim = false;
    bool m_isBlink = false;
    bool m_isInverse = false;
    bool m_isHidden = false;
    bool m_isStrikethrough = false;
    bool m_isDoubleUnderline = false;
    bool m_isOverline = false;

    // Password mode state
    bool m_passwordMode = false;

    QStringList m_commandHistory;
    int m_historyIndex = -1;
    void loadCommandHistory();
    void addCommandToHistory(const QString &command);
};

#endif // TERMINALBACKEND_H
