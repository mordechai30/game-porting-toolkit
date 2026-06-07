---
name: debugging-rendering-issues
description: ALWAYS use when a user porting a game to Metal reports a rendering issue — blank screen, wrong output, or anything that looks incorrect on Metal vs. the source platform. Covers black screen, missing geometry, wrong colors, gamma/sRGB problems, texture artifacts, z-fighting, alpha blending, flickering, visual corruption, and upside-down/mirrored geometry. Works with or without a GPU trace. Do NOT trigger when the user just wants to inspect an existing .gputrace.
---

# Metal Rendering Diagnosis

## When This Skill Helps

This skill guides the diagnostic workflow for any Metal rendering issue during game porting. For **specific symptoms** where you're confident in the cause, you can diagnose directly — but still recommend the `using-gpudebug` skill to confirm the diagnosis in a GPU trace before the developer changes code. For **ambiguous or underspecified problems** ("something looks off", "rendering is broken", multiple overlapping symptoms), use the full workflow below to turn vague reports into specific, actionable diagnoses efficiently.

## Gather Context

The most important step for ambiguous problems. Ask the developer:

1. **What do you see?** (blank, partial, or wrong-looking?)
2. **What do you expect?** (screenshot from source platform or description)
3. **What is the source API?** (D3D11, D3D12, Vulkan, OpenGL, or MoltenVK)
4. **Do you have a GPU trace** (`.gputrace`)?

If no GPU trace is available, recommend capturing one — use the `using-gpucapture` skill. If a GPU trace is available, use the `using-gpudebug` skill to inspect render state, bindings, and resource contents.

## Diagnostic Strategy

1. **Gather context** to resolve ambiguity
2. **Match symptom** using the router below — diagnose directly from this file
3. **Tiered elimination** — only if the symptom is still ambiguous or the router's candidate was ruled out, load a reference file (see Fallback section at end)

**After finding the cause:** If a GPU trace is available, use the `using-gpudebug` skill to confirm the diagnosis before reading or changing code. Then search the developer's codebase for the relevant code and suggest or implement the specific fix.

## Symptom Router

Match the symptom to the most likely cause. The gotchas column contains non-obvious traps — check these even when you're confident in the diagnosis.

| Symptom | Cause | Gotchas |
|---|---|---|
| Clear color visible, no geometry | Viewport zero-size, culling/winding, or depth state | Reversed depth: clear value + compare function must change together |
| Partial corruption each frame | Store action `.dontCare` | With MSAA, resolve texture + resolve store action both required |
| Flickering correct/corrupt | Load action `.dontCare` (TBDR), store action, buffering race, or Metal 4 barrier missing `MTL4VisibilityOptionDevice` | Worse at higher frame rates = buffering race, not static misconfiguration |
| Colors washed out / low contrast | sRGB pixel format missing | `GL_FRAMEBUFFER_SRGB` toggle → Metal pixel format. `newTextureViewWithPixelFormat:` for dual-access |
| Colors oversaturated / too dark | Double sRGB conversion or no gamma at all | Both `_sRGB` format AND manual `pow(color, 1/2.2)` = double-encode |
| Background color wrong shade | sRGB clear color | sRGB render targets interpret clear color in linear space |
| Wrong or garbled textures | Pixel format translation | BGRA vs RGBA channel order; `MTLTextureSwizzleChannels` |
| Alpha blending wrong / dark halos | Premultiplied vs straight alpha | CoreAnimation expects premultiplied alpha on the drawable. D3D blend enum integers differ from Metal — don't cast directly |
| Z-fighting everywhere | Reversed depth not fully ported | Clear value + compare function must change together. Depth bias units differ across APIs and between D24/D32F formats — rescale needed |
| Objects wrong depth order | Depth clear + compare mismatch | |
| Objects appear/disappear | Buffering race on dynamic buffers | |
| Ray tracing all-miss (sky only) | Resource residency missing | Binding ≠ residency. Metal 4: no `useResource`/`useHeap` — use `MTLResidencySet` on command queue or command buffer. After TLAS rebuild, residency set must be updated and re-committed |
| Wrong texture on surface | Resource binding index mismatch | Metal 4: `MTL4ArgumentTable` replaces per-encoder binds. `maxTextureBindCount` defaults may be too low |
| Geometry upside down / mirrored | Y-axis flip or winding | Negate Y in projection OR flip viewport — do ONE, not both. Viewport flip also requires flipping winding |
| Scene too bright / highlights blown | HDR headroom / EDR | Apple EDR: SDR 0.0–1.0, HDR extends above. Different from D3D12/Vulkan swapchain models |
| Colors clamped / banding | Shader output range | Metal clamps Unorm writes to [0,1]. 8-bit where source used 16-bit float = precision loss |
| Geometry correct shape but black | Texture sampling or shader output | Check texture bound and populated, mipmaps generated, then shader `[[position]]` and fragment return |

## Metal 4

**Binding** — `MTL4ArgumentTable` with fixed slot limits (31 buffers, 128 textures, 16 samplers). Set on encoder via `setArgumentTable:`. `initializeBindings` defaults NO — unset slots are garbage, not zero.

**Residency** — All GPU-accessed resources must be in a committed `MTLResidencySet` (on queue or command buffer). Binding does NOT grant residency — non-resident reads return zeros silently. `beginCommandBufferWithAllocator:` clears prior `useResidencySet:` calls — must re-associate every frame. After TLAS rebuild, residency set must be updated.

**Barriers** — `MTL4VisibilityOptionNone` = execution order only, no cache flush. D3D12 transitions implicitly flush. Use `MTL4VisibilityOptionDevice` for data dependencies.

**Other** — `D24_UNORM_S8_UINT` not universally supported on Apple GPUs; default to `Depth32Float_Stencil8`. D3D `COLOR_WRITE_ENABLE` / Vulkan `VkColorComponentFlags` to `MTLColorWriteMask` — bit layout reversed, naive cast drops channels. Metal has no subpasses.


## Fallback: Tiered Elimination

Only when the symptom router above doesn't resolve the issue. Load one tier reference file at a time.

- **Tier 1** — 7 instant checks: `references/tier-1-instant-checks.md`
- **Tier 2** — 14 state checks: `references/tier-2-state-inspection.md`
- **Tier 3** — 7 data checks: `references/tier-3-data-inspection.md`

If all tiers are exhausted, review shader source and verify transform math.
