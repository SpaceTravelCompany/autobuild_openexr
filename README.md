# autobuild_openexr

`autobuild_openexr` builds only the pieces needed for OpenEXR:

- `openexr` `v3.4.9`
- `Imath` `v3.2.2`
- `libdeflate` `v1.25`

Each dependency lives in `libs/` as a git submodule. The build scripts auto-initialize missing submodules, but a manual checkout works too:

```bash
git submodule update --init --recursive
```

## Build scripts

The top-level entry point is:

```bash
./build_all.sh
```

Build order:

1. `libdeflate`
2. `Imath`
3. `openexr`

Individual steps are also available:

```bash
./build_libdeflate.sh
./build_Imath.sh
./build_openexr.sh
```

## Build modes

All scripts support the same mode flags:

- default: Linux cross-target build
- `--native` or `-n`: native Linux build only
- `--android` or `-a`: Android build
- `--windows` or `-w`: native Windows x64 build
- `--windows-arm` or `-wa`: native Windows ARM64 build

Linux targets:

- `aarch64-linux-gnu`
- `riscv64-linux-gnu`
- `x86_64-linux-gnu`
- `i686-linux-gnu`
- `arm-linux-gnueabihf`

Android targets:

- `aarch64-linux-android35`
- `riscv64-linux-android35`
- `x86_64-linux-android35`
- `i686-linux-android35`
- `armv7a-linux-androideabi35`

## Install layout

Artifacts are installed under `install/<name>/<target>/`:

- `install/libdeflate/<target>`
- `install/Imath/<target>`
- `install/openexr/<target>`

## Policy notes

- `build_openexr.sh` forces `OPENEXR_FORCE_INTERNAL_DEFLATE=OFF`.
- If OpenEXR resolves to the vendored deflate anyway, the build fails immediately.
- OpenEXR keeps its vendored `OpenJPH`.
- `build_openexr.sh` applies a small local runtime SIMD patch to the `openexr` submodule so the ZIP dispatch is initialized and the x86_64 Linux/Android ZIP fast path is compiled in without raising the global library baseline.
