# Game Porting Toolkit 4 — Skill reference

See the top-level [README](../../README.md) for installation and the workflow overview.

## Codex packaging

This package is in `plugins/game-porting-skills/` so the repository marketplace
can load it with `./plugins/game-porting-skills`. `.codex-plugin/plugin.json`
loads every directory in `skills/`.

`porting-assistant` is a workflow skill. It routes porting requests through the
milestone lifecycle and replaces the removed `agents/porting-assistant.md`.
This is required because Codex plugin manifests do not support an `agents`
field.

The package also keeps Claude and Gemini metadata. Both use this package path
and the shared skills.

## Expert skills

Expert domain knowledge for porting games to Apple platforms.

| Expert skill | Description |
|---|---|
| `translating-to-metal4-api` | API reference and cross-API translation tables (Metal 3, D3D12, Vulkan → Metal 4), TBDR architecture |
| `managing-metal4-synchronization` | Barriers, fences, events, cross-API state transition translation |
| `managing-metal4-resources` | Buffers, textures, residency, descriptor heaps |
| `creating-metal4-shader-pipelines` | Pipeline state creation — render/compute/mesh PSOs via `MTL4Compiler` from already-compiled metallibs, flexible PSOs, color-attachment mapping, caching |
| `presenting-metal-drawables` | Drawable presentation, frame pacing, vsync control, CAMetalLayer, CAMetalDisplayLink |
| `managing-metal-cpp-lifetimes` | Metal object lifetime management for Obj-C/ARC and metal-cpp |
| `integrating-metal-shaderconverter-shaders` | Metal shader converter integration — argument buffer binding, descriptor tables, root signatures |
| `compiling-with-metal-shaderconverter` | Shader conversion — compile DXIL to metallib, reflection output, debug info management |
| `using-metalfx-temporal-upscaler` | MetalFX temporal upscaling (`MTLFXTemporalScaler`) integration |
| `using-metalfx-frame-interpolation` | MetalFX frame interpolation (`MTLFXFrameInterpolator`) with PresentThread |
| `setting-up-macos-window` | Window management, `CAMetalLayer` setup, input handling, fullscreen, bridging D3D concepts to Metal |
| `using-game-controller` | `GCController` API — porting from XInput, DirectInput, RawInput, or GameInput |
| `using-metal-validation` | Enable, configure, and interpret Metal API validation, shader validation, and load/store-action visual indicators |
| `using-gpucapture` | Capture a `.gputrace` from a running Metal application via the `gpucapture` CLI |
| `using-gpudebug` | Inspect, navigate, and extract resources from a `.gputrace` via the `gpudebug` CLI |
| `debugging-rendering-issues` | Diagnose any Metal rendering issue — blank screens, visual corruption, incorrect colors, depth issues, binding problems |

## Workflow skills

Use `porting-assistant` to orchestrate milestones.

| Workflow skill | Description |
|---|---|
| `porting-methodology` | Core methodology — porting goals, milestone lifecycle, escalation, stub conventions |
| `porting-assistant` | Route a porting request through the milestone lifecycle |
| `porting-discover` | Analyze the codebase before porting — produces a discovery report with Game Porting Toolkit evaluation, trace analysis, and feature coverage |
| `porting-plan-goal` | Define the next porting goal with milestones |
| `porting-start-milestone` | Prepare for the next milestone — study code, load skills, produce prep summary |
| `porting-execute` | Write code for the current milestone |
| `porting-validate` | Run the validation checklist before committing |
| `porting-handoff` | Close out a milestone — commit, update status, write handoff note |
| `porting-status` | Show current porting status (read-only) |
