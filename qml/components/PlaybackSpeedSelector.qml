import QtQuick
import QtQml
import QtQuick.Controls

import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: speedSelector

    required property var renderer
    required property var playbackSpeedOptions
    required property real reservedWidth
    readonly property bool panelVisible: speedPopup.visible

    implicitWidth: reservedWidth
    implicitHeight: Math.max(24, speedButtonLabel.implicitHeight)

    Timer {
        id: closeTimer
        interval: 150
        onTriggered: speedPopup.close()
    }

    Popup {
        id: speedPopup
        x: speedTrigger.x + (speedTrigger.width - width) / 2
        y: speedTrigger.y - height - 8
        width: 96
        height: speedOptionsColumn.implicitHeight + 16
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

        contentItem: Column {
            id: speedOptionsColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Repeater {
                model: speedSelector.playbackSpeedOptions

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: PlayerFormat.playbackSpeedMatches(
                        speedSelector.renderer.playbackSpeed,
                        modelData.value
                    )

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
                        onClicked: {
                            speedSelector.renderer.setPlaybackSpeed(parent.modelData.value)
                            speedPopup.close()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: speedTrigger
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: speedSelector.reservedWidth
        height: Math.max(24, speedButtonLabel.implicitHeight)

        HoverHandler {
            id: speedButtonHoverHandler
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                    speedPopup.open()
                } else {
                    closeTimer.start()
                }
            }
        }

        Text {
            id: speedButtonLabel
            anchors.centerIn: parent
            text: PlayerFormat.playbackSpeedButtonText(
                speedSelector.renderer.playbackSpeed,
                speedSelector.playbackSpeedOptions
            )
            color: "#CBD5E0"
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }
}
