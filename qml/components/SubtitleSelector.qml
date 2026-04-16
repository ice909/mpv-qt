import QtQuick
import QtQuick.Controls

Item {
    id: subtitleSelector

    required property var renderer
    readonly property bool panelVisible: subtitlePopup.visible
    readonly property real popupEdgePadding: 12

    implicitWidth: 24
    implicitHeight: 24

    Timer {
        id: closeTimer
        interval: 150
        onTriggered: subtitlePopup.close()
    }

    Popup {
        id: subtitlePopup
        parent: Overlay.overlay
        x: {
            if (!parent) {
                return 0
            }

            const preferredX = subtitleTrigger.mapToItem(
                parent,
                (subtitleTrigger.width - width) / 2,
                0
            ).x
            const maxX = Math.max(
                subtitleSelector.popupEdgePadding,
                parent.width - width - subtitleSelector.popupEdgePadding
            )

            return Math.max(
                subtitleSelector.popupEdgePadding,
                Math.min(preferredX, maxX)
            )
        }
        y: parent
            ? subtitleTrigger.mapToItem(parent, 0, -height - 8).y
            : 0
        width: 240
        height: subtitleContentColumn.implicitHeight + 16
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
            id: subtitleContentColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Item {
                width: parent.width
                height: subtitlePanelTitle.implicitHeight

                Text {
                    id: subtitlePanelTitle
                    anchors.left: parent.left
                    text: "字幕"
                    color: "#FFFFFF"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }

            ScrollView {
                id: subtitleScrollView
                width: parent.width
                height: Math.min(subtitleOptionsColumn.implicitHeight, 360 - 16 - subtitlePanelTitle.implicitHeight - subtitleContentColumn.spacing)
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
                                onClicked: {
                                    subtitleSelector.renderer.setSubtitleId(subtitleOption.modelData.id)
                                    subtitlePopup.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: subtitleTrigger
        anchors.centerIn: parent
        width: 24
        height: 24

        HoverHandler {
            id: subtitleButtonHoverHandler
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                    subtitlePopup.open()
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
            source: subtitleButtonHoverHandler.hovered || subtitleSelector.panelVisible
                ? "qrc:/lzc-player/assets/icons/subtitle-hover.svg"
                : "qrc:/lzc-player/assets/icons/subtitle.svg"
        }
    }
}
