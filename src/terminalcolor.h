#ifndef TERMINALCOLOR_H
#define TERMINALCOLOR_H

#include <QString>

class TerminalColor {
public:
    static QString ansi256ToHtmlColor(int code);
};

#endif // TERMINALCOLOR_H
