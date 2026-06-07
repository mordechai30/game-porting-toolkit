# Game Porting Toolkit Evaluation and Trace Collection

Reference document for `porting-discover`. Covers Game Porting Toolkit evaluation, GPU frame capture, and trace collection/analysis.

## Apple Platform Resources

- **Apple Games overview** — https://developer.apple.com/games/
- **Game Porting Toolkit** — https://developer.apple.com/games/game-porting-toolkit/
- **Metal documentation** — https://developer.apple.com/documentation/metal?language=objc
- **Metal sample code** — https://developer.apple.com/metal/sample-code/
- **Metal developer tools** — https://developer.apple.com/metal/tools/

## Game Porting Toolkit Evaluation

Before native porting begins, evaluate the game using Game Porting Toolkit. Run the unmodified Windows binary on macOS via Game Porting Toolkit's evaluation environment for Windows games. This is a triage step — observe what works, what breaks, what's slow. You can test the game and validate it's shaders.

What to look for:

- **Shader performance** — which shaders are slow? Same Metal IR the native port will use.
- **CPU-GPU synchronization** — excessive fences, pipeline stalls, per-frame readbacks
- **Precision issues** — artifacts in physics, animation, or rendering from floating-point differences
- **Rendering correctness** — missing features, broken blending, culling issues
- **Crash points** — which subsystems fail (narrows platform dependencies)
- **Performance profile** — CPU-bound vs GPU-bound, heaviest subsystems

### Parallel workstreams from evaluation environment findings

Game Porting Toolkit's evaluation environment can unlock work that runs in parallel with the native port:

- **Shader optimization** — heaviest shaders transfer directly to the native port
- **CPU-GPU synchronization fixes** — excessive pipeline flushes, redundant barriers, GPU readbacks that stall frames
- **Precision and correctness bugs** — wrong results under Metal's precision model will exist in the native port too
- **Rendering pipeline optimization** — broken or slow render passes can be investigated from the engine side
- **Asset and shader pipeline issues** — assets or shader variants that fail to convert can be fixed from source content

## GPU Frame Capture from the evaluation environment

The most valuable evaluation environment artifact — rendering ground truth for validation comparison during the native port.

**If the user has an existing `.gputrace`:** Ask for the path. Record it in the Reference Artifacts table.

**If the user can run the game using the evaluation environment now:**
1. User launches the game using the evaluation environment with `MTL_CAPTURE_ENABLED=1` set
2. User navigates to a representative scene (good geometry, lighting, post-processing visible)
3. User tells the agent they're ready
4. Agent finds the game process and captures a gputrace

For detailed gputrace capture mechanics, load the `using-gpucapture` skill.

**The agent cannot launch games using the evaluation environment** — the user must launch and navigate to the right scene. The agent captures when signaled.

## RenderDoc XML Capture (from Windows)

The developer captures a frame with RenderDoc on Windows and exports as "XML + ZIP Capture" (File → Export). Most useful from a debug/development build with PIX markers and shader debug info.

The XML contains:
- **PIX debug markers** (`BeginEvent`/`EndEvent`) — the engine's own render pass hierarchy
- **Every draw call and dispatch** with full parameters
- **Pipeline state bindings** — which shaders, root signatures, and resources are bound per draw
- **Resource creation** — all buffers, textures, heaps with dimensions and formats
- **Command list submission structure** — how the engine batches work

Parse the XML to extract the frame hierarchy:
- `ID3D12GraphicsCommandList::BeginEvent` / `EndEvent` — render pass structure
- `ID3D12GraphicsCommandList::DrawIndexedInstanced` / `DrawInstanced` — geometry draws
- `ID3D12GraphicsCommandList::Dispatch` — compute dispatches
- `ID3D12GraphicsCommandList::ExecuteIndirect` — indirect draws/dispatches
- `ID3D12CommandQueue::ExecuteCommandLists` — submission boundaries

This gives the exact per-frame rendering pipeline — which passes exist, what order they run, how many draws/dispatches each contains. Cross-reference pass names against the source code to locate implementations.

## Metal System Trace (from macOS using the Game Porting Toolkit's evaluation environment)

CPU and GPU timeline with Metal encoder data. Requires the game running under the evaluation environment on a representative scene.

```bash
# Find the game process
ps aux | grep -i <game_name>

# Capture trace
xcrun xctrace record --template "Metal System Trace" \
    --attach <PID> --time-limit 10s \
    --output <game>.trace
```

Export key tables:

```bash
# Metal encoder intervals (per-encoder GPU timing)
xcrun xctrace export --input <game>.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]'

# Metal application intervals (CPU-side encoder creation timing)
xcrun xctrace export --input <game>.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-intervals"]'

# Encoder list with frame boundaries
xcrun xctrace export --input <game>.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-encoders-list"]'

# CPU time profile
xcrun xctrace export --input <game>.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'

# Signpost intervals (fence/sync events)
xcrun xctrace export --input <game>.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]'
```

Determine:
- **CPU vs GPU bound** — compare CPU frame time (time-profile) vs GPU frame time (metal-gpu-intervals). If GPU finishes before CPU submits the next frame, the game is CPU-bound.
- **CPU-GPU synchronization problems** — GPU idle gaps between encoders (metal-gpu-intervals), signpost wait events, CPU threads blocked on GPU completion
- **Encoder structure** — how many command buffers per frame, how work is batched (metal-application-encoders-list)

## Memgraph (from macOS with Game Porting Toolkit's evaluation environment)

Process memory snapshot.

```bash
leaks --outputGraph=<game>.memgraph <PID>
```

Analyze:

```bash
vmmap --summary <game>.memgraph    # VM region breakdown
heap <game>.memgraph               # heap allocation summary
footprint <game>.memgraph          # physical memory footprint
```

Look for:
- **GPU residency strategy** — IOAccelerator region sizes inform MTLHeap sizing
- **UMA waste** — separate CPU/GPU copies of the same data (unnecessary on Apple unified memory)
- **Sync-related staging buffers** — upload/readback heaps that may be eliminable in native port
- **Leaks and suspicious allocations** — `leaks <game>.memgraph`
- **Custom allocators vs malloc** — informs whether the engine's allocator strategy needs porting or can be simplified

## Using Traces in the Discovery Report

Each trace type grounds specific findings:

- **RenderDoc XML** — use PIX marker hierarchy to identify every render pass, draw/dispatch counts, submission order. This becomes the roadmap for rendering bring-up.
- **Metal System Trace** — GPU encoder timing identifies heaviest passes. CPU vs GPU bound informs optimization focus. Encoder structure informs Metal command buffer strategy.
- **Memgraph** — physical footprint informs residency strategy. UMA waste patterns inform what to simplify in native port.
- **GPU frame capture** — rendering ground truth. During validation, the native port's output can be compared against this reference.

If the developer provides traces, the discovery report must be grounded in them — not generic assumptions.
