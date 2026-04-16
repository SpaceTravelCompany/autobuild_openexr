#!/bin/bash

readonly DEFAULT_LINUX_TARGETS=(
    "aarch64-linux-gnu"
    "riscv64-linux-gnu"
    "x86_64-linux-gnu"
    "i686-linux-gnu"
    "arm-linux-gnueabihf"
)

readonly DEFAULT_WINDOWS_TARGETS=(
    "native-windows"
)

readonly DEFAULT_WINDOWS_ARM_TARGETS=(
    "native-windows-arm64"
)

readonly DEFAULT_ANDROID_TARGETS=(
    "aarch64-linux-android35"
    "riscv64-linux-android35"
    "x86_64-linux-android35"
    "i686-linux-android35"
    "armv7a-linux-androideabi35"
)

readonly DEFAULT_ANDROID_ARCHES=(
    "aarch64-linux-android"
    "riscv64-linux-android"
    "x86_64-linux-android"
    "i686-linux-android"
    "arm-linux-androideabi"
)

NATIVE_ONLY=false
ANDROID_ONLY=false
WINDOWS_ONLY=false
WINDOWS_ARM_ONLY=false

LINUX_TARGETS=("${DEFAULT_LINUX_TARGETS[@]}")
WINDOWS_TARGETS=("${DEFAULT_WINDOWS_TARGETS[@]}")
WINDOWS_ARM_TARGETS=("${DEFAULT_WINDOWS_ARM_TARGETS[@]}")
ANDROIDS=("${DEFAULT_ANDROID_TARGETS[@]}")
ANDROID_ARCH=("${DEFAULT_ANDROID_ARCHES[@]}")

NDK_API_LEVEL="35"
NDK_TOOLCHAIN_DIR=""

detect_ndk_toolchain_dir() {
    local ndk_home="$1"
    local prebuilt_root="${ndk_home}/toolchains/llvm/prebuilt"

    if [[ -d "${prebuilt_root}/linux-x86_64" ]]; then
        echo "${prebuilt_root}/linux-x86_64"
    elif [[ -d "${prebuilt_root}/darwin-x86_64" ]]; then
        echo "${prebuilt_root}/darwin-x86_64"
    else
        find "${prebuilt_root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1
    fi
}

if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt" ]]; then
    NDK_TOOLCHAIN_DIR="$(detect_ndk_toolchain_dir "${ANDROID_NDK_HOME}")"
fi

android_cc() {
    echo "${NDK_TOOLCHAIN_DIR}/bin/$1-clang"
}

android_cxx() {
    echo "${NDK_TOOLCHAIN_DIR}/bin/$1-clang++"
}

get_build_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    else
        getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4
    fi
}

require_android_ndk() {
    if [[ -z "${ANDROID_NDK_HOME:-}" || -z "${NDK_TOOLCHAIN_DIR}" || ! -d "${NDK_TOOLCHAIN_DIR}" ]]; then
        echo "error: ANDROID_NDK_HOME must point to a valid Android NDK" >&2
        exit 1
    fi
}

require_file() {
    local path="$1"
    local message="$2"

    if [[ ! -f "${path}" ]]; then
        echo "error: ${message}" >&2
        exit 1
    fi
}

ensure_submodule_initialized() {
    local rel_path="$1"
    local abs_path="${SCRIPT_DIR}/${rel_path}"

    if git -C "${abs_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    git -C "${SCRIPT_DIR}" submodule update --init --recursive "${rel_path}"
}

append_common_cmake_args() {
    local target="$1"
    local android_arch="$2"
    local language="$3"
    local -n args_ref="$4"

    if [[ "${ANDROID_ONLY}" == true ]]; then
        require_android_ndk
        args_ref+=(-DCMAKE_C_COMPILER="$(android_cc "${target}")")
        if [[ "${language}" == "cxx" ]]; then
            args_ref+=(-DCMAKE_CXX_COMPILER="$(android_cxx "${target}")")
        fi
    elif [[ "${WINDOWS_ONLY}" == true || "${WINDOWS_ARM_ONLY}" == true ]]; then
        args_ref+=(-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded)
    else
        args_ref+=(-DCMAKE_C_COMPILER=clang)
        if [[ "${target}" != "native" ]]; then
            args_ref+=(-DCMAKE_C_COMPILER_TARGET="${target}")
        fi
        if [[ "${language}" == "cxx" ]]; then
            args_ref+=(-DCMAKE_CXX_COMPILER=clang++)
            if [[ "${target}" != "native" ]]; then
                args_ref+=(-DCMAKE_CXX_COMPILER_TARGET="${target}")
            fi
        fi
    fi
}

print_target_banner() {
    local target="$1"
    local android_arch="${2:-}"

    echo "=========================================="
    if [[ -n "${android_arch}" ]]; then
        echo "Target: ${target} (${android_arch})"
    else
        echo "Target: ${target}"
    fi
    echo "=========================================="
}

run_selected_targets() {
    local callback="$1"
    local target

    if [[ "${ANDROID_ONLY}" == true ]]; then
        local i
        for i in "${!ANDROIDS[@]}"; do
            target="${ANDROIDS[$i]}"
            print_target_banner "${target}" "${ANDROID_ARCH[$i]}"
            "${callback}" "${target}" "${ANDROID_ARCH[$i]}"
        done
    elif [[ "${WINDOWS_ARM_ONLY}" == true ]]; then
        for target in "${WINDOWS_ARM_TARGETS[@]}"; do
            print_target_banner "${target}"
            "${callback}" "${target}" ""
        done
    elif [[ "${WINDOWS_ONLY}" == true ]]; then
        for target in "${WINDOWS_TARGETS[@]}"; do
            print_target_banner "${target}"
            "${callback}" "${target}" ""
        done
    else
        for target in "${LINUX_TARGETS[@]}"; do
            print_target_banner "${target}"
            "${callback}" "${target}" ""
        done
    fi
}

cmake_cache_bool_equals() {
    local cache_path="$1"
    local var_name="$2"
    local expected="$3"

    [[ -f "${cache_path}" ]] && grep -Eq "^${var_name}:BOOL=${expected}$" "${cache_path}"
}

target_requires_runtime_zip_sse41() {
    local target="$1"

    if [[ "${target}" == "native" ]]; then
        local host_arch
        host_arch="$(uname -m)"
        [[ "${host_arch}" == "x86_64" || "${host_arch}" == "amd64" ]]
        return
    fi

    [[ "${target}" == "x86_64-linux-gnu" || "${target}" == "x86_64-linux-android35" ]]
}

parse_build_args() {
    local mode_count=0

    while (($# > 0)); do
        case "$1" in
            --native|-n)
                NATIVE_ONLY=true
                LINUX_TARGETS=("native")
                ((mode_count += 1))
                ;;
            --android|-a)
                ANDROID_ONLY=true
                ((mode_count += 1))
                ;;
            --windows|-w)
                WINDOWS_ONLY=true
                ((mode_count += 1))
                ;;
            --windows-arm|-wa)
                WINDOWS_ARM_ONLY=true
                ((mode_count += 1))
                ;;
            *)
                echo "error: unknown flag: $1" >&2
                exit 1
                ;;
        esac
        shift
    done

    if (( mode_count > 1 )); then
        echo "error: specify only one build mode at a time" >&2
        exit 1
    fi

    if [[ "${ANDROID_ONLY}" == true ]]; then
        require_android_ndk
    fi
}
