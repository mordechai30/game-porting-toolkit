# Session Workflow

## Overview

Resolve helper paths from this skill folder when you run them from another directory.

This skill enables Metal GPU profiling, debugging, and shader analysis on macOS using Apple's command-line toolchain. The primary tools are:

- **`xctrace`** — CLI for Instruments; records Metal System Traces, exports GPU data as XML
- **`xcrun metal`** — Metal shader compiler toolchain (compile, archive, link)
- **Metal environment variables** — validation layers, Performance HUD, programmatic capture
- **`log`** — macOS unified logging for Metal HUD and validation output
- **`parse_gputrace.py`** — CLI tool for extracting buffer/texture data from `.gputrace` captures

### Prerequisites

Before any Metal debugging, verify the environment:

```bash
# Check Xcode is installed (full Xcode, not just Command Line Tools)
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer

# Check xctrace is available
xcrun xctrace version

# Check Metal compiler
xcrun -sdk macosx metal --version

# List available GPU devices (requires a Swift/ObjC helper or Python)
system_profiler SPDisplaysDataType | grep -A5 "Chipset\|Metal"
```

**IMPORTANT**: `xctrace` and Metal tools require **full Xcode**, not just Command Line Tools.

## 1. Automated Session Lifecycle

Every Metal debugging session follows a strict pipeline: **Doctor → Record → Export → Parse → Analyze → Report**. Codex should execute the requested steps, then retain the trace and analysis output unless the user asks to remove them.

### Step 0: Doctor — Verify environment

**Run this FIRST before any debugging session.** If any check fails, stop and tell the user what's missing.

```bash
# Create working directories
mkdir -p ./traces/analysis

# Verify toolchain
xcode-select -p                          # Must show Xcode.app path, NOT CommandLineTools
xcrun xctrace version                    # Must succeed
xcrun -sdk macosx metal --version        # Must succeed
system_profiler SPDisplaysDataType | grep -i "metal\|chipset"  # GPU info

# For iOS: check connected devices
xcrun xctrace list devices 2>/dev/null   # List all available targets

# Check parse helper is available
python3 -c "import xml.etree.ElementTree" 2>/dev/null && echo "XML parser OK"
```

**If `xcode-select -p` returns `/Library/Developer/CommandLineTools`**, tell the user:
```
Xcode Command Line Tools is installed but full Xcode is required.
Install from: https://developer.apple.com/xcode/
Then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Step 1: Record — Capture a Metal System Trace

Choose the right recording mode based on the user's request:

```bash
# MODE A: Launch and profile (most common)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 10s \
  --no-prompt \
  --output ./traces/capture.trace \
  --launch -- /path/to/app [args...]

# MODE B: Attach to running process
xcrun xctrace record \
  --template 'Metal System Trace' \
  --attach <PID_OR_NAME> \
  --time-limit 10s \
  --no-prompt \
  --output ./traces/capture.trace

# MODE C: With validation enabled (for debugging errors)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --env MTL_DEBUG_LAYER=1 \
  --env MTL_SHADER_VALIDATION=1 \
  --time-limit 10s \
  --no-prompt \
  --output ./traces/capture.trace \
  --launch -- /path/to/app

# MODE D: iOS device (over USB)
xcrun xctrace record \
  --template 'Metal System Trace' \
  --device '<DEVICE_NAME_OR_UDID>' \
  --attach <APP_NAME> \
  --time-limit 10s \
  --no-prompt \
  --output ./traces/capture.trace
```

**Decision guide:**
- User says "profile my app" → Mode A
- User says "it's already running" → Mode B
- User says "I'm getting errors" or "something is wrong" → Mode C
- User mentions iPhone/iPad → Mode D

**IMPORTANT**: Always use `--no-prompt` for automation. Always use `--time-limit` (default 10s, adjust if user specifies). Always use `--output` with explicit path.

### Step 2: Export — Extract structured data from trace

First discover what's in the trace, then export the relevant tables.

```bash
# 2a. Get table of contents (ALWAYS do this first)
xcrun xctrace export --input ./traces/capture.trace --toc \
  > ./traces/analysis/toc.xml

# 2b. Show available schemas to decide what to export
grep 'schema=' ./traces/analysis/toc.xml

# 2c. Export Metal GPU driver events (primary data source)
xcrun xctrace export --input ./traces/capture.trace \
  --output ./traces/analysis/gpu_events.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-driver-event-intervals"]'

# 2d. Export GPU hardware counters (if available — Apple Silicon)
xcrun xctrace export --input ./traces/capture.trace \
  --output ./traces/analysis/gpu_counters.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-intervals"]' \
  2>/dev/null || echo "No GPU counter data in this trace"

# 2e. Export Metal GPU execution intervals (if available)
xcrun xctrace export --input ./traces/capture.trace \
  --output ./traces/analysis/gpu_intervals.xml \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
  2>/dev/null || echo "No GPU interval data in this trace"
```

**Schema availability varies** by Xcode version, template, and GPU. Always check the TOC first and export what's there. Don't fail if a schema is missing — report what was found.

### Step 3: Parse — Convert XML to structured data

Use the `parse_trace.py` helper (included in this repo) or inline Python to extract actionable data.

```bash
# Summary of what was captured
python3 scripts/parse_trace.py ./traces/analysis/gpu_events.xml --summary

# Get structured data as JSON
python3 scripts/parse_trace.py ./traces/analysis/gpu_events.xml --format json --limit 50

# Get as TSV for scanning
python3 scripts/parse_trace.py ./traces/analysis/gpu_events.xml --format tsv --limit 30

# If parse_trace.py is not available, use inline Python:
python3 << 'PARSE_SCRIPT'
import xml.etree.ElementTree as ET
import json

tree = ET.parse('./traces/analysis/gpu_events.xml')
root = tree.getroot()

# Build ref resolution map
id_map = {}
for elem in root.iter():
    eid = elem.get('id')
    if eid is not None:
        id_map[eid] = elem

def resolve(elem):
    ref = elem.get('ref')
    if ref and ref in id_map:
        return id_map[ref]
    return elem

def get_val(elem):
    r = resolve(elem)
    return r.get('fmt', r.text or '')

rows = root.findall('.//row')
print(f"Total events: {len(rows)}")

# Parse first 30 rows into dicts
parsed = []
headers = None
for row in rows[:30]:
    cols = list(row)
    if headers is None:
        headers = [c.tag for c in cols]
    entry = {headers[i]: get_val(c) for i, c in enumerate(cols)}
    parsed.append(entry)

print(json.dumps(parsed, indent=2))
PARSE_SCRIPT
```

### Step 4: Analyze — Interpret the data

After parsing, Codex should analyze the results and look for:

**Performance profiling:**
- GPU busy time per frame (>16ms = below 60fps, >8ms = below 120fps)
- Large wire memory events (excessive per-frame resource allocation)
- Gaps between GPU submissions (CPU-bound)
- Long shader execution intervals (complex shaders)
- Imbalanced encoder durations (one pass dominating)

**Validation errors:**
- Pattern-match stderr and log output for Metal error codes
- Classify errors: API misuse vs shader bug vs resource issue
- Map errors to specific command encoders via labels

**Shader issues:**
- Compile-time warnings/errors from `xcrun metal`
- Runtime validation errors from `MTL_SHADER_VALIDATION`

### Step 5: Report — Present findings to user

Structure the report as:
1. **Environment**: GPU model, macOS version, device (Mac/iOS)
2. **Summary**: Total events, recording duration, overall health
3. **Key findings**: Sorted by severity (errors → warnings → info)
4. **Specific data**: Relevant numbers, event counts, durations
5. **Recommendations**: Concrete next steps

### Complete automated workflow example

This is what Codex should execute end-to-end when a user says "profile my Metal app":

```bash
#!/bin/bash
set -e
APP_PATH="$1"
TRACE_DIR="./traces"
ANALYSIS_DIR="$TRACE_DIR/analysis"

# Doctor
mkdir -p "$ANALYSIS_DIR"
xcode-select -p >/dev/null 2>&1 || { echo "ERROR: Xcode not found"; exit 1; }
xcrun xctrace version >/dev/null 2>&1 || { echo "ERROR: xctrace not available"; exit 1; }

# Record
echo "Recording Metal System Trace (10s)..."
xcrun xctrace record \
  --template 'Metal System Trace' \
  --time-limit 10s \
  --no-prompt \
  --output "$TRACE_DIR/capture.trace" \
  --launch -- "$APP_PATH"

# Export TOC
echo "Exporting trace data..."
xcrun xctrace export --input "$TRACE_DIR/capture.trace" --toc \
  > "$ANALYSIS_DIR/toc.xml"

# Export all available Metal tables
for schema in metal-driver-event-intervals gpu-counter-intervals metal-gpu-intervals; do
  if grep -q "schema=\"$schema\"" "$ANALYSIS_DIR/toc.xml"; then
    echo "Exporting $schema..."
    xcrun xctrace export --input "$TRACE_DIR/capture.trace" \
      --output "$ANALYSIS_DIR/${schema}.xml" \
      --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$schema\"]"
  fi
done

# Parse and summarize
echo "Analyzing..."
for xml in "$ANALYSIS_DIR"/*.xml; do
  [ "$xml" = "$ANALYSIS_DIR/toc.xml" ] && continue
  echo "=== $(basename "$xml") ==="
  python3 scripts/parse_trace.py "$xml" --summary 2>/dev/null || \
    python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$xml')
rows = tree.getroot().findall('.//row')
print(f'  Rows: {len(rows)}')
"
done

echo "Done. Analysis files in $ANALYSIS_DIR/"
```

### Parallel workflows: Validation + Profiling + Logs

Codex can run multiple debugging streams simultaneously for maximum signal:

```bash
# Record trace with all validation layers AND HUD logging in one shot
xcrun xctrace record \
  --template 'Metal System Trace' \
  --env MTL_DEBUG_LAYER=1 \
  --env MTL_SHADER_VALIDATION=1 \
  --env MTL_HUD_ENABLED=1 \
  --env MTL_HUD_LOGGING_ENABLED=1 \
  --time-limit 10s \
  --no-prompt \
  --output ./traces/full_debug.trace \
  --launch -- /path/to/app 2> ./traces/analysis/stderr.log &

TRACE_PID=$!

# Simultaneously capture Metal logs from unified log
log stream --predicate 'subsystem == "com.apple.Metal"' \
  --timeout 15 > ./traces/analysis/metal_log.txt 2>/dev/null &

LOG_PID=$!

# Wait for trace to finish
wait $TRACE_PID

# Give log stream a moment then stop it
sleep 2
kill $LOG_PID 2>/dev/null

# Now analyze ALL data sources:
echo "=== Validation Errors (stderr) ==="
grep -i "error\|warning\|invalid\|fault" ./traces/analysis/stderr.log || echo "None"

echo "=== Metal Log Entries ==="
wc -l < ./traces/analysis/metal_log.txt
grep -i "error" ./traces/analysis/metal_log.txt || echo "No errors in log"

echo "=== Trace Data ==="
xcrun xctrace export --input ./traces/full_debug.trace --toc
```

### Session state awareness

Unlike RenderDoc's daemon model (open/close), xctrace sessions are **fire-and-forget**: each `record` command runs to completion, and the resulting `.trace` file is a self-contained snapshot. This means:

- **No session to manage** — no open/close, no daemon, no leaked processes
- **Multiple traces can coexist** — name them meaningfully (before.trace, after.trace)
- **Traces are immutable** — once recorded, they don't change
- **Export is idempotent** — re-export the same trace as many times as needed
- **Cleanup is just file deletion** — `rm` the .trace bundle when done
