import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQml

import mpvtest 1.0

Item {
    width: 1280
    height: 720
    readonly property var hostWindow: Window.window
    property bool controlsVisible: true
    readonly property bool overlayOpen:
        speedMenu.opened || qualityMenu.opened || subtitleMenu.opened || volumePopup.opened

    function syncControlsVisibility() {
        if (!renderer.playing || overlayOpen) {
            controlsVisible = true
            hideControlsTimer.stop()
            return
        }

        hideControlsTimer.restart()
    }

    function showControlsTemporarily() {
        controlsVisible = true
        syncControlsVisibility()
    }

    function formatTime(seconds) {
        const safe = Math.max(0, Math.floor(seconds || 0))
        const hours = Math.floor(safe / 3600)
        const minutes = Math.floor((safe % 3600) / 60)
        const secs = safe % 60

        function pad(value) {
            return value < 10 ? "0" + value : String(value)
        }

        if (hours > 0) {
            return hours + ":" + pad(minutes) + ":" + pad(secs)
        }
        return pad(minutes) + ":" + pad(secs)
    }

    component ControlButton: Button {
        implicitHeight: 40
        implicitWidth: Math.max(40, contentItem.implicitWidth + 18)
        padding: 0

        background: Rectangle {
            radius: 12
            color: parent.down ? "#3A3F55" : parent.hovered ? "#31364A" : "#262B3D"
            border.width: 1
            border.color: parent.highlighted ? "#8FB2FF" : "#3C435D"
        }

        contentItem: Text {
            text: parent.text
            color: "#F3F6FF"
            font.pixelSize: 14
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    MpvObject {
        id: renderer
        objectName: "renderer"
        anchors.fill: parent

        Component.onCompleted: {
            if (initialFile) {
                renderer.loadFile(initialFile)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                showControlsTemporarily()
            }
        }

        onPointChanged: showControlsTemporarily()
    }

    Timer {
        id: hideControlsTimer
        interval: 1800
        repeat: false
        onTriggered: {
            if (renderer.playing && !overlayOpen) {
                controlsVisible = false
            }
        }
    }

    Connections {
        target: renderer

        function onPlayingChanged() {
            syncControlsVisibility()
        }
    }

    onOverlayOpenChanged: syncControlsVisibility()

    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        onActivated: renderer.togglePause()
    }

    Rectangle {
        id: controlsBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 64
        y: controlsVisible ? parent.height - height : parent.height + 10
        color: "#D911141C"
        border.width: 1
        border.color: "#2A3144"
        opacity: controlsVisible ? 1 : 0
        enabled: controlsVisible

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#E61A1F2B" }
                GradientStop { position: 1.0; color: "#F012141A" }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                ControlButton {
                    text: renderer.playing ? "暂停" : "播放"
                    onClicked: renderer.togglePause()
                }

                ControlButton {
                    text: "-10s"
                    onClicked: renderer.seekRelative(-10)
                }

                ControlButton {
                    text: "+10s"
                    onClicked: renderer.seekRelative(10)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 10

                Text {
                    color: "#D9E1F7"
                    font.pixelSize: 13
                    text: formatTime(progressBar.dragging ? progressBar.previewValue : renderer.timePos)
                }

                Item {
                    id: progressBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    property bool dragging: false
                    property bool awaitingSeek: false
                    property real previewValue: 0
                    readonly property real maxValue: Math.max(renderer.duration, 0.001)
                    readonly property real shownValue: dragging || awaitingSeek ? previewValue : renderer.timePos
                    readonly property real progress: Math.max(0, Math.min(1, shownValue / maxValue))

                    function updateFromPosition(positionX) {
                        const ratio = Math.max(0, Math.min(1, positionX / width))
                        previewValue = ratio * maxValue
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        radius: 3
                        color: "#253047"

                        Rectangle {
                            width: parent.width * progressBar.progress
                            height: parent.height
                            radius: parent.radius
                            color: "#7EA8FF"
                        }
                    }

                    Rectangle {
                        x: progressBar.progress * (progressBar.width - width)
                        anchors.verticalCenter: parent.verticalCenter
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

                Text {
                    color: "#D9E1F7"
                    font.pixelSize: 13
                    text: formatTime(renderer.duration)
                }
            }

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                ControlButton {
                    id: speedButton
                    text: renderer.playbackSpeed.toFixed(2) + "x"
                    onClicked: speedMenu.open()

                    Menu {
                        id: speedMenu
                        y: -height - 12

                        Instantiator {
                            model: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                            delegate: MenuItem {
                                required property double modelData
                                text: modelData.toFixed(2) + "x"
                                onTriggered: renderer.setPlaybackSpeed(modelData)
                            }

                            onObjectAdded: (index, object) => speedMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => speedMenu.removeItem(object)
                        }
                    }
                }

                ControlButton {
                    id: qualityButton
                    text: renderer.qualityLabel || "画质"
                    onClicked: qualityMenu.open()

                    Menu {
                        id: qualityMenu
                        y: -height - 12

                        MenuItem {
                            text: renderer.qualityLabel ? "当前: " + renderer.qualityLabel : "等待视频信息"
                            enabled: false
                        }
                    }
                }

                ControlButton {
                    id: subtitleButton
                    text: "字幕"
                    onClicked: subtitleMenu.open()

                    Menu {
                        id: subtitleMenu
                        y: -height - 12

                        Instantiator {
                            model: renderer.subtitleTracks
                            delegate: MenuItem {
                                required property var modelData
                                text: modelData.title
                                checkable: true
                                checked: renderer.subtitleId === modelData.id
                                onTriggered: renderer.setSubtitleId(modelData.id)
                            }

                            onObjectAdded: (index, object) => subtitleMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => subtitleMenu.removeItem(object)
                        }
                    }
                }

                ControlButton {
                    id: volumeButton
                    text: "音量 " + Math.round(renderer.volume)
                    onClicked: volumePopup.open()
                }

                Popup {
                    id: volumePopup
                    parent: volumeButton
                    x: (parent.width - width) / 2
                    y: -height - 12
                    width: 64
                    height: 176
                    padding: 12
                    modal: false
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    background: Rectangle {
                        radius: 14
                        color: "#F0121723"
                        border.width: 1
                        border.color: "#323A52"
                    }

                    Item {
                        id: volumeBar
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 24
                        property bool dragging: false
                        property real previewValue: renderer.volume
                        readonly property real shownValue: dragging ? previewValue : renderer.volume
                        readonly property real progress: Math.max(0, Math.min(1, shownValue / 100))

                        function updateFromPosition(positionY) {
                            const ratioFromTop = Math.max(0, Math.min(1, positionY / height))
                            previewValue = (1 - ratioFromTop) * 100
                        }

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
                            y: (1 - volumeBar.progress) * (volumeBar.height - height)
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
                                renderer.setVolume(volumeBar.previewValue)
                            }

                            onPositionChanged: (mouse) => {
                                if (pressed) {
                                    volumeBar.updateFromPosition(mouse.y)
                                    renderer.setVolume(volumeBar.previewValue)
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

                ControlButton {
                    text: hostWindow && hostWindow.visibility === Window.FullScreen ? "退出全屏" : "全屏"
                    onClicked: {
                        if (!hostWindow) {
                            return
                        }

                        if (hostWindow.visibility === Window.FullScreen) {
                            hostWindow.showNormal()
                        } else {
                            hostWindow.showFullScreen()
                        }
                    }
                }
            }
        }
    }
}
