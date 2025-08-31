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

    // This handler resets the input state when password mode is toggled
    onPasswordModeActiveChanged: {
        textArea.actualInputText = ""
        // Clear any visible text from the input area
        var promptPos = textArea.promptPosition
    }

    /* ===  Root-level helpers exported to main.qml  === */
    function appendText(data)        { scrollView.appendText(data) }
    function insertPastedText(text)  { scrollView.insertPastedText(text) }
    function setCommandFromHistory(cmd) {
        var promptPos = textArea.promptPosition
        if (promptPos <= 0 || promptPos > textArea.length) return
        textArea.remove(promptPos, textArea.length - promptPos)
        textArea.insert(promptPos, cmd)
        textArea.cursorPosition = promptPos + cmd.length
    }

    /* ===  Signals  === */
    signal sendCommand(string command)
    signal pasteRequested()
    signal copyRequested(string textToCopy)
    signal sendKeyData(string keyData)
    signal openLinkRequested(string url)
    signal openSettingsRequested()

    /* ===  Utility functions  === */
    function getHoverColor(baseColor) {
        const c = Qt.color(baseColor)
        if (c.hsv === undefined) return "#444"
        let hsv = c.hsv
        let newV = Math.min(1.0, hsv.v + 0.1)
        return Qt.hsva(hsv.h, hsv.s, newV, hsv.a)
    }

    function getPressedColor(baseColor) {
        const c = Qt.color(baseColor)
        if (c.hsv === undefined) return "#555"
        let hsv = c.hsv
        let newV = Math.max(0.0, hsv.v - 0.1)
        return Qt.hsva(hsv.h, hsv.s, newV, hsv.a)
    }

    function getContrastingTextColor(backgroundColor) {
        const c = Qt.color(backgroundColor)
        const luminance = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
        return luminance > 0.5 ? "black" : "white"
    }

    /* ===  ScrollView + TextArea  === */
    ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded

        function clearTerminal() {
            textArea.clear()
            textArea.promptPosition = 0
            ScrollBar.vertical.position = 0.0
        }

        function scrollToBottom() {
            ScrollBar.vertical.position = 1.0
        }

        function insertPastedText(text) {
            if (textArea.cursorPosition < textArea.promptPosition)
                textArea.cursorPosition = textArea.length
            textArea.insert(textArea.cursorPosition, text)
        }

        function appendText(data) {
            const wasAtBottom = scrollView.atYEnd

            // Replace control characters or specific patterns
            let cleaned = data.replace(/\^C/g, '<span style="color:red;">aborted</span>')

            // Replace URLs with clickable links
            const urlRegex = /(?:(?:https?|ftp):\/\/|www\.|ftp\.)(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[-A-Z0-9+&@#\/%=~_|$?!:,.])*(?:\([-A-Z0-9+&@#\/%=~_|$?!:,.]*\)|[A-Z0-9+&@#\/%=~_|$])/igm
            const formatted = cleaned.replace(urlRegex, url =>
                `<a href="${url}"><font color="${container.currentTheme.Color4}" style="text-decoration:underline">${url}</font></a>`)

            textArea.insert(textArea.length, formatted)
            textArea.promptPosition = textArea.length
            textArea.cursorPosition = textArea.length

            if (wasAtBottom) Qt.callLater(scrollToBottom)
            Qt.callLater(() => textArea.forceActiveFocus())
        }


        TextArea {
            id: textArea
            height: Math.max(scrollView.availableHeight, implicitHeight)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            property int promptPosition: 0
            property string actualInputText: "" // Stores the real text in password mode
            color: container.currentTheme.Foreground
            background: Rectangle { color: container.currentTheme.Background }
            font.family: "monospace"
            font.pixelSize: 14
            focus: true
            selectByMouse: true
            selectionColor: container.currentTheme.Color4 || "#4682b4"
            selectedTextColor: container.currentTheme.Background || "#FFFFFF"
            hoverEnabled: true


            cursorDelegate: Rectangle {
                width: 2; height: textArea.font.pixelSize; color: textArea.color; visible: textArea.activeFocus
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }

            onPressed: mouse => {
                           if (mouse.button === Qt.RightButton) {
                               contextMenu.hasSelection = textArea.selectedText.length > 0
                               const pos = mapToItem(container, mouse.x, mouse.y)
                               contextMenu.x = pos.x
                               contextMenu.y = pos.y
                               contextMenu.open()
                               mouse.accepted = true
                           }
                       }

            Keys.onPressed: (event) => {
                                // Prevent moving the cursor into the read-only area
                                if (textArea.cursorPosition < promptPosition) {
                                    textArea.cursorPosition = textArea.length
                                }

                                // ==== Standard Key Handling (Copy/Paste, etc.) ====
                                if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift ||
                                    event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                                    event.accepted = false
                                    return
                                }
                                if (event.matches(StandardKey.Copy)) {
                                    if (textArea.selectedText.length > 0) {
                                        container.copyRequested(textArea.selectedText)
                                        textArea.deselect()
                                    } else {
                                        container.sendKeyData("\x03") // Send Ctrl+C interrupt
                                    }
                                    event.accepted = true
                                    return
                                }
                                if (event.matches(StandardKey.Paste)) {
                                    // Disable pasting in password mode for security
                                    if (!container.passwordModeActive) {
                                        container.pasteRequested();
                                    }
                                    event.accepted = true;
                                    return
                                }
                                if (event.matches(StandardKey.SelectAll)) { textArea.select(promptPosition, textArea.length); event.accepted = true; return }

                                // ==== History Navigation ====
                                if (event.key === Qt.Key_Up) {
                                    // Don't allow history navigation in password mode
                                    if (!container.passwordModeActive) {
                                        textArea.cursorPosition = textArea.length
                                        terminalBackend.recallPreviousHistory() // Assuming terminalBackend is in scope
                                    }
                                    event.accepted = true
                                    return
                                }
                                if (event.key === Qt.Key_Down) {
                                    // Don't allow history navigation in password mode
                                    if (!container.passwordModeActive) {
                                        textArea.cursorPosition = textArea.length
                                        terminalBackend.recallNextHistory() // Assuming terminalBackend is in scope
                                    }
                                    event.accepted = true
                                    return
                                }

                                // ==== Enter/Return Key ====
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    const command = container.passwordModeActive
                                    ? textArea.actualInputText
                                    : textArea.getText(promptPosition, textArea.length).trim()

                                    if (container.passwordModeActive) {
                                        textArea.actualInputText = ""
                                    }

                                    // Finalize the current input line by appending a newline.
                                    // This makes the UI update immediately and avoids depending on backend echo.

                                    promptPosition = textArea.length // The new editable position is now at the end.

                                    if (!container.passwordModeActive && command === "clear") {
                                        // `clear` command is special-cased to only affect the QML side
                                        scrollView.clearTerminal();
                                        container.sendCommand(""); // Send an empty command to get a new prompt
                                    } else {
                                        container.sendCommand(command)
                                    }
                                    event.accepted = true
                                    return
                                }


                                // ==== Backspace Key ====
                                if (event.key === Qt.Key_Backspace) {
                                    if (textArea.cursorPosition > promptPosition) {
                                        if (container.passwordModeActive) {
                                            // Password mode: update hidden text and remove one visible char
                                            if (textArea.actualInputText.length > 0) {
                                                textArea.actualInputText = textArea.actualInputText.slice(0, -1);
                                                textArea.remove(textArea.cursorPosition - 1, textArea.cursorPosition);
                                            }
                                        } else {
                                            // Normal mode: explicitly remove one character instead of relying on default behavior
                                            textArea.remove(textArea.cursorPosition - 1, textArea.cursorPosition);
                                        }
                                    }
                                    // In all cases, we have now handled the event or blocked it.
                                    event.accepted = true;
                                    return;
                                }

                                // ==== Block Deletions Before Prompt ====
                                if ((event.key === Qt.Key_Delete) && textArea.selectionStart < promptPosition) {
                                    event.accepted = true
                                    return
                                }

                                // ==== Control Characters & Special Keys ====
                                if (event.key === Qt.Key_Tab) { container.sendKeyData("\x09"); event.accepted = true; return }
                                const controlCharMap = { [Qt.Key_D]: "\x04", [Qt.Key_E]: "\x05", [Qt.Key_K]: "\x0B", [Qt.Key_L]: "\x0C",
                                    [Qt.Key_Q]: "\x11", [Qt.Key_R]: "\x12", [Qt.Key_S]: "\x13", [Qt.Key_U]: "\x15",
                                    [Qt.Key_W]: "\x17", [Qt.Key_Z]: "\x1A" }
                                if (event.modifiers === Qt.ControlModifier && controlCharMap[event.key]) { container.sendKeyData(controlCharMap[event.key]); event.accepted = true; return }
                                if (event.modifiers === Qt.AltModifier) {
                                    switch (event.key) {
                                        case Qt.Key_B: container.sendKeyData("\x1bb"); event.accepted = true; return
                                        case Qt.Key_F: container.sendKeyData("\x1bf"); event.accepted = true; return
                                    }
                                }

                                // Block left arrow from going past the prompt
                                if (event.key === Qt.Key_Left && textArea.cursorPosition <= promptPosition) { event.accepted = true; return }

                                // ==== Password Mode Character Input ====
                                if (container.passwordModeActive && event.text.length > 0) {
                                    textArea.actualInputText += event.text;
                                    textArea.insert(textArea.cursorPosition, '●');
                                    event.accepted = true;
                                    return;
                                }

                                // Allow default handling for normal text input
                                event.accepted = false
                            }

            onTextChanged: {
                if (textArea.cursorPosition < promptPosition)
                    textArea.cursorPosition = textArea.length
            }

            Component.onCompleted: forceActiveFocus()
            onActiveFocusChanged: {
                if (!activeFocus && !contextMenu.visible && !infoPopup.visible)
                    Qt.callLater(() => forceActiveFocus())
            }
        }
    }

    // MouseArea captures right-clicks over the whole component to open the context menu.
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

        // This overlay closes the context menu when clicking anywhere else.
        MouseArea {
            id: overlay
            anchors.fill: parent
            enabled: contextMenu.visible
            acceptedButtons: Qt.AllButtons
            onPressed: (mouse) => { contextMenu.close(); mouse.accepted = false; }
            z: contextMenu.z - 1
        }

        /* ===  Context Menu === */
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
                    width: parent.width; height: 30; visible: contextMenu.clickedLink === "" && contextMenu.hasSelection && !container.passwordModeActive
                    color: copyMouseArea.pressed ? container.getPressedColor(container.currentTheme.Background) : (copyMouseArea.containsMouse ? container.getHoverColor(container.currentTheme.Background) : "transparent")
                    radius: contextMenu.radius
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; text: "Copy"; color: copyMouseArea.containsMouse ? container.getContrastingTextColor(parent.color) : container.currentTheme.Foreground || "#f2f2f2" }
                    MouseArea { id: copyMouseArea; anchors.fill: parent; hoverEnabled: true; onClicked: { container.copyRequested(textArea.selectedText); contextMenu.close() } }
                }
                Rectangle { width: parent.width - 10; height: 1; anchors.horizontalCenter: parent.horizontalCenter; color: container.currentTheme.Color0Intense || "#444"; visible: (contextMenu.clickedLink !== "") || (contextMenu.clickedLink === "" && contextMenu.hasSelection) }
                Rectangle {
                    width: parent.width; height: 30; visible: !container.passwordModeActive
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
                padding: 15
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

