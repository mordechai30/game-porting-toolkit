# libmetalirconverter — Supplemental Reference

## Complete compile loop

```c
// 1. Wrap DXIL
IRObject* dxilObj = IRObjectCreateFromDXIL(dxilBytes, dxilSize, IRBytecodeOwnershipNone);
// IRBytecodeOwnershipNone: caller keeps dxilBytes alive through step 3.
// Use IRBytecodeOwnershipCopy when lifetime is inconvenient.

// 2. Create compiler and bind root signature
IRCompiler* compiler = IRCompilerCreate();
IRCompilerSetGlobalRootSignature(compiler, rootSig);  // NULL = linear layout

// 3. Compile DXIL → Metal IR
IRError* err = NULL;
IRObject* metalIR = IRCompilerAllocCompileAndLink(compiler, NULL, dxilObj, &err);
IRObjectDestroy(dxilObj);
if (!metalIR) {
    uint32_t code = IRErrorGetCode(err);
    IRErrorDestroy(err);
    // handle ...
}

// 4. Extract metallib (Apple: zero-copy via dispatch_data_t)
IRMetalLibBinary* lib = IRMetalLibBinaryCreate();
IRObjectGetMetalLibBinary(metalIR, stage, lib);  // stage matches what was compiled
dispatch_data_t data = IRMetalLibGetBytecodeData(lib);
id<MTLLibrary> mtlLib = [device newLibraryWithData:data error:&nsError];

// 5. Cleanup — compiler before rootSig (rootSig must outlive compiler)
IRMetalLibBinaryDestroy(lib);
IRObjectDestroy(metalIR);
IRCompilerDestroy(compiler);
IRRootSignatureDestroy(rootSig);
```

Non-Apple: use `IRMetalLibGetBytecodeSize` + `IRMetalLibGetBytecode` to copy bytes into a caller-owned buffer instead of step 4.

## Reflection

```c
IRShaderReflection* refl = IRShaderReflectionCreate();
// Compute threadgroup size
if (IRObjectGetReflection(metalIR, IRShaderStageCompute, refl)) {
    IRVersionedCSInfo csInfo = { .version = IRReflectionVersion_1_0 };
    if (IRShaderReflectionCopyComputeInfo(refl, IRReflectionVersion_1_0, &csInfo)) {
        uint32_t* tg = csInfo.info_1_0.tg_size;  // [x, y, z]
        IRShaderReflectionReleaseComputeInfo(&csInfo);
    }
}
IRShaderReflectionDestroy(refl);
```

Resource locations in the top-level argument buffer:

```c
size_t count = IRShaderReflectionGetResourceCount(refl);
IRResourceLocation* locs = malloc(count * sizeof(IRResourceLocation));
IRShaderReflectionGetResourceLocations(refl, locs);
// locs[i].topLevelOffset, .resourceType, .resourceName (points into refl — do not outlive it)
free(locs);
```

---

## Root signature struct initialization

The header documents the struct fields but not how to populate them:

```c
IRDescriptorRange ranges[] = {{
    .RangeType = IRDescriptorRangeTypeSRV, .NumDescriptors = 4,
    .BaseShaderRegister = 0, .RegisterSpace = 0,
    .OffsetInDescriptorsFromTableStart = 0
}};
IRRootParameter params[] = {{
    .ParameterType = IRRootParameterTypeDescriptorTable,
    .DescriptorTable = { .NumDescriptorRanges = 1, .pDescriptorRanges = ranges },
    .ShaderVisibility = IRShaderVisibilityAll
}};
IRStaticSamplerDescriptor staticSamplers[] = {{
    .Filter           = IRFilterMinMagMipLinear,
    .AddressU         = IRTextureAddressModeWrap,
    .AddressV         = IRTextureAddressModeWrap,
    .AddressW         = IRTextureAddressModeWrap,
    .MipLODBias       = 0.0f,
    .MaxAnisotropy    = 0,
    .ComparisonFunc   = IRComparisonFunctionNever,
    .BorderColor      = IRStaticBorderColorTransparentBlack,
    .MinLOD           = 0.0f,
    .MaxLOD           = FLT_MAX,
    .ShaderRegister   = 0,
    .RegisterSpace    = 0,
    .ShaderVisibility = IRShaderVisibilityAll
}};
IRVersionedRootSignatureDescriptor vDesc = {
    .version = IRRootSignatureVersion_1_0,
    .desc_1_0 = {
        .NumParameters     = 1, .pParameters     = params,
        .NumStaticSamplers = 1, .pStaticSamplers = staticSamplers,
        .Flags             = IRRootSignatureFlagNone
    }
};
IRRootSignature* rootSig = IRRootSignatureCreateFromDescriptor(&vDesc, &err);
```

---

## Per-compilation-reset options

These settings reset after each `IRCompilerAllocCompileAndLink` call. Set them immediately before each compilation that needs them.

```c
// Dual-source blending
IRCompilerSetDualSourceBlendingConfiguration(compiler,
    IRDualSourceBlendingConfigurationDecideAtRuntime);
// decideAtRuntime injects a 'dualSourceBlendingEnabled' uint8_t function constant —
// supply it at PSO creation time via MTLFunctionConstantValues.

// Depth feedback
IRCompilerSetDepthFeedbackConfiguration(compiler,
    IRDepthFeedbackConfigurationDecideAtRuntime);
// Analogous function constant: 'depthFeedbackEnabled'

// Integer render target mask (bit 1 = int-compatible, bit 0 = float-compatible)
IRCompilerSetIntRTMask(compiler, 0b00000011);  // RT0 and RT1 are int-compatible

// Output sample mask (default: 0xFFFFFFFF = all samples)
IRCompilerSetSampleMask(compiler, 0x0F);
```

---

## Ray tracing compilation

### Recommended setup (Metal shader converter 3.0+)

```c
// 1. Gather intrinsic masks from all shaders in the pipeline
uint64_t chsMask  = IRObjectGatherRaytracingIntrinsics(chsObj,  "ClosestHit");
uint64_t missMask = IRObjectGatherRaytracingIntrinsics(missObj, "Miss");
// Use IRIntrinsicMaskAnyHitShaderAll / IRIntrinsicMaskCallableShaderAll as defaults
// for stages not present in your pipeline.

// 2. Build pipeline configuration
IRRayTracingPipelineConfiguration* rtcfg = IRRayTracingPipelineConfigurationCreate();
IRRayTracingPipelineConfigurationSetMaxAttributeSizeInBytes(rtcfg, 32);
IRRayTracingPipelineConfigurationSetIntrinsicMasks(rtcfg,
    chsMask, missMask,
    IRIntrinsicMaskAnyHitShaderAll, IRIntrinsicMaskCallableShaderAll);
IRRayTracingPipelineConfigurationSetRayGenerationCompilationMode(rtcfg,
    IRRayGenerationCompilationKernel);
IRRayTracingPipelineConfigurationSetIntersectionFunctionCompilationMode(rtcfg,
    IRIntersectionFunctionCompilationIntersectionFunctionBufferFunction);
// Requires GPUFamilyApple9, macOS 16 / iOS 19+. Fallback:
// IRIntersectionFunctionCompilationVisibleFunction (older devices)

// Optional
IRRayTracingPipelineConfigurationSetMaxRecursiveDepth(rtcfg, 4);
IRRayTracingPipelineConfigurationEnableDirectStateAccess(rtcfg, true);  // macOS 15+
IRRayTracingPipelineConfigurationEnableIntersectionFunctionGroups(rtcfg, true);

// 3. Install on compiler (must be consistent across all shaders in the pipeline)
IRCompilerSetRayTracingPipelineConfiguration(compiler, rtcfg);

// 4. Compile each stage
IRCompilerSetHitgroupType(compiler, IRHitGroupTypeTriangles);
IRObject* chsMetalIR = IRCompilerAllocCompileAndLink(compiler, "ClosestHit", chsObj, &err);

// 5. Fuse intersection + any-hit (when both are present)
IRObject* fusedIR = IRCompilerAllocCombineCompileAndLink(compiler,
    "Intersection", intersectionObj,
    "AnyHit",       anyHitObj,
    &err);

// 6. Synthesize auxiliary functions
IRMetalLibBinary* rayDispatchLib = IRMetalLibBinaryCreate();
IRMetalLibSynthesizeIndirectRayDispatchFunction(compiler, rayDispatchLib);

IRMetalLibBinary* intersectLib = IRMetalLibBinaryCreate();
IRMetalLibSynthesizeIndirectIntersectionFunction(compiler, intersectLib);

// 7. Cleanup
IRRayTracingPipelineConfigurationDestroy(rtcfg);
```

Intrinsic masks must be consistent across all shaders in the same pipeline. Providing incorrect masks causes undefined behavior.

---

## Geometry/tessellation emulation compilation

For an emulated pipeline (see `integrating-metal-shaderconverter-shaders` § geometry-tessellation), the vertex shader requires two extra compile steps: enable emulation lowering, and synthesize a separate stage-in metallib. Without both, pipeline creation fails.

```c
IRCompilerEnableGeometryAndTessellationEmulation(compiler, true);
// then IRCompilerAllocCompileAndLink(...)
```

**Only the vertex shader compile call needs it.** The flag changes how the VS is lowered for the mesh emulation pipeline. HS/DS/GS/FS conversion ignores it — you may pass `false` or omit the call.

**Stage-in synthesis** — emulation pipelines consume a separately synthesized stage-in metallib (delivered to integration as `stageInLibrary`). Build an `IRVersionedInputLayoutDescriptor` describing the VS input semantics, then:

```c
IRMetalLibBinary* stageInBin = IRMetalLibBinaryCreate();
IRMetalLibSynthesizeStageInFunction(compiler, vsReflection, &inputDesc, stageInBin);
// extract bytecode → MTLLibrary as in the compile loop above
```

The result contains one function whose name is converter-determined; retrieval guidance is in `integrating-metal-shaderconverter-shaders` SKILL.md. For input-layout descriptor field semantics see `metal_irconverter/metal_irconverter.h`.
