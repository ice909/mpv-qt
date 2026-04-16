import QtQuick
import QtQuick.Controls
import "../utils/PlayerFormat.js" as PlayerFormat

Item {
    id: qualitySelector

    required property var renderer
    required property real reservedWidth
    readonly property bool panelVisible: qualityPopup.visible

    implicitWidth: reservedWidth
    implicitHeight: Math.max(24, qualityButtonLabel.implicitHeight)

    // 触发按钮区域
    Item {
        id: qualityTrigger
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: reservedWidth
        height: Math.max(24, qualityButtonLabel.implicitHeight)

        HoverHandler {
            id: buttonHoverHandler
            cursorShape: Qt.PointingHandCursor
            // 鼠标进入按钮时打开 Popup（并取消待关闭操作）
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                    qualityPopup.open()
                } else {
                    closeTimer.start()
                }
            }
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

    // 延迟关闭定时器（间隙容忍）
    Timer {
        id: closeTimer
        interval: 150
        onTriggered: qualityPopup.close()
    }

    Popup {
        id: qualityPopup
        // 定位在按钮正上方
        x: qualityTrigger.x + (qualityTrigger.width - width) / 2
        y: qualityTrigger.y - height - 8
        width: 168
        height: qualityOptionsColumn.implicitHeight + 16
        padding: 0

        // 关闭策略：Esc 关闭、点击外部关闭（可选）
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        // 鼠标进入 Popup 内部时，阻止关闭计时
        HoverHandler {
            onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.start()
        }

        // 自定义面板外观
        background: Rectangle {
            radius: 10
            color: "#141924"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)
        }

        contentItem: Column {
            id: qualityOptionsColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Repeater {
                model: qualitySelector.renderer.videoTracks

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: qualitySelector.renderer.videoId === modelData.id

                    width: parent.width
                    height: 32
                    radius: 6
                    color: qualityOptionMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: parent.selected ? "#2173df" : "#CBD5E0"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.detail
                        color: parent.selected ? "#FFFFFF" : Qt.rgba(203/255, 213/255, 224/255, 0.8)
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: qualityOptionMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            qualitySelector.renderer.setVideoId(parent.modelData.id)
                            qualityPopup.close()
                        }
                    }
                }
            }
        }
    }
}
