import QtQuick
import QtQml

import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: speedSelector

    required property var renderer
    required property var playbackSpeedOptions
    required property real reservedWidth
    readonly property bool panelVisible:
        speedButtonHoverHandler.hovered || speedGapMouseArea.containsMouse || speedPanelHoverHandler.hovered

    implicitWidth: reservedWidth
    implicitHeight: Math.max(24, speedButtonLabel.implicitHeight)

    Rectangle {
        id: speedPanel
        visible: speedSelector.panelVisible
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
                        onClicked: speedSelector.renderer.setPlaybackSpeed(parent.modelData.value)
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
        width: speedSelector.reservedWidth
        height: Math.max(24, speedButtonLabel.implicitHeight)

        HoverHandler {
            id: speedButtonHoverHandler
            cursorShape: Qt.PointingHandCursor
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
