import QtQuick
import QtQuick.Controls

Item {
    id: subtitleSelector

    required property var renderer
    readonly property bool panelVisible:
        subtitleButtonHoverHandler.hovered || subtitleGapMouseArea.containsMouse || subtitlePanelHoverHandler.hovered

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        id: subtitlePanel
        visible: subtitleSelector.panelVisible
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
                        model: subtitleSelector.renderer.subtitleTracks

                        delegate: Rectangle {
                            id: subtitleOption
                            required property var modelData
                            readonly property bool selected: subtitleSelector.renderer.subtitleId === modelData.id
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
                                onClicked: subtitleSelector.renderer.setSubtitleId(subtitleOption.modelData.id)
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
            source: subtitleButtonHoverHandler.hovered || subtitleSelector.panelVisible
                ? "qrc:/lzc-player/assets/icons/subtitle-hover.svg"
                : "qrc:/lzc-player/assets/icons/subtitle.svg"
        }
    }
}
