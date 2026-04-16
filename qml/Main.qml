import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQml

import mpvtest 1.0

Item {
    width: 1280
    height: 720
    readonly property var hostWindow: Window.window
    property bool controlsVisible: true
    readonly property var playbackSpeedOptions: [
        { value: 2.0, label: "2.0x" },
        { value: 1.75, label: "1.75x" },
        { value: 1.5, label: "1.5x" },
        { value: 1.25, label: "1.25x" },
        { value: 1.0, label: "1.0x" },
        { value: 0.7, label: "0.7x" },
        { value: 0.5, label: "0.5x" }
    ]
    readonly property bool speedPanelVisible:
        speedButtonHoverHandler.hovered || speedGapMouseArea.containsMouse || speedPanelHoverHandler.hovered
    readonly property bool qualityPanelVisible:
        qualityButtonHoverHandler.hovered || qualityGapMouseArea.containsMouse || qualityPanelHoverHandler.hovered
    readonly property bool subtitlePanelVisible:
        subtitleButtonHoverHandler.hovered || subtitleGapMouseArea.containsMouse || subtitlePanelHoverHandler.hovered
    readonly property bool volumePanelVisible:
        volumeButtonHoverHandler.hovered || volumeGapMouseArea.containsMouse || volumePanelHoverHandler.hovered
    readonly property real speedButtonReservedWidth: Math.ceil(Math.max(speedDefaultTextMetrics.advanceWidth, speedMaxTextMetrics.advanceWidth)) + 16
    readonly property real qualityButtonReservedWidth: Math.ceil(Math.max(qualityDefaultTextMetrics.advanceWidth, qualityMaxTextMetrics.advanceWidth)) + 16
    readonly property bool overlayOpen:
        speedPanelVisible || qualityPanelVisible || subtitlePanelVisible || volumePanelVisible

    function syncControlsVisibility() {
        if (!renderer.playing || overlayOpen) {
            controlsVisible = true
            hideControlsTimer.stop()
            return
        }

        hideControlsTimer.restart()
    }

    function showControlsTemporarily() {
        controlsVisible = true
        syncControlsVisibility()
    }

    function formatTime(seconds) {
        const safe = Math.max(0, Math.floor(seconds || 0))
        const hours = Math.floor(safe / 3600)
        const minutes = Math.floor((safe % 3600) / 60)
        const secs = safe % 60

        function pad(value) {
            return value < 10 ? "0" + value : String(value)
        }

        if (hours > 0) {
            return hours + ":" + pad(minutes) + ":" + pad(secs)
        }
        return pad(minutes) + ":" + pad(secs)
    }

    function formatNetworkSpeed(bytesPerSecond) {
        const speed = Math.max(0, Number(bytesPerSecond) || 0)
        if (speed >= 1024 * 1024) {
            return (speed / (1024 * 1024)).toFixed(2) + " MB/s"
        }
        if (speed >= 1024) {
            return (speed / 1024).toFixed(1) + " KB/s"
        }
        return Math.round(speed) + " B/s"
    }

    function playbackSpeedMatches(value) {
        return Math.abs((Number(renderer.playbackSpeed) || 1.0) - value) < 0.001
    }

    function formatPlaybackSpeedLabel(value) {
        const speed = Number(value) || 1.0
        for (let i = 0; i < playbackSpeedOptions.length; ++i) {
            const option = playbackSpeedOptions[i]
            if (Math.abs(option.value - speed) < 0.001) {
                return option.label
            }
        }

        const scaled = Math.round(speed * 100)
        return (scaled % 10 === 0 ? speed.toFixed(1) : speed.toFixed(2)) + "x"
    }

    function playbackSpeedButtonText() {
        return playbackSpeedMatches(1.0) ? "倍速" : formatPlaybackSpeedLabel(renderer.playbackSpeed)
    }

    function qualityButtonText() {
        return renderer.qualityLabel || "原画质"
    }

    function volumeIconSource() {
        const volume = Math.round(Number(renderer.volume) || 0)
        if (volume <= 0) {
            return "qrc:/lzc-player/assets/icons/volume-mute.svg"
        }
        if (volume < 50) {
            return "qrc:/lzc-player/assets/icons/volume-small.svg"
        }
        return "qrc:/lzc-player/assets/icons/volume.svg"
    }

    TextMetrics {
        id: speedDefaultTextMetrics
        font.pixelSize: 14
        font.weight: Font.Medium
        text: "倍速"
    }

    TextMetrics {
        id: speedMaxTextMetrics
        font.pixelSize: 14
        font.weight: Font.Medium
        text: "1.75x"
    }

    TextMetrics {
        id: qualityDefaultTextMetrics
        font.pixelSize: 14
        font.weight: Font.Medium
        text: "原画质"
    }

    TextMetrics {
        id: qualityMaxTextMetrics
        font.pixelSize: 14
        font.weight: Font.Medium
        text: "1080P"
    }

    component ControlButton: Button {
        id: controlButton
        property url iconSource: ""
        property int iconSize: 20
        property bool chromeless: false
        readonly property bool iconOnly: iconSource.toString().length > 0

        implicitHeight: iconOnly ? iconSize : 40
        implicitWidth: iconOnly ? iconSize : Math.max(40, contentItem.implicitWidth + 18)
        padding: 0

        background: Rectangle {
            radius: controlButton.chromeless ? 0 : 12
            color: controlButton.chromeless
                ? "transparent"
                : parent.down ? "#3A3F55" : parent.hovered ? "#31364A" : "#262B3D"
            border.width: controlButton.chromeless ? 0 : 1
            border.color: controlButton.chromeless
                ? "transparent"
                : parent.highlighted ? "#8FB2FF" : "#3C435D"
        }

        contentItem: Item {
            implicitWidth: controlButton.iconOnly ? icon.implicitWidth : label.implicitWidth
            implicitHeight: controlButton.iconOnly ? icon.implicitHeight : label.implicitHeight

            Image {
                id: icon
                anchors.centerIn: parent
                visible: controlButton.iconOnly
                source: controlButton.iconSource
                sourceSize.width: controlButton.iconSize
                sourceSize.height: controlButton.iconSize
                width: controlButton.iconSize
                height: controlButton.iconSize
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                id: label
                anchors.fill: parent
                visible: !controlButton.iconOnly
                text: controlButton.text
                color: "#F3F6FF"
                font.pixelSize: 14
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    MpvObject {
        id: renderer
        objectName: "renderer"
        anchors.fill: parent

        Component.onCompleted: {
            if (initialFile) {
                renderer.loadFile(initialFile)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 18
        anchors.rightMargin: 18
        radius: 14
        color: "#B8141924"
        border.width: 1
        border.color: "#39445F"
        z: 2

        implicitWidth: speedInfoRow.implicitWidth + 24
        implicitHeight: speedInfoRow.implicitHeight + 16

        Row {
            id: speedInfoRow
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: renderer.networkSpeed > 0 ? "#7EA8FF" : "#5A657F"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "网速 " + formatNetworkSpeed(renderer.networkSpeed)
                color: "#F3F6FF"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                showControlsTemporarily()
            }
        }

        onPointChanged: showControlsTemporarily()
    }

    Timer {
        id: hideControlsTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (renderer.playing && !overlayOpen) {
                controlsVisible = false
            }
        }
    }

    Connections {
        target: renderer

        function onPlayingChanged() {
            syncControlsVisibility()
        }
    }

    onOverlayOpenChanged: syncControlsVisibility()

    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        onActivated: renderer.togglePause()
    }

    Shortcut {
        sequence: "I"
        context: Qt.ApplicationShortcut
        onActivated: renderer.command([
            "script-binding",
            "stats/display-stats-toggle"
        ])
    }

    Shortcut {
        sequence: "`"
        context: Qt.ApplicationShortcut
        onActivated: renderer.command([
            "script-binding",
            "commands/open"
        ])
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (renderer.consoleOpen) {
                renderer.command([
                    "keypress",
                    "ESC"
                ])
            }
        }
    }

    Keys.onPressed: (event) => {
        if (!renderer.consoleOpen) {
            return
        }

        if (event.key === Qt.Key_Escape) {
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Backspace) {
            renderer.command(["keypress", "BS"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            renderer.command(["keypress", "ENTER"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Left) {
            renderer.command(["keypress", "LEFT"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Right) {
            renderer.command(["keypress", "RIGHT"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Up) {
            renderer.command(["keypress", "UP"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down) {
            renderer.command(["keypress", "DOWN"])
            event.accepted = true
            return
        }

        if (event.text && event.text.length > 0 && event.text >= " ") {
            renderer.command(["keypress", event.text])
            event.accepted = true
        }
    }

    Rectangle {
        id: controlsBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 48
        y: controlsVisible ? parent.height - height : parent.height + 10
        color: "transparent"
        border.width: 0
        opacity: controlsVisible ? 1 : 0
        enabled: controlsVisible

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.33; color: "#5E000000" }
                GradientStop { position: 0.66; color: "#BF000000" }
                GradientStop { position: 1.0; color: "#BF000000" }
            }
        }

        Item {
            id: progressBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottom: parent.top
            Layout.preferredHeight: 24
            height: 24
            property bool dragging: false
            property bool awaitingSeek: false
            property real previewValue: 0
            readonly property real maxValue: Math.max(renderer.duration, 0.001)
            readonly property real shownValue: dragging || awaitingSeek ? previewValue : renderer.timePos
            readonly property real progress: Math.max(0, Math.min(1, shownValue / maxValue))
            readonly property real bufferProgress: Math.max(0, Math.min(1, renderer.bufferEnd / maxValue))
            readonly property bool hovered: progressHoverHandler.hovered || dragging
            readonly property real trackHeight: hovered ? 6 : 3

            function updateFromPosition(positionX) {
                const ratio = Math.max(0, Math.min(1, positionX / width))
                previewValue = ratio * maxValue
            }

            Rectangle {
                id: progressTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: progressBar.trackHeight
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.15)
                clip: true

                Rectangle {
                    width: parent.width * progressBar.bufferProgress
                    height: parent.height
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.3)
                }

                Rectangle {
                    width: parent.width * progressBar.progress
                    height: parent.height
                    radius: parent.radius
                    color: "#3374DB"
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                x: progressBar.progress * (progressBar.width - width)
                anchors.verticalCenter: parent.verticalCenter
                visible: progressBar.hovered
                width: 12
                height: 12
                radius: 6
                color: "#FFFFFF"
            }

            HoverHandler {
                id: progressHoverHandler
                cursorShape: Qt.PointingHandCursor
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onPressed: (mouse) => {
                    progressBar.dragging = true
                    progressBar.updateFromPosition(mouse.x)
                }

                onPositionChanged: (mouse) => {
                    if (pressed) {
                        progressBar.updateFromPosition(mouse.x)
                    }
                }

                onReleased: (mouse) => {
                    progressBar.updateFromPosition(mouse.x)
                    progressBar.awaitingSeek = true
                    renderer.seekTo(progressBar.previewValue)
                    progressBar.dragging = false
                }

                onCanceled: {
                    progressBar.dragging = false
                    progressBar.awaitingSeek = false
                }
            }

            Connections {
                target: renderer

                function onTimePosChanged() {
                    if (
                        progressBar.awaitingSeek
                        && Math.abs(renderer.timePos - progressBar.previewValue) <= 0.5
                    ) {
                        progressBar.awaitingSeek = false
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12

            RowLayout {
                spacing: 16
                Layout.alignment: Qt.AlignVCenter

                ControlButton {
                    iconSource: renderer.playing
                        ? "qrc:/lzc-player/assets/icons/pause.svg"
                        : "qrc:/lzc-player/assets/icons/play.svg"
                    iconSize: 24
                    chromeless: true
                    onClicked: renderer.togglePause()
                }

                ControlButton {
                    iconSource: "qrc:/lzc-player/assets/icons/seek-backward.svg"
                    iconSize: 20
                    chromeless: true
                    onClicked: renderer.seekRelative(-10)
                }

                ControlButton {
                    iconSource: "qrc:/lzc-player/assets/icons/seek-forward.svg"
                    iconSize: 20
                    chromeless: true
                    onClicked: renderer.seekRelative(10)
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    textFormat: Text.RichText
                    color: "#FFFFFF"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    text: "<span style='color:#FFFFFF;'>"
                        + formatTime(progressBar.dragging ? progressBar.previewValue : renderer.timePos)
                        + " / </span><span style='color:rgba(255,255,255,0.8);'>"
                        + formatTime(renderer.duration)
                        + "</span>"
                }
            }

            Item {
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 16
                Layout.alignment: Qt.AlignVCenter

                Item {
                    id: speedSelector
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: speedButtonReservedWidth
                    implicitHeight: Math.max(24, speedButtonLabel.implicitHeight)

                    Rectangle {
                        id: speedPanel
                        visible: speedPanelVisible
                        anchors.horizontalCenter: speedTrigger.horizontalCenter
                        anchors.bottom: speedTrigger.top
                        anchors.bottomMargin: 8
                        width: 96
                        height: speedOptionsColumn.implicitHeight + 16
                        radius: 10
                        color: "#141924"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        z: 2

                        HoverHandler {
                            id: speedPanelHoverHandler
                        }

                        Column {
                            id: speedOptionsColumn
                            x: 8
                            y: 8
                            width: parent.width - 16
                            spacing: 4

                            Repeater {
                                model: playbackSpeedOptions

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: playbackSpeedMatches(modelData.value)

                                    width: parent ? parent.width : 80
                                    height: 32
                                    implicitWidth: 80
                                    implicitHeight: 32
                                    radius: 6
                                    color: speedOptionMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: parent.selected ? Qt.rgba(33 / 255, 115 / 255, 223 / 255, 1) : "#CBD5E0"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: parent.selected
                                        text: "✓"
                                        color: "#FFFFFF"
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: speedOptionMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: renderer.setPlaybackSpeed(parent.modelData.value)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: speedGapMouseArea
                        anchors.right: speedPanel.right
                        anchors.bottom: speedTrigger.top
                        width: speedPanel.width
                        height: speedPanel.anchors.bottomMargin
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Item {
                        id: speedTrigger
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: speedButtonReservedWidth
                        height: Math.max(24, speedButtonLabel.implicitHeight)

                        HoverHandler {
                            id: speedButtonHoverHandler
                            cursorShape: Qt.PointingHandCursor
                        }

                        Text {
                            id: speedButtonLabel
                            anchors.centerIn: parent
                            text: playbackSpeedButtonText()
                            color: "#CBD5E0"
                            font.pixelSize: 14
                            font.weight: Font.Medium

                        }
                    }
                }

                Item {
                    id: qualitySelector
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: qualityButtonReservedWidth
                    implicitHeight: Math.max(24, qualityButtonLabel.implicitHeight)

                    Rectangle {
                        id: qualityPanel
                        visible: qualityPanelVisible
                        anchors.horizontalCenter: qualityTrigger.horizontalCenter
                        anchors.bottom: qualityTrigger.top
                        anchors.bottomMargin: 8
                        width: 168
                        height: qualityOptionsColumn.implicitHeight + 16
                        radius: 10
                        color: "#141924"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        z: 2

                        HoverHandler {
                            id: qualityPanelHoverHandler
                        }

                        Column {
                            id: qualityOptionsColumn
                            x: 8
                            y: 8
                            width: parent.width - 16
                            spacing: 4

                            Repeater {
                                model: renderer.videoTracks

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: renderer.videoId === modelData.id

                                    width: parent ? parent.width : 152
                                    height: 32
                                    implicitWidth: 152
                                    implicitHeight: 32
                                    radius: 6
                                    color: qualityOptionMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: parent.selected ? Qt.rgba(33 / 255, 115 / 255, 223 / 255, 1) : "#CBD5E0"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.detail
                                        color: parent.selected ? "#FFFFFF" : Qt.rgba(203 / 255, 213 / 255, 224 / 255, 0.8)
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        id: qualityOptionMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: renderer.setVideoId(parent.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: qualityGapMouseArea
                        anchors.right: qualityPanel.right
                        anchors.bottom: qualityTrigger.top
                        width: qualityPanel.width
                        height: qualityPanel.anchors.bottomMargin
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Item {
                        id: qualityTrigger
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: qualityButtonReservedWidth
                        height: Math.max(24, qualityButtonLabel.implicitHeight)

                        HoverHandler {
                            id: qualityButtonHoverHandler
                            cursorShape: Qt.PointingHandCursor
                        }

                        Text {
                            id: qualityButtonLabel
                            anchors.centerIn: parent
                            text: qualityButtonText()
                            color: "#CBD5E0"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                    }
                }

                Item {
                    id: subtitleSelector
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 24
                    implicitHeight: 24

                    Rectangle {
                        id: subtitlePanel
                        visible: subtitlePanelVisible
                        anchors.horizontalCenter: subtitleTrigger.horizontalCenter
                        anchors.bottom: subtitleTrigger.top
                        anchors.bottomMargin: 8
                        width: 240
                        height: Math.min(subtitlePanelColumn.implicitHeight + 16, 360)
                        radius: 10
                        color: "#141924"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        z: 2

                        HoverHandler {
                            id: subtitlePanelHoverHandler
                        }

                        Column {
                            id: subtitlePanelColumn
                            x: 8
                            y: 8
                            width: parent.width - 16
                            spacing: 0

                            Item {
                                width: parent.width
                                height: subtitlePanelTitle.implicitHeight + 18

                                Text {
                                    id: subtitlePanelTitle
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.top: parent.top
                                    anchors.topMargin: 4
                                    text: "字幕"
                                    color: "#FFFFFF"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                            }

                            ScrollView {
                                id: subtitleScrollView
                                width: parent.width
                                height: Math.min(subtitleOptionsColumn.implicitHeight, 360 - 16 - subtitlePanelTitle.implicitHeight - 18)
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                contentWidth: availableWidth

                                Column {
                                    id: subtitleOptionsColumn
                                    width: subtitleScrollView.availableWidth
                                    spacing: 4

                                    Repeater {
                                        model: renderer.subtitleTracks

                                        delegate: Rectangle {
                                            id: subtitleOption
                                            required property var modelData
                                            readonly property bool selected: renderer.subtitleId === modelData.id
                                            readonly property bool offOption: modelData.id === 0

                                            width: parent ? parent.width : 208
                                            height: offOption ? 40 : 56
                                            radius: 6
                                            color: subtitleOptionMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                                            Column {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: offOption ? 0 : 3

                                                Text {
                                                    width: parent.width
                                                    color: subtitleOption.selected ? Qt.rgba(33 / 255, 115 / 255, 223 / 255, 1) : "#CBD5E0"
                                                    font.pixelSize: 14
                                                    font.weight: Font.Medium
                                                    text: subtitleOption.modelData.title
                                                        + (subtitleOption.modelData.isDefault ? " - 默认" : "")
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    visible: !subtitleOption.offOption && !!subtitleOption.modelData.detail
                                                    width: parent.width
                                                    color: Qt.rgba(203 / 255, 213 / 255, 224 / 255, 0.8)
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                    text: subtitleOption.modelData.detail
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                id: subtitleOptionMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: renderer.setSubtitleId(subtitleOption.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: subtitleGapMouseArea
                        anchors.right: subtitlePanel.right
                        anchors.bottom: subtitleTrigger.top
                        width: subtitlePanel.width
                        height: subtitlePanel.anchors.bottomMargin
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Item {
                        id: subtitleTrigger
                        anchors.centerIn: parent
                        width: 24
                        height: 24

                        HoverHandler {
                            id: subtitleButtonHoverHandler
                            cursorShape: Qt.PointingHandCursor
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            source: subtitleButtonHoverHandler.hovered || subtitlePanelVisible
                                ? "qrc:/lzc-player/assets/icons/subtitle-hover.svg"
                                : "qrc:/lzc-player/assets/icons/subtitle.svg"
                        }
                    }
                }

                Item {
                    id: volumeSelector
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 24
                    implicitHeight: 24

                    Rectangle {
                        id: volumePanel
                        visible: volumePanelVisible
                        anchors.horizontalCenter: volumeTrigger.horizontalCenter
                        anchors.bottom: volumeTrigger.top
                        anchors.bottomMargin: 8
                        width: 72
                        height: 212
                        radius: 10
                        color: "#141924"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        z: 2

                        HoverHandler {
                            id: volumePanelHoverHandler
                        }

                        Item {
                            id: volumeBar
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            width: 28
                            property bool dragging: false
                            property real previewValue: renderer.volume
                            readonly property real shownValue: dragging ? previewValue : renderer.volume
                            readonly property real progress: Math.max(0, Math.min(1, shownValue / 100))

                            function updateFromPosition(positionY) {
                                const ratioFromTop = Math.max(0, Math.min(1, positionY / height))
                                previewValue = (1 - ratioFromTop) * 100
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                text: Math.round(volumeBar.shownValue).toString()
                                color: "#FFFFFF"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 30
                                anchors.bottom: parent.bottom
                                width: parent.width

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 6
                                    radius: 3
                                    color: "#253047"

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: parent.height * volumeBar.progress
                                        radius: parent.radius
                                        color: "#7EA8FF"
                                    }
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: (1 - volumeBar.progress) * (parent.height - height)
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: "#F5F8FF"
                                    border.width: 2
                                    border.color: "#6B96FF"
                                }

                                MouseArea {
                                    anchors.fill: parent

                                    onPressed: (mouse) => {
                                        volumeBar.dragging = true
                                        volumeBar.updateFromPosition(mouse.y)
                                        renderer.setVolume(volumeBar.previewValue)
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (pressed) {
                                            volumeBar.updateFromPosition(mouse.y)
                                            renderer.setVolume(volumeBar.previewValue)
                                        }
                                    }

                                    onReleased: {
                                        volumeBar.dragging = false
                                    }

                                    onCanceled: {
                                        volumeBar.dragging = false
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: volumeGapMouseArea
                        anchors.horizontalCenter: volumePanel.horizontalCenter
                        anchors.bottom: volumeTrigger.top
                        width: volumePanel.width
                        height: volumePanel.anchors.bottomMargin
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Item {
                        id: volumeTrigger
                        anchors.centerIn: parent
                        width: 28
                        height: 38

                        HoverHandler {
                            id: volumeButtonHoverHandler
                            cursorShape: Qt.PointingHandCursor
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            source: volumeIconSource()
                        }
                    }
                }

                ControlButton {
                    iconSource: hostWindow && hostWindow.visibility === Window.FullScreen
                        ? "qrc:/lzc-player/assets/icons/quit-fullscreen.svg"
                        : "qrc:/lzc-player/assets/icons/fullscreen.svg"
                    iconSize: 24
                    chromeless: true
                    onClicked: {
                        if (!hostWindow) {
                            return
                        }

                        if (hostWindow.visibility === Window.FullScreen) {
                            hostWindow.showNormal()
                        } else {
                            hostWindow.showFullScreen()
                        }
                    }
                }
            }
        }
    }
}
