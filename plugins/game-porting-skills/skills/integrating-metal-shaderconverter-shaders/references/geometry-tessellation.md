---
name: geometry-tessellation
description: Porting HLSL geometry and tessellation stages to Metal via Metal shader converter companion emulation. Companion use is strongly recommended — pipeline creation and draw dispatch encapsulate significant internal mesh shader logic.
---

# Geometry and tessellation pipeline emulation

Metal shader converter maps HLSL geometry and tessellation stages to Metal mesh shaders via companion-provided pipeline creation functions and draw helpers.

**Requires macOS 14 / iOS 17** (verified from companion header `API_AVAILABLE` annotation).

> **Without the companion**: requires manually assembling `MTLMeshRenderPipelineDescriptor` with function constants, linked functions, and fixed internal names, plus computing mesh threadgroup sizes per draw. Manual reimplementation is error-prone.

**Compilation prerequisite** — compile each stage and synthesize the vertex stage-in metallib per `compiling-with-metal-shaderconverter` § geometry/tessellation emulation. The pipeline descriptor below consumes those metallibs.

## Reflection data

Pipeline config values must come from Metal shader converter reflection — do not hardcode them.

| Config field | Stage | IRShaderReflection field | Offline JSON key |
|---|---|---|---|
| `gsVertexSizeInBytes` / `vsOutputSizeInBytes` | Vertex | `IRVSInfo_1_0.vertex_output_size_in_bytes` | `state.vertex_output_size_in_bytes` |
| `gsMaxInputPrimitivesPerMeshThreadgroup` (GS present) | GS | `IRGSInfo_1_0.max_input_primitives_per_mesh_threadgroup` | `state.max_input_primitives_per_mesh_threadgroup` |
| `gsMaxInputPrimitivesPerMeshThreadgroup` (passthrough, no GS) | DS | `IRDSInfo_1_0.max_input_prims_per_mesh_threadgroup` | `state.max_input_prims_per_mesh_threadgroup` |
| `gsInstanceCount` (GS present) | GS | `IRGSInfo_1_0.instance_count` | `state.instance_count` |
| `outputPrimitiveType` | HS | `IRHSInfo_1_0.tessellator_output_primitive` | `state.tessellator_output_primitive` |
| `hsMaxPatchesPerObjectThreadgroup` | HS | `IRHSInfo_1_0.max_patches_per_object_threadgroup` | `state.max_patches_per_object_threadgroup` |
| `hsInputControlPointCount` | HS | `IRHSInfo_1_0.input_control_point_count` | `state.input_control_point_count` |
| `hsMaxObjectThreadsPerThreadgroup` | HS | `IRHSInfo_1_0.max_object_threads_per_patch` | `state.max_object_threads_per_patch` |
| `hsMaxTessellationFactor` | HS | `IRHSInfo_1_0.max_tessellation_factor` | `state.max_tessellation_factor` |

Applies when converting in-process (`libmetalirconverter`). CLI path: deserialize the JSON file with `IRShaderReflectionCreateFromJSON(jsonString)` — the same copy functions apply.

```cpp
IRShaderReflection* refl = IRShaderReflectionCreate();
IRObjectGetReflection(vertexIR, IRShaderStageVertex, refl);
IRVersionedVSInfo vsInfo;
IRShaderReflectionCopyVertexInfo(refl, IRReflectionVersion_1_0, &vsInfo);
IRShaderReflectionDestroy(refl);
```

Other stages: `IRShaderReflectionCopyGeometryInfo`, `IRShaderReflectionCopyHullInfo`, `IRShaderReflectionCopyDomainInfo` — same pattern.

## Pipeline descriptor

`IRGeometryEmulationPipelineDescriptor` / `IRGeometryTessellationEmulationPipelineDescriptor` — full field listing in `metal_irconverter_runtime/metal_irconverter_runtime.h`. Each field draws from an artifact produced earlier:

| Source | Fields |
|---|---|
| Reflection-derived `pipelineConfig` | `pipelineConfig` |
| Stage-in synthesis | `stageInLibrary` |
| Per-stage metallib + HLSL entry | `vertexLibrary/vertexFunctionName`, `geometryLibrary/geometryFunctionName`, `hullLibrary`, `domainLibrary`, `fragmentLibrary/fragmentFunctionName` |
| Caller-supplied | `basePipelineDescriptor` (`MTLMeshRenderPipelineDescriptor` with attachments only) |

Construct via `IRRuntimeNewGeometryEmulationPipeline` or `IRRuntimeNewGeometryTessellationEmulationPipeline`. Validate stage interfaces first with `IRRuntimeValidateTessellationPipeline` (8 HS/DS/GS reflection values — see header).

**Passthrough GS** — when there is no geometry stage, set `geometryLibrary = NULL` and pick the name by topology, plus `gsInstanceCount = 1`:

| Topology | `geometryFunctionName` |
|---|---|
| Triangles | `kIRTrianglePassthroughGeometryShader` |
| Lines | `kIRLinePassthroughGeometryShader` |
| Points | `kIRPointPassthroughGeometryShader` |

For the corresponding `gsMaxInputPrimitivesPerMeshThreadgroup` passthrough sourcing, see the reflection table above.

## Draw-time bindings

Emulation pipelines are mesh pipelines — most TLAB-style buffers bind on **both object and mesh stages**.

| Binding | Bind point | Stages | When |
|---|---|---|---|
| TLAB | `kIRArgumentBufferBindPoint` | object + mesh | always |
| HS/DS TLAB | `kIRArgumentBufferHullDomainBindPoint` | object + mesh | tessellation only |
| Vertex buffer table (`IRRuntimeVertexBuffers[31]`: `addr`, `length`, `stride`) | `kIRVertexBufferBindPoint` (6) | object | always |
| Tessellator tables (size: `IRRuntimeTessellatorTablesSize`, fill: `IRRuntimeLoadTessellatorTables`) | `kIRRuntimeTessellatorTablesBindPoint` | object + mesh | tessellation only |
| Descriptor / sampler heap (or 8-byte zero buffer if unused) | `kIRDescriptorHeapBindPoint`, `kIRSamplerHeapBindPoint` | object + mesh | always — encoder rejected otherwise |

Make every vertex / index / descriptor / tessellator buffer resident with stage mask `MTLRenderStageObject | MTLRenderStageMesh`. The draw helpers do not call `useResource`.

### Dispatch

| Pipeline | Topology constants | Indexed | Non-indexed |
|---|---|---|---|
| Geometry | `IRRuntimePrimitiveType{Triangle,Line,Point}` | `IRRuntimeDrawIndexedPrimitivesGeometryEmulation` | `IRRuntimeDrawPrimitivesGeometryEmulation` |
| Tessellation | `IRRuntimePrimitiveType{3,4}ControlPointPatchlist` | `IRRuntimeDrawIndexedPatchesTessellationEmulation` | `IRRuntimeDrawPatchesTessellationEmulation` |

Helpers consume the same `pipelineConfig` used at pipeline creation.

## Metal 4 encoders

| Pipeline | Indexed | Non-indexed |
|---|---|---|
| Geometry | `IRRuntime4DrawIndexedPrimitivesGeometryEmulation` | `IRRuntime4DrawPrimitivesGeometryEmulation` |
| Tessellation | `IRRuntime4DrawIndexedPatchesTessellationEmulation` | `IRRuntime4DrawPatchesTessellationEmulation` |

Define `IR_RUNTIME_METAL4` before including the companion header to expose the typedefs (`mtl4renderencoder_t`, `mtl4argumenttable_t`) and the `IRRuntime4*` declarations.

### Scratch buffer

The Metal 3 helpers push `IRRuntimeDrawParams` and `IRRuntimeDrawInfo` inline via `setObjectBytes` / `setMeshBytes` — Metal 4 has no equivalent. The Metal 4 helpers take a caller-owned `MTLBuffer` and `memcpy` into it instead, then bind its GPU address through the supplied argument table.

- **Size** — at least `IRRuntime4DrawGetScratchBufferSize()` per concurrent draw region. The buffer needs to be CPU-writable (`MTLResourceStorageModeShared`) since the helper writes via `.contents`. Sub-allocate per draw via `scratchBufferOffset` using the same per-frame-in-flight pattern as the TLAB.
- **Argument table** — must be available on both object and mesh stages of the encoder.
- **Index buffer** — passed as a raw `uint64_t` GPU address (indexed variants only). Caller owns residency and lifetime.
- **Residency** — scratch buffer, vertex / index buffers, descriptor and sampler heaps, and tessellator tables must be resident on the encoder for the duration of the draw. The helpers do not manage residency.

## Anti-patterns

- **Pipeline creation fails.** Confirm shaders were compiled per `compiling-with-metal-shaderconverter` § geometry/tessellation emulation (flag + stage-in metallib).
- **Forgetting tessellator tables.** Tessellation silently produces no geometry.
- **TLAB only on the object stage.** Fragment / GS reads return zero.
- **No zero-bind on descriptor / sampler heap bind points.** Encoder rejected by validation.
- **Residency mask missing object or mesh.** GPU reads from unmapped memory silently.
- **Wrong passthrough GS constant for topology.** Triangle constant on a line pipeline produces wrong output, no error.
- **`gsMaxInputPrimitivesPerMeshThreadgroup` from the wrong stage.** Real GS → GS reflection. Passthrough → DS reflection.
- **Assuming `hullFunctionName` / `domainFunctionName` are used for lookup.** Companion retrieves HS/DS by fixed internal names.
- **Two `IRRuntime4Draw*` calls sharing a scratch-buffer region.** Both reads can be in-flight concurrently — bump-allocate per draw, and double-buffer the scratch buffer across frames-in-flight just like the TLAB.
