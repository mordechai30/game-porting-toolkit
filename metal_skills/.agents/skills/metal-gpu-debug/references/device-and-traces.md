# Device And Traces

## 2. iOS Device Support

`xctrace` can profile Metal apps on physical iOS/iPadOS devices over USB or Wi-Fi.

### List connected devices

```bash
xcrun xctrace list devices
# Shows: Mac, connected iPhones/iPads, simulators
```

### Record on iOS device

```bash
# By device name
xcrun xctrace record \
  --template 'Metal System Trace' \
  --device 'iPhone 15 Pro' \
  --attach MyApp \
  --time-limit 10s \
  --output ios_trace.trace

# By UDID (more reliable)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --device 00008110-XXXXXXXXXXXX \
  --attach MyApp \
  --time-limit 10s \
  --output ios_trace.trace

# Launch app on device (must be installed)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --device 'iPhone 15 Pro' \
  --time-limit 10s \
  --output ios_trace.trace \
  --launch -- com.yourcompany.yourapp
```

### iOS-specific notes

- Device must be **unlocked** and **trusted** by the Mac
- App must be installed on device (use Xcode or `ios-deploy`)
- `--launch` uses **bundle identifier** (not path) on iOS
- `--attach` uses **process name** or PID
- Export/parse works identically — the `.trace` format is the same
- Shader compilation for iOS uses `-sdk iphoneos`:
  ```bash
  xcrun -sdk iphoneos metal -c Shader.metal -o Shader.air
  ```
- `.gputrace` capture on iOS requires Xcode attached to the device

## 3. Metal System Trace — Record & Export

Metal System Trace is the primary tool for GPU profiling. It captures CPU/GPU timeline, driver events, shader execution, and hardware counters.

### Record a trace

```bash
# Profile a running app by name
xcrun xctrace record \
  --template 'Metal System Trace' \
  --attach <PID_OR_NAME> \
  --time-limit 5s \
  --output trace.trace

# Launch and profile
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 5s \
  --output trace.trace \
  --launch -- /path/to/your/app [args...]

# With environment variables (e.g., enable validation)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --env MTL_DEBUG_LAYER=1 \
  --env MTL_SHADER_VALIDATION=1 \
  --time-limit 5s \
  --output trace.trace \
  --launch -- /path/to/your/app
```

Key options:
- `--time-limit 5s` — auto-stop after duration (supports ms, s, m, h)
- `--attach PID` — attach to running process
- `--all-processes` — trace all Metal apps system-wide
- `--env VAR=value` — set environment variables for launched process
- `--target-stdout -` — redirect app stdout to terminal
- `--no-prompt` — skip prompts (useful in scripts)

### Other useful templates

```bash
# List all available templates
xcrun xctrace list templates
# Key Metal-relevant templates:
#   - Metal System Trace    (GPU timeline, driver events, counters)
#   - Game Performance       (Metal + display + thermal)
#   - Counters               (hardware performance counters)
#   - GPU                    (GPU-focused template, if available)
```

### Export trace data as XML

```bash
# See what's in the trace (table of contents)
xcrun xctrace export --input trace.trace --toc

# Export Metal driver events (GPU work intervals, wire memory, etc.)
xcrun xctrace export --input trace.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'

# Export to file instead of stdout
xcrun xctrace export --input trace.trace \
  --output metal_events.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'

# Export GPU counter data
xcrun xctrace export --input trace.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-intervals"]'
```

### Common Metal table schemas

| Schema | Contains |
|--------|----------|
| `metal-driver-event-intervals` | Metal driver events (GPU work, wire memory, resource events) |
| `gpu-counter-intervals` | Hardware GPU performance counters |
| `metal-gpu-intervals` | GPU execution intervals per encoder |
| `time-profile` | CPU time profiling samples |

**TIP**: Always run `--toc` first to see available schemas — they vary by template, Xcode version, and GPU.

### Parse exported XML

The XML uses a reference system to avoid duplication. Nodes with `id` attributes are originals; nodes with `ref` attributes point back to them.

```bash
# Quick extraction with xmllint or python
xcrun xctrace export --input trace.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]' \
  | python3 -c "
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.stdin)
for row in tree.findall('.//row'):
    print([col.get('fmt', col.text or '') for col in row])
"
```
