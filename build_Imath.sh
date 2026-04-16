#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

IMATH_SOURCE_DIR="${SCRIPT_DIR}/libs/Imath"
ensure_submodule_initialized "libs/Imath"

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/Imath/${target}"
    local install_dir="${SCRIPT_DIR}/install/Imath/${target}"

    echo "----------------------------------------"
    echo "Building Imath for ${target}"
    echo "----------------------------------------"

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
