#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_ROOT="${QT_ROOT:-${MSYSTEM_PREFIX:-${MINGW_PREFIX:-}}}"
MPV_ROOT="${MPV_ROOT:-${ROOT_DIR}/third_party/mpv}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/msys2-mingw64}"
DIST_ROOT="${DIST_ROOT:-${ROOT_DIR}/dist/windows}"
APP_NAME="${APP_NAME:-lzc-player}"
VERSION="${VERSION:-0.1}"
ARCH="${ARCH:-x86_64}"
PACKAGE_DIR="${PACKAGE_DIR:-${DIST_ROOT}/${APP_NAME}}"
ZIP_PATH="${ZIP_PATH:-${DIST_ROOT}/${APP_NAME}-${VERSION}-windows-${ARCH}.zip}"
RUN_BUILD="${RUN_BUILD:-1}"

readonly -a MPV_RUNTIME_DLL_NAMES=(
    "zlib1.dll"
    "libdouble-conversion.dll"
    "libbz2-1.dll"
    "libmd4c.dll"
    "libb2-1.dll"
    "libbrotlicommon.dll"
    "libbrotlidec.dll"
    "libbrotlienc.dll"
    "libgraphite2.dll"
    "libharfbuzz-0.dll"
    "libfreetype-6.dll"
    "libfribidi-0.dll"
    "libass-9.dll"
    "libiconv-2.dll"
    "libcharset-1.dll"
    "libglib-2.0-0.dll"
    "libintl-8.dll"
    "libpcre2-8-0.dll"
    "libpcre2-16-0.dll"
    "libffi-8.dll"
    "libpng16-16.dll"
    "libexpat-1.dll"
    "libicuuc78.dll"
    "libicuin78.dll"
    "libicudt78.dll"
    "liblzma-5.dll"
    "libzstd.dll"
)

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

strip_dll_version_suffix() {
    local dll_name="$1"
    local stem="${dll_name%.dll}"

    if [[ "${stem}" =~ ^(.+[^0-9])([0-9]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    printf '%s\n' "${stem}"
}

find_version_flexible_file() {
    local directory="$1"
    local dll_name="$2"
    local stem candidate

    if [[ -f "${directory}/${dll_name}" ]]; then
        printf '%s\n' "${directory}/${dll_name}"
        return 0
    fi

    stem="$(strip_dll_version_suffix "${dll_name}")"
    if [[ "${stem}" == "${dll_name%.dll}" ]]; then
        return 1
    fi

    for candidate in "${directory}/${stem}"*.dll; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

find_runtime_dll() {
    local dll_name="$1"
    shift

    local directory path
    for directory in "$@"; do
        path="$(find_version_flexible_file "${directory}" "${dll_name}" || true)"
        if [[ -n "${path}" ]]; then
            printf '%s\n' "${path}"
            return 0
        fi
    done

    return 1
}

copy_if_exists() {
    local source="$1"
    local target_dir="$2"
    if [[ -f "${source}" ]]; then
        cp -f "${source}" "${target_dir}/"
    fi
}

copy_dir_if_exists() {
    local source="$1"
    local target_dir="$2"
    local target_path

    if [[ ! -d "${source}" ]]; then
        return
    fi

    target_path="${target_dir}/$(basename "${source}")"
    rm -rf "${target_path}"
    cp -R "${source}" "${target_dir}/"
}

find_qt_plugin_root() {
    find_first_existing \
        "${QT_ROOT}/plugins" \
        "${QT_ROOT}/share/qt6/plugins" \
        "${QT_ROOT}/lib/qt6/plugins"
}

copy_qt_svg_runtime() {
    local target_dir="$1"
    local plugin_root="$2"
    local imageformats_dir="${target_dir}/imageformats"

    mkdir -p "${imageformats_dir}"

    copy_if_exists "${plugin_root}/imageformats/qsvg.dll" "${imageformats_dir}"
    copy_if_exists "${plugin_root}/imageformats/qsvgicon.dll" "${imageformats_dir}"
    copy_if_exists "${QT_ROOT}/bin/Qt6Svg.dll" "${target_dir}"
    copy_if_exists "${QT_ROOT}/bin/Qt6SvgWidgets.dll" "${target_dir}"
    copy_if_exists "${QT_ROOT}/bin/Qt6Xml.dll" "${target_dir}"
}

find_qml_import_root() {
    find_first_existing \
        "${QT_ROOT}/qml" \
        "${QT_ROOT}/lib/qt6/qml" \
        "${QT_ROOT}/share/qt6/qml"
}

copy_qml_runtime_modules() {
    local target_dir="$1"
    local qml_import_root="$2"
    local qml_target_dir="${target_dir}/qml"

    mkdir -p "${qml_target_dir}"

    # windeployqt does not reliably deploy QML imports from qrc-based apps in all MSYS2 setups.
    # Copy the required runtime trees explicitly so imports like QtQuick.Controls always resolve.
    copy_dir_if_exists "${qml_import_root}/Qt" "${qml_target_dir}"
    copy_dir_if_exists "${qml_import_root}/QtQml" "${qml_target_dir}"
    copy_dir_if_exists "${qml_import_root}/QtQuick" "${qml_target_dir}"
}

write_qt_conf() {
    local target_dir="$1"

    cat > "${target_dir}/qt.conf" <<'EOF'
[Paths]
Prefix=.
Plugins=plugins
Imports=qml
Qml2Imports=qml
QmlImports=qml
EOF
}

copy_software_gl_runtime() {
    local target_dir="$1"

    copy_if_exists "${QT_ROOT}/bin/opengl32sw.dll" "${target_dir}"

    local llvm_dll
    for llvm_dll in "${QT_ROOT}"/bin/libLLVM*.dll; do
        if [[ -f "${llvm_dll}" ]]; then
            copy_if_exists "${llvm_dll}" "${target_dir}"
        fi
    done
}

copy_mpv_runtime_whitelist() {
    local target_dir="$1"
    local dll_name source_path

    for dll_name in "${MPV_RUNTIME_DLL_NAMES[@]}"; do
        source_path="$(find_runtime_dll \
            "${dll_name}" \
            "${QT_ROOT}/bin" \
            "${MPV_ROOT}/bin" \
            "${MPV_ROOT}" || true)"
        if [[ -n "${source_path:-}" ]]; then
            copy_if_exists "${source_path}" "${target_dir}"
        fi
    done
}

if [[ -z "${QT_ROOT}" ]]; then
    echo "QT_ROOT is not set and MSYSTEM_PREFIX is unavailable. Run this from an MSYS2 MinGW shell or export QT_ROOT." >&2
    exit 1
fi

export PATH="${QT_ROOT}/share/qt6/bin:${QT_ROOT}/bin:${MPV_ROOT}/bin:${MPV_ROOT}:${BUILD_DIR}:${PATH}"
QML_IMPORT_ROOT="$(find_qml_import_root || true)"
QT_PLUGIN_ROOT="$(find_qt_plugin_root || true)"

if [[ "${RUN_BUILD}" != "0" ]]; then
    bash "${ROOT_DIR}/scripts/build-msys2.sh"
fi

EXECUTABLE_PATH="${BUILD_DIR}/${APP_NAME}.exe"
MPV_RUNTIME_DLL="$(find_first_existing \
    "${BUILD_DIR}/libmpv-2.dll" \
    "${MPV_ROOT}/libmpv-2.dll" \
    "${MPV_ROOT}/bin/libmpv-2.dll" \
    "${MPV_ROOT}/libmpv.dll" \
    "${MPV_ROOT}/bin/libmpv.dll")"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
    echo "Built executable not found: ${EXECUTABLE_PATH}" >&2
    exit 1
fi

if [[ -z "${MPV_RUNTIME_DLL:-}" ]]; then
    echo "libmpv runtime DLL not found in build output or ${MPV_ROOT}." >&2
    exit 1
fi

if ! command -v windeployqt >/dev/null 2>&1; then
    echo "windeployqt not found. Install Qt tools in the MSYS2 MinGW environment." >&2
    exit 1
fi

if ! command -v 7z >/dev/null 2>&1; then
    echo "7z not found. Install p7zip in the MSYS2 environment." >&2
    exit 1
fi

rm -rf "${PACKAGE_DIR}" "${ZIP_PATH}"
mkdir -p "${PACKAGE_DIR}" "${DIST_ROOT}"

cp -f "${EXECUTABLE_PATH}" "${PACKAGE_DIR}/"
cp -f "${MPV_RUNTIME_DLL}" "${PACKAGE_DIR}/"

windeployqt --release --no-translations --qmldir "${ROOT_DIR}/qml" "${PACKAGE_DIR}/${APP_NAME}.exe"
write_qt_conf "${PACKAGE_DIR}"

if [[ -n "${QML_IMPORT_ROOT}" ]]; then
    copy_qml_runtime_modules "${PACKAGE_DIR}" "${QML_IMPORT_ROOT}"
else
    echo "Qt QML import root not found under ${QT_ROOT}; skipping manual QML runtime copy." >&2
fi

if [[ -n "${QT_PLUGIN_ROOT}" ]]; then
    # The control bar icons are SVG assets loaded via QML Image, so the SVG imageformat plugin
    # must be present on Windows even when windeployqt does not detect it automatically.
    copy_qt_svg_runtime "${PACKAGE_DIR}" "${QT_PLUGIN_ROOT}"
else
    echo "Qt plugin root not found under ${QT_ROOT}; skipping manual SVG runtime copy." >&2
fi

copy_if_exists "${QT_ROOT}/bin/libstdc++-6.dll" "${PACKAGE_DIR}"
copy_if_exists "${QT_ROOT}/bin/libgcc_s_seh-1.dll" "${PACKAGE_DIR}"
copy_if_exists "${QT_ROOT}/bin/libwinpthread-1.dll" "${PACKAGE_DIR}"
copy_software_gl_runtime "${PACKAGE_DIR}"
copy_mpv_runtime_whitelist "${PACKAGE_DIR}"

pushd "${DIST_ROOT}" >/dev/null
7z a -tzip "${ZIP_PATH}" "$(basename "${PACKAGE_DIR}")" >/dev/null
popd >/dev/null

echo "Windows package created."
echo "Package directory: ${PACKAGE_DIR}"
echo "Zip archive: ${ZIP_PATH}"
