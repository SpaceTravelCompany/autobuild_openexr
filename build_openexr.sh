#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

OPENEXR_SOURCE_DIR="${SCRIPT_DIR}/libs/openexr"

ensure_submodule_initialized "libs/openexr"

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/openexr/${target}"
    local install_dir="${SCRIPT_DIR}/install/openexr/${target}"
    local imath_prefix="${SCRIPT_DIR}/install/Imath/${target}"
    local deflate_prefix="${SCRIPT_DIR}/install/libdeflate/${target}"
    local openjph_prefix="${SCRIPT_DIR}/install/openjph/${target}"
    local imath_config="${imath_prefix}/lib/cmake/Imath/ImathConfig.cmake"
    local deflate_config="${deflate_prefix}/lib/cmake/libdeflate/libdeflate-config.cmake"
    local openjph_config="${openjph_prefix}/lib/cmake/openjph/openjph-config.cmake"
    local configure_log="${build_dir}/configure.log"
    local runtime_zip_sse41="OFF"
    local -a arch_feature_args=()

    if target_requires_runtime_zip_sse41 "${target}"; then
        runtime_zip_sse41="ON"
    fi

    require_file "${imath_config}" "missing Imath install for ${target}; run build_Imath.sh first"
    require_file "${deflate_config}" "missing libdeflate install for ${target}; run build_libdeflate.sh first"
    require_file "${openjph_config}" "missing openjph install for ${target}; run build_openjph.sh first"

    if [[ "${target}" == "native-windows" ]]; then
        arch_feature_args+=(-DCMAKE_C_FLAGS=/clang:-mssse3\ /clang:-msse4.1)
        arch_feature_args+=(-DCMAKE_CXX_FLAGS=/clang:-mssse3\ /clang:-msse4.1)
    fi

    echo "----------------------------------------"
    echo "Building OpenEXR for ${target}"
    echo "----------------------------------------"

    mkdir -p "${build_dir}" "${install_dir}"

    local -a cmake_args=(
        -S "${OPENEXR_SOURCE_DIR}"
        -B "${build_dir}"
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_CXX_STANDARD=17
        -DCMAKE_INSTALL_PREFIX="${install_dir}"
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_WEBSITE=OFF
        -DOPENEXR_IS_SUBPROJECT=ON
        -DOPENEXR_BUILD_TOOLS=OFF
        -DOPENEXR_BUILD_EXAMPLES=OFF
        -DOPENEXR_BUILD_PYTHON=OFF
        -DOPENEXR_BUILD_OSS_FUZZ=OFF
        -DOPENEXR_TEST_LIBRARIES=OFF
        -DOPENEXR_TEST_TOOLS=OFF
        -DOPENEXR_TEST_PYTHON=OFF
        -DOPENEXR_EXTRA_MATH_LIB=
        -DOPENEXR_FORCE_INTERNAL_DEFLATE=OFF
        -DOPENEXR_FORCE_INTERNAL_IMATH=OFF
        -DOPENEXR_FORCE_INTERNAL_OPENJPH=OFF
        -DOPENEXR_ENABLE_THREADING=OFF
        -DOPENEXR_ENABLE_RUNTIME_ZIP_SSE41="${runtime_zip_sse41}"
        -DCMAKE_PREFIX_PATH="${imath_prefix};${deflate_prefix};${openjph_prefix}"
        -DImath_DIR="${imath_prefix}/lib/cmake/Imath"
        -Dlibdeflate_DIR="${deflate_prefix}/lib/cmake/libdeflate"
        -Dopenjph_DIR="${openjph_prefix}/lib/cmake/openjph"
    )

    append_common_cmake_args "${target}" "${android_arch}" "cxx" cmake_args
    cmake_args+=("${arch_feature_args[@]}")

    cmake "${cmake_args[@]}" 2>&1 | tee "${configure_log}"

    if grep -Eq 'libdeflate (forced internal|was not found, using vendored code)' "${configure_log}"; then
        echo "error: OpenEXR fell back to the internal libdeflate for ${target}" >&2
        exit 1
    fi

    if ! grep -Eq 'Using externally provided libdeflate|Using libdeflate from ' "${configure_log}"; then
        echo "error: OpenEXR configure did not confirm the external libdeflate for ${target}" >&2
        exit 1
    fi

    cmake --build "${build_dir}" --config Release --parallel "$(get_build_jobs)"
    cmake --install "${build_dir}" --config Release

    echo "OpenEXR build complete (${target}): ${install_dir}"
    echo ""
}

run_selected_targets build_target
