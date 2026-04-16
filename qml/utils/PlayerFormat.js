.pragma library

function pad(value) {
    return value < 10 ? "0" + value : String(value)
}

function formatTime(seconds) {
    const safe = Math.max(0, Math.floor(seconds || 0))
    const hours = Math.floor(safe / 3600)
    const minutes = Math.floor((safe % 3600) / 60)
    const secs = safe % 60

    if (hours > 0) {
        return hours + ":" + pad(minutes) + ":" + pad(secs)
    }

    return pad(minutes) + ":" + pad(secs)
}

function formatNetworkSpeed(bytesPerSecond) {
    const speed = Math.max(0, Number(bytesPerSecond) || 0)

    if (speed >= 1024 * 1024) {
        return (speed / (1024 * 1024)).toFixed(2) + " MB/s"
    }

    if (speed >= 1024) {
        return (speed / 1024).toFixed(1) + " KB/s"
    }

    return Math.round(speed) + " B/s"
}

function playbackSpeedMatches(currentSpeed, value) {
    return Math.abs((Number(currentSpeed) || 1.0) - value) < 0.001
}

function formatPlaybackSpeedLabel(value, playbackSpeedOptions) {
    const speed = Number(value) || 1.0

    for (let i = 0; i < playbackSpeedOptions.length; ++i) {
        const option = playbackSpeedOptions[i]
        if (Math.abs(option.value - speed) < 0.001) {
            return option.label
        }
    }

    const scaled = Math.round(speed * 100)
    return (scaled % 10 === 0 ? speed.toFixed(1) : speed.toFixed(2)) + "x"
}

function playbackSpeedButtonText(currentSpeed, playbackSpeedOptions) {
    return playbackSpeedMatches(currentSpeed, 1.0)
        ? "倍速"
        : formatPlaybackSpeedLabel(currentSpeed, playbackSpeedOptions)
}

function qualityButtonText(qualityLabel) {
    return qualityLabel || "原画质"
}

function volumeIconSource(volume) {
    const roundedVolume = Math.round(Number(volume) || 0)
    if (roundedVolume <= 0) {
        return "qrc:/lzc-player/assets/icons/volume-mute.svg"
    }

    if (roundedVolume < 50) {
        return "qrc:/lzc-player/assets/icons/volume-small.svg"
    }

    return "qrc:/lzc-player/assets/icons/volume.svg"
}
