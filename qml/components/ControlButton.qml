import QtQuick
import QtQuick.Controls

Button {
    id: controlButton

    property url iconSource: ""
    property int iconSize: 20
    property bool chromeless: false
    readonly property bool iconOnly: iconSource.toString().length > 0

    implicitHeight: iconOnly ? iconSize : 40
    implicitWidth: iconOnly ? iconSize : Math.max(40, contentItem.implicitWidth + 18)
    padding: 0

    background: Rectangle {
        radius: controlButton.chromeless ? 0 : 12
        color: controlButton.chromeless
            ? "transparent"
            : parent.down ? "#3A3F55" : parent.hovered ? "#31364A" : "#262B3D"
        border.width: controlButton.chromeless ? 0 : 1
        border.color: controlButton.chromeless
            ? "transparent"
            : parent.highlighted ? "#8FB2FF" : "#3C435D"
    }

    contentItem: Item {
        implicitWidth: controlButton.iconOnly ? icon.implicitWidth : label.implicitWidth
        implicitHeight: controlButton.iconOnly ? icon.implicitHeight : label.implicitHeight

        Image {
            id: icon
            anchors.centerIn: parent
            visible: controlButton.iconOnly
            source: controlButton.iconSource
            sourceSize.width: controlButton.iconSize
            sourceSize.height: controlButton.iconSize
            width: controlButton.iconSize
            height: controlButton.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        Text {
            id: label
            anchors.fill: parent
            visible: !controlButton.iconOnly
            text: controlButton.text
            color: "#F3F6FF"
            font.pixelSize: 14
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
