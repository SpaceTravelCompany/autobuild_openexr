#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

IMATH_SOURCE_DIR="${SCRIPT_DIR}/libs/Imath"
IMATH_PATCH_BACKUP_DIR=""
IMATH_PATCH_ACTIVE=0

ensure_submodule_initialized "libs/Imath"

cleanup_imath_patch() {
    if [[ "${IMATH_PATCH_ACTIVE}" != "1" ]] || [[ -z "${IMATH_PATCH_BACKUP_DIR}" ]]; then
        return
    fi

    cp "${IMATH_PATCH_BACKUP_DIR}/CMakeLists.txt" \
       "${IMATH_SOURCE_DIR}/src/Imath/CMakeLists.txt"
    rm -rf "${IMATH_PATCH_BACKUP_DIR}"
}

trap cleanup_imath_patch EXIT

ensure_imath_patch_applied() {
    local cmake_file="${IMATH_SOURCE_DIR}/src/Imath/CMakeLists.txt"

    if grep -q 'WIN32 AND NOT MINGW' "${cmake_file}"; then
        return
    fi

    IMATH_PATCH_BACKUP_DIR="$(mktemp -d)"
    cp "${cmake_file}" "${IMATH_PATCH_BACKUP_DIR}/CMakeLists.txt"
    IMATH_PATCH_ACTIVE=1

    python - "${cmake_file}" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()
old = """include(CheckLibraryExists)
check_library_exists(m sin "" HAVE_LIB_M)
if (HAVE_LIB_M)
    target_link_libraries(${IMATH_LIBRARY} PUBLIC m)
endif()"""
new = """include(CheckLibraryExists)
if (WIN32 AND NOT MINGW)
    set(HAVE_LIB_M OFF)
else()
    check_library_exists(m sin "" HAVE_LIB_M)
endif()
if (HAVE_LIB_M)
    target_link_libraries(${IMATH_LIBRARY} PUBLIC m)
endif()"""

if old not in text:
    raise SystemExit("failed to locate Imath libm block")

p.write_text(text.replace(old, new))
PY

    if ! grep -q 'WIN32 AND NOT MINGW' "${cmake_file}"; then
        echo "error: unable to apply the local Imath Windows libm patch" >&2
        exit 1
    fi
}

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/Imath/${target}"
    local install_dir="${SCRIPT_DIR}/install/Imath/${target}"

    echo "----------------------------------------"
    echo "Building Imath for ${target}"
    echo "----------------------------------------"

    ensure_imath_patch_applied
    mkdir -p "${build_dir}" "${install_dir}"

    local -a cmake_args=(
        -S "${IMATH_SOURCE_DIR}"
        -B "${build_dir}"
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_INSTALL_PREFIX="${install_dir}"
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_WEBSITE=OFF
        -DIMATH_INSTALL=ON
        -DIMATH_INSTALL_PKG_CONFIG=ON
        -DPYTHON=OFF
        -DPYBIND11=OFF
    )

    append_common_cmake_args "${target}" "${android_arch}" "cxx" cmake_args

    cmake "${cmake_args[@]}"
    cmake --build "${build_dir}" --config Release --parallel "$(get_build_jobs)"
    cmake --install "${build_dir}" --config Release

    echo "Imath build complete (${target}): ${install_dir}"
    echo ""
}

run_selected_targets build_target
