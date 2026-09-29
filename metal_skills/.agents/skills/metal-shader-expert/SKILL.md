---
name: metal-shader-expert
description: Develop Metal Shading Language shaders, PBR effects, tile-based rendering patterns, and Apple GPU shader optimization. Use for shader authoring and shader performance work; use metal-gpu-debug for capture and validation workflows.
metadata:
  category: Graphics
  tags:
  - metal
  - shaders
  - gpu
  - pbr
  - apple
---

# Metal Shader Expert

Guidance for Metal shaders, real-time rendering, visual effects, and Apple GPU tile-based rendering.

## When to Use This Skill

**Use for:**
- Metal Shading Language (MSL) development
- Apple GPU optimization (TBDR architecture)
- PBR rendering pipelines
- Compute shaders and parallel processing
- Ray tracing on Apple Silicon
- Shader performance analysis; use `metal-gpu-debug` for capture and validation steps

**Do NOT use for:**
- WebGL/GLSL → different architecture, browser constraints
- CUDA → NVIDIA-only
- OpenGL → deprecated on Apple since 2018
- CPU-side optimization → use general performance tools

## Expert vs Novice Shibboleths

| Topic | Novice | Expert |
|-------|--------|--------|
| **Data types** | Uses `float` everywhere | Defaults to `half` (16-bit), `float` only when precision needed |
| **Specialization** | Runtime branching | Function constants for compile-time specialization |
| **Memory** | Everything in device space | Knows constant/device/threadgroup tradeoffs |
| **Architecture** | Treats like desktop GPU | Understands TBDR: tile memory is free, bandwidth is expensive |
| **Ray tracing** | Uses intersection queries | Uses intersector API (hardware-aligned) |
| **Debugging** | Print debugging | GPU capture, shader profiler, occupancy analysis |

## Common Anti-Patterns

### 32-Bit Everything
| What it looks like | Why it's wrong |
|--------------------|----------------|
| `float4 color`, `float3 normal` everywhere | Wastes registers, reduces occupancy, doubles bandwidth |
| **Instead**: Default to `half`, upgrade to `float` only for positions/depth |

### Ignoring TBDR Architecture
| What it looks like | Why it's wrong |
|--------------------|----------------|
| Treating Apple GPU like immediate-mode renderer | Tile memory reads are free; bandwidth is not |
| **Instead**: Use `[[color(n)]]` freely, prefer memoryless targets, avoid unnecessary store |

### Runtime Branching for Constants
| What it looks like | Why it's wrong |
|--------------------|----------------|
| `if (material.useNormalMap)` checked every fragment | Creates divergent warps, wastes ALU |
| **Instead**: Function constants + pipeline specialization |

### Intersection Queries for Ray Tracing
| What it looks like | Why it's wrong |
|--------------------|----------------|
| Using query-based API | Doesn't align with hardware; less efficient grouping |
| **Instead**: Use intersector API with explicit result handling |

## Evolution Timeline

| Era | Key Development |
|-----|-----------------|
| Pre-2020 | Metal 2.x, OpenGL migration, basic compute |
| 2020-2022 | Apple Silicon, unified memory, tile shaders critical |
| 2023-2024 | Metal 3, mesh shaders, ray tracing HW acceleration |
| 2025+ | Neural Engine + GPU cooperation, Vision Pro foveated rendering |

**Apple Family 9 Note**: Threadgroup memory less advantageous vs direct device access.

## Philosophy: Play, Exposition, Tools

**Play**: The best shaders come from experimentation and happy accidents. Try weird ideas, build beautiful effects.

**Exposition**: If you can't explain it clearly, you don't understand it yet. Comment generously, show the math visually.

**Tools**: A good debug tool saves 100 hours of guessing. Build visualization for every complex shader.

## Core Competencies

| Area | Skills |
|------|--------|
| **MSL** | Kernel functions, vertex/fragment, tile shaders, ray tracing |
| **Production** | Asset pipelines, artist-friendly parameters, fast iteration |
| **Rendering** | PBR, IBL, volumetrics, post-processing, mesh shaders |
| **Debug** | Heat maps, shader inspection, GPU profiling, custom overlays |

## MCP Integrations

| MCP | Purpose |
|-----|---------|
| **Firecrawl** | Research SIGGRAPH papers, Apple GPU architecture |
| **WebFetch** | Fetch Apple Metal documentation |

## Reference Files

| File | Contents |
|------|----------|
| `references/pbr-shaders.md` | Cook-Torrance BRDF, material structs, lighting calculations |
| `references/noise-effects.md` | Hash functions, FBM, Voronoi, domain warping, animated effects |
| `references/debug-tools.md` | Heat maps, debug modes, overdraw viz, NaN detection, wireframe |

## Integration with Other Skills

- **physics-rendering-expert** - Jacobi solver GPU compute shaders
- **native-app-designer** - Visualization and debugging UI

---

*Craft beautiful, performant Metal shaders with the artistry of film production and the pragmatism of real-time constraints.*
