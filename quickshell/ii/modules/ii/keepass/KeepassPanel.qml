import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        id: keepassLoader
        active: KeePass.open

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:keepass"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true

            mask: Region { item: content }

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow]
                onCleared: KeePass.close()
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    KeePass.close()
                    event.accepted = true
                }
            }

            Rectangle {
                id: content
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Appearance.sizes.elevationMargin * 2
                radius: Appearance.rounding.normal
                color: Appearance.colors.colBackgroundSurfaceContainer
                border.color: Appearance.colors.colLayer1Border
                implicitWidth: 640
                implicitHeight: column.implicitHeight + 20

                Component.onCompleted: column.focusDefault()

                ColumnLayout {
                    id: column
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    focus: true

                    function focusDefault() {
                        if (!KeePass.open) return;
                        if (!KeePass.unlocked) {
                            unlockPassword.forceActiveFocus();
                            return;
                        }
                        if (KeePass.addMode) {
                            addEntryName.forceActiveFocus();
                            return;
                        }
                        entryList.forceActiveFocus();
                    }

                    Connections {
                        target: KeePass
                        function onOpenChanged() { column.focusDefault(); }
                        function onUnlockedChanged() {
                            column.focusDefault()
                            if (KeePass.unlocked && KeePass.addMode && KeePass.pendingPassword.length > 0) {
                                addPassword.text = KeePass.pendingPassword
                                KeePass.pendingPassword = ""
                                addPanel.addPasswordVisible = true
                            }
                        }
                        function onAddModeChanged() {
                            column.focusDefault()
                            if (KeePass.addMode && KeePass.unlocked && KeePass.pendingPassword.length > 0) {
                                addPassword.text = KeePass.pendingPassword
                                KeePass.pendingPassword = ""
                                addPanel.addPasswordVisible = true
                            }
                        }
                        function onGeneratedPasswordChanged() {
                            if (KeePass.generatedPassword.length > 0) {
                                addPassword.text = KeePass.generatedPassword
                                addPanel.addPasswordVisible = true
                                KeePass.generatedPassword = ""
                            }
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (!KeePass.unlocked) {
                                KeePass.unlock(unlockPassword.text)
                                unlockPassword.text = ""
                                event.accepted = true
                            } else if (KeePass.addMode) {
                                KeePass.addEntry(addEntryName.text, addPassword.text, addUsername.text, addUrl.text)
                                addPanel.clearForm()
                                event.accepted = true
                            } else if (KeePass.selectedEntry.length > 0) {
                                KeePass.copyPassword()
                                event.accepted = true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: KeePass.addMode ? Translation.tr("KeePass - Save") : Translation.tr("KeePass")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        // Lock indicator: verde = sbloccato (clic riblocca), rosso = bloccato
                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: if (KeePass.unlocked) KeePass.lock()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: KeePass.unlocked ? "lock_open" : "lock"
                                iconSize: Appearance.font.pixelSize.larger
                                color: KeePass.unlocked
                                    ? Appearance.m3colors.m3tertiary
                                    : Appearance.colors.colError
                            }
                        }
                        IconToolbarButton {
                            text: "close"
                            onClicked: KeePass.close()
                        }
                    }

                    // Unlock panel
                    Rectangle {
                        visible: !KeePass.unlocked
                        Layout.fillWidth: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        border.color: Appearance.colors.colLayer1Border
                        implicitHeight: unlockColumn.implicitHeight + 16
                        ColumnLayout {
                            id: unlockColumn
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            ToolbarTextField {
                                id: unlockPassword
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Vault password")
                                echoMode: TextInput.Password
                                onAccepted: {
                                    KeePass.unlock(unlockPassword.text)
                                    unlockPassword.text = ""
                                }
                            }

                            // TTL selector
                            RowLayout {
                                spacing: 4
                                StyledText {
                                    text: Translation.tr("Stay unlocked:")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                Repeater {
                                    model: [
                                        { label: "5 min",  ttl: 300   },
                                        { label: "30 min", ttl: 1800  },
                                        { label: "4 ore",  ttl: 14400 }
                                    ]
                                    delegate: DialogButton {
                                        required property var modelData
                                        buttonText: modelData.label
                                        toggled: KeePass.cacheTtl === modelData.ttl
                                        onClicked: KeePass.cacheTtl = modelData.ttl
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 8
                                DialogButton {
                                    buttonText: Translation.tr("Unlock")
                                    onClicked: {
                                        KeePass.unlock(unlockPassword.text)
                                        unlockPassword.text = ""
                                    }
                                }
                                DialogButton {
                                    buttonText: Translation.tr("Cancel")
                                    onClicked: KeePass.close()
                                }
                            }
                        }
                    }

                    // Error
                    StyledText {
                        visible: KeePass.lastError.length > 0
                        text: KeePass.lastError
                        color: Appearance.colors.colNegative
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    // List & detail
                    ColumnLayout {
                        visible: KeePass.unlocked && !KeePass.addMode
                        spacing: 8

                        ToolbarTextField {
                            id: filterField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Search entries")
                            onTextChanged: KeePass.filter = text
                        }

                        ListView {
                            id: entryList
                            Layout.fillWidth: true
                            implicitHeight: Math.min(420, entryList.contentHeight + 8)
                            clip: true
                            spacing: 2
                            model: KeePass.filteredEntries(KeePass.filter)
                            focus: true
                            KeyNavigation.tab: showButton
                            KeyNavigation.backtab: copyButton
                            currentIndex: 0
                            highlightFollowsCurrentItem: true
                            highlightMoveDuration: 80
                            highlight: Rectangle {
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer3Hover
                            }
                            delegate: DialogListItem {
                                required property var modelData
                                Layout.fillWidth: true
                                active: ListView.isCurrentItem
                                contentItem: StyledText {
                                    text: modelData
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                onClicked: {
                                    KeePass.openEntry(modelData)
                                }
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down) {
                                    entryList.currentIndex = Math.min(entryList.count - 1, entryList.currentIndex + 1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    entryList.currentIndex = Math.max(0, entryList.currentIndex - 1)
                                    event.accepted = true
                                } else
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && entryList.currentIndex >= 0) {
                                    const currentEntry = entryList.model[entryList.currentIndex]
                                    if (KeePass.selectedEntry === currentEntry) {
                                        KeePass.copyPassword()
                                    } else {
                                        KeePass.openEntry(currentEntry)
                                    }
                                    event.accepted = true
                                }
                            }
                        }

                        Rectangle {
                            visible: KeePass.selectedEntry.length > 0
                            Layout.fillWidth: true
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer1
                            border.color: Appearance.colors.colLayer1Border
                            implicitHeight: detailColumn.implicitHeight + 16
                            ColumnLayout {
                                id: detailColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                StyledText {
                                    text: KeePass.selectedEntry
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer0
                                    border.color: Appearance.colors.colLayer0Border
                                    implicitHeight: 36
                                    TextEdit {
                                        anchors.centerIn: parent
                                        text: KeePass.reveal ? KeePass.revealedPassword : "••••••••••"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                        selectByMouse: true
                                        readOnly: true
                                        wrapMode: TextEdit.NoWrap
                                    }
                                }
                                RowLayout {
                                    spacing: 8
                                    DialogButton {
                                        id: showButton
                                        buttonText: KeePass.reveal ? Translation.tr("Hide") : Translation.tr("Show")
                                        KeyNavigation.tab: copyButton
                                        KeyNavigation.backtab: entryList
                                        onClicked: {
                                            if (KeePass.reveal) {
                                                KeePass.reveal = false
                                                KeePass.revealedPassword = ""
                                            } else {
                                                KeePass.showPassword()
                                            }
                                        }
                                    }
                                    DialogButton {
                                        id: copyButton
                                        buttonText: Translation.tr("Copy Password")
                                        KeyNavigation.tab: copyUsernameButton
                                        KeyNavigation.backtab: showButton
                                        onClicked: KeePass.copyPassword()
                                    }
                                    DialogButton {
                                        id: copyUsernameButton
                                        buttonText: Translation.tr("Copy Username")
                                        KeyNavigation.tab: entryList
                                        KeyNavigation.backtab: copyButton
                                        onClicked: KeePass.copyUsername()
                                    }
                                }
                            }
                        }
                    }

                    // Add panel
                    ColumnLayout {
                        id: addPanel
                        visible: KeePass.unlocked && KeePass.addMode
                        spacing: 8

                        property bool addPasswordVisible: false
                        property int genLength: 20
                        property bool genUppercase: true
                        property bool genNumbers: true
                        property bool genSymbols: true

                        function clearForm() {
                            addEntryName.text = ""
                            addUsername.text = ""
                            addUrl.text = ""
                            addPassword.text = ""
                            addPasswordVisible = false
                        }

                        ToolbarTextField {
                            id: addEntryName
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Entry name (e.g. Email/GitHub)")
                        }
                        ToolbarTextField {
                            id: addUsername
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Username (optional)")
                        }
                        ToolbarTextField {
                            id: addUrl
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("URL (optional)")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            ToolbarTextField {
                                id: addPassword
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Password")
                                echoMode: addPanel.addPasswordVisible ? TextInput.Normal : TextInput.Password
                                onAccepted: {
                                    KeePass.addEntry(addEntryName.text, addPassword.text, addUsername.text, addUrl.text)
                                    addPanel.clearForm()
                                }
                            }

                            RippleButton {
                                implicitWidth: 34
                                implicitHeight: 34
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                onClicked: addPanel.addPasswordVisible = !addPanel.addPasswordVisible
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: addPanel.addPasswordVisible ? "visibility_off" : "visibility"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            DialogButton {
                                buttonText: Translation.tr("Generate")
                                onClicked: KeePass.generate(addPanel.genLength, addPanel.genUppercase, addPanel.genNumbers, addPanel.genSymbols)
                            }
                        }

                        // Generator options
                        RowLayout {
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Len:")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Repeater {
                                model: [8, 12, 20]
                                delegate: DialogButton {
                                    required property int modelData
                                    buttonText: modelData.toString()
                                    toggled: addPanel.genLength === modelData
                                    colEnabled: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                    onClicked: addPanel.genLength = modelData
                                }
                            }
                            Item { implicitWidth: 8 }
                            DialogButton {
                                buttonText: "A-Z"
                                toggled: addPanel.genUppercase
                                colEnabled: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                onClicked: addPanel.genUppercase = !addPanel.genUppercase
                            }
                            DialogButton {
                                buttonText: "0-9"
                                toggled: addPanel.genNumbers
                                colEnabled: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                onClicked: addPanel.genNumbers = !addPanel.genNumbers
                            }
                            DialogButton {
                                buttonText: "!@#"
                                toggled: addPanel.genSymbols
                                colEnabled: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                onClicked: addPanel.genSymbols = !addPanel.genSymbols
                            }
                        }

                        RowLayout {
                            spacing: 8
                            DialogButton {
                                buttonText: Translation.tr("Save")
                                onClicked: {
                                    KeePass.addEntry(addEntryName.text, addPassword.text, addUsername.text, addUrl.text)
                                    addPanel.clearForm()
                                }
                            }
                            DialogButton {
                                buttonText: Translation.tr("Cancel")
                                onClicked: KeePass.close()
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "keepass"

        function toggle(): void {
            if (KeePass.open) {
                KeePass.close()
            } else {
                KeePass.openList()
            }
        }

        function add(): void {
            KeePass.openAddWithSelection()
        }
    }

    GlobalShortcut {
        name: "keepassToggle"
        description: "Toggle KeePass panel"
        onPressed: {
            if (KeePass.open) {
                KeePass.close()
            } else {
                KeePass.openList()
            }
        }
    }

    GlobalShortcut {
        name: "keepassAdd"
        description: "Toggle KeePass add panel (pre-fill with primary selection)"
        onPressed: {
            KeePass.openAddWithSelection()
        }
    }
}
