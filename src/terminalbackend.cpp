#include "terminalbackend.h"
#include "settingsmanager.h"
#include "terminalcolor.h"
#include <QDebug>
#include <QSocketNotifier>
#include <QGuiApplication>
#include <QClipboard>
#include <QDesktopServices>
#include <QUrl>
#include <QString>
#include <QStringList>
#include <termios.h>
#include <pty.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>
#include <QMimeData>
#include <QTextDocument>
#include <QDir>
#include <QSettings>
#include <QTextStream>
#include <QRegularExpression>
#include <QMetaType>

// Theme Management
void TerminalBackend::discoverColorSchemes(const QString &directory)
{
    m_availableColorSchemes.clear();
    QDir dir(directory);
    QStringList filter({"*.schema"});
    QFileInfoList files = dir.entryInfoList(filter, QDir::Files | QDir::Readable, QDir::Name);

    for (const QFileInfo &fileInfo : files) {
        QString themeName;
        QFile schemaFile(fileInfo.absoluteFilePath());
        if (schemaFile.open(QIODevice::ReadOnly)) {
            QTextStream in(&schemaFile);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith("title")) {
                    themeName = line.mid(5).trimmed();
                    break;
                }
            }
            schemaFile.close();
        }
        if (themeName.isEmpty()) {
            themeName = fileInfo.baseName();
        }

        QVariantMap theme;
        theme["name"] = themeName;
        theme["path"] = fileInfo.absoluteFilePath();
        m_availableColorSchemes.append(theme);
    }
    emit availableColorSchemesChanged();
}

QVariantList TerminalBackend::availableColorSchemes() const
{
    return m_availableColorSchemes;
}

void TerminalBackend::applyColorScheme(const QString &filePath, bool isLiveChange)
{
    m_colorScheme.clear();
    if (filePath.isEmpty() || !QFile::exists(filePath)) {
        qWarning() << "Color scheme file not found:" << filePath;
        m_colorScheme["Background"] = QColor(Qt::black);
        m_colorScheme["Foreground"] = QColor(Qt::white);
    } else {
        QMap<int, QString> slotMap;
        slotMap[0] = "Foreground"; slotMap[1] = "Background";
        slotMap[2] = "Color0"; slotMap[3] = "Color1"; slotMap[4] = "Color2";
        slotMap[5] = "Color3"; slotMap[6] = "Color4"; slotMap[7] = "Color5";
        slotMap[8] = "Color6"; slotMap[9] = "Color7";
        slotMap[10] = "ForegroundIntense"; slotMap[11] = "BackgroundIntense";
        slotMap[12] = "Color0Intense"; slotMap[13] = "Color1Intense";
        slotMap[14] = "Color2Intense"; slotMap[15] = "Color3Intense";
        slotMap[16] = "Color4Intense"; slotMap[17] = "Color5Intense";
        slotMap[18] = "Color6Intense"; slotMap[19] = "Color7Intense";

        QFile schemaFile(filePath);
        if (schemaFile.open(QIODevice::ReadOnly)) {
            QTextStream in(&schemaFile);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith("color")) {
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() >= 5) {
                        int slot = parts[1].toInt();
                        int r = parts[2].toInt();
                        int g = parts[3].toInt();
                        int b = parts[4].toInt();
                        if (slotMap.contains(slot)) {
                            m_colorScheme[slotMap[slot]] = QColor(r, g, b);
                        }
                    }
                }
            }
            schemaFile.close();
        }
    }

    QColor defaultBg = m_colorScheme.value("Background");
    if (!defaultBg.isValid()) defaultBg = QColor(Qt::black);

    QColor defaultFg = m_colorScheme.value("Foreground");
    if (!defaultFg.isValid()) defaultFg = QColor(Qt::white);

    m_foregroundColor = defaultFg.name();
    m_backgroundColor = defaultBg.name();

    // Emit the full theme map for other UI components
    QVariantMap colorMap;
    for(auto it = m_colorScheme.constBegin(); it != m_colorScheme.constEnd(); ++it) {
        colorMap.insert(it.key(), it.value());
    }
    emit themeColorsReady(colorMap);

    if (isLiveChange) {
        emit forceClear();
    }
    //qDebug() << "Applied color scheme:" << filePath;
}

QString TerminalBackend::getColorFromScheme(int ansiCode)
{
    QString key;
    if (ansiCode >= 30 && ansiCode <= 37) key = QString("Color%1").arg(ansiCode - 30);
    else if (ansiCode >= 40 && ansiCode <= 47) key = QString("Color%1").arg(ansiCode - 40);
    else if (ansiCode >= 90 && ansiCode <= 97) key = QString("Color%1Intense").arg(ansiCode - 90);
    else if (ansiCode >= 100 && ansiCode <= 107) key = QString("Color%1Intense").arg(ansiCode - 100);

    if (!key.isEmpty() && m_colorScheme.contains(key)) {
        return m_colorScheme[key].name();
    }

    return TerminalColor::ansi256ToHtmlColor(ansiCode);
}


// PTY and Process Management

TerminalBackend::TerminalBackend(QObject *parent, const QString &startDir)
    : QObject(parent), m_startDir(startDir), m_passwordMode(false)
{
    qRegisterMetaType<QString>("QString");

    loadCommandHistory();
}

void TerminalBackend::startTerminal()
{
    if (m_masterFd != -1) {
        //qWarning() << "Terminal already started.";
        return;
    }

    SettingsManager settings;
    QString savedThemePath = settings.loadColorSchemePath();
    if (!savedThemePath.isEmpty()) {
        applyColorScheme(savedThemePath, false);
    } else {
        m_colorScheme["Background"] = QColor(Qt::black);
        m_colorScheme["Foreground"] = QColor(Qt::white);
        // Default palette
        m_foregroundColor = m_colorScheme["Foreground"].name();
        m_backgroundColor = m_colorScheme["Background"].name();
    }

    struct winsize ws;
    ws.ws_row = 24;
    ws.ws_col = 80;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    pid_t pid = forkpty(&m_masterFd, nullptr, nullptr, &ws);
    if (pid < 0) {
        qWarning() << "forkpty failed:" << strerror(errno);
        emit newData("Error: Could not create PTY.\n");
        return;
    }

    if (pid == 0) { // Child Process
        setenv("LANG", "en_US.UTF-8", 1);
        setenv("LC_ALL", "en_US.UTF-8", 1);
        setenv("TERM", "xterm-256color", 1);
        setenv("LS_COLORS", "di=34:ln=36:so=35:pi=33:ex=32", 1);
        std::string homeDir = getenv("HOME");
        std::string historyPath = homeDir + "/.qmshell_history";

        setenv("HISTFILE", historyPath.c_str(), 1);
        setenv("HISTSIZE", "10000", 1);
        setenv("HISTFILESIZE", "10000", 1);
        setenv("PROMPT_COMMAND", "history -a; history -c; history -r", 1);

        if (!m_startDir.isEmpty()) {
            if (chdir(m_startDir.toLocal8Bit().constData()) != 0) {
                chdir(getenv("HOME"));
            }
        } else {
            chdir(getenv("HOME"));
        }

        setenv("PS1", "\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ ", 1);
        setenv("PS2", "> ", 1);

        struct termios tty;
        tcgetattr(STDIN_FILENO, &tty);
        tty.c_lflag &= ~(ECHO | ICANON);
        tcsetattr(STDIN_FILENO, TCSANOW, &tty);

        execlp("bash", "bash", "-i", (char*)nullptr);
        _exit(1);
    }
    else { // Parent Process
        m_childPid = pid;
        QSocketNotifier *notifier =
            new QSocketNotifier(m_masterFd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this, notifier] {
            char buffer[4096];
            ssize_t n = read(m_masterFd, buffer, sizeof(buffer));
            if (n > 0) {
                processTerminalOutput(QByteArray(buffer, n));
            } else if (n <= 0) {
                emit newData("\n[Process completed]");
                notifier->setEnabled(false);
            }
        });
    }
}


TerminalBackend::~TerminalBackend()
{
    if (m_masterFd >= 0) close(m_masterFd);
    if (m_childPid > 0) {
        kill(m_childPid, SIGTERM);
        waitpid(m_childPid, nullptr, 0);
    }
}

//  ANSI Parsing and Data Processing

QString TerminalBackend::parseAnsiToHtml(const QString &text)
{
    QString htmlOutput;
    QString currentText;

    auto flushCurrentText = [&]() {
        if (!currentText.isEmpty()) {
            QString sanitized = currentText.toHtmlEscaped();
            QString replaced = sanitized.replace("\n", "<br>");

            QString fg = m_foregroundColor.isEmpty() ? m_colorScheme.value("Foreground", QColor(Qt::white)).name() : m_foregroundColor;
            QString bg = m_backgroundColor;


            QString style;
            if (!fg.isEmpty()) style += QStringLiteral("color:") + fg + QStringLiteral(";");
            if (!bg.isEmpty()) style += QStringLiteral("background-color:") + bg + QStringLiteral(";");
            if (m_isBold) style += QStringLiteral("font-weight:bold;");
            if (m_isItalic) style += QStringLiteral("font-style:italic;");
            if (m_isUnderlined) style += QStringLiteral("text-decoration:underline;");
            if (m_isDim) style += QStringLiteral("opacity:0.6;");
            if (m_isBlink) style += QStringLiteral("text-decoration:blink;");
            if (m_isInverse) style += QStringLiteral("filter:invert(1);");
            if (m_isHidden) style += QStringLiteral("visibility:hidden;");
            if (m_isStrikethrough) style += QStringLiteral("text-decoration:line-through;");
            if (m_isDoubleUnderline) style += QStringLiteral("text-decoration:underline double;");
            if (m_isOverline) style += QStringLiteral("text-decoration:overline;");

            if (!style.isEmpty()) {
                htmlOutput += QStringLiteral("<span style=\"") + style + QStringLiteral("\">") + replaced + QStringLiteral("</span>");
            } else {
                htmlOutput += replaced;
            }
            currentText.clear();
        }
    };

    for (int i = 0; i < text.size(); ++i) {
        QChar c = text[i];

        if (c == QChar('\x1B')) { // Start of an escape sequence
            flushCurrentText();
            if (i + 1 < text.size() && text[i + 1] == QChar('[')) {
                i++; // Consume '['
                QString params;
                while (i + 1 < text.size() && ( (text[i + 1] >= QChar('0') && text[i + 1] <= QChar('9')) || text[i+1] == QChar(';') || text[i+1] == QChar('?')) ) {
                    i++;
                    params += text[i];
                }
                if (i + 1 < text.size() && text[i + 1] >= QChar(0x40) && text[i + 1] <= QChar(0x7E)) {
                    i++;
                    QChar finalByte = text[i];
                    if (finalByte == QChar('m')) {
                        QStringList codes = params.split(';');
                        if (codes.isEmpty() || (codes.size() == 1 && codes[0].isEmpty())) {
                            codes.append("0");
                        }
                        for (int j = 0; j < codes.size(); ++j) {
                            int code = codes[j].toInt();

                            switch (code) {
                            case 0:
                                m_foregroundColor.clear();
                                m_backgroundColor.clear();
                                m_isBold = m_isItalic = m_isUnderlined = false;
                                m_isDim = m_isBlink = m_isInverse = m_isHidden = m_isStrikethrough = m_isDoubleUnderline = m_isOverline = false;
                                break;
                            case 1:  m_isBold = true; break;
                            case 2:  m_isDim = true; break;
                            case 3:  m_isItalic = true; break;
                            case 4:  m_isUnderlined = true; break;
                            case 5:  m_isBlink = true; break;
                            case 7:  m_isInverse = true; break;
                            case 8:  m_isHidden = true; break;
                            case 9:  m_isStrikethrough = true; break;
                            case 21: m_isDoubleUnderline = true; break;
                            case 22: m_isBold = m_isDim = false; break;
                            case 23: m_isItalic = false; break;
                            case 24: m_isUnderlined = m_isDoubleUnderline = false; break;
                            case 25: m_isBlink = false; break;
                            case 27: m_isInverse = false; break;
                            case 28: m_isHidden = false; break;
                            case 29: m_isStrikethrough = false; break;
                            case 53: m_isOverline = true; break;
                            case 55: m_isOverline = false; break;
                            case 39: m_foregroundColor.clear(); break;
                            case 49: m_backgroundColor.clear(); break;

                            case 38:
                                if (j + 2 < codes.size() && codes[j+1].toInt() == 5) {
                                    m_foregroundColor = TerminalColor::ansi256ToHtmlColor(codes[j+2].toInt());
                                    j += 2;
                                }
                                break;

                            case 48:
                                if (j + 2 < codes.size() && codes[j+1].toInt() == 5) {
                                    m_backgroundColor = TerminalColor::ansi256ToHtmlColor(codes[j+2].toInt());
                                    j += 2;
                                }
                                break;

                            default:
                                if ((code >= 30 && code <= 37) || (code >= 90 && code <= 97)) {
                                    m_foregroundColor = getColorFromScheme(code);
                                } else if ((code >= 40 && code <= 47) || (code >= 100 && code <= 107)) {
                                    m_backgroundColor = getColorFromScheme(code);
                                }
                                break;
                            }
                        }
                    }
                }
            }
            else if (i + 1 < text.size() && text[i + 1] == QChar(']')) {
                i++; // Consume ']'
                while (i + 1 < text.size() && text[i + 1] != QChar('\x07')) { i++; }
                if (i + 1 < text.size()) { i++; }
            }
        } else if (c != QChar('\r') && c != QChar('\b')) {
            currentText += c;
        }
    }
    flushCurrentText();
    return htmlOutput;
}

void TerminalBackend::processTerminalOutput(const QByteArray &data)
{
    QString text = QString::fromUtf8(data);
    if (m_passwordMode && text.contains('\n')) {
        m_passwordMode = false;
        emit passwordModeChanged(false);
    }
    QString trimmedText = text.trimmed();
    if (!m_passwordMode && trimmedText.endsWith(':') && trimmedText.toLower().contains("password")) {
        m_passwordMode = true;
        emit passwordModeChanged(true);
    }

    QString html = parseAnsiToHtml(text);
    if (!html.isEmpty()) {
        emit newData(html);
    }
}

// QML Interaction slots

void TerminalBackend::sendCommand(const QString &command)
{
    if (m_masterFd >= 0) {
        QByteArray data = command.toUtf8() + '\n';
        ::write(m_masterFd, data.constData(), data.size());
    }

    addCommandToHistory(command);
}

// Slot to emit recalled history command to QML
void TerminalBackend::recallHistoryCommand(const QString &command)
{
    emit historyCommandRecalled(command);
}

// Recall previous command from history
void TerminalBackend::recallPreviousHistory()
{
    if (m_commandHistory.isEmpty()) return;
    if (m_historyIndex < 0) m_historyIndex = m_commandHistory.size();
    if (m_historyIndex > 0) m_historyIndex--;
    emit historyCommandRecalled(m_commandHistory.at(m_historyIndex));
}

// Recall next command from history
void TerminalBackend::recallNextHistory()
{
    if (m_commandHistory.isEmpty()) return;
    if (m_historyIndex < m_commandHistory.size() - 1) {
        m_historyIndex++;
        emit historyCommandRecalled(m_commandHistory.at(m_historyIndex));
    } else {
        m_historyIndex = m_commandHistory.size();
        emit historyCommandRecalled("");
    }
}

// Load command history from file
void TerminalBackend::loadCommandHistory()
{
    m_commandHistory.clear();
    m_historyIndex = -1;
    QString historyFile = QDir::homePath() + "/.qmshellinal_history";
    QFile file(historyFile);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (!line.isEmpty()) m_commandHistory.append(line);
        }
        file.close();
    }
}

// Add command to history and file
void TerminalBackend::addCommandToHistory(const QString &command)
{
    if (command.trimmed().isEmpty()) return;
    if (!m_commandHistory.isEmpty() && m_commandHistory.last() == command) return;
    m_commandHistory.append(command);
    m_historyIndex = m_commandHistory.size();
    QString historyFile = QDir::homePath() + "/.qmshell_history";
    QFile file(historyFile);
    if (file.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream out(&file);
        out << command << "\n";
        file.close();
    }
}

void TerminalBackend::sendKeyData(const QByteArray &keyData)
{
    if (m_masterFd >= 0) {
        ::write(m_masterFd, keyData.constData(), keyData.size());
    }
}

void TerminalBackend::paste()
{
    if (m_masterFd < 0) {
        return;
    }

    QClipboard *clipboard = QGuiApplication::clipboard();
    const QMimeData *mimeData = clipboard->mimeData();
    QString text;

    if (mimeData->hasHtml()) {
        QTextDocument doc;
        doc.setHtml(mimeData->html());
        text = doc.toPlainText();
    } else if (mimeData->hasText()) {
        text = mimeData->text();
    }

    if (text.isEmpty()) {
        text = clipboard->text(QClipboard::Selection);
    }

    text.replace("\r", "");
    emit clipboardTextReady(text);
}

void TerminalBackend::openLink(const QString &url)
{
    QDesktopServices::openUrl(QUrl(url));
}

void TerminalBackend::copyToClipboard(const QString &text)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (clipboard) {
        clipboard->setText(text);
    }
}
