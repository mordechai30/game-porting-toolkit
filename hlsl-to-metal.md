
# is there any tool which can convert hlsl (DX11+) shaders to metal shaders? perhaps via sprv?

Yes, this is a well-trodden path. The standard pipeline is:

**HLSL → SPIR-V → MSL**

1. **DXC (DirectXShaderCompiler)** — Microsoft's official HLSL compiler can target SPIR-V directly (not just DXIL) when built/invoked with the `-spirv` flag. This handles DX11/DX12-style HLSL (SM 5.0–6.x), including most common intrinsics and semantics.
   ```
   dxc -spirv -T ps_6_0 -E main shader.hlsl -Fo shader.spv
   ```

2. **SPIRV-Cross** (Khronos, open source) — takes the SPIR-V and cross-compiles it to Metal Shading Language (MSL).
   ```
   spirv-cross --msl shader.spv --output shader.metal
   ```
   It handles resource binding remapping, buffer layouts, and the various MSL version targets (you can specify `--msl-version` for different Metal feature sets).

This two-step chain (DXC → SPIRV-Cross) is exactly what a lot of cross-platform engines and middleware use under the hood (Unity, Unreal's shader cross-compilation, various homebrew engines, etc.), so it's mature and well-tested.

**Alternatives / related tools:**
- **SPIRV-Reflect** — not a converter, but useful alongside SPIRV-Cross for extracting reflection info if you need it for pipeline setup on the Metal side.
- **glslang** — can also emit SPIR-V but typically from GLSL/HLSL front-end; less commonly used for HLSL→SPIR-V than DXC these days.
- **Tint** (part of Google's Dawn/WebGPU project) — can also convert SPIR-V to MSL, and increasingly supports WGSL as an intermediate too, if you're already in a WebGPU-adjacent pipeline.
- **naga** (Rust, part of the wgpu project) — supports HLSL/SPIR-V/WGSL as inputs and MSL as an output, used heavily in wgpu-based engines.

**Practical notes:**
- Some HLSL constructs (certain intrinsics, wave/subgroup ops, root signatures, bindless patterns) don't map 1:1 to MSL and may need manual patching after conversion.
- Vertex attribute/buffer binding conventions differ between D3D and Metal, so you'll likely need to write or auto-generate binding remap tables (SPIRV-Cross has APIs for this).
- If you're doing this at scale, wrapping the DXC→SPIRV-Cross pipeline into a build step (many engines do this) is much easier than doing it shader-by-shader by hand.

If you tell me your source engine/toolchain (raw D3D11 HLSL, Unity, custom engine, etc.) and target (macOS/iOS Metal), I can help sketch out a concrete build pipeline or troubleshoot specific conversion issues.

# so we have two alternatives for the second stage:
first stage: hlsl to sprv glslang (SPIRV-Reflect for meta or engine setup/data of the shader)
second stage: sprv to metal Tint or naga, an option to get normal metal shading human readable code?
i assume both options of the second stage produce sort of binary MSL?

A quick correction and then the answer to your actual question:

**On stage 1:** glslang's HLSL front-end is quite limited/legacy compared to DXC's — it doesn't support modern HLSL (SM 6.x), and Microsoft itself points people to DXC for HLSL→SPIR-V now. glslang is really more of a GLSL compiler with partial HLSL support bolted on. DXC is the one actively maintained for this. So I'd stick with **DXC → SPIR-V**, then SPIRV-Reflect for metadata if you want it.

**On your actual question — no, neither Tint nor naga (nor SPIRV-Cross, for that matter) produces binary MSL.** They all produce **human-readable MSL source code** (`.metal` text files). That's actually the whole point of "cross-compilation" here — these tools do source-to-source translation, not compilation to a binary format.

The actual binary step (`.metallib`) happens *after*, via Apple's own toolchain:
```
xcrun metal -c shader.metal -o shader.air
xcrun metallib shader.air -o shader.metallib
```
That's Apple's proprietary compiler (`metal`/`metallib`), and it's the only thing that can produce Metal's binary intermediate (AIR) or final compiled library. Neither Tint nor naga nor SPIRV-Cross have access to that pipeline — Apple hasn't opened it up.

So the full realistic pipeline is:

```
HLSL --(DXC)--> SPIR-V --(SPIRV-Cross / Tint / naga)--> MSL (.metal, text) --(xcrun metal/metallib)--> .metallib (binary)
```

**Choosing between SPIRV-Cross, Tint, and naga for stage 2** (all three output readable `.metal`, not just SPIRV-Cross as I mentioned earlier):
- **SPIRV-Cross** — most mature specifically for MSL output, widest real-world usage, best documented binding-remap API, good choice if MSL is your only real target.
- **Tint** — part of Dawn, strong if you're also going through WGSL or need WebGPU-adjacent tooling; MSL backend is solid but slightly less battle-tested standalone than SPIRV-Cross.
- **naga** — good if your toolchain is Rust-based (wgpu ecosystem), supports many targets from one IR, but historically has had more edge-case gaps in MSL output fidelity than SPIRV-Cross for complex shaders.

For a pure "get correct MSL out the other end" goal with a C++/native toolchain, **SPIRV-Cross is usually still the safest default** — it's had the most years of MSL-specific hardening. Tint/naga are compelling mainly if you're already inside their respective ecosystems (Dawn/WebGPU or wgpu/Rust).

# what apple suggest for directx to metal shader translations?

Apple's official answer is their own **Metal Shader Converter (MSC)**, part of the Game Porting Toolkit ecosystem. It's a different path from the DXC → SPIRV-Cross approach I described earlier — worth knowing the distinction.

## Apple's recommended pipeline

Metal Shader Converter consumes DXIL to produce Metal, and you use it alongside the open source DXC compiler to build an end-to-end shader pipeline. So concretely:

```
HLSL --(DXC, targeting DXIL not SPIR-V)--> DXIL --(Metal Shader Converter)--> .metallib
```

This is **not** the SPIR-V route at all. Apple's tool consumes **DXIL** (DirectX's own IL) directly, rather than going through SPIR-V as an intermediate. Key differences from what we discussed:

- The conversion from DXIL to Metal happens at the binary level, and it's very fast.
- It goes **straight to a compiled `.metallib`** — you don't necessarily get human-readable `.metal` source out of it the way SPIRV-Cross/Tint/naga do (though it can also emit source-level output depending on how you invoke it).
- By default, shader converter generates a Metal library for the latest version of macOS, along with a JSON file containing useful reflection data — so it replaces the SPIRV-Reflect step too.
- It also enables you to leverage advanced Apple GPU features like Mesh Shaders and raytracing pipelines, and integrates with Metal's own debugging/profiling/validation tools since it understands HLSL semantics natively.

## Why Apple built its own instead of endorsing SPIR-V

Apple's stated rationale is really about fidelity and feature coverage for game-porting specifically: going DXIL → Metal preserves more of D3D12's semantics (root signatures, resource binding models, raytracing/mesh shader features) than round-tripping through SPIR-V's more generic representation. It's purpose-built for people porting real D3D12 games, not a general shader cross-compiler.

## Practical takeaway

- **If you're porting a D3D12 game** (their explicit target use case) → use **DXC → DXIL → Metal Shader Converter**. This is what Apple ships tooling, docs, sample code, and WWDC sessions for, and it's bundled with the **Game Porting Toolkit**.
- **If you're on D3D11**, or need a cross-platform pipeline that also targets Vulkan/OpenGL/WebGPU alongside Metal, the DXC(-spirv) → SPIR-V → SPIRV-Cross path is still the more general/flexible choice — Apple's tool is specifically DXIL-in, not SPIR-V-in.
- Metal Shader Converter itself runs on **both Windows and macOS**, so you can even wire it into a Windows-based build pipeline to produce `.metallib` files ahead of time. It can be invoked from the command line or by linking against its dynamic library on both Windows and macOS.

If your source is DX11-only HLSL (as in your first message), you'd typically still compile through DXC targeting a DXIL profile (DXC supports SM5.x-style HLSL compiled to DXIL fine) to feed Metal Shader Converter — you're not locked into D3D12-authored shaders specifically, just DXIL as the intermediate format.


# apple's convertor can't work with hlsl<6.0?

Correct — you've spotted the real constraint, and it confirms it.

**DXIL fundamentally requires Shader Model 6.0+.** DXC compiles HLSL programs for shader model 6.0 or higher — that's baked into DXC itself. Shader models 9 and below aren't supported by DXIL, and the DXIL version is typically tied to the shader model, with the minimum for standard shader stages (VS/PS/CS/etc.) being 6.0.

Since **Metal Shader Converter consumes DXIL as its input**, it inherits that floor: anything compiled as SM < 6.0 (i.e., classic DX11-era HLSL using `vs_5_0`, `ps_5_0`, etc., or DX9/10-era) can't feed into it directly — there's no DXIL representation for it.

## What "DX11+" actually splits into

This matters because DX11 HLSL spans two different worlds:
- **SM 5.0/5.1 HLSL, compiled with `fxc`** → produces **DXBC**, not DXIL. This is the "legacy" path, still extremely common in real DX11 codebases.
- **SM 6.0+ HLSL, compiled with `dxc`** → produces **DXIL**. You can write SM6.0+ syntax and target DX11 runtimes in some cases too, but a lot of existing DX11 shader code is still SM5.x/DXBC.

So if your shaders are literally DXBC (SM5.x, compiled via old `fxc`), Apple's Metal Shader Converter path doesn't apply directly — you'd need to either:
1. **Recompile from HLSL source with DXC targeting SM6.0+** (if you have source, which is the normal case) — then you're back on the MSC path. This is usually trivial since SM5.x HLSL syntax is a subset of what SM6.x DXC accepts, modulo a few legacy intrinsics/register syntax quirks.
2. Use **`dxilconv`** — Microsoft's DXBC→DXIL converter — a DLL providing a converter from DXBC, the older shader bytecode format — as a bridge if you only have compiled DXBC binaries and no source.
3. Fall back to the **DXC(-spirv) → SPIR-V → SPIRV-Cross** route, since DXC's HLSL front-end (not just its DXIL backend) accepts SM5.x-style syntax fine when emitting SPIR-V — this path doesn't care about the SM6.0 DXIL floor at all.

## Practical bottom line

- **Have HLSL source, even if written against SM5.x semantics?** → just compile it with DXC targeting SM6.0 (`-T ps_6_0` etc.) instead of `fxc`. Most DX11 shader source recompiles cleanly this way, then goes straight into Metal Shader Converter.
- **Only have precompiled DXBC binaries, no source?** → you're stuck either reverse-engineering to source, or using `dxilconv` to hop DXBC→DXIL first, or going the SPIR-V/SPIRV-Cross route which doesn't have this restriction.

So it's less "Apple's converter can't handle old HLSL" and more "Apple's converter can't handle old **DXBC**" — the moment you recompile through DXC with a 6.x target, even genuinely DX11-era shader source becomes fair game for MSC.


# but if we work:
shader.hlsl (< 6.0) =>(glslang or DXC + SPIRV-Reflect for metadata) => SPIRV => SPIRV-Cross => shader.metal
then we an even use:
shader.glsl =>(glslang + SPIRV-Reflect for metadata) => SPIRV => SPIRV-Cross => shader.metal
?

Yes, exactly — and this is actually the core insight of why SPIR-V exists as an IR. Once you're in SPIR-V, **SPIRV-Cross and SPIRV-Reflect don't know or care what source language produced it.** HLSL and GLSL become indistinguishable at that point. So both your pipelines are structurally identical:

```
shader.hlsl (any SM) --[frontend]--> SPIR-V --[SPIRV-Reflect]--> metadata
                                           --[SPIRV-Cross]--> shader.metal

shader.glsl --[glslang]--> SPIR-V --[SPIRV-Reflect]--> metadata
                                 --[SPIRV-Cross]--> shader.metal
```

One correction on tool choice, though, tying back to the SM6.0 issue:

## Use DXC, not glslang, for the HLSL leg

For the **HLSL < 6.0 → SPIR-V** step, prefer **DXC with `-spirv`**, not glslang. Two reasons:

1. **DXC's SPIR-V backend doesn't have the SM6.0 floor that DXIL has.** That restriction is specific to DXIL as a target — SPIR-V is a different backend entirely, so DXC will happily take `-T ps_5_0`-style profiles and emit SPIR-V from them. You get to skip the whole DXBC/dxilconv headache discussed earlier.
2. **glslang's HLSL frontend is the weaker, less-maintained one** — as I mentioned earlier, it's really a GLSL compiler with partial/legacy HLSL support bolted on, and Microsoft's own guidance points people to DXC for HLSL. It'll choke on more real-world HLSL constructs than DXC will.

So really: **DXC is your one HLSL→SPIR-V tool regardless of shader model** — you just point it at DXIL or SPIR-V as the output target depending on which path you're taking. glslang's role is specifically for the GLSL leg.

## Corrected pipeline pair

```
shader.hlsl (any SM, 4.0–6.x) --(DXC -spirv)--> SPIR-V ─┐
                                                          ├─> SPIRV-Reflect (metadata)
shader.glsl                    --(glslang)-----> SPIR-V ─┘   SPIRV-Cross (→ shader.metal)
```

This is genuinely a clean, unified architecture — one SPIR-V intermediate, two frontends feeding it (DXC for HLSL, glslang for GLSL), and one shared backend/reflection toolchain (SPIRV-Cross + SPIRV-Reflect) regardless of source language. It's a legitimate reason to prefer this over Apple's MSC path if you have a mixed HLSL/GLSL codebase and want one consistent build pipeline rather than maintaining two separate toolchains.

The trade-off, as before: you lose Apple's DXIL-native handling of things like mesh shaders/raytracing pipeline objects and the tighter Metal-debugger integration that comes from MSC understanding HLSL semantics directly — SPIRV-Cross's MSL output is generic and may need more manual patching for those advanced features.


# do previous versions of apple tools support hlsl<6.0?

That MethanePowered table actually answers this directly — it's not that older Apple tool versions handled pre-6.0 differently, it's that **Metal Shader Converter itself has always had limited/partial support for pre-6.0 shader models**, as a documented, ongoing constraint. Metal Shader Converter's feature support matrix lists **Pre-6.0 as "Limited" support with "Limited" error-detection, noting "some features not supported."**

So to directly answer your question:

## No — there wasn't a better past version for HLSL < 6.0

This isn't a "used to support it, now doesn't" situation, or the reverse. It's the opposite of what the phrasing might suggest:

- Apple's Metal Shader Converter has **never been built around SM < 6.0 as a first-class target**. It's fundamentally a DXIL consumer, and DXIL fundamentally starts at SM6.0.
- The "Pre-6.0 / Limited" row in that support matrix suggests some pre-6.0 constructs *can* pass through in practice (likely because DXC can still compile older-style HLSL syntax down to DXIL even when targeting SM6.0 profiles — SM5.x syntax is largely a subset of what SM6.x DXC accepts) — but it's explicitly caveated as incomplete, with weaker validation/error detection.
- This has been consistent across GPTK 1 → 2 → 3 and MSC's version history; the WWDC materials from 2023 onward all frame the tool the same way — DXIL in, full support from SM6.0.

## Practical implication

There's no older/alternate Apple tool version worth chasing for better legacy support. Your options remain what we already covered:

1. **Recompile HLSL source through DXC targeting SM6.0+** — even if originally written for SM5.x — then feed the resulting DXIL into MSC. This is the path Apple actually supports well, and it's why the "Limited" pre-6.0 row exists at all — DXC will often *compile* older-style code to a 6.x target, MSC just doesn't guarantee full feature/validation coverage for whatever legacy constructs ride along.
2. **Go the SPIR-V route instead** (DXC `-spirv` → SPIRV-Cross) for anything that hits MSC's pre-6.0 limitations — this path has no shader-model floor at all, since it doesn't touch DXIL.
3. If you're stuck with **compiled DXBC binaries with no source** (true legacy, pre-DXC-era), that's outside both paths natively; you'd need `dxilconv` (DXBC→DXIL bridge) or a DXBC-aware SPIR-V frontend — worth noting **`dxbc-spirv`** (doitsujin) exists as a purpose-built SSA-based compiler for Direct3D Shader Models 5.1 and older, translating DXBC directly to SPIR-V, bypassing DXC/DXIL entirely. That's actually your cleanest option if source is unavailable.

So the practical rule of thumb stands: **if you have source, recompile with DXC at SM6.0+ and prefer that surface regardless of which backend (DXIL/MSC or SPIR-V/SPIRV-Cross) you target; if you only have legacy DXBC binaries, dxbc-spirv or dxilconv are your bridges.**
