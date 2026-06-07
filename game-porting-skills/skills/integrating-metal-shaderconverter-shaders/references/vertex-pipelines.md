---
name: vertex-pipelines
description: Setting up vertex pipelines for Metal shader converter shaders — Metal vertex fetch and separate stage-in function. Companion use is optional; binding point constants are the only companion dependency.
---

# Vertex pipeline setup

## Companion constants used in this section

| Constant | Value | Purpose |
|---|---|---|
| `kIRVertexBufferBindPoint` | 6 | First vertex buffer bind index |
| `kIRStageInAttributeStartIndex` | 11 | First vertex attribute index |

## Metal vertex fetch (default)

**Attribute indices** start at `kIRStageInAttributeStartIndex` (11). **Vertex buffer indices** start at `kIRVertexBufferBindPoint` (6).

```objc
// ObjC — configure Metal vertex fetch for two float4 attributes
MTLVertexDescriptor* vd = [[MTLVertexDescriptor alloc] init];

vd.attributes[kIRStageInAttributeStartIndex].format = MTLVertexFormatFloat4;
vd.attributes[kIRStageInAttributeStartIndex].offset = 0;
vd.attributes[kIRStageInAttributeStartIndex].bufferIndex = kIRVertexBufferBindPoint;

// Layout — one interleaved buffer at kIRVertexBufferBindPoint
vd.layouts[kIRVertexBufferBindPoint].stride = 32;
vd.layouts[kIRVertexBufferBindPoint].stepFunction = MTLVertexStepFunctionPerVertex;

pipelineDescriptor.vertexDescriptor = vd;
```

### Binding vertex buffers at draw time

```objc
[enc setVertexBuffer:vertexBuffer offset:0 atIndex:kIRVertexBufferBindPoint];
```

## Separate stage-in function

For vertex shaders that require flexible datatype conversions or dynamic attribute offsets, Metal shader converter can synthesize a separate stage-in function — a Metal visible function that the converted vertex shader calls at runtime.

**When to use**: if your HLSL vertex input requires format conversions that Metal vertex fetch cannot express in a `MTLVertexDescriptor`.

### Compilation

**CLI**: `--vertex-stage-in` — Metal shader converter produces two metallibs: one for the vertex function, one for the stage-in function.

**Library API**: call `IRCompilerSetStageInGenerationMode(compiler, IRStageInCodeGenerationModeUseSeparateStageInFunction)` before compiling, then call `IRMetalLibSynthesizeStageInFunction` to produce the stage-in metallib.

### Pipeline state assembly

The stage-in function is a Metal visible function — link it to the pipeline via `MTLLinkedFunctions`:

```objc
// ObjC — link stage-in function to a vertex pipeline
id<MTLLibrary> stageInLib = [device newLibraryWithData:stageInMetallib error:&error];
id<MTLFunction> stageInFn = [stageInLib newFunctionWithName:stageInLib.functionNames.firstObject];

MTLLinkedFunctions* linked = [[MTLLinkedFunctions alloc] init];
linked.functions = @[stageInFn];

MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
// ... set vertex/fragment functions, render attachments ...
desc.vertexLinkedFunctions = linked;

id<MTLRenderPipelineState> pso = [device newRenderPipelineStateWithDescriptor:desc error:&error];
```

The vertex shader calls the stage-in function automatically — no additional draw-time binding beyond the standard TLAB.

## Anti-patterns

- **Attribute indices starting at 0 instead of `kIRStageInAttributeStartIndex`.** Metal shader converter reserves the first 11 attribute indices. Attributes bound at indices 0–10 are silently ignored or produce wrong data.
- **Vertex buffer indices starting at 0 instead of `kIRVertexBufferBindPoint`.** Vertex buffers must start at index 6. Binding at lower indices collides with TLAB and heap bind points.
