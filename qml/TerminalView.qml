import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.platform 1.1

Item {
    id: container
    anchors.fill: parent

    property alias textArea: textArea
    property bool passwordModeActive: false
    property var currentTheme: ({
        "Background": "#1C2126",
        "Foreground": "#f2f2f2",
        "Color4": "#87CEFA"
    })

    signal sendCommand(string command)
    signal pasteRequested()
    signal copyRequested(string textToCopy)
    signal sendKeyData(string keyData)
    signal openLinkRequested(string url)
    signal openSettingsRequested()

    function appendText(data) {
        scrollView.appendText(data)
    }

    function insertPastedText(text) {
        scrollView.insertPastedText(text)
    }

    // Function to calculate a hover color based on the background color
    function getHoverColor(baseColor) {
        const c = Qt.color(baseColor);
        if (c.hsv === undefined) return "#444";
        let hsv = c.hsv;
        let newV = Math.min(1.0, hsv.v + 0.1);
        return Qt.hsva(hsv.h, hsv.s, newV, hsv.a);
    }

    // Function to calculate a pressed color based on the background color
    function getPressedColor(baseColor) {
        const c = Qt.color(baseColor);
        if (c.hsv === undefined) return "#555";
        let hsv = c.hsv;
        let newV = Math.max(0.0, hsv.v - 0.1);
        return Qt.hsva(hsv.h, hsv.s, newV, hsv.a);
    }

    // Function to get a contrasting text color (white or black) based on a background color
    function getContrastingTextColor(backgroundColor) {
        const c = Qt.color(backgroundColor);
        const luminance = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b);
        return luminance > 0.5 ? "black" : "white";
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

        function clearTerminal() {
            textArea.clear();
            ScrollBar.vertical.position = 0.0;
        }

        function scrollToBottom() {
            ScrollBar.vertical.position = 1.0;
        }

        function insertPastedText(text) {
            textArea.insert(textArea.cursorPosition, text);
        }

        function appendText(data) {
            const wasAtBottom = scrollView.atYEnd;

            // URL detection and styling
            const urlRegex = /(?:(?:https?|ftp):\/\/|www\.|ftp\.)(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[-A-Z0-9+&@#\/%=~_|$?!:,.])*(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[A-Z0-9+&@#\/%=~_|$])/igm;

            // Replace URLs with styled HTML links using rich text
            const formattedData = data.replace(urlRegex, (url) => {
                return `<a href="${url}"><font color="${container.currentTheme.Color4}" style="text-decoration:underline">${url}</font></a>`;
            });

            textArea.insert(textArea.length, formattedData);
            textArea.promptPosition = textArea.length;
            textArea.cursorPosition = textArea.length;
            if (wasAtBottom) {
                Qt.callLater(scrollToBottom);
            }
            Qt.callLater(() => textArea.forceActiveFocus());
        }

        TextArea {
            id: textArea
            width: Math.max(scrollView.availableWidth, implicitWidth)
            height: Math.max(scrollView.availableHeight, implicitHeight)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            property int promptPosition: 0
            color: container.currentTheme.Foreground
            background: Rectangle {
                id: backgroundRect
                color: container.currentTheme.Background
            }
            font.family: "monospace"
            font.pixelSize: 14
            focus: true
            selectByMouse: true
            selectionColor: container.currentTheme.Color4 || "#4682b4"
            selectedTextColor: container.currentTheme.Background || "#FFFFFF"
            hoverEnabled: true
            cursorDelegate: Rectangle {
                width: 2
                height: textArea.font.pixelSize
                color: textArea.color
                visible: textArea.activeFocus
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }

            Keys.onPressed: (event) => {
                if (event.matches(StandardKey.Copy)) {
                    if (textArea.selectedText.length > 0) { container.copyRequested(textArea.selectedText); }
                    else if (event.modifiers === Qt.ControlModifier) { container.sendKeyData("\x03"); }
                    event.accepted = true; return;
                }
                if (event.matches(StandardKey.Paste)) { container.pasteRequested(); event.accepted = true; return; }
                if (event.matches(StandardKey.Cut)) { container.sendKeyData("\x18"); event.accepted = true; return; }
                if (event.matches(StandardKey.SelectAll)) { textArea.select(promptPosition, textArea.length); event.accepted = true; return; }
                switch (event.key) {
                    case Qt.Key_Up: terminalBackend.recallPreviousHistory(); event.accepted = true; return;
                    case Qt.Key_Down: terminalBackend.recallNextHistory(); event.accepted = true; return;
                }
                if (event.key === Qt.Key_Tab) { container.sendKeyData("\x09"); event.accepted = true; return; }
                const controlCharMap = { [Qt.Key_D]: "\x04", [Qt.Key_E]: "\x05", [Qt.Key_K]: "\x0B", [Qt.Key_L]: "\x0C", [Qt.Key_Q]: "\x11", [Qt.Key_R]: "\x12", [Qt.Key_S]: "\x13", [Qt.Key_U]: "\x15", [Qt.Key_W]: "\x17", [Qt.Key_Z]: "\x1A", };
                if (event.modifiers === Qt.ControlModifier && controlCharMap[event.key]) { container.sendKeyData(controlCharMap[event.key]); event.accepted = true; return; }
                if (event.modifiers === Qt.AltModifier) {
                    switch (event.key) {
                        case Qt.Key_B: container.sendKeyData("\x1bb"); event.accepted = true; return;
                        case Qt.Key_F: container.sendKeyData("\x1bf"); event.accepted = true; return;
                    }
                }
                if (textArea.cursorPosition < promptPosition) { textArea.cursorPosition = textArea.length; }
                if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && textArea.cursorPosition <= promptPosition) { event.accepted = true; return; }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    const command = textArea.getText(promptPosition, textArea.length).trim();

                    if (command === "clear") {
                        scrollView.clearTerminal();
                                                sendCommand("");
                        event.accepted = true;
                        return;
                    }

                    container.sendCommand(command);
                    event.accepted = true;
                    return;
                }
                event.accepted = false;
            }

            Component.onCompleted: forceActiveFocus()
            onActiveFocusChanged: { if (!activeFocus && !contextMenu.visible && !infoPopup.visible) { Qt.callLater(() => forceActiveFocus()) } }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: textArea.linkAt(mouseX, mouseY) ? Qt.PointingHandCursor : Qt.IBeamCursor
                onClicked: (mouse) => { if (mouse.button === Qt.LeftButton) { const link = textArea.linkAt(mouse.x, mouse.y); if (link) { container.openLinkRequested(link); } } }
                onPressed: (mouse) => { mouse.accepted = false; }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                const textAreaPos = textArea.mapFromItem(this, mouse.x, mouse.y);
                let url = "";

                // Check if the right-click is on a link created with rich text
                const richTextLink = textArea.linkAt(textAreaPos.x, textAreaPos.y);
                if (richTextLink !== "") {
                    url = richTextLink;
                } else if (textArea.selectedText.length > 0) {
                    // If no rich text link, check if the selected text is a URL
                    const potentialUrl = textArea.selectedText.trim();
                    const urlRegex = /^(https?|ftp):\/\/[^\s/$.?#].[^\s]*$/i;
                    if (urlRegex.test(potentialUrl)) {
                        url = potentialUrl;
                    }
                }

                contextMenu.clickedLink = url;
                contextMenu.hasSelection = textArea.selectedText.length > 0;
                contextMenu.x = mouse.x;
                contextMenu.y = mouse.y;
                contextMenu.open();
            }
        }
    }

    MouseArea {
        id: overlay
        anchors.fill: parent
        enabled: contextMenu.visible
        acceptedButtons: Qt.AllButtons
        onPressed: (mouse) => { contextMenu.close(); mouse.accepted = false; }
        z: contextMenu.z - 1
    }

    Rectangle {
        id: contextMenu
        width: 180; height: childrenRect.height
        border.width: 1; radius: 6;
        border.color: container.currentTheme.Color0Intense || "#444";
        color: container.currentTheme.BackgroundIntense || "#333"
        visible: false; z: 10; focus: visible
        onVisibleChanged: { if (visible) { forceActiveFocus(); } else { textArea.forceActiveFocus(); } }
        onActiveFocusChanged: { if (!activeFocus && visible) { close(); } }
        Keys.onEscapePressed: close()
        property string clickedLink: ""
        property bool hasSelection: false
        function open() { visible = true; forceActiveFocus(); }
        function close() { visible = false; textArea.forceActiveFocus(); }

        Column {
            spacing: 1; width: parent.width
            Rectangle {
                width: parent.width; height: 30; visible: contextMenu.clickedLink !== ""
                property color hoverColor: container.getHoverColor(container.currentTheme.Background)
                property color pressedColor: container.getPressedColor(container.currentTheme.Background)
                color: openLinkMouseArea.pressed ? pressedColor : (openLinkMouseArea.containsMouse ? hoverColor : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Open Link"; color: openLinkMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: openLinkMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.openLinkRequested(contextMenu.clickedLink); contextMenu.close() } }
            }
            Rectangle {
                width: parent.width; height: 30; visible: contextMenu.clickedLink !== ""
                color: copyLinkMouseArea.pressed ? pressedColor : (copyLinkMouseArea.containsMouse ? hoverColor : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Copy Link Address"; color: copyLinkMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: copyLinkMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.copyRequested(contextMenu.clickedLink); contextMenu.close() } }
            }
            Rectangle {
                width: parent.width; height: 30; visible: contextMenu.clickedLink === "" && contextMenu.hasSelection
                color: copyMouseArea.pressed ? container.getPressedColor(container.currentTheme.Background) : (copyMouseArea.containsMouse ? container.getHoverColor(container.currentTheme.Background) : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Copy"; color: copyMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: copyMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.copyRequested(textArea.selectedText); contextMenu.close() } }
            }
            Rectangle { width: parent.width - 10; height: 1; anchors.horizontalCenter: parent.horizontalCenter; color: container.currentTheme.Color0Intense || "#444"; visible: (contextMenu.clickedLink !== "") || (contextMenu.clickedLink === "" && contextMenu.hasSelection) }
            Rectangle {
                width: parent.width; height: 30
                color: pasteMouseArea.pressed ? container.getPressedColor(container.currentTheme.Background) : (pasteMouseArea.containsMouse ? container.getHoverColor(container.currentTheme.Background) : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Paste"; color: pasteMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: pasteMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.pasteRequested(); contextMenu.close() } }
            }
            Rectangle { width: parent.width - 10; height: 1; anchors.horizontalCenter: parent.horizontalCenter; color: container.currentTheme.Color0Intense || "#444"; visible: true }
            Rectangle {
                width: parent.width; height: 30
                color: settingsMouseArea.pressed ? container.getPressedColor(container.currentTheme.Background) : (settingsMouseArea.containsMouse ? container.getHoverColor(container.currentTheme.Background) : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Settings"; color: settingsMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: settingsMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.openSettingsRequested(); contextMenu.close() } }
            }
            Rectangle { width: parent.width - 10; height: 1; anchors.horizontalCenter: parent.horizontalCenter; color: container.currentTheme.Color0Intense || "#444"; visible: true }
            Rectangle {
                width: parent.width; height: 30
                color: aboutMouseArea.pressed ? container.getPressedColor(container.currentTheme.Background) : (aboutMouseArea.containsMouse ? container.getHoverColor(container.currentTheme.Background) : "transparent")
                radius: contextMenu.radius
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "about"; color: aboutMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                MouseArea { id: aboutMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { infoPopup.open(); contextMenu.close() } }
            }
        }
    }

    Popup {
        id: infoPopup
        width: container.width /1.5; height: contentHeight
        modal: true; focus: true
        anchors.centerIn: parent
        background: Rectangle {
            color: container.currentTheme.Background || "#1C2126";
            border.color: container.currentTheme.Color3 || "#fff000";
            radius: 8
        }
        contentItem: Column {
            spacing: 15
            Text { text: "Qmshell."; font.pixelSize: 16; color: container.currentTheme.ForegroundIntense || "gray"; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            Text { text: "version:" + appVersion; font.pixelSize: 14; color: container.currentTheme.Foreground || "gray"; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            Text { text: "Info:" + appBuildInfo; font.pixelSize: 14; color: container.currentTheme.Color3 || "gray"; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            Text {
                text: "Source Code: Available on GitHub"; color: container.currentTheme.Color4 || "grey"; font.underline: true; anchors.horizontalCenter: parent.horizontalCenter
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Qt.openUrlExternally("https://github.com/khumnath/qmshell"); infoPopup.close() } }
            }
            Text {
                text: "This is a free and open-source project. In search of unicode supported" +
                        "lightweight terminal, this terminal is invented.";
                font.pixelSize: 13; color: container.currentTheme.ForegroundFaint || "#8787af"; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            }
            Button {
                text: "OK"; width: parent.width / 4; anchors.horizontalCenter: parent.horizontalCenter; onClicked: infoPopup.close()
                background: Rectangle {
                    color: container.currentTheme.Background || "#1C2126";
                    border.color: container.currentTheme.Color3 || "#fff000";
                    radius: 8
                }
                contentItem: Text { text: qsTr("OK"); color: container.currentTheme.Foreground || "#ffffff"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; anchors.fill: parent }
            }
        }
    }
}
