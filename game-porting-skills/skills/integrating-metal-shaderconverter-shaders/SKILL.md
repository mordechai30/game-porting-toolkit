---
name: integrating-metal-shaderconverter-shaders
description: ALWAYS use when integrating Metal shader converter (commonly referred to as MSC) shaders at runtime — binding model, top-level argument buffer (TLAB), root signature resource locations, descriptor/sampler heaps, static samplers, bindless resources, vertex fetch, separate stage-in, geometry/tessellation emulation, compute dispatch, unbounded arrays, and append/consume buffers. Do NOT trigger for compiling DXIL/HLSL to metallib — use compiling-with-metal-shaderconverter for that.
---

# Metal shader converter — Integration Guide

## Overview

Runtime integration: Metal requirements, binding model, pipeline setup, and common failure modes. Assumes metallib files are compiled.

## References

Read the reference file for your use case before writing integration code:

| Use case | Reference file |
|---|---|
| TLAB layout, root signatures, static samplers, descriptor encoding, compute dispatch, unbounded arrays, append/consume | `references/binding-model.md` |
| Metal vertex fetch, separate stage-in function | `references/vertex-pipelines.md` |
| Geometry and tessellation pipeline emulation | `references/geometry-tessellation.md` |

**Source materials** — consult to verify API details or look up full implementations:

- `metal_irconverter/metal_irconverter.h` — Metal shader converter API: root signature, reflection, descriptor format
- `metal_irconverter_runtime/metal_irconverter_runtime.h` — companion header (**header-only**: read implementations directly when a helper is not used or to understand the manual path)
- `/opt/metal-shaderconverter/docs/UserManual.md` — canonical reference; read only if the user's question isn't answered by the reference files above

## Metal constraints

### Sampler state

All samplers must be created with `supportArgumentBuffers = YES`. Without it, `gpuResourceID` returns an invalid handle and the GPU reads a zeroed descriptor.

### Texture type mapping

Metal shader converter maps HLSL texture types to Metal as follows. Supply Metal textures of the correct type — mismatches produce sampling errors or black output with no validation warning.

| HLSL | Metal |
|---|---|
| 1D `*` | 2D |
| 1D Array | 2D Array |
| 2D `*` | 2D |
| 2D Array | 2D Array |
| Cube `*` | Cube |
| Cube Array | Cube Array |
| 1D Multisampled `*` | 2D Multisampled |
| 1D Multisampled Array | 2D Multisampled Array |
| 2D Multisampled `*` | 2D Multisampled |
| 2D Multisampled Array | 2D Multisampled Array |
| 3D | No change |

`* Metal shader converter 2.x mapped these to the Array variant instead. See version differences below.`

Metal shader converter 3.0 changed the Metal texture type for several HLSL types (marked `*` above) from the Array variant to the non-array variant. If you are using shaders compiled with Metal shader converter 2.x, enable the compatibility flag to preserve the old behavior:

- **CLI**: `--forceTextureArray`
- **Library**: `IRCompilerSetCompatibilityFlags(compiler, IRCompatibilityFlagForceTextureArray)`

Metal shader converter 3.0 also removed the requirement to use companion draw helpers (`IRRuntimeDrawIndexedPrimitives` etc.) for standard vertex/fragment draws. Geometry and tessellation emulation variants still require the companion.

### Depth and stencil texture reads

D3D12 allows reading depth as `Texture2D<float>` via an SRV. Metal depth and stencil formats are in a separate format compatibility group from color formats — a Metal shader converter shader expecting `texture2d<float>` cannot sample a depth texture directly.

Common symptom: post-processing passes (SSAO, DoF, screen-space reflections) that sample the depth buffer produce all-zeros or garbage with no validation error.

Resolution: create an explicit `MTLPixelFormatR32Float` copy of the depth buffer, or use `MTLTextureUsagePixelFormatView` to reinterpret the depth data where the format permits.

## Reflection

Always verify host-side binding code against Metal shader converter reflection — do not hardcode offsets or threadgroup sizes.

- **Offline** (at asset build time): `--output-reflection-file <path>` writes a JSON file per shader stage. Parse and store alongside the metallib.
- **Runtime** (via `libmetalirconverter`): `IRObjectGetReflection(obj, stage, reflection)` followed by stage-specific copy functions (`IRShaderReflectionCopyComputeInfo`, `IRShaderReflectionCopyGeometryInfo`, etc.).

Metal shader converter reflection covers top-level TLAB entries only. To determine individual resource offsets within descriptor tables, you need to use DXC/DXIL reflection.

## Retrieving functions from synthesized metallibs

When Metal shader converter synthesizes a helper metallib — stage-in (`IRMetalLibSynthesizeStageInFunction`) or the libraries consumed by geometry/tessellation emulation — the result contains a single Metal function whose name is determined by Metal shader converter, not by your HLSL entry point. Hardcoding the name is fragile across Metal shader converter versions.

Query `MTLLibrary.functionNames` (count is expected to be 1) and take the first entry:

```objc
id<MTLFunction> fn = [lib newFunctionWithName:lib.functionNames.firstObject];
```

(`functionNames()[0]` in metal-cpp.)

## Companion header

The companion header is optional for standard binding work. It provides:

- **Binding point constants** (`kIR*BindPoint`) — always useful; reference files list which constants each use case depends on
- **Descriptor setter helpers** (`IRDescriptorTableSet*`) — save encoding work; header-only implementations document the encoding logic for the manual path
- **Geometry/tessellation emulation** — required; no practical substitute
- **Append/consume buffer helpers** — convenience; header-only implementations also document the manual path

**Metal 3 vs Metal 4:** The companion is encoder-agnostic except for the geometry/tessellation emulation draw helpers, which have separate Metal 3 and Metal 4 variants.

Include setup:

```cpp
#include <Metal/Metal.hpp>          // or Metal/Metal.h
#define IR_RUNTIME_METALCPP         // define before every inclusion (selects metal-cpp types)
#define IR_RUNTIME_METAL4           // optional — exposes IRRuntime4* emulation draw helpers; same "before every inclusion" rule
#define IR_PRIVATE_IMPLEMENTATION   // define in exactly one .cpp/.mm file
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>
```

`IR_RUNTIME_METALCPP` must be defined before every inclusion — it selects the Metal types used throughout. Mismatching types between translation units causes silent ABI breakage.

## HLSL Metal-language features

### Function constants

For shaders that declare function constants in HLSL via `MTL_FUNCTION_CONSTANT()`, bind values at function retrieval time:

```objc
MTLFunctionConstantValues *fcv = [[MTLFunctionConstantValues alloc] init];
simd_float4 color = simd_make_float4(1.0, 1.0, 0.0, 1.0);
[fcv setConstantValue:&color type:MTLDataTypeUInt4 atIndex:0];
```

**Always use `MTLDataTypeUInt4`** regardless of the declared HLSL type — the runtime treats each function constant as an opaque 16-byte value. Passing the natural Metal type (e.g. `MTLDataTypeFloat4`) silently binds the wrong data with no validation error.

The companion header provides a convenience helper that handles the packing:

```c
IRRuntimeFunctionConstantValue colorFC = { .f0 = color.x, .f1 = color.y, .f2 = color.z, .f3 = color.w };
IRRuntimeSetFunctionConstantValue(fcv, 0, &colorFC);
```

Use the resulting `MTLFunctionConstantValues` when retrieving the function from the metallib (`newFunctionWithName:constantValues:error:`), then pass that function into your pipeline descriptor.

For HLSL declaration syntax and compile-time setup, see `compiling-with-metal-shaderconverter` and its `references/hlsl-metal-extensions.md`.

### Framebuffer fetch

No host-side binding code — the feature is enabled at compile time and the shader reads the current attachment value via `MTL_LOAD_FRAMEBUFFER`. Ensure the render pass attachment uses `MTLLoadActionLoad` for any target the shader reads; with `MTLLoadActionDontCare` or `MTLLoadActionClear` the value the shader sees is undefined or the cleared color.

## Anti-patterns

1. **Hardcoding binding point values.** Use named constants (`kIRDescriptorHeapBindPoint`, `kIRArgumentBufferBindPoint`, etc.). Values may change between Metal shader converter versions.
2. **Not making resources resident for indirect access.** Any resource accessed through a descriptor table or bindless heap must be made resident via `useResource` or `useHeap` before the draw or dispatch. The GPU silently reads from unmapped memory without this.

## Debugging

Metal shader converter convention violations rarely produce errors at the API level. Wrong TLAB layout, mismatched param counts, bad descriptor entries, and non-resident resources all produce silent GPU-side corruption.

Enable Metal shader validation for additional coverage: `MTL_SHADER_VALIDATION=1`. Do not rely on it catching everything — it does not cover all binding model violations.

**Symptom → where to look:**
- Black output or wrong colors → descriptor table GPU addresses (absolute vs relative), sampler lifetime, descriptor type mismatch (buffer vs texture setter)
- Wrong constant values → verify root constants are written inline, not as a pointer; verify host param count matches HLSL root signature
- All zeros from a buffer resource → confirm `IRDescriptorTableSetBuffer` was used, not `IRDescriptorTableSetTexture`
- Geometry/tessellation corruption → vertex buffers bound on object stage, all buffers resident, pipeline config values from reflection
