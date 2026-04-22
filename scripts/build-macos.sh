#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/macos}"
QT_ROOT="${QT_ROOT:-}"
MPV_ROOT="${MPV_ROOT:-${ROOT_DIR}/third_party/mpv/macos}"
MPV_INCLUDE_DIR="${MPV_INCLUDE_DIR:-${MPV_ROOT}/include}"
MPV_LIBRARY="${MPV_LIBRARY:-${MPV_ROOT}/lib/libmpv.dylib}"
MPV_RUNTIME_LIBRARY="${MPV_RUNTIME_LIBRARY:-${MPV_LIBRARY}}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}"
CMAKE_OSX_ARCHITECTURES="${CMAKE_OSX_ARCHITECTURES:-}"
RUN_MACDEPLOYQT="${RUN_MACDEPLOYQT:-1}"
COPY_EXTRA_QT_RUNTIME="${COPY_EXTRA_QT_RUNTIME:-1}"
FIX_QT_PLUGIN_RPATHS="${FIX_QT_PLUGIN_RPATHS:-1}"
CLEAN_BUILD_DIR="${CLEAN_BUILD_DIR:-0}"
CMAKE_BIN="${CMAKE_BIN:-$(command -v cmake || true)}"
NINJA_BIN="${NINJA_BIN:-$(command -v ninja || true)}"

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

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

require_file() {
    local path="$1"
    local description="$2"
    if [[ ! -f "${path}" ]]; then
        fail "${description} not found: ${path}"
    fi
}

require_dir() {
    local path="$1"
    local description="$2"
    if [[ ! -d "${path}" ]]; then
        fail "${description} not found: ${path}"
    fi
}

find_macdeployqt() {
    find_first_existing \
        "${QT_ROOT}/bin/macdeployqt" \
        "${QT_ROOT}/libexec/macdeployqt" \
        "$(command -v macdeployqt || true)"
}

find_qt_plugin_root() {
    find_first_existing \
        "${QT_ROOT}/plugins" \
        "${QT_ROOT}/share/qt6/plugins" \
        "${QT_ROOT}/lib/qt6/plugins"
}

join_by_semicolon() {
    local first=1
    local item
    for item in "$@"; do
        [[ -z "${item}" ]] && continue
        if [[ ${first} -eq 1 ]]; then
            printf '%s' "${item}"
            first=0
        else
            printf ';%s' "${item}"
        fi
    done
}

libmpv_supports_gl() {
    local library="$1"
    if strings "${library}" 2>/dev/null | grep -Fq -- "-Dgl=disabled"; then
        return 1
    fi
    return 0
}

fix_plugin_rpaths() {
    local plugin_root="$1"
    local plugin

    [[ -d "${plugin_root}" ]] || return 0

    while IFS= read -r -d '' plugin; do
        install_name_tool -delete_rpath @loader_path/../../lib "${plugin}" 2>/dev/null || true
        install_name_tool -delete_rpath @loader_path/../../../lib "${plugin}" 2>/dev/null || true
        install_name_tool -delete_rpath @executable_path/../lib "${plugin}" 2>/dev/null || true
        install_name_tool -add_rpath @loader_path/../../Frameworks "${plugin}" 2>/dev/null || true
        install_name_tool -add_rpath @loader_path/../../../Frameworks "${plugin}" 2>/dev/null || true
    done < <(find "${plugin_root}" -name '*.dylib' -print0)
}

copy_framework_if_missing() {
    local framework_name="$1"
    local source="${QT_ROOT}/lib/${framework_name}"
    local target="${APP_BUNDLE}/Contents/Frameworks/${framework_name}"

    if [[ -e "${source}" && ! -e "${target}" ]]; then
        cp -R "${source}" "${target}"
    fi
}

copy_plugin_if_missing() {
    local relative_path="$1"
    local source="${QT_PLUGIN_ROOT}/${relative_path}"
    local target="${APP_BUNDLE}/Contents/PlugIns/${relative_path}"

    if [[ -e "${source}" && ! -e "${target}" ]]; then
        mkdir -p "$(dirname "${target}")"
        cp -f "${source}" "${target}"
    fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "scripts/build-macos.sh must be run on macOS"
fi

[[ -n "${CMAKE_BIN}" ]] || fail "cmake not found"
require_dir "${ROOT_DIR}" "project root"

if [[ -z "${QT_ROOT}" ]]; then
    fail "QT_ROOT is not set. Example: QT_ROOT=/Users/lnks/Qt/6.8.3/macos"
fi

require_dir "${QT_ROOT}" "Qt root"
require_dir "${MPV_ROOT}" "MPV root"
require_dir "${MPV_INCLUDE_DIR}" "libmpv include directory"
require_file "${MPV_INCLUDE_DIR}/mpv/client.h" "libmpv header"
require_file "${MPV_INCLUDE_DIR}/mpv/render.h" "libmpv header"
require_file "${MPV_INCLUDE_DIR}/mpv/render_gl.h" "libmpv header"
require_file "${MPV_INCLUDE_DIR}/mpv/stream_cb.h" "libmpv header"
require_file "${MPV_LIBRARY}" "libmpv library"
require_file "${MPV_RUNTIME_LIBRARY}" "libmpv runtime library"

if [[ "${CMAKE_GENERATOR}" == "Ninja" && -z "${NINJA_BIN}" ]]; then
    fail "Ninja generator selected but ninja was not found"
fi

if ! libmpv_supports_gl "${MPV_LIBRARY}"; then
    fail "The selected libmpv was built with '-Dgl=disabled' and cannot work with this project's render_gl path"
fi

MACDEPLOYQT_BIN="$(find_macdeployqt || true)"
QT_PLUGIN_ROOT="$(find_qt_plugin_root || true)"
if [[ "${RUN_MACDEPLOYQT}" != "0" && -z "${MACDEPLOYQT_BIN}" ]]; then
    fail "macdeployqt not found under QT_ROOT or PATH"
fi

if [[ "${CLEAN_BUILD_DIR}" != "0" ]]; then
    rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}"

CMAKE_ARCH_ARGS=()
if [[ -n "${CMAKE_OSX_ARCHITECTURES}" ]]; then
    CMAKE_ARCH_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}")
fi

MPV_BUNDLE_SEARCH_PATHS_VALUE="$(join_by_semicolon \
    "${MPV_ROOT}" \
    "${MPV_ROOT}/lib" \
    "${MPV_ROOT}/Frameworks" \
    "$(dirname "${MPV_RUNTIME_LIBRARY}")")"

export PATH="${QT_ROOT}/bin:${PATH}"

"${CMAKE_BIN}" -S "${ROOT_DIR}" -B "${BUILD_DIR}" \
    -G "${CMAKE_GENERATOR}" \
    "${CMAKE_ARCH_ARGS[@]}" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DCMAKE_PREFIX_PATH="${QT_ROOT}" \
    -DMPV_ROOT="${MPV_ROOT}" \
    -DMPV_INCLUDE_DIR="${MPV_INCLUDE_DIR}" \
    -DMPV_LIBRARY="${MPV_LIBRARY}" \
    -DMPV_RUNTIME_LIBRARY="${MPV_RUNTIME_LIBRARY}" \
    -DMPV_BUNDLE_SEARCH_PATHS="${MPV_BUNDLE_SEARCH_PATHS_VALUE}"

"${CMAKE_BIN}" --build "${BUILD_DIR}" --parallel

APP_BUNDLE="${BUILD_DIR}/lzc-player.app"
require_dir "${APP_BUNDLE}" "built app bundle"

if [[ "${RUN_MACDEPLOYQT}" != "0" ]]; then
    "${MACDEPLOYQT_BIN}" "${APP_BUNDLE}" -qmldir="${ROOT_DIR}/qml"
fi

if [[ "${COPY_EXTRA_QT_RUNTIME}" != "0" ]]; then
    copy_framework_if_missing "QtQuickLayouts.framework"
    copy_framework_if_missing "QtQuickControls2Basic.framework"
    copy_framework_if_missing "QtQuickControls2BasicStyleImpl.framework"
    copy_framework_if_missing "QtQuickControls2.framework"
    copy_framework_if_missing "QtQuickControls2Impl.framework"
    copy_framework_if_missing "QtQuickTemplates2.framework"
    copy_framework_if_missing "QtSvg.framework"
    copy_framework_if_missing "QtSvgWidgets.framework"

    if [[ -n "${QT_PLUGIN_ROOT}" ]]; then
        copy_plugin_if_missing "imageformats/libqsvg.dylib"
        copy_plugin_if_missing "iconengines/libqsvgicon.dylib"
    fi
fi

if [[ "${FIX_QT_PLUGIN_RPATHS}" != "0" ]]; then
    fix_plugin_rpaths "${APP_BUNDLE}/Contents/PlugIns"
fi

printf 'Build completed.\n'
printf 'App bundle: %s\n' "${APP_BUNDLE}"
printf 'Executable: %s\n' "${APP_BUNDLE}/Contents/MacOS/lzc-player"
printf 'libmpv: %s\n' "${MPV_RUNTIME_LIBRARY}"
printf '\n'
printf 'Suggested verification:\n'
printf '  QT_DEBUG_PLUGINS=1 "%s"\n' "${APP_BUNDLE}/Contents/MacOS/lzc-player"
