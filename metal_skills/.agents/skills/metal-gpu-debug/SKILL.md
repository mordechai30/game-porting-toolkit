---
name: metal-gpu-debug
description: Use for Metal GPU profiling, validation, shader compilation, frame capture, or MoltenVK debugging on macOS or iOS. Do not use for RenderDoc, D3D, non-macOS Vulkan, or web rendering.
---

# Metal GPU Debugging

Use this skill for Metal profiling, validation, shader compilation, frame capture, and MoltenVK debugging on Apple platforms. Confirm the app, device, output path, and capture duration before starting a capture or trace. Check the installed Xcode and tools before using a command.

## Read by task

- Session setup and automated trace workflow: [session-workflow.md](references/session-workflow.md).
- iOS devices, Metal System Trace, and XML export: [device-and-traces.md](references/device-and-traces.md).
- Validation, performance HUD, and `.gputrace` capture: [validation-and-capture.md](references/validation-and-capture.md).
- Shader compilation, device data, and debugging recipes: [shaders-and-recipes.md](references/shaders-and-recipes.md).
- Exact `xctrace` syntax: [xctrace-quick-ref.md](references/xctrace-quick-ref.md).
- Focused recipes: [debugging-recipes.md](references/debugging-recipes.md).

The scripts in `scripts/` parse existing trace exports and capture bundles. Treat `.gputrace` parsing as best-effort because bundle internals can change. Verify important findings in Xcode or `gpudebug` when available.
