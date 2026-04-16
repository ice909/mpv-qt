import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import "../utils/PlayerFormat.js" as PlayerFormat

Rectangle {
    id: controlsBar

    required property var renderer
    required property var hostWindow
    required property bool controlsVisible
    required property var playbackSpeedOptions
    required property real speedButtonReservedWidth
    required property real qualityButtonReservedWidth
    readonly property bool overlayOpen:
        speedSelector.panelVisible
        || qualitySelector.panelVisible
        || subtitleSelector.panelVisible
        || volumeSelector.panelVisible

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

    PlaybackProgressBar {
        id: progressBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottom: parent.top
        height: 24
        renderer: controlsBar.renderer
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
                iconSource: controlsBar.renderer.playing
                    ? "qrc:/lzc-player/assets/icons/pause.svg"
                    : "qrc:/lzc-player/assets/icons/play.svg"
                iconSize: 24
                chromeless: true
                onClicked: controlsBar.renderer.togglePause()
            }

            ControlButton {
                iconSource: "qrc:/lzc-player/assets/icons/seek-backward.svg"
                iconSize: 20
                chromeless: true
                onClicked: controlsBar.renderer.seekRelative(-10)
            }

            ControlButton {
                iconSource: "qrc:/lzc-player/assets/icons/seek-forward.svg"
                iconSize: 20
                chromeless: true
                onClicked: controlsBar.renderer.seekRelative(10)
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                textFormat: Text.RichText
                color: "#FFFFFF"
                font.pixelSize: 14
                font.weight: Font.Medium
                text: "<span style='color:#FFFFFF;'>"
                    + PlayerFormat.formatTime(progressBar.shownValue)
                    + " / </span><span style='color:rgba(255,255,255,0.8);'>"
                    + PlayerFormat.formatTime(controlsBar.renderer.duration)
                    + "</span>"
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter

            PlaybackSpeedSelector {
                id: speedSelector
                Layout.alignment: Qt.AlignVCenter
                renderer: controlsBar.renderer
                playbackSpeedOptions: controlsBar.playbackSpeedOptions
                reservedWidth: controlsBar.speedButtonReservedWidth
            }

            QualitySelector {
                id: qualitySelector
                Layout.alignment: Qt.AlignVCenter
                renderer: controlsBar.renderer
                reservedWidth: controlsBar.qualityButtonReservedWidth
            }

            SubtitleSelector {
                id: subtitleSelector
                Layout.alignment: Qt.AlignVCenter
                renderer: controlsBar.renderer
            }

            VolumeSelector {
                id: volumeSelector
                Layout.alignment: Qt.AlignVCenter
                renderer: controlsBar.renderer
            }

            ControlButton {
                iconSource: controlsBar.hostWindow && controlsBar.hostWindow.visibility === Window.FullScreen
                    ? "qrc:/lzc-player/assets/icons/quit-fullscreen.svg"
                    : "qrc:/lzc-player/assets/icons/fullscreen.svg"
                iconSize: 24
                chromeless: true
                onClicked: {
                    if (!controlsBar.hostWindow) {
                        return
                    }

                    if (controlsBar.hostWindow.visibility === Window.FullScreen) {
                        controlsBar.hostWindow.showNormal()
                    } else {
                        controlsBar.hostWindow.showFullScreen()
                    }
                }
            }
        }
    }
}
