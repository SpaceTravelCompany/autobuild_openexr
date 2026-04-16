#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_vars.sh"
parse_build_args "$@"

OPENEXR_SOURCE_DIR="${SCRIPT_DIR}/libs/openexr"
OPENEXR_PATCH_BACKUP_DIR=""
OPENEXR_PATCH_ACTIVE=0

ensure_submodule_initialized "libs/openexr"

cleanup_openexr_patch() {
    if [[ "${OPENEXR_PATCH_ACTIVE}" != "1" ]] || [[ -z "${OPENEXR_PATCH_BACKUP_DIR}" ]]; then
        return
    fi

    cp "${OPENEXR_PATCH_BACKUP_DIR}/ImfHeader.cpp" \
       "${OPENEXR_SOURCE_DIR}/src/lib/OpenEXR/ImfHeader.cpp"
    cp "${OPENEXR_PATCH_BACKUP_DIR}/CMakeLists.txt" \
       "${OPENEXR_SOURCE_DIR}/src/lib/OpenEXR/CMakeLists.txt"
    rm -rf "${OPENEXR_PATCH_BACKUP_DIR}"
}

trap cleanup_openexr_patch EXIT

ensure_openexr_patch_applied() {
    local header_file="${OPENEXR_SOURCE_DIR}/src/lib/OpenEXR/ImfHeader.cpp"
    local cmake_file="${OPENEXR_SOURCE_DIR}/src/lib/OpenEXR/CMakeLists.txt"
    local needs_patch=0

    if ! grep -q 'OPENEXR_ENABLE_RUNTIME_ZIP_SSE41' "${cmake_file}"; then
        needs_patch=1
    fi

    if ! grep -q '#include "ImfZip.h"' "${header_file}"; then
        needs_patch=1
    fi

    if ! grep -q 'Zip::initializeFuncs ();' "${header_file}"; then
        needs_patch=1
    fi

    if [[ "${needs_patch}" != "1" ]]; then
        return
    fi

    OPENEXR_PATCH_BACKUP_DIR="$(mktemp -d)"
    cp "${header_file}" "${OPENEXR_PATCH_BACKUP_DIR}/ImfHeader.cpp"
    cp "${cmake_file}" "${OPENEXR_PATCH_BACKUP_DIR}/CMakeLists.txt"
    OPENEXR_PATCH_ACTIVE=1

    if ! grep -q 'OPENEXR_ENABLE_RUNTIME_ZIP_SSE41' "${cmake_file}"; then
        cat <<'EOF' >> "${cmake_file}"

if(OPENEXR_ENABLE_RUNTIME_ZIP_SSE41)
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    set_property(SOURCE ImfZip.cpp APPEND PROPERTY COMPILE_OPTIONS
      "$<$<CXX_COMPILER_ID:Clang>:-msse4.1>"
      "$<$<CXX_COMPILER_ID:Clang>:-fno-vectorize>"
      "$<$<CXX_COMPILER_ID:Clang>:-fno-slp-vectorize>"
      "$<$<CXX_COMPILER_ID:GNU>:-msse4.1>"
      "$<$<CXX_COMPILER_ID:GNU>:-fno-tree-vectorize>")
    message(STATUS "Enabling runtime ZIP SIMD for ImfZip.cpp")
  endif()
endif()
EOF
    fi

    if ! grep -q '#include "ImfZip.h"' "${header_file}"; then
        perl -0pi -e 's/#include "ImfNamespace.h"/#include "ImfZip.h"\n#include "ImfNamespace.h"/' "${header_file}"
    fi

    if ! grep -q 'Zip::initializeFuncs ();' "${header_file}"; then
        perl -0pi -e 's!(\s+// Register functions, for example specialized functions\r?\n\s+// for different CPU architectures\.\r?\n\s+//\r?\n)!$1        Zip::initializeFuncs ();\n!' "${header_file}"
    fi

    if ! grep -q 'OPENEXR_ENABLE_RUNTIME_ZIP_SSE41' "${cmake_file}" || \
       ! grep -q '#include "ImfZip.h"' "${header_file}" || \
       ! grep -q 'Zip::initializeFuncs ();' "${header_file}"; then
        echo "error: unable to apply the local OpenEXR runtime SIMD patch" >&2
        exit 1
    fi
}

build_target() {
    local target="$1"
    local android_arch="${2:-}"
    local build_dir="${SCRIPT_DIR}/build/openexr/${target}"
    local install_dir="${SCRIPT_DIR}/install/openexr/${target}"
    local imath_prefix="${SCRIPT_DIR}/install/Imath/${target}"
    local deflate_prefix="${SCRIPT_DIR}/install/libdeflate/${target}"
    local imath_config="${imath_prefix}/lib/cmake/Imath/ImathConfig.cmake"
    local deflate_config="${deflate_prefix}/lib/cmake/libdeflate/libdeflate-config.cmake"
    local configure_log="${build_dir}/configure.log"
    local runtime_zip_sse41="OFF"

    if target_requires_runtime_zip_sse41 "${target}"; then
        runtime_zip_sse41="ON"
    fi

    require_file "${imath_config}" "missing Imath install for ${target}; run build_Imath.sh first"
    require_file "${deflate_config}" "missing libdeflate install for ${target}; run build_libdeflate.sh first"

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
        -DOPENEXR_BUILD_TOOLS=OFF
        -DOPENEXR_BUILD_EXAMPLES=OFF
        -DOPENEXR_BUILD_PYTHON=OFF
        -DOPENEXR_BUILD_OSS_FUZZ=OFF
        -DOPENEXR_TEST_LIBRARIES=OFF
        -DOPENEXR_TEST_TOOLS=OFF
        -DOPENEXR_TEST_PYTHON=OFF
        -DOPENEXR_FORCE_INTERNAL_DEFLATE=OFF
        -DOPENEXR_FORCE_INTERNAL_IMATH=OFF
        -DOPENEXR_FORCE_INTERNAL_OPENJPH=ON
        -DOPENEXR_ENABLE_THREADING=OFF
        -DOPENEXR_ENABLE_RUNTIME_ZIP_SSE41="${runtime_zip_sse41}"
        -DCMAKE_PREFIX_PATH="${imath_prefix};${deflate_prefix}"
        -DImath_DIR="${imath_prefix}/lib/cmake/Imath"
        -Dlibdeflate_DIR="${deflate_prefix}/lib/cmake/libdeflate"
    )

    append_common_cmake_args "${target}" "${android_arch}" "cxx" cmake_args

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

ensure_openexr_patch_applied
run_selected_targets build_target
