# Shaders And Recipes

## 7. Metal Shader Compilation

Compile, validate, and inspect Metal shaders from the command line.

### Compile shaders

```bash
# Compile .metal to intermediate representation (.air)
xcrun -sdk macosx metal -c MyShader.metal -o MyShader.air

# With warnings and debug info
xcrun -sdk macosx metal -c -gline-tables-only -Weverything MyShader.metal -o MyShader.air

# Archive
xcrun -sdk macosx metal-ar rcs MyShader.metalar MyShader.air

# Link into a Metal library (.metallib)
xcrun -sdk macosx metallib MyShader.metalar -o MyShader.metallib

# One-step compile + link
xcrun -sdk macosx metal MyShader.metal -o MyShader.metallib
```

### Cross-compile for specific targets

```bash
# List available GPU architectures
xcrun metal-arch

# Target specific platform
xcrun -sdk iphoneos metal -c Shader.metal -o Shader.air
xcrun -sdk macosx metal -c -target air64-apple-macos14 Shader.metal -o Shader.air
```

### HLSL to Metal (via shader converter)

```bash
# Convert HLSL → DXIL → Metal IR
dxc shaders.hlsl -T vs_6_0 -E MainVS -Fo vertex.dxil
metal-shaderconverter vertex.dxil -o vertex.metallib
```

### Validate shaders without running

```bash
# Compile with all warnings — catches issues at build time
xcrun -sdk macosx metal -c -Weverything -Werror MyShader.metal -o /dev/null

# Check Metal version compatibility
xcrun -sdk macosx metal -c -std=metal3.0 MyShader.metal -o /dev/null
```

## 8. GPU Device Information

```bash
# System-level GPU info
system_profiler SPDisplaysDataType

# Metal feature set / GPU family (grep for relevant info)
system_profiler SPDisplaysDataType | grep -E "Chipset|Metal|VRAM|GPU"
```

## 9. Debugging Recipes

### Recipe: Profile GPU performance

```bash
# 1. Record a Metal System Trace
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 10s \
  --output perf.trace \
  --launch -- /path/to/app

# 2. See what data is available
xcrun xctrace export --input perf.trace --toc

# 3. Export GPU driver events
xcrun xctrace export --input perf.trace \
  --output gpu_events.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'

# 4. Export GPU counters (if available)
xcrun xctrace export --input perf.trace \
  --output gpu_counters.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-intervals"]'

# 5. Open in Instruments for visual analysis
open perf.trace
```

### Recipe: Find shader compilation errors

```bash
# 1. Compile with maximum warnings
xcrun -sdk macosx metal -c -Weverything -Werror MyShader.metal -o /dev/null 2>&1

# 2. If it compiles, check at runtime with validation
MTL_SHADER_VALIDATION=1 /path/to/app 2>&1 | tee shader_errors.log

# 3. Check logs for shader validation errors
log show --predicate 'subsystem == "com.apple.Metal"' --last 5m --level error
```

### Recipe: Detect Metal API misuse

```bash
# 1. Run with API validation
MTL_DEBUG_LAYER=1 /path/to/app 2>&1 | tee api_errors.log

# 2. Record with validation for post-mortem analysis
xcrun xctrace record \
  --template 'Metal System Trace' \
  --env MTL_DEBUG_LAYER=1 \
  --time-limit 10s \
  --output validated.trace \
  --launch -- /path/to/app

# 3. Check for errors
grep -i "error\|warning\|invalid\|violation" api_errors.log
```

### Recipe: Monitor real-time performance

```bash
# 1. Enable HUD with logging
MTL_HUD_ENABLED=1 MTL_HUD_LOGGING_ENABLED=1 /path/to/app &
APP_PID=$!

# 2. Stream performance data
log stream --predicate 'subsystem == "com.apple.Metal" AND category == "HUD"' &

# 3. When done, stop
kill $APP_PID
```

### Recipe: Capture a frame for Xcode debugging

```bash
# For Vulkan apps (via MoltenVK)
METAL_CAPTURE_ENABLED=1 \
MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=2 \
MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE=/tmp/frame.gputrace \
/path/to/vulkan/app

# Open in Xcode Metal Debugger
open /tmp/frame.gputrace
```

### Recipe: Debug Metal rendering issues (visual + data)

Use the **Autonomous Metal Debugging Workflow** in Section 6. It covers screenshot capture, .gputrace analysis, source code reading, shader compilation, and the fix/verify loop — with fallbacks when buffer data is unavailable.

### Recipe: Compare performance before/after a change

```bash
# 1. Record baseline
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 10s \
  --output before.trace \
  --launch -- /path/to/app

# 2. Make your change, rebuild

# 3. Record after
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 10s \
  --output after.trace \
  --launch -- /path/to/app

# 4. Export both and compare
xcrun xctrace export --input before.trace --output before.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'
xcrun xctrace export --input after.trace --output after.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'

# 5. Diff the XML or parse with Python for numerical comparison
```

## 10. Output Size Management

Metal System Traces can be very large. Follow these rules:

1. **Use `--time-limit`**: Always limit recording duration (5-10s is usually enough)
2. **Export specific schemas**: Use `--xpath` to extract only the data you need
3. **Use `--toc` first**: Understand what's in the trace before bulk-exporting
4. **Pipe through filters**: Use `grep`, `xmllint`, or Python to extract specific data
5. **Retain traces by default**: `.trace` bundles can be 100MB+; ask before deleting them

## 11. Limitations vs RenderDoc

| Capability | Metal Skill | RenderDoc Skill |
|-----------|-------------|-----------------|
| Frame capture | ✅ .gputrace | ✅ .rdc (full CLI) |
| GPU profiling | ✅ xctrace + export | ⚠️ GPU counters if available |
| Shader compilation | ✅ xcrun metal | N/A (different workflow) |
| Validation errors | ✅ env vars + log stream | ✅ API validation layer |
| Performance HUD | ✅ MTL_HUD_ENABLED | N/A |
| Buffer inspection (CLI) | ⚠️ Xcode-initiated captures only | ✅ rdc buffer |
| Buffer statistics | ⚠️ Xcode-initiated captures only | ❌ |
| Draw call inspection | ❌ Xcode only | ✅ rdc draws/pipeline |
| Pixel history | ❌ Xcode only | ✅ rdc pixel |
| Shader step-through | ❌ Xcode only | ✅ rdc debug pixel |
| Render target export | ❌ Xcode only | ✅ rdc rt → PNG |
| Texture readback (CLI) | ⚠️ MTLTexture files (if present) | ✅ Full rdc-cli API |
| Visual output inspection | ✅ in-app saveTexture or screencapture | ❌ (headless only) |

**Key difference**: Metal debugging is split between CLI (profiling/validation/buffer inspection) and GUI (Xcode for draw calls, pixel history, shader debugging). The label injection technique with `parse_gputrace.py` partially bridges this gap by enabling CLI buffer/texture data inspection from `.gputrace` captures. RenderDoc still provides more complete CLI access.

## Command Reference

For the complete xctrace command reference, see [references/xctrace-quick-ref.md](xctrace-quick-ref.md).

For extended debugging recipes, see [references/debugging-recipes.md](debugging-recipes.md).
