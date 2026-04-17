#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURE_PRESET="${CONFIGURE_PRESET:-msys2-mingw64}"
BUILD_PRESET="${BUILD_PRESET:-build-msys2-mingw64}"
QT_ROOT="${QT_ROOT:-${MSYSTEM_PREFIX:-${MINGW_PREFIX:-}}}"
MPV_ROOT="${MPV_ROOT:-${ROOT_DIR}/third_party/mpv}"
RUN_WINDEPLOYQT="${RUN_WINDEPLOYQT:-1}"

find_first_existing() {
    local path
    for path in "$@"; do
        if [[ -e "${path}" ]]; then
            printf '%s\n' "${path}"
            return 0
        fi
    done
    return 1
}

if [[ -z "${QT_ROOT}" ]]; then
    echo "QT_ROOT is not set and MSYSTEM_PREFIX is unavailable. Run this from an MSYS2 MinGW shell or export QT_ROOT." >&2
    exit 1
fi

if [[ ! -d "${QT_ROOT}" ]]; then
    echo "Qt root does not exist: ${QT_ROOT}" >&2
    exit 1
fi

if [[ ! -f "${MPV_ROOT}/include/mpv/client.h" ]]; then
    echo "libmpv headers not found under ${MPV_ROOT}/include/mpv." >&2
    echo "Extract mpv-dev-x86_64-20260417-git-c865008.7z to ${ROOT_DIR}/third_party/mpv or export MPV_ROOT." >&2
    exit 1
fi

MPV_LIBRARY="$(find_first_existing \
    "${MPV_ROOT}/libmpv.dll.a" \
    "${MPV_ROOT}/lib/libmpv.dll.a" \
    "${MPV_ROOT}/lib/libmpv-2.dll.a")"
MPV_RUNTIME_DLL="$(find_first_existing \
    "${MPV_ROOT}/libmpv-2.dll" \
    "${MPV_ROOT}/bin/libmpv-2.dll" \
    "${MPV_ROOT}/libmpv.dll" \
    "${MPV_ROOT}/bin/libmpv.dll")"

if [[ -z "${MPV_LIBRARY:-}" ]]; then
    echo "libmpv import library not found in ${MPV_ROOT}." >&2
    exit 1
fi

if [[ -z "${MPV_RUNTIME_DLL:-}" ]]; then
    echo "libmpv runtime DLL not found in ${MPV_ROOT}." >&2
    exit 1
fi

export PATH="${QT_ROOT}/bin:${PATH}"

cmake --preset "${CONFIGURE_PRESET}" \
    -DCMAKE_PREFIX_PATH="${QT_ROOT}" \
    -DMPV_ROOT="${MPV_ROOT}" \
    -DMPV_LIBRARY="${MPV_LIBRARY}" \
    -DMPV_RUNTIME_DLL="${MPV_RUNTIME_DLL}"

cmake --build --preset "${BUILD_PRESET}" --parallel

OUTPUT_DIR="${ROOT_DIR}/build/msys2-mingw64"
EXECUTABLE_PATH="${OUTPUT_DIR}/lzc-player.exe"

if [[ "${RUN_WINDEPLOYQT}" != "0" ]]; then
    if command -v windeployqt >/dev/null 2>&1; then
        windeployqt --release "${EXECUTABLE_PATH}"
    else
        echo "windeployqt not found in PATH; skipping Qt runtime deployment." >&2
    fi
fi

echo "Build completed."
echo "Executable: ${EXECUTABLE_PATH}"
echo "Bundled libmpv DLL: ${OUTPUT_DIR}/libmpv-2.dll"
