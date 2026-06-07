---
name: compiling-with-metal-shaderconverter
description: ALWAYS use when compiling DXIL/HLSL to metallib with Metal shader converter (commonly referred to as MSC) via the metal-shaderconverter CLI or libmetalirconverter (IRCompiler, IRObject, IRShaderReflection) at runtime. Covers offline/runtime DXIL compilation, root signatures, reflection output, ray tracing shaders, geometry/tessellation emulation compilation, framebuffer fetch in HLSL, programmable blending in HLSL, Metal_HLSL.inc, and compatibility flags. Do NOT trigger for binding compiled shaders to encoders — use integrating-metal-shaderconverter-shaders for that.
---

# Metal shader converter — CLI & Library

## Overview

Two modes: **CLI** (`metal-shaderconverter`) for offline/build-time compilation, **library** (`libmetalirconverter` C API) for runtime compilation. Both produce metallibs consumed by the Metal framework. Use the CLI for build pipelines and asset cooking; use the library when DXIL must be compiled at runtime (e.g., an engine that ships DXIL and compiles to metallib on first load).

For binding compiled shaders to Metal encoders at draw/dispatch time, see `integrating-metal-shaderconverter-shaders`.

## Decision Guide

| Scenario | Use |
|---|---|
| Build pipeline, asset cooking, offline shader cache | CLI |
| Compile DXIL to metallib at runtime | Library |
| Dynamic root signatures not known until runtime | Library |
| Generate reflection JSON for binding code | CLI (`--output-reflection-file`) |
| Runtime reflection after compilation | Library (`IRShaderReflection`) |

---

## CLI

### Step 1: Check availability

```sh
metal-shaderconverter --version
```

If not found, download from https://developer.apple.com/download/all/?q=Metal%20Shader%20Converter

### Step 2: Read the man page

```sh
man metal-shaderconverter | col -b
```

Authoritative flag reference. If unavailable, use `metal-shaderconverter --help`.

### Step 3: Key invocations

metal-shaderconverter only accepts DXIL — compile HLSL with DXC first:

```sh
dxc -T vs_6_0 -E main shader.hlsl -Fo shader.dxil
metal-shaderconverter shader.dxil -o shader.metallib
```

Generate reflection alongside the metallib when binding code is needed:

```sh
metal-shaderconverter shader.dxil -o shader.metallib --output-reflection-file shader.json
```

Read `references/cli.md` for multi-shader workflows and debug/dsym handling.

---

## Library (libmetalirconverter)

### Step 1: Read the API reference

```sh
man libmetalirconverter | col -b
```

If the man page is unavailable, read the header at `metal_irconverter/metal_irconverter.h` (macOS default: `/usr/local/include/metal_irconverter/`).

### Step 2: Link

Link against `metalirconverter` (`-lmetalirconverter`). The library is at `/usr/local/lib/libmetalirconverter.dylib` on macOS by default.

```c
#include <metal_irconverter/metal_irconverter.h>
```

### Step 3: Key patterns

The notes below cover what's easy to miss when reading the API reference. See `references/library.md` for a complete compile-loop example.

**Lifetime.** `rootSig` must outlive the `IRCompiler` that references it — destroy the compiler first. Don't share an `IRCompiler` across threads concurrently; compilation is expensive, prefer worker threads or pre-compile offline.

**Bytecode extraction.** On Apple, `IRMetalLibGetBytecodeData(lib)` returns a zero-copy `dispatch_data_t` that `[MTLDevice newLibraryWithData:error:]` consumes directly. Non-Apple: use `IRMetalLibGetBytecodeSize` + `IRMetalLibGetBytecode` to copy into a caller-owned buffer.

**Reflection.** Each `IRShaderReflectionCopy*Info` allocates; always pair with the matching `Release*Info`. Same rule for `IRShaderReflectionCopyFunctionConstants`.

**Root signature struct initialization.** The header documents the struct fields but not how to populate them — see `references/library.md`.

Read `references/library.md` for the complete compile loop, root signature struct initialization, per-compilation-reset options, and ray tracing compilation.

---

## HLSL Metal-language features

Metal shader converter 3.0+ exposes Metal features to HLSL via `Metal_HLSL.inc`: **function constants** for shader specialization, and **framebuffer fetch** for programmable blending.

See `references/hlsl-metal-extensions.md` for declaration syntax, compile flags (CLI and library), and the root signature caveat.

---

## Anti-patterns

1. **Freeing DXIL before compile returns with `IRBytecodeOwnershipNone`** — the IRObject holds a raw pointer; keep the buffer alive until after compile returns.
2. **Calling `CopyXxxInfo` without the matching `ReleaseXxxInfo`** — each Copy allocates; the Release frees it.
3. **Setting root signature after calling compile** — `IRCompilerSetGlobalRootSignature` must be called before `IRCompilerAllocCompileAndLink`.
4. **Caching reflection JSON across library versions** — the JSON format may change between versions; deserializing data from a different version causes undefined behavior.
