import QtQuick

import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: qualitySelector

    required property var renderer
    required property real reservedWidth
    readonly property bool panelVisible:
        qualityButtonHoverHandler.hovered || qualityGapMouseArea.containsMouse || qualityPanelHoverHandler.hovered

    implicitWidth: reservedWidth
    implicitHeight: Math.max(24, qualityButtonLabel.implicitHeight)

    Rectangle {
        id: qualityPanel
        visible: qualitySelector.panelVisible
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
                model: qualitySelector.renderer.videoTracks

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: qualitySelector.renderer.videoId === modelData.id

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
                        onClicked: qualitySelector.renderer.setVideoId(parent.modelData.id)
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
        width: qualitySelector.reservedWidth
        height: Math.max(24, qualityButtonLabel.implicitHeight)

        HoverHandler {
            id: qualityButtonHoverHandler
            cursorShape: Qt.PointingHandCursor
        }

        Text {
            id: qualityButtonLabel
            anchors.centerIn: parent
            text: PlayerFormat.qualityButtonText(qualitySelector.renderer.qualityLabel)
            color: "#CBD5E0"
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }
}
