import QtQuick 2.15
import QtQuick.Controls 2.15
import qmshell.settings 1.0

ApplicationWindow {
    id: root
    width: 600
    height: 700
    visible: true
    color: currentThemeColors.Background || "#1C2126"

    property var currentThemeColors: ({
        "Background": "#1C2126",
        "Foreground": "#f2f2f2"
    })

    property var settingsWindow: null

    function openSettings() {
        if (!settingsWindow) {
            var component = Qt.createComponent("qrc:/qml/SettingsWindow.qml");
            if (component.status === Component.Ready) {
                settingsWindow = component.createObject(root, {
                    "mainTerminalWindow": root,
                    "terminalView": terminalView,
                    "currentTheme": currentThemeColors
                });

                if (settingsWindow) {
                    settingsWindow.closing.connect(function() {
                        settingsWindow.destroy();
                        settingsWindow = null;
                    });
                } else {
                     console.error("Failed to create SettingsWindow object.");
                }

            } else {
                console.error("Error loading SettingsWindow.qml:", component.errorString());
                return;
            }
        }
        settingsWindow.show();
        settingsWindow.requestActivate();
    }

    Connections {
        target: terminalBackend

        function onThemeColorsReady(colors) {
            //console.log("QML: Full theme received.")
            currentThemeColors = colors;
            terminalView.textArea.color = colors.Foreground;
            terminalView.textArea.background.color = colors.Background;

            //  If the settings window is open, update its theme property too
            if (settingsWindow) {
                settingsWindow.currentTheme = colors;
            }
        }

        function onForceClear() {
            terminalView.textArea.clear();
            terminalBackend.sendCommand("");
        }

        function onNewData(htmlData) {
            terminalView.appendText(htmlData)
        }
        function onClipboardTextReady(text) {
            terminalView.insertPastedText(text)
        }
        function onPasswordModeChanged(active) {
            terminalView.passwordModeActive = active;
        }
    }

    TerminalView {
        id: terminalView
        anchors.fill: parent
        anchors.margins: 1
        currentTheme: root.currentThemeColors

        onSendCommand: (command) => terminalBackend.sendCommand(command)
        onPasteRequested: terminalBackend.paste()
        onCopyRequested: (textToCopy) => terminalBackend.copyToClipboard(textToCopy)
        onSendKeyData: (keyData) => terminalBackend.sendKeyData(keyData)
        onOpenLinkRequested: (url) => terminalBackend.openLink(url)
        onOpenSettingsRequested: root.openSettings()
    }

    Rectangle {
        id: settingsOverlay
        anchors.fill: parent
        visible: settingsWindow && settingsWindow.visible
        color: "transparent"
        z: 1
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                if (settingsWindow && settingsWindow.visible) {
                    settingsWindow.close();
                }
            }
        }
    }

    Component.onCompleted: {
        var savedGeometry = SettingsManager.loadWindowGeometry();
        root.x = savedGeometry.x;
        root.y = savedGeometry.y;
        root.width = savedGeometry.width;
        root.height = savedGeometry.height;

        terminalBackend.discoverColorSchemes(":/data/color_schemes");

        var savedSettings = SettingsManager.loadTerminalSettings();
        terminalView.textArea.font.pixelSize = savedSettings.fontSize || 14;

        terminalBackend.startTerminal();
    }

    onClosing: {
        var currentGeometry = { "x": root.x, "y": root.y, "width": root.width, "height": root.height };
        SettingsManager.saveWindowGeometry(currentGeometry);
    }
}
