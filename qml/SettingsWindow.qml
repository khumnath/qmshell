import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import qmshell.settings 1.0

Window {
    id: settingsWindow
    width: 400
    height: 250
    title: "Qmterm Settings"
    color: currentTheme.Background || "#1C2126"
    visible: false
    modality: Qt.NonModal
    flags: Qt.Dialog

    property var terminalView
    property var mainTerminalWindow
    property var currentTheme: ({
        "Background": "#1C2126",
        "Foreground": "#f2f2f2"
    })

    onActiveChanged: {
        if (!active) {
            close();
        }
    }

    function saveFontSettings() {
        var settings = {
            fontSize: Math.round(fontSizeSlider.value)
        };
        SettingsManager.saveTerminalSettings(settings);
    }

    function getContrastingTextColor(backgroundColor) {
        const c = Qt.color(backgroundColor);
        const luminance = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b);
        return luminance > 0.5 ? "black" : "white";
    }

    Column {
        anchors.fill: parent
        spacing: 15
        padding: 20

        Text { text: "Qmshell"; color: settingsWindow.currentTheme.Foreground || "#f2f2f2"; font.pixelSize: 18; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
        Text { text: "Terminal Emulator"; color: settingsWindow.currentTheme.Color3 || "#f2fAA2"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }

        GridLayout {
            columns: 3
            anchors.horizontalCenter: parent.horizontalCenter
            columnSpacing: 10
            rowSpacing: 10

            Text { text: "Font Size:"; color: settingsWindow.currentTheme.Foreground || "#f2f2f2"; Layout.alignment: Qt.AlignVCenter }

            Slider {
                id: fontSizeSlider
                from: 8; to: 24; value: 14
                stepSize: 1
                Layout.fillWidth: true

                background: Rectangle {
                    implicitWidth: 200
                    implicitHeight: 8
                    color: settingsWindow.currentTheme.Background || "lightgrey"
                    border.color: fontSizeSlider.hovered || fontSizeSlider.pressed ? settingsWindow.currentTheme.Color4 || "#87CEFA" : settingsWindow.currentTheme.Color0Intense || "#444"
                    border.width: 1
                    radius: 4

                    Rectangle {
                        height: parent.height
                        width: parent.width * (fontSizeSlider.value - fontSizeSlider.from) / (fontSizeSlider.to - fontSizeSlider.from)
                        color: fontSizeSlider.hovered ? Qt.lighter(settingsWindow.currentTheme.Color4, 1.2) : settingsWindow.currentTheme.Color4
                        anchors.left: parent.left
                    }
                }

                handle: Rectangle {
                    width: 16; height: 16
                    radius: 8
                    color: fontSizeSlider.pressed ? settingsWindow.currentTheme.Color4 : (fontSizeSlider.hovered ? Qt.lighter(settingsWindow.currentTheme.Color4, 1.2) : settingsWindow.currentTheme.Color4)
                    border.color: settingsWindow.currentTheme.Foreground || "#f2f2f2"
                    border.width: 1

                    x: (fontSizeSlider.visualPosition * fontSizeSlider.width) - (width / 2)
                    y: (fontSizeSlider.height / 2) - (height / 2)
                }

                onValueChanged: {
                    fontSizeValue.text = Math.round(value);
                    if (terminalView) {
                        terminalView.textArea.font.pixelSize = Math.round(value);
                    }
                    saveFontSettings();
                }
            }

            Text { id: fontSizeValue; text: Math.round(fontSizeSlider.value); color: settingsWindow.currentTheme.Foreground || "#f2f2f2"; width: 30; horizontalAlignment: Text.Right; Layout.alignment: Qt.AlignVCenter }

            Text { text: "Theme:"; color: settingsWindow.currentTheme.Foreground || "#f2f2f2"; Layout.alignment: Qt.AlignVCenter }

            ComboBox {
                id: backgroundCombo
                Layout.fillWidth: true
                Layout.columnSpan: 2

                model: terminalBackend.availableColorSchemes
                textRole: "name"

                background: Rectangle {
                    implicitWidth: 120
                    implicitHeight: 30
                    color: backgroundCombo.pressed ? settingsWindow.currentTheme.BackgroundIntense : settingsWindow.currentTheme.Background
                    border.color: backgroundCombo.hovered || backgroundCombo.pressed ? settingsWindow.currentTheme.Color4 || "#87CEFA" : settingsWindow.currentTheme.Color0Intense || "#444"
                    border.width: 1
                    radius: 4
                }

                contentItem: Text {
                    text: backgroundCombo.displayText
                    color: backgroundCombo.pressed || backgroundCombo.hovered ? getContrastingTextColor(backgroundCombo.background.color) : settingsWindow.currentTheme.Foreground
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 4
                }

                onCurrentIndexChanged: {
                    if (currentIndex >= 0) {
                        var selectedTheme = terminalBackend.availableColorSchemes[currentIndex];
                        var themePath = selectedTheme.path;
                        terminalBackend.applyColorScheme(themePath, true);
                        SettingsManager.saveColorSchemePath(themePath);
                    }
                }

                function findCurrentTheme() {
                    var currentPath = SettingsManager.loadColorSchemePath();
                    if (!currentPath) return;
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].path === currentPath) {
                            currentIndex = i;
                            return;
                        }
                    }
                }

                onModelChanged: findCurrentTheme()

                delegate: ItemDelegate {
                    width: backgroundCombo.width
                    highlighted: backgroundCombo.highlightedIndex === index

                    background: Rectangle {
                        color: parent.highlighted ? settingsWindow.currentTheme.BackgroundIntense : settingsWindow.currentTheme.Background
                        border.color: parent.highlighted ? settingsWindow.currentTheme.Color4 || "#87CEFA" : "transparent"
                        border.width: 1
                        radius: 4
                    }
                    contentItem: Text {
                        text: modelData.name
                        color: parent.highlighted ? getContrastingTextColor(settingsWindow.currentTheme.BackgroundIntense) : settingsWindow.currentTheme.Foreground || "#f2f2f2"
                        leftPadding: 4
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                popup: Popup {
                    y: backgroundCombo.height + 2
                    width: parent.width
                    height: Math.min(200, contentItem.implicitHeight + padding * 2)
                    padding: 5
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: backgroundCombo.popup.visible ? backgroundCombo.delegateModel : null
                        currentIndex: backgroundCombo.highlightedIndex
                        ScrollIndicator.vertical: ScrollIndicator { }
                    }
                    background: Rectangle {
                        color: settingsWindow.currentTheme.BackgroundIntense || "#2E3436"
                        border.color: settingsWindow.currentTheme.Color0Intense || "#444"
                        border.width: 1
                        radius: 4
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (mainTerminalWindow) {
            transientParent = mainTerminalWindow;
        }

        var savedSettings = SettingsManager.loadTerminalSettings();
        if (savedSettings) {
            Qt.callLater(function() {
                fontSizeSlider.value = savedSettings.fontSize || 14;
            });
        }
    }
}
