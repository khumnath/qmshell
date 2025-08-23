#
# qmshell.pro - The Qt Project File
#
QT += core gui widgets quick quickcontrols2

!system(bash $$PWD/update_version.sh) {
    warning("The version update script failed to run. Version info may be stale or incorrect.")
}


CONFIG += c++17

TARGET = qmshell

RESOURCES += qmshell.qrc

SOURCES += \
    src/main.cpp \
    src/settingsmanager.cpp \
    src/terminalbackend.cpp \
    src/terminalcolor.cpp

HEADERS += \
    src/settingsmanager.h \
    src/terminalbackend.h \
    src/terminalcolor.h

    icon.path = /usr/share/icons/hicolor
    icon.files = $$files($$PWD/data/icons/hicolor/*/*/qmshell.png)

    svgicon.path = /usr/share/icons/hicolor/scalable/apps
    svgicon.files = $$PWD/data/icons/hicolor/scalable/apps/qmshell.svg

    desktop.path = /usr/share/applications
    desktop.files = $$PWD/data/qmlterm.desktop

    INSTALLS += icon svgicon desktop


qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
