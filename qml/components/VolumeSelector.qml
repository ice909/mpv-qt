import QtQuick

import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: volumeSelector

    required property var renderer
    readonly property bool panelVisible:
        volumeButtonHoverHandler.hovered || volumeGapMouseArea.containsMouse || volumePanelHoverHandler.hovered

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        id: volumePanel
        visible: volumeSelector.panelVisible
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
            source: PlayerFormat.volumeIconSource(volumeSelector.renderer.volume)
        }
    }
}
