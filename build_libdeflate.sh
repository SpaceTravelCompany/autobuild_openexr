#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

LIBDEFLATE_SOURCE_DIR="${SCRIPT_DIR}/libs/libdeflate"
ensure_submodule_initialized "libs/libdeflate"

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/libdeflate/${target}"
    local install_dir="${SCRIPT_DIR}/install/libdeflate/${target}"

    echo "----------------------------------------"
    echo "Building libdeflate for ${target}"
    echo "----------------------------------------"

    mkdir -p "${build_dir}" "${install_dir}"

    local -a cmake_args=(
        -S "${LIBDEFLATE_SOURCE_DIR}"
        -B "${build_dir}"
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="${install_dir}"
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DLIBDEFLATE_BUILD_STATIC_LIB=ON
        -DLIBDEFLATE_BUILD_SHARED_LIB=OFF
        -DLIBDEFLATE_BUILD_GZIP=OFF
        -DLIBDEFLATE_BUILD_TESTS=OFF
        -DLIBDEFLATE_USE_SHARED_LIB=OFF
    )

    append_common_cmake_args "${target}" "${android_arch}" "c" cmake_args

    cmake "${cmake_args[@]}"
    cmake --build "${build_dir}" --config Release --parallel "$(get_build_jobs)"
    cmake --install "${build_dir}" --config Release --prefix "${install_dir}"

    echo "libdeflate build complete (${target}): ${install_dir}"
    echo ""
}

run_selected_targets build_target
