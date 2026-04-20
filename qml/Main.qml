import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQml

import "components"
import "utils/PlayerFormat.js" as PlayerFormat

import mpvtest 1.0

Item {
    id: mainView
    width: 1280
    height: 720
    focus: true

    readonly property var hostWindow: Window.window
    property bool controlsVisible: true
    property bool loadingOverlayActive: renderer.loading
    readonly property var playbackSpeedOptions: [
        { value: 2.0, label: "2.0x" },
        { value: 1.75, label: "1.75x" },
        { value: 1.5, label: "1.5x" },
        { value: 1.25, label: "1.25x" },
        { value: 1.0, label: "1.0x" },
        { value: 0.7, label: "0.7x" },
        { value: 0.5, label: "0.5x" }
    ]
    readonly property real speedButtonReservedWidth:
        Math.ceil(Math.max(speedDefaultTextMetrics.advanceWidth, speedMaxTextMetrics.advanceWidth)) + 16
    readonly property real qualityButtonReservedWidth:
        Math.ceil(Math.max(qualityDefaultTextMetrics.advanceWidth, qualityMaxTextMetrics.advanceWidth)) + 16
    readonly property bool overlayOpen: controlsBar.overlayOpen
    readonly property bool startupHasSource:
        (initialPlaylist && initialPlaylist.length > 0) || !!initialFile
    property bool entryConsumed: startupHasSource
    readonly property bool emptyStateVisible:
        !entryConsumed && !renderer.hasMedia && !renderer.loading

    function syncControlsVisibility() {
        if (!renderer.hasMedia) {
            controlsVisible = false
            hideControlsTimer.stop()
            return
        }

        if (renderer.consoleOpen) {
            controlsVisible = false
            hideControlsTimer.stop()
            return
        }

        if (!renderer.playing || overlayOpen) {
            controlsVisible = true
            hideControlsTimer.stop()
            return
        }

        hideControlsTimer.restart()
    }

    function showControlsTemporarily() {
        if (!renderer.hasMedia) {
            controlsVisible = false
            hideControlsTimer.stop()
            return
        }

        if (renderer.consoleOpen) {
            controlsVisible = false
            hideControlsTimer.stop()
            return
        }

        controlsVisible = true
        syncControlsVisibility()
    }

    function ensureKeyboardFocus() {
        if (hostWindow) {
            hostWindow.requestActivate()
        }

        mainView.forceActiveFocus(Qt.OtherFocusReason)
    }

    function openSelectedFile(path) {
        if (path === undefined || path === null) {
            return
        }

        const resolvedPath = path.toString().trim()
        if (!resolvedPath) {
            return
        }

        entryConsumed = true
        renderer.setPlaylistItems([])
        renderer.loadFile(resolvedPath)
        ensureKeyboardFocus()
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

    MpvPlayerView {
        id: renderer
        objectName: "renderer"
        anchors.fill: parent

        Component.onCompleted: {
            mainView.ensureKeyboardFocus()

            if (initialStartPosition) {
                renderer.setStartupPosition(initialStartPosition)
            }

            if (initialPlaylist && initialPlaylist.length > 0) {
                renderer.setPlaylistItems(initialPlaylist)
                renderer.playEpisode(0)
            } else if (initialFile) {
                renderer.loadFile(initialFile)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
        visible: !renderer.hasMedia
    }

    Item {
        id: loadingOverlay
        anchors.centerIn: parent
        width: 58
        height: 58
        z: 3
        visible: loadingOverlayActive || opacity > 0
        opacity: renderer.loading ? 1 : 0
        enabled: false

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: "#78000000"
        }

        Item {
            id: spinner
            anchors.centerIn: parent
            width: 34
            height: 34

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: true
            }

            Canvas {
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()

                    const lineWidth = 2.2
                    const diameter = Math.min(width, height) - lineWidth - 2
                    const startAngle = -Math.PI * 0.82
                    const endAngle = Math.PI * 0.82

                    ctx.beginPath()
                    ctx.strokeStyle = "#FFFFFF"
                    ctx.lineWidth = lineWidth
                    ctx.lineCap = "round"
                    ctx.arc(width / 2, height / 2, diameter / 2, startAngle, endAngle, false)
                    ctx.stroke()
                }
            }
        }
    }

    Rectangle {
        visible: renderer.hasMedia
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
                text: PlayerFormat.formatNetworkSpeed(renderer.networkSpeed)
                color: "#F3F6FF"
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 2
        visible: mainView.emptyStateVisible || playerWindow.dropActive

        Rectangle {
            anchors.fill: parent
            color: playerWindow.dropActive ? "#261B4ED8" : "transparent"
            border.width: playerWindow.dropActive ? 2 : 0
            border.color: "#6EA1FF"
        }

        Column {
            anchors.centerIn: parent
            spacing: 16

            Button {
                id: openFileButton
                anchors.horizontalCenter: parent.horizontalCenter
                text: "选择文件"
                onClicked: playerWindow.openSystemFileDialog()

                background: Rectangle {
                    radius: 16
                    color: openFileButton.down ? "#3D6ED8" : openFileButton.hovered ? "#5B89EC" : "#4E79E6"
                    implicitWidth: 192
                    implicitHeight: 54
                }

                contentItem: Text {
                    text: openFileButton.text
                    color: "#F7FAFF"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: playerWindow.dropActive ? "松开即可开始播放" : "拖拽文件进来去播放"
                color: "#C2CAE0"
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
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
            if (renderer.hasMedia && renderer.playing && !overlayOpen) {
                controlsVisible = false
            }
        }
    }

    Timer {
        id: loadingOverlayHideTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (!renderer.loading) {
                loadingOverlayActive = false
            }
        }
    }

    Connections {
        target: renderer

        function onPlayingChanged() {
            syncControlsVisibility()
        }

        function onHasMediaChanged() {
            syncControlsVisibility()
        }

        function onLoadingChanged() {
            if (renderer.loading) {
                loadingOverlayHideTimer.stop()
                loadingOverlayActive = true
                return
            }

            loadingOverlayHideTimer.restart()
        }

        function onConsoleOpenChanged() {
            if (renderer.consoleOpen) {
                mainView.ensureKeyboardFocus()
            }
        }
    }

    Connections {
        target: playerWindow

        function onFileSelected(path) {
            mainView.openSelectedFile(path)
        }

        function onFileDropped(path) {
            mainView.openSelectedFile(path)
        }
    }

    onOverlayOpenChanged: syncControlsVisibility()

    Shortcut {
        sequence: "MediaNext"
        context: Qt.ApplicationShortcut
        enabled: renderer.hasPlaylist && !renderer.consoleOpen
        onActivated: renderer.playNextEpisode()
    }

    Shortcut {
        sequence: "MediaPrevious"
        context: Qt.ApplicationShortcut
        enabled: renderer.hasPlaylist && !renderer.consoleOpen
        onActivated: renderer.playPrevEpisode()
    }

    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        enabled: renderer.hasMedia && !renderer.consoleOpen
        onActivated: renderer.togglePause()
    }

    Shortcut {
        sequence: "I"
        context: Qt.ApplicationShortcut
        enabled: !renderer.consoleOpen
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

        if (event.key === Qt.Key_Tab) {
            renderer.command(["keypress", "TAB"])
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Space) {
            renderer.command(["keypress", "SPACE"])
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

    PlaybackControlsBar {
        id: controlsBar
        visible: renderer.hasMedia
        renderer: renderer
        hostWindow: mainView.hostWindow
        controlsVisible: parent.controlsVisible
        playbackSpeedOptions: parent.playbackSpeedOptions
        speedButtonReservedWidth: parent.speedButtonReservedWidth
        qualityButtonReservedWidth: parent.qualityButtonReservedWidth
    }
}
