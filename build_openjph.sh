#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

OPENJPH_SOURCE_DIR="${SCRIPT_DIR}/libs/openjph"
ensure_submodule_initialized "libs/openjph"

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/openjph/${target}"
    local install_dir="${SCRIPT_DIR}/install/openjph/${target}"
    local disable_ssse3="OFF"

    if [[ "${target}" == "native-windows" || "${target}" == "native-windows-arm64" ]]; then
        disable_ssse3="ON"
    fi

    echo "----------------------------------------"
    echo "Building OpenJPH for ${target}"
    echo "----------------------------------------"

    rm -rf "${build_dir}"
    mkdir -p "${build_dir}" "${install_dir}"

    local -a cmake_args=(
        -S "${OPENJPH_SOURCE_DIR}"
        -B "${build_dir}"
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_INSTALL_PREFIX="${install_dir}"
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DBUILD_SHARED_LIBS=OFF
        -DOJPH_ENABLE_TIFF_SUPPORT=OFF
        -DOJPH_BUILD_EXECUTABLES=OFF
        -DOJPH_BUILD_STREAM_EXPAND=OFF
        -DOJPH_BUILD_TESTS=OFF
        -DOJPH_BUILD_FUZZER=OFF
        -DOJPH_DISABLE_SSSE3="${disable_ssse3}"
    )

    append_common_cmake_args "${target}" "${android_arch}" "cxx" cmake_args

    cmake "${cmake_args[@]}"
    cmake --build "${build_dir}" --config Release --parallel "$(get_build_jobs)"
    cmake --install "${build_dir}" --config Release --prefix "${install_dir}"

    echo "OpenJPH build complete (${target}): ${install_dir}"
    echo ""
}

run_selected_targets build_target
