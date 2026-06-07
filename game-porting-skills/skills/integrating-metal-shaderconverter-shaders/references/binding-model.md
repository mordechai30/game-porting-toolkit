---
name: binding-model
description: TLAB layout, root signatures, static samplers, descriptor table encoding, dynamic resources (bindless), compute dispatch, unbounded arrays, and append/consume buffers. Companion setter helpers are header-only — implementations document the IRDescriptorTableEntry encoding logic.
---

# Core binding model

## Companion constants used in this section

| Constant | Value | Purpose |
|---|---|---|
| `kIRArgumentBufferBindPoint` | 2 | Bind slot for the top-level argument buffer |
| `kIRDescriptorHeapBindPoint` | 0 | Bind slot for the bindless resource heap |
| `kIRSamplerHeapBindPoint` | 1 | Bind slot for the bindless sampler heap |

## Top-Level Argument Buffer (TLAB)

The TLAB is the bridge between CPU resource binding and GPU shader access. Every Metal shader converter pipeline receives its resources through a single argument buffer bound at index `kIRArgumentBufferBindPoint` (2).

### Entry types

| Entry type | What to write | Size |
|---|---|---|
| **Root constants** | Raw constant bytes, copied **inline** | N bytes, 4-byte aligned |
| **Root arguments** — CBV, buffer SRV, buffer UAV only | 64-bit GPU address of the buffer | 8 bytes |
| **Descriptor table** | 64-bit absolute GPU address of the table buffer | 8 bytes |

> Textures and texture UAVs cannot be root arguments — they must go in a descriptor table.

**Root constants are inline** — memcpy directly into the TLAB at `topLevelOffset`. Writing a GPU address instead produces garbage with no error.

### Calculating offsets

Use `IRRootSignatureGetResourceLocations` — do not calculate offsets manually. Metal shader converter adds alignment padding between parameters and this only applies to top-level entries only.

To determine individual resource locations and offsets within descriptor tables, you need to use DXC/DXIL reflection.

### Argument buffer synchronization

The TLAB is CPU/GPU shared. Each draw or dispatch needs its own region. 

**Pattern**: bump allocator per frame-in-flight. Backed by a `MTLBuffer`, allocate a region per draw, write resource bindings, bind via `setBuffer:offset:atIndex:` at `kIRArgumentBufferBindPoint` (2). Alternatively, `setVertexBytes:` / `setFragmentBytes:` copies inline data without a persistent buffer — useful for small per-draw TLABs.

## Root Signature Conventions

### Param count must match between host and HLSL

If host-side `NumParameters` differs from HLSL, every TLAB offset is misaligned — the shader silently reads wrong data. Static samplers add one extra entry beyond `NumParameters`; see below.

### Static samplers

Metal shader converter does not bake static samplers into the pipeline as D3D12 does. When static samplers are present, you must supply them at runtime as a sampler descriptor table.

`IRRootSignatureGetResourceCount` returns `NumParameters + 1` when static samplers are present. The extra entry is always last — its offset is at `locations[count - 1].topLevelOffset`.

Populate `samplerTableBuffer` with one `IRDescriptorTableEntry` per static sampler using `IRDescriptorTableSetSampler` (or manually — see Descriptor Table Encoding below).

## Descriptor Table Encoding

Each descriptor table is a `MTLBuffer` of `IRDescriptorTableEntry` values — 3 × `uint64_t` (24 bytes). The TLAB holds the table's absolute GPU address.

Use `IRDescriptorTableSetBuffer`, `IRDescriptorTableSetTexture`, and `IRDescriptorTableSetSampler` from the companion header — header-only; implementations document the `IRDescriptorTableEntry` encoding logic for the manual path.

### Manual encoding (without companion)

`IRDescriptorTableEntry` layout:

| Field | Buffer | Texture | Sampler |
|---|---|---|---|
| `gpuVA` (uint64) | Buffer GPU address | 0 | `sampler.gpuResourceID._impl` |
| `textureViewID` (uint64) | 0 | `texture.gpuResourceID._impl` | 0 |
| `metadata` (uint64) | `bufSize` (bits 31:0) \| `texViewOffset` (bits 39:32) \| `typedBit` (bit 63) | `float_bits(minLODClamp)` in low 32 | `float_bits(lodBias)` |

For a plain `StructuredBuffer` or `ByteAddressBuffer` with no typed view: `metadata = bufferSizeInBytes`.

### Descriptor table GPU addresses must be absolute

The TLAB entry must be the **absolute GPU address** — `[tableBuffer gpuAddress] + byteOffset`. A relative offset dereferences the wrong memory.

### Sampler lifetime

`IRDescriptorTableSetSampler` copies `gpuResourceID._impl` — an integer handle, not an object reference. Releasing the sampler after encoding leaves a dangling handle — the GPU reads a dead value silently.

Keep sampler objects alive for at least as long as any descriptor entry that references them.

### Buffer vs texture descriptor type

`StructuredBuffer`, `ByteAddressBuffer`, and `RWStructuredBuffer` are buffer types — they must use `IRDescriptorTableSetBuffer` (or the manual buffer encoding). Using `IRDescriptorTableSetTexture` writes `gpuVA = 0`, causing the shader to dereference address zero.

## Dynamic Resources (Bindless)

Bindless pipelines bind a resource heap and a sampler heap directly to the shader. The shader indexes into them using integer handles.

**Required bind points** (companion constants):

| Heap | Bind index |
|---|---|
| Resource heap | `kIRDescriptorHeapBindPoint` (0) |
| Sampler heap | `kIRSamplerHeapBindPoint` (1) |

Each heap is a `MTLBuffer` containing `IRDescriptorTableEntry` values encoded with the setter functions or manual encoding shown above. Call `useResource` or `useHeap` for all resources indirectly accessed through these heaps.

## Compute dispatch

Do not hardcode `[numthreads(X,Y,Z)]` — query from Metal shader converter reflection at build time and store alongside the PSO.

| Path | How to get `tg_size` |
|---|---|
| CLI (`--output-reflection-file`) | JSON key `tg_size` — array `[X, Y, Z]` |
| Library (`IRShaderReflectionCopyComputeInfo`) | `csinfo.info_1_0.tg_size[0..2]`; release with `IRShaderReflectionReleaseComputeInfo` after |

Bind the TLAB at `kIRArgumentBufferBindPoint` (2) on the compute encoder — same as render pipelines.

## Unbounded arrays

Unbounded arrays (`StructuredBuffer<T> inBuffers[] : register(t0, space0)`) require **explicit root signature layout** — incompatible with automatic linear binding mode.

At runtime they are no different from bounded descriptor tables — same `IRDescriptorTableEntry` encoding (see Descriptor Table Encoding above). Entry count is fixed at conversion time by the root signature.

## Append/Consume buffers

`AppendStructuredBuffer` and `ConsumeStructuredBuffer` require an atomic counter alongside the storage buffer. Metal shader converter uses a texture atomic to implement this counter.

Use `IRRuntimeCreateAppendBufferView`, `IRDescriptorTableSetBufferView`, and `IRRuntimeGetAppendBufferCount` from the companion header — header-only; implementations document counter buffer setup (16-byte aligned, `MTLTextureTypeTextureBuffer` wrapping) for the manual path.

**Requires macOS 14 / iOS 17**. Counter buffer must use `MTLResourceStorageModeShared` to read the count on the CPU.

## Metal 4 binding

Bind-point constants and `IRDescriptorTableEntry` encoding are unchanged on Metal 4. Two host-side differences:

- **Argument table** — bind the TLAB, descriptor heap, and sampler heap via `setAddress:atIndex:` at the Metal shader converter bind constants. See `translating-to-metal4-api` § Resource Binding (Argument Tables).
- **Residency** — add the TLAB, descriptor / sampler heaps, and every resource reached through `IRDescriptorTableEntry` to a `MTLResidencySet`. See `managing-metal4-resources/references/residency.md`.

## Anti-patterns

- **Root constants written as a pointer.** The shader reads raw bytes from the TLAB at the constant's offset. Writing a GPU address produces garbage with no error.
- **Manually calculated TLAB offsets.** Metal shader converter adds alignment padding. Use `IRRootSignatureGetResourceLocations`.
- **Treating static samplers as baked pipeline state.** They are not. Supply them as a runtime descriptor table whenever the pipeline uses static samplers.
- **Buffer SRV encoded with `IRDescriptorTableSetTexture`.** Writes `gpuVA = 0`; shader reads from address zero.
- **Descriptor table pointer as a buffer-relative offset.** Must be an absolute GPU address — the shader dereferences it directly.
- **Releasing a sampler after encoding its descriptor entry.** The entry holds an integer handle, not a reference. Dead handles produce no error.
- **Mismatched root signature `NumParameters` between host and HLSL.** Silently misaligns every TLAB offset.
- **Hardcoding compute threadgroup sizes.** Query `tg_size` from reflection — hardcoded values break when the HLSL shader changes.
- **Using unbounded arrays with automatic linear layout.** They require explicit root signature layout. The conversion will fail or produce wrong offsets.
- **Storing the append buffer counter in a non-Shared buffer.** Reading the counter on the CPU requires `MTLResourceStorageModeShared`.
