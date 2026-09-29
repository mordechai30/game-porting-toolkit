# Validation And Capture

## 4. Metal Validation Layers

Runtime error detection for Metal API misuse and shader bugs.

### Enable via environment variables

```bash
# API Validation — catches Metal API misuse
export MTL_DEBUG_LAYER=1

# Shader Validation — instruments shaders to detect GPU-side errors
export MTL_SHADER_VALIDATION=1

# Combined: launch app with both
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 /path/to/your/app
```

### Enable via xctrace

```bash
xcrun xctrace record \
  --template 'Metal System Trace' \
  --env MTL_DEBUG_LAYER=1 \
  --env MTL_SHADER_VALIDATION=1 \
  --time-limit 10s \
  --output validated.trace \
  --launch -- /path/to/your/app
```

### Read validation errors

Validation errors appear in stderr and in macOS unified log:

```bash
# Stream Metal validation errors live
log stream --predicate 'subsystem == "com.apple.Metal"' --level error

# Search recent logs
log show --predicate 'subsystem == "com.apple.Metal"' --last 5m
```

### Programmatic validation log access

If you're writing Metal code, `commandBuffer.logs` provides structured error info after completion — encoder label, debug location (file + line), and error classification.

## 5. Metal Performance HUD

Real-time overlay showing FPS, frame time, GPU time, memory usage.

### Enable

```bash
# Per-process via environment variable
MTL_HUD_ENABLED=1 /path/to/your/app

# System-wide (all Metal apps)
/bin/launchctl setenv MTL_HUD_ENABLED 1
# Disable:
/bin/launchctl unsetenv MTL_HUD_ENABLED

# Enable HUD data logging to syslog
MTL_HUD_ENABLED=1 MTL_HUD_LOGGING_ENABLED=1 /path/to/your/app
```

### Parse HUD log data

When `MTL_HUD_LOGGING_ENABLED=1`, metrics are logged to the system log:

```bash
# Stream HUD metrics
log stream --predicate 'subsystem == "com.apple.Metal" AND category == "HUD"'

# Export recent HUD data
log show --predicate 'subsystem == "com.apple.Metal" AND category == "HUD"' --last 1m
```

HUD metrics include: FPS, present interval (frame time), GPU time, process memory, GPU memory, display refresh rate, direct vs composited rendering path.

## 6. Programmatic Frame Capture (.gputrace)

Capture Metal frames to `.gputrace` files without Xcode attached, then inspect buffer/texture data from CLI.

### Via environment variables (MoltenVK / any Metal app)

```bash
# For Vulkan apps via MoltenVK:
export METAL_CAPTURE_ENABLED=1
export MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=2          # 1=device lifecycle, 2=first frame
export MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE=/tmp/capture.gputrace
/path/to/vulkan/app

# For native Metal apps (requires Info.plist MetalCaptureEnabled=true
# or METAL_CAPTURE_ENABLED=1 environment variable):
METAL_CAPTURE_ENABLED=1 /path/to/metal/app
```

### Via MTLCaptureManager (in-app)

For apps you control, add capture support using MTLCaptureManager. See `capture_frame.swift` for a complete example. The key pattern for adding capture to an existing app:

```swift
let captureManager = MTLCaptureManager.shared()
if captureManager.supportsDestination(.gpuTraceDocument) {
    let descriptor = MTLCaptureDescriptor()
    descriptor.captureObject = device
    descriptor.destination = .gpuTraceDocument
    descriptor.outputURL = URL(fileURLWithPath: "./capture.gputrace")
    try captureManager.startCapture(with: descriptor)

    // ... encode and submit Metal work ...

    captureManager.stopCapture()
}
```

Run with: `METAL_CAPTURE_ENABLED=1 ./your_app`

### Open .gputrace in Xcode

```bash
open /tmp/capture.gputrace
# Opens in Xcode's Metal Debugger with full inspection capabilities:
# - Draw call list and stepping
# - Pipeline state at each draw
# - Texture/buffer inspection
# - Shader debugging
# - Performance profiling
# - Dependency viewer
```

### Autonomous Metal Debugging Workflow

When debugging a Metal rendering issue, Codex executes the requested workflow. It gathers data from multiple sources in parallel when that is safe, then branches based on what data is available.

#### Step 1: Gather all signal sources (run in parallel)

Launch these data-gathering steps simultaneously — they are independent:

```bash
# A. Screenshot the app's rendered output
./build_and_run.sh --screenshot        # preferred: in-app framebuffer readback
# OR: screencapture -w -x output.png   # fallback: macOS window capture

# B. Capture .gputrace (programmatic)
METAL_CAPTURE_ENABLED=1 ./your_app     # produces capture.gputrace

# C. Compile shaders with maximum warnings
xcrun -sdk macosx metal -c -Weverything Shaders.metal -o /dev/null 2>&1

# D. Read source code — Codex reads .metal files and Swift renderer code directly
```

#### Step 2: Analyze the capture

```bash
# 2a. List all resources and shader functions
python3 scripts/parse_gputrace.py capture.gputrace

# 2b. Check what data files exist in the capture
ls capture.gputrace/MTLBuffer-* 2>/dev/null && echo "BUFFER DATA AVAILABLE" || echo "NO BUFFER FILES"
ls capture.gputrace/MTLTexture-* 2>/dev/null && echo "TEXTURE DATA AVAILABLE" || echo "NO TEXTURE FILES"
```

**Branch on buffer availability:**

- **MTLBuffer files exist** (Xcode-initiated captures): Parse buffer data directly
  ```bash
  python3 scripts/parse_gputrace.py capture.gputrace --buffer "Vertex" --layout float4 --index 0-10
  python3 scripts/parse_gputrace.py capture.gputrace --dump-all
  ```
- **No MTLBuffer files** (typical for programmatic captures): Fall back to source code analysis
  - Read the Swift/ObjC code that creates and fills buffers
  - Read the `.metal` shader code that consumes the buffers
  - The capture metadata still tells you what resources exist and what shaders run — use this as an inventory to guide source code reading
- **MTLTexture files exist**: Read raw texture data for render target analysis

#### Step 3: Diagnose from all available sources

Combine signal from every source gathered in Steps 1–2. Each source catches different bug categories:

| Source | What it reveals | Bug categories |
|--------|----------------|----------------|
| **Screenshot** | Visual output | Wrong colors, flipped geometry, missing faces, transparency issues, blank screen |
| **Source code** (.metal + Swift) | Logic and data flow | Wrong vertex data, shader math errors, incorrect pipeline config, buffer layout mismatches |
| **Capture metadata** | Resource inventory | Confirms what buffers/textures exist, shader function names, resource labels |
| **Shader compilation warnings** | Static analysis | Unused variables, implicit conversions, potential precision issues |
| **Validation errors** (if enabled) | API correctness | Mismatched formats, missing bindings, out-of-bounds access, shader faults |

**Decision logic when buffer data is unavailable:**
- If no `MTLBuffer` files → Codex reads source code to understand vertex data, uniform values, and buffer layouts
- If no `MTLTexture` files → Codex uses screenshot for visual inspection of rendered output
- Programmatic captures always provide: resource labels, shader function names, texture snapshots (render targets)

#### Step 4: Fix and verify

```bash
# 1. Apply fixes to source code (.metal shaders, Swift renderer)

# 2. Rebuild and screenshot
./build_and_run.sh --screenshot

# 3. Compare before/after visually (Codex reads output.png)

# 4. If still wrong, repeat from Step 1
```

The loop continues until the screenshot shows correct output or the user is satisfied.

### Label Injection

Codex should ensure every Metal object has a `.label` set in source code. Labels are preserved in `.gputrace` captures and enable resource identification from CLI.

```swift
// Add .label to every MTLBuffer, MTLTexture, MTLCommandBuffer, MTLCommandEncoder
vertexBuffer.label = "Vertex Buffer"
colorBuffer.label = "Color Buffer"
uniformBuffer.label = "Uniform Buffer"
commandBuffer.label = "Frame \(frameNumber)"
encoder.label = "Main Render Pass"
```

**Rules:**
- Use descriptive names with spaces (e.g., "Particle Buffer" not "particleBuf")
- Labels with spaces are reliably distinguishable from binary data in the `.gputrace`
- Never remove existing labels — only add missing ones
- Add labels to every object that lacks one

### Reference: parse_gputrace.py usage

```bash
# List all captured resources with their labels
python3 scripts/parse_gputrace.py capture.gputrace

# Read specific buffer by label (partial match works)
python3 scripts/parse_gputrace.py capture.gputrace --buffer "Color Output" --layout float4 --index 100

# Read compound struct (e.g., Particle = position + velocity + color)
python3 scripts/parse_gputrace.py capture.gputrace --buffer "Particle" --layout "float4,float4,float4" --index 0-10

# Dump summary statistics for all buffers
python3 scripts/parse_gputrace.py capture.gputrace --dump-all

# Output as JSON
python3 scripts/parse_gputrace.py capture.gputrace --buffer "Color Output" --layout float4 --index 100 --json
```

#### Supported layout types

| Layout | Bytes | Example |
|--------|-------|---------|
| `float` | 4 | Scalar energy, distance, time |
| `float2` | 8 | UV coordinates |
| `float3` | 12 | Position, normal (without padding) |
| `float4` | 16 | RGBA color, position+mass, SIMD4 |
| `uint32` | 4 | Index, count |
| `int32` | 4 | Signed integer |
| `float4,float4,float4` | 48 | Compound struct (e.g., Particle) |

### Reference: .gputrace internal structure

| File | Format | Contents |
|------|--------|----------|
| `MTLBuffer-{id}-{snap}` | Raw binary (IEEE 754 LE) | GPU buffer memory snapshot |
| `MTLTexture-{id}-{snap}` | Raw binary | GPU texture memory snapshot |
| `metadata` | Binary plist | Session UUID, API, device info |
| `device-resources-*` | MTSP binary | Resource registry with labels, shader names |
| `store0` | zlib-compressed MTSP | Encoded command buffer data |
| `capture` / `unsorted-capture` | MTSP binary | Metal API call sequences |
| `index` | Custom (`xdic` magic) | File table / hash table |

### Reference: CLI capabilities by capture type

| Capability | CLI (programmatic capture) | CLI (Xcode-initiated capture) | Xcode GUI |
|-----------|---------------------------|------------------------------|-----------|
| List resources with labels | ✅ | ✅ | ✅ |
| List shader function names | ✅ | ✅ | ✅ |
| Read texture/render target data | ✅ (MTLTexture files present) | ✅ | ✅ |
| Read buffer contents at index | ❌ (no MTLBuffer files) | ✅ | ✅ |
| Buffer statistics (min/max/mean) | ❌ | ✅ | ❌ (manual) |
| Draw call stepping | ❌ | ❌ | ✅ |
| Pixel history | ❌ | ❌ | ✅ |
| Shader step-through | ❌ | ❌ | ✅ |
| Pipeline state inspection | ❌ | ❌ | ✅ |
| Dependency viewer | ❌ | ❌ | ✅ |
| Command buffer replay | ❌ | ❌ | ✅ |

### Reference: Screenshot capture techniques

#### Method 1: In-app auto-screenshot (Preferred)

The most reliable approach is to add a `--screenshot` mode to the app itself. This renders a few frames, reads back the framebuffer texture, and saves it as a PNG — no external tools required.

**Swift code to add to your Metal app:**

```swift
// Add to your renderer class:
static func saveTexture(_ texture: MTLTexture, to path: String) {
    let w = texture.width, h = texture.height
    let bytesPerRow = w * 4
    var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
    texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                     from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: w, height: h, depth: 1)),
                     mipmapLevel: 0)
    // BGRA → RGBA, force alpha to 255 for screenshot visibility
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let tmp = pixels[i]
        pixels[i] = pixels[i + 2]
        pixels[i + 2] = tmp
        pixels[i + 3] = 255
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: bytesPerRow, bitsPerPixel: 32)!
    memcpy(rep.bitmapData!, &pixels, pixels.count)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}
```

**Usage in the draw loop** (save after a few frames, then exit):

```swift
// In draw(in:) after cb.present(drawable) and cb.commit():
if frameCount == 3 && screenshotMode {
    cb.waitUntilCompleted()
    Self.saveTexture(drawable.texture, to: "./output.png")
    print("Screenshot saved: ./output.png")
    DispatchQueue.main.async { NSApp.terminate(nil) }
}
```

**Important**: Set `metalView.framebufferOnly = false` before rendering to allow texture readback.

#### Method 2: macOS screencapture (Fallback)

If the app doesn't support `--screenshot`, use macOS `screencapture` to capture the window:

```bash
# Launch the app in background
./your_app &
APP_PID=$!
sleep 1

# Capture the app's window (-w = frontmost window, -x = no sound)
screencapture -w -x /tmp/screenshot.png

# Stop the app
kill $APP_PID 2>/dev/null
```
