import QtQuick
import QtQuick.Controls

import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: volumeSelector

    required property var renderer
    readonly property bool panelVisible: volumePopup.visible

    implicitWidth: 24
    implicitHeight: 24

    Timer {
        id: closeTimer
        interval: 150
        onTriggered: volumePopup.close()
    }

    Popup {
        id: volumePopup
        x: volumeTrigger.x + (volumeTrigger.width - width) / 2
        y: volumeTrigger.y - height - 8
        width: 72
        height: 212
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        HoverHandler {
            onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.start()
        }

        background: Rectangle {
            radius: 10
            color: "#141924"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)
        }

        contentItem: Item {
            id: volumeBar
            implicitWidth: 28
            implicitHeight: 188
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: 28
            property bool dragging: false
            property real previewValue: volumeSelector.renderer.volume
            readonly property real shownValue: dragging ? previewValue : volumeSelector.renderer.volume
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
                        volumeSelector.renderer.setVolume(volumeBar.previewValue)
                    }

                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            volumeBar.updateFromPosition(mouse.y)
                            volumeSelector.renderer.setVolume(volumeBar.previewValue)
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

    Item {
        id: volumeTrigger
        anchors.centerIn: parent
        width: 24
        height: 24

        HoverHandler {
            id: volumeButtonHoverHandler
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                    volumePopup.open()
                } else {
                    closeTimer.start()
                }
            }
        }

        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            source: PlayerFormat.volumeIconSource(volumeSelector.renderer.volume)
        }
    }
}
