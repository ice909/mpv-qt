#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QT_ROOT="${QT_ROOT:-${MSYSTEM_PREFIX:-${MINGW_PREFIX:-}}}"
MPV_ROOT="${MPV_ROOT:-${ROOT_DIR}/third_party/mpv}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/msys2-mingw64}"
DIST_ROOT="${DIST_ROOT:-${ROOT_DIR}/dist/windows}"
APP_NAME="${APP_NAME:-lzc-player}"
PACKAGE_DIR="${PACKAGE_DIR:-${DIST_ROOT}/${APP_NAME}}"
ZIP_PATH="${ZIP_PATH:-${DIST_ROOT}/${APP_NAME}-windows-x86_64.zip}"
RUN_BUILD="${RUN_BUILD:-1}"
RUNTIME_DEPENDENCY_COPY_COUNT=0

readonly -a MPV_RUNTIME_DLL_NAMES=(
    "zlib1.dll"
    "libdouble-conversion.dll"
    "libbz2-1.dll"
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

copy_if_exists() {
    local source="$1"
    local target_dir="$2"
    if [[ -f "${source}" ]]; then
        cp -f "${source}" "${target_dir}/"
    fi
}

normalize_path() {
    local path="$1"

    if [[ -z "${path}" ]]; then
        return 1
    fi

    case "${path}" in
        [A-Za-z]:\\*|[A-Za-z]:/*)
            if command -v cygpath >/dev/null 2>&1; then
                cygpath -u "${path}"
                return 0
            fi
            ;;
    esac

    printf '%s\n' "${path}"
}

is_allowed_runtime_path() {
    local normalized_path="$1"
    local allowed_prefix

    for allowed_prefix in \
        "${QT_ROOT}" \
        "${MPV_ROOT}" \
        "${BUILD_DIR}" \
        "${PACKAGE_DIR}"; do
        if [[ -n "${allowed_prefix}" && "${normalized_path}" == "${allowed_prefix}"* ]]; then
            return 0
        fi
    done

    return 1
}

copy_runtime_dependencies() {
    local binary_path="$1"
    local target_dir="$2"
    local line dll_path dll_name normalized_path target_path

    while IFS= read -r line; do
        dll_path="${line# }"
        dll_path="${dll_path% }"

        case "${dll_path}" in
            ""|not\ found|not\ found\ *)
                continue
                ;;
        esac

        normalized_path="$(normalize_path "${dll_path}")"
        if [[ ! -f "${normalized_path}" ]]; then
            continue
        fi

        if ! is_allowed_runtime_path "${normalized_path}"; then
            continue
        fi

        dll_name="$(basename "${normalized_path}")"
        case "${dll_name,,}" in
            kernel32.dll|user32.dll|gdi32.dll|advapi32.dll|ole32.dll|oleaut32.dll|shell32.dll|\
            setupapi.dll|winmm.dll|ws2_32.dll|imm32.dll|comdlg32.dll|crypt32.dll|rpcrt4.dll|\
            opengl32.dll|dwmapi.dll|uxtheme.dll|version.dll|bcrypt.dll|ntdll.dll|shlwapi.dll|\
            msvcrt.dll|sechost.dll|combase.dll)
                continue
                ;;
        esac

        target_path="${target_dir}/${dll_name}"
        if [[ ! -f "${target_path}" ]]; then
            cp -f "${normalized_path}" "${target_path}"
            RUNTIME_DEPENDENCY_COPY_COUNT=$((RUNTIME_DEPENDENCY_COPY_COUNT + 1))
        fi
    done < <(ntldd -R "${binary_path}" 2>/dev/null | awk '/=>/ { print $3 }')
}

copy_dependency_closure() {
    local target_dir="$1"
    local max_rounds="${2:-20}"
    local round copied_this_round binary_path

    for ((round = 1; round <= max_rounds; round++)); do
        RUNTIME_DEPENDENCY_COPY_COUNT=0

        while IFS= read -r binary_path; do
            copy_runtime_dependencies "${binary_path}" "${target_dir}"
        done < <(find "${target_dir}" -maxdepth 1 -type f \( -iname "*.exe" -o -iname "*.dll" \) | sort)

        copied_this_round="${RUNTIME_DEPENDENCY_COPY_COUNT}"
        if ((copied_this_round == 0)); then
            echo "Dependency closure completed in ${round} round(s)."
            return 0
        fi

        echo "Dependency closure round ${round}: copied ${copied_this_round} DLL(s)."
    done

    echo "Dependency closure did not converge after ${max_rounds} rounds." >&2
    return 1
}

copy_mpv_runtime_whitelist() {
    local target_dir="$1"
    local dll_name source_path

    for dll_name in "${MPV_RUNTIME_DLL_NAMES[@]}"; do
        source_path="$(find_first_existing \
            "${QT_ROOT}/bin/${dll_name}" \
            "${MPV_ROOT}/bin/${dll_name}" \
            "${MPV_ROOT}/${dll_name}")"
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

if ! command -v ntldd >/dev/null 2>&1; then
    echo "ntldd not found. Install mingw-w64-x86_64-ntldd in the MSYS2 MinGW environment." >&2
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

copy_if_exists "${QT_ROOT}/bin/libstdc++-6.dll" "${PACKAGE_DIR}"
copy_if_exists "${QT_ROOT}/bin/libgcc_s_seh-1.dll" "${PACKAGE_DIR}"
copy_if_exists "${QT_ROOT}/bin/libwinpthread-1.dll" "${PACKAGE_DIR}"
copy_if_exists "${QT_ROOT}/bin/opengl32sw.dll" "${PACKAGE_DIR}"
copy_mpv_runtime_whitelist "${PACKAGE_DIR}"

copy_dependency_closure "${PACKAGE_DIR}"

pushd "${DIST_ROOT}" >/dev/null
7z a -tzip "${ZIP_PATH}" "$(basename "${PACKAGE_DIR}")" >/dev/null
popd >/dev/null

echo "Windows package created."
echo "Package directory: ${PACKAGE_DIR}"
echo "Zip archive: ${ZIP_PATH}"
