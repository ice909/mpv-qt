#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="lzc-player"
APP_DISPLAY_NAME="Lzc Player"
BUILD_DIR="${BUILD_DIR:-/tmp/lzc-player-build}"
APPDIR="${APPDIR:-/tmp/${APP_NAME}.AppDir}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
QT_ROOT="${QT_ROOT:-/opt/Qt/6.8.2/gcc_64}"

export PATH="${QT_ROOT}/bin:${PATH}"
export CMAKE_PREFIX_PATH="${QT_ROOT}:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="${QT_ROOT}/lib:${LD_LIBRARY_PATH:-}"
export QMAKE="${QT_ROOT}/bin/qmake"
export VERSION="${VERSION:-0.1}"
export ARCH="${ARCH:-x86_64}"
export QML_SOURCES_PATHS="${QML_SOURCES_PATHS:-/src/qml}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

if [[ ! -x /usr/local/bin/linuxdeployqt ]]; then
    echo "linuxdeployqt not found at /usr/local/bin/linuxdeployqt" >&2
    exit 1
fi

rm -rf "${BUILD_DIR}" "${APPDIR}"
cmake -S /src -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${QT_ROOT}" \
    -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "${BUILD_DIR}" --parallel
DESTDIR="${APPDIR}" cmake --install "${BUILD_DIR}"

cat > "${APPDIR}/${APP_NAME}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_DISPLAY_NAME}
Exec=${APP_NAME} %f
Icon=${APP_NAME}
Categories=AudioVideo;Player;Video;
MimeType=video/mp4;video/x-matroska;video/x-msvideo;video/quicktime;audio/mpeg;audio/flac;
Terminal=false
DESKTOP

mkdir -p "${APPDIR}/usr/share/applications"
cp "${APPDIR}/${APP_NAME}.desktop" "${APPDIR}/usr/share/applications/${APP_NAME}.desktop"

python3 - "${APPDIR}/${APP_NAME}.png" <<'PY'
import struct
import sys
import zlib

path = sys.argv[1]
width = height = 256

def rgba(x, y):
    t = (x + y) / (2 * (width - 1))
    r = int(15 + (110 - 15) * (1 - t))
    g = int(23 + (231 - 23) * (1 - t))
    b = int(42 + (249 - 42) * (1 - t))
    cx = x - width / 2
    cy = y - height / 2
    if 76 <= x <= 180 and 70 <= y <= 180:
        left = x >= 96
        upper = y >= -0.6 * (x - 96) + 76
        lower = y <= 0.6 * (x - 96) + 180
        if left and upper and lower:
            return (248, 250, 252, 235)
    if abs(y - 196) <= 7 and 54 <= x <= 202:
        return (224, 242, 254, 200)
    if abs(y - 196) <= 7 and 54 <= x <= 128:
        return (248, 250, 252, 255)
    if cx * cx + cy * cy > 126 * 126:
        return (0, 0, 0, 0)
    return (r, g, b, 255)

raw = bytearray()
for y in range(height):
    raw.append(0)
    for x in range(width):
        raw.extend(rgba(x, y))

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")
with open(path, "wb") as f:
    f.write(png)
PY

pushd "${APPDIR}" >/dev/null
ln -sf "usr/bin/${APP_NAME}" AppRun
popd >/dev/null

pushd /tmp >/dev/null
rm -f "${APP_NAME}"*.AppImage "${APP_NAME}"*.zsync
# Exclude Qt SQL drivers entirely; this app does not use them, and some
# upstream Qt packages depend on external client libraries unavailable here.
rm -rf "${QT_ROOT}/plugins/sqldrivers"
linuxdeployqt "${APPDIR}/usr/bin/${APP_NAME}" \
    -executable="${APPDIR}/usr/bin/${APP_NAME}" \
    -bundle-non-qt-libs \
    -qmldir=/src/qml \
    -appimage \
    -unsupported-allow-new-glibc
popd >/dev/null

mkdir -p "${OUTPUT_DIR}"
find /tmp -maxdepth 1 -type f -name "*.AppImage" -exec cp {} "${OUTPUT_DIR}/" \;
find /tmp -maxdepth 1 -type f -name "*.zsync" -exec cp {} "${OUTPUT_DIR}/" \;

echo "Generated files:"
find "${OUTPUT_DIR}" -maxdepth 1 -type f \( -name "*.AppImage" -o -name "*.zsync" \) -print
