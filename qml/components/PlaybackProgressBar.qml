import QtQuick

Item {
    id: progressBar

    required property var renderer
    property bool dragging: false
    property bool awaitingSeek: false
    property real previewValue: 0
    readonly property real maxValue: Math.max(renderer.duration, 0.001)
    readonly property real shownValue: dragging || awaitingSeek ? previewValue : renderer.timePos
    readonly property real progress: Math.max(0, Math.min(1, shownValue / maxValue))
    readonly property real bufferProgress: Math.max(0, Math.min(1, renderer.bufferEnd / maxValue))
    readonly property bool hovered: progressHoverHandler.hovered || dragging
    readonly property real trackHeight: hovered ? 6 : 3

    function updateFromPosition(positionX) {
        const ratio = Math.max(0, Math.min(1, positionX / width))
        previewValue = ratio * maxValue
    }

    Rectangle {
        id: progressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: progressBar.trackHeight
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.15)
        clip: true

        Rectangle {
            width: parent.width * progressBar.bufferProgress
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.3)
        }

        Rectangle {
            width: parent.width * progressBar.progress
            height: parent.height
            radius: parent.radius
            color: "#3374DB"
        }

        Behavior on height {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        x: progressBar.progress * (progressBar.width - width)
        anchors.verticalCenter: parent.verticalCenter
        visible: progressBar.hovered
        width: 12
        height: 12
        radius: 6
        color: "#FFFFFF"
    }

    HoverHandler {
        id: progressHoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onPressed: (mouse) => {
            progressBar.dragging = true
            progressBar.updateFromPosition(mouse.x)
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                progressBar.updateFromPosition(mouse.x)
            }
        }

        onReleased: (mouse) => {
            progressBar.updateFromPosition(mouse.x)
            progressBar.awaitingSeek = true
            renderer.seekTo(progressBar.previewValue)
            progressBar.dragging = false
        }

        onCanceled: {
            progressBar.dragging = false
            progressBar.awaitingSeek = false
        }
    }

    Connections {
        target: renderer

        function onTimePosChanged() {
            if (
                progressBar.awaitingSeek
                && Math.abs(renderer.timePos - progressBar.previewValue) <= 0.5
            ) {
                progressBar.awaitingSeek = false
            }
        }
    }
}
