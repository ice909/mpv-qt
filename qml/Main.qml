import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQml

import "components"
import "utils/PlayerFormat.js" as PlayerFormat

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
    readonly property real speedButtonReservedWidth:
        Math.ceil(Math.max(speedDefaultTextMetrics.advanceWidth, speedMaxTextMetrics.advanceWidth)) + 16
    readonly property real qualityButtonReservedWidth:
        Math.ceil(Math.max(qualityDefaultTextMetrics.advanceWidth, qualityMaxTextMetrics.advanceWidth)) + 16
    readonly property bool overlayOpen: controlsBar.overlayOpen

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
                text: "网速 " + PlayerFormat.formatNetworkSpeed(renderer.networkSpeed)
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

    PlaybackControlsBar {
        id: controlsBar
        renderer: renderer
        hostWindow: hostWindow
        controlsVisible: parent.controlsVisible
        playbackSpeedOptions: parent.playbackSpeedOptions
        speedButtonReservedWidth: parent.speedButtonReservedWidth
        qualityButtonReservedWidth: parent.qualityButtonReservedWidth
    }
}
