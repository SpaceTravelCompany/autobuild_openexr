#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ARGS=("$@")

echo "=========================================="
echo "OpenEXR dependency build started"
echo "=========================================="
echo ""

"${SCRIPT_DIR}/build_libdeflate.sh" "${BUILD_ARGS[@]}"
"${SCRIPT_DIR}/build_Imath.sh" "${BUILD_ARGS[@]}"
"${SCRIPT_DIR}/build_openexr.sh" "${BUILD_ARGS[@]}"

echo ""
echo "=========================================="
echo "OpenEXR dependency build finished"
echo "=========================================="
