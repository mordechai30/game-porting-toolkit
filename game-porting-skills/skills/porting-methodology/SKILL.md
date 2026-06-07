---
name: porting-methodology
description: Core development methodology for porting games and engines to Apple platforms. Defines porting goals, milestone lifecycle, debugging escalation, and conventions. Preloaded by the porting agent.
---

# Platform Porting Methodology

## Overview

This skill defines **how** to approach an Apple platform port — the workflow, phases, conventions, and discipline. Domain-specific knowledge (Metal 4 API patterns, platform skills, anti-patterns, debugging strategies) lives in companion skills loaded alongside this one.

The methodology operates at two levels:
- **Porting goal** — a persistent objective spanning multiple sessions (e.g., "get the simplest sample running on Metal 4")
- **Milestone** — a bounded unit of work within a goal, completed in one session

**Core principle: collaboration.** This is a collaborative process between the agent and the user. The agent should surface decisions, trade-offs, and uncertainties to the user rather than making unilateral choices. When in doubt — ask. When deviating from convention — discuss. When stuck — escalate. The user has context the agent doesn't (reference implementations, project constraints, team preferences).

## References

- Engine-specific discovery report (produced by `porting-discover`, read at session start)
- Goal document and handoff notes (produced by this methodology, persist across sessions)

## Artifact Storage

**`<project-root>`** — the agent's current working directory, which is the root of the project being ported unless the user defines it otherwise.

All agent artifacts are stored in the agent's **artifact directory** at `<project-root>/.porting/`.

- **Discovery report:** `<project-root>/.porting/discovery-report.md`
- **Goal documents:** `<project-root>/.porting/goal-<name>.md`
- **Handoff notes:** `<project-root>/.porting/porting-handoff-<goal-name>-M<x>.md`
- **porting-memory.md:** `<project-root>/.porting/porting-memory.md`

**Handoff note naming includes the goal name** to prevent conflicts when multiple goals share the same milestone numbers (e.g., `handoff-basic-rendering-M2.md`, not `handoff-M2.md`).

### Session Start

At the start of every session — whether the user invokes a workflow skill or starts conversationally — do this before any other work:
1. Locate the **artifact directory**. If the directory does not exist, create it.
2. If **porting-memory.md** exists, read it. It carries the watch list, feature status, and prior-session context that must be in mind for this session.
3. If **porting-memory.md** does not exist, the project has not been discovered yet. Tell the user to run `/porting-discover` to bootstrap it.

---

## Porting Goals

A **porting goal** is the top-level organizational unit. It defines what you're trying to achieve and persists across multiple sessions and milestones.

### Pre-requisite

Before any goal can be created, `porting-discover` must have been run to analyze the target codebase and produce a discovery report with feature coverage matrix. This is a one-time step per codebase. After discovery completes, the agent should prompt the user to run `porting-plan-goal` to define the first porting goal.

### Goal Document

Every porting goal has a **goal document** stored in the agent's artifact directory (e.g., `goal-basic-rendering.md`). The agent reads this at the start of every session.

**Contents:**
- **Target:** What to port, what success looks like
- **Key decisions:** Language choice (ObjC vs metal-cpp vs C++), off-limits subsystems, scope constraints
- **Milestone tracker:** Which milestones are complete, which is current, what's next
- **Architecture notes:** Key codebase discoveries that apply across all milestones (buffer index partitioning, descriptor layout conventions, engine-specific patterns)
- **Selection rationale:** Why this target was chosen (simplest sample, exercises specific features, builds on prior goal)
- **Watch list and feature status** live in `porting-memory.md`, not in the goal document. See Phase 4: Handoff for update instructions.

### Goal Lifecycle

1. **Plan** — `porting-plan-goal` reads the discovery report and current porting state. Agent proposes a goal. User and agent negotiate scope, decisions, constraints. Goal document created.
2. **Execute** — Milestones within the goal. Each milestone follows the four-phase lifecycle (prepare/porting-execute/porting-validate/porting-handoff). One session per milestone, handoff notes bridge sessions.
3. **Complete** — All milestones done. Goal document updated with final status. Run `porting-plan-goal` again to propose the next porting goal.

### Goal Selection

When choosing the next porting goal:
- Start with the **simplest viable target** — the one that exercises the fewest backend features while still producing a visible, verifiable result
- Each subsequent goal should add a **bounded set of new features** on top of what's already ported
- The feature coverage matrix (from discovery) guides ordering: pick the goal with the smallest feature delta from the current state
- When the feature delta is primarily **one new capability** that the rest of the pipeline depends on (e.g., compute), consolidate milestones aggressively — don't create separate milestones for features that will work automatically once the core capability is implemented

---

## Milestones

A **milestone** is a bounded unit of work with a clear, verifiable success criterion. Each milestone is completed in one session and follows the four-phase lifecycle described below.

The specific milestones for each porting goal are defined during `porting-plan-goal` and tracked in the goal document. The number and scope of milestones varies by goal — a first goal that starts from scratch will have more milestones than a subsequent goal that builds on existing work.

### Milestone Principles

- **One targeted feature per milestone.** Each milestone should focus on a single capability (e.g., "depth buffer", "compute dispatch", "texture sampling", "windowing"). If a milestone touches more than one major feature, it's too large — split it. Measuring scope by file count or line count is misleading; a single feature can span many files.
- **Each milestone must have a clear success criterion** that can be verified before moving on (e.g., "project compiles", "screen clears to a color", "target renders completely").
- **The application must build and run at the end of every milestone.** The first milestones of the first porting goal are the exception — early milestones may target compilation and basic launch before the app can render anything.
- **Milestones should be ordered by dependency.** Each milestone builds on the previous one. Do not attempt features that depend on infrastructure not yet implemented.
- **One session per milestone.** If a milestone is too large for one session, split it into smaller milestones during planning.


### Recommended Bring-Up Order (First Porting Goal)

When creating the first porting goal for a codebase — where no Apple platform support exists — milestones split into two phases: **foundation** (platform infrastructure) and **rendering** (graphics backend). Skip foundation milestones that the engine already provides (check the discovery report's Platform Readiness).

**Foundation milestones** (platform skills):

| Milestone | Success Criterion | Skill to Load |
|---|---|---|
| M0: Build | Project compiles and links for macOS with stubs for unavailable subsystems | — |
| M1: Content Pipeline | All shaders compile to metallibs, all assets loadable | `creating-metal4-shader-pipelines` |
| M2: Window + Main Loop | Window opens, main loop ticks, frame callbacks fire | `setting-up-macos-window` |
| M3: Input | One input method functional (keyboard+mouse on macOS, controller on iOS) | `using-game-controller` |

**Rendering milestones** (domain skills):

| Milestone | Success Criterion |
|---|---|
| M4: Device + Capabilities | `MTLDevice` created, capabilities queried, engine GPU descriptor populated |
| M5: Presentation + First Clear | Full present pipeline working: command buffer → render pass → drawable → present |
| M6: Shader Loading + Pipelines | Pre-compiled shaders loaded, pipeline states created |
| M7: Vertex Drawing | First geometry on screen — vertex buffers, vertex descriptors, draw calls |
| M8: Full Scene | Textures, descriptors, index buffers, samplers, UI — target renders completely |
| M9: Polish | Barriers, queries, debug markers, resource labels, presentation/vsync, memory cleanup |

This sequence applies regardless of the source API (D3D12, Vulkan, OpenGL). Each step has a clear visual or behavioral success criterion. Subsequent porting goals build on existing infrastructure and will have fewer, more targeted milestones.

`porting-plan-goal` should use this sequence as a starting template for the first goal's milestones, adapting it based on what the engine already provides and what the discovery report recommends.

### Mandatory Early Tasks

These should be addressed as early as possible:

1. **Application builds and runs without crashing.** The first milestones should get the application building and running without crashes. This includes stubbing out unavailable subsystems so the application can link and run. If the engine lacks a macOS platform layer (windowing, input, content pipeline), these are handled as foundation milestones (M0-M3) using the corresponding platform skills — not deferred as "outside scope."

2. **Metal validation layers.** Load `using-metal-validation` for env-var setup, launch rule, and gotchas. Use validation layers as a diagnostic tool — run with them periodically and whenever you get stuck, as they often provide direct leads for fixing issues. During early milestones, validation errors from unimplemented features are expected and acceptable. Before completing a goal, all validation errors should be resolved.

3. **Debug markers and resource labels early.** If the engine already has debug marker and resource label calls in other backends (e.g., D3D12, Vulkan), implement the Metal equivalents early — `pushDebugGroup`/`popDebugGroup` on encoders for markers, `.label` on resources for labels. This is near-zero effort and makes GPU frame captures immediately useful. If the engine does not use debug markers in any backend, encourage adding them as a dedicated milestone — the debugging payoff is significant.

4. **Metal HUD enabled during development.** Set `MTL_HUD_ENABLED=1` for visual frame rate, GPU time, memory, and present mode feedback. Add `MTL_HUD_LOG_ENABLED=1` to log per-frame statistics to the console — the agent can parse this output to self-diagnose performance and presentation issues. Especially valuable when debugging frame pacing.

## Skill Loading

Before starting work on a milestone, load domain skills based on what the code needs. Load what's relevant — not everything.

| Working On | Load These Skills |
|---|---|
| Any rendering milestone | `translating-to-metal4-api`, `using-gpucapture`, `using-gpudebug`, `using-metal-validation`, `debugging-rendering-issues` |
| Window, main loop, display timing | `setting-up-macos-window` |
| Input, controllers, keyboard/mouse | `using-game-controller` |
| API translation, command buffers, encoders | `translating-to-metal4-api` |
| Buffers, textures, residency, storage modes | `managing-metal4-resources` |
| Shader conversion (HLSL/DXIL → metallib) | `compiling-with-metal-shaderconverter` |
| Shader compilation, pipeline states, PSOs | `creating-metal4-shader-pipelines` |
| Metal shader converter binding model, argument buffers | `integrating-metal-shaderconverter-shaders` |
| Barriers, fences, synchronization | `managing-metal4-synchronization` |
| Drawable presentation, vsync, frame pacing | `presenting-metal-drawables` |
| Object lifetimes, ARC, autorelease | `managing-metal-cpp-lifetimes` |
| Temporal upscaling, MetalFX | `using-metalfx-temporal-upscaler` |
| Frame interpolation, frame gen | `using-metalfx-frame-interpolation` |
| Rendering issues (blank screen, visual corruption, wrong colors) | `debugging-rendering-issues` |
| Metal validation, debug layer, shader validation | `using-metal-validation` |
| GPU frame capture | `using-gpucapture` |
| GPU trace inspection and analysis | `using-gpudebug` |

---

## Milestone Lifecycle — Four Phases

Every milestone follows this four-phase sequence. **The phases are strictly sequential and user-gated.** Each phase is collaborative — the agent and user will typically iterate back and forth (asking questions, reviewing output, requesting changes, providing feedback) before the phase is complete. The user signals that a phase is done and they're ready to move on by invoking the next phase's skill (`/porting-execute`, `/porting-validate`, `/porting-handoff`). The agent MUST NOT self-transition — only an explicit skill invocation from the user advances the phase.

**Phase transition rules:**
- `/porting-start-milestone` → agent and user collaborate on preparation → user invokes `/porting-execute` when satisfied
- `/porting-execute` → agent and user collaborate on implementation → user invokes `/porting-validate` when ready
- `/porting-validate` → agent and user collaborate on validation → user invokes `/porting-handoff` when passing
- `/porting-handoff` → agent writes handoff artifacts → session ends

**Always validate in a fresh session.** After completing Phase 2 (Execute), the agent should recommend committing work and starting a new session for `/porting-validate` and `/porting-handoff`. This ensures the validation checklist runs without being influenced by accumulated implementation context.

### Phase 1: Prepare

**Before writing any code.**

1. **Read the goal document** — big picture, decisions, what's done
2. **Read the previous milestone's handoff note** — where we left off, what's next, what to watch for. This is your memory from the last session.
3. **Study the code paths** that will change — read the functions, trace the call sites
4. **Identify work items** — grep for `STUB(Mx)` from previous milestones, check handoff note's deferred list
5. **Load and read relevant skills** based on what the code actually needs (not from a static table). You MUST actually read each skill's key sections — not just load it. Extract the specific patterns, API conventions, and anti-patterns that apply to this milestone's work items. Cite them in the preparation summary.
6. **Ask the user** about anything undiscoverable before starting — do not guess at conventions, magic numbers, or architectural decisions you can't verify from the codebase. Do NOT ask questions whose answers are in your loaded skills.

**Output:** A preparation summary for user review. Lists: what will change, which skills were loaded (with key patterns cited), what questions need answers, estimated scope.

**Gate: STOP. Do NOT write code. Do NOT proceed to Phase 2.** Wait for the user to review, answer questions, and invoke `/porting-execute`.

### Phase 2: Execute

**Writing code. The user has invoked `/porting-execute` giving explicit permission to proceed.**

Follow these conventions:

- **Match the engine's architecture and patterns.** Use its allocators, naming conventions, include ordering, struct layouts. If you see a reason to deviate from existing patterns, discuss with the user first and get approval.
- **Leverage existing engine systems.** Before implementing any subsystem (memory allocation, descriptor management, resource loading, synchronization, etc.), check if the engine already provides it. Use what exists rather than building parallel infrastructure. If an existing system doesn't fully meet Metal 4's needs, extend it rather than duplicating it.
- **Preserve existing backend code when editing shared files.** When modifying files that contain multiple backend implementations, read the full file first and verify that other backends' code paths remain intact after your changes. Do not overwrite or remove code belonging to other backends.
- **Minimize platform-divergent code duplication.** When a function differs between backends in only a few API calls, use surgical `#ifdef` (or the engine's platform macro) around the divergent calls rather than duplicating entire functions or large code blocks.
- **MUST consult loaded skills before implementing.** Before writing code for a subsystem, re-read the specific skill that covers it. Before asking the user a question, check if the answer is in a loaded skill. Skills contain curated, verified patterns — use them. Only go to SDK headers when the skill doesn't cover what you need.
- **Stub convention:** `// STUB(Mx): <what it is> — <what it should become>`. Example: `// STUB(M4): fake CPU backing memory — replace with [mtlBuffer contents] when real MTLBuffer is created`. This makes `grep "STUB(M4)"` produce an exact task list for milestone M4.
- **Hardcoded values:** If you hardcode a value to unblock progress, always comment what the correct source should be: `// HARDCODED: should read from pRasterizerState->mFrontFace (M3 fix)`
- **Use a debug build configuration.** Always develop and test with a debuggable build (assertions enabled, optimizations off, debug symbols included). This ensures crashes produce useful stack traces and assertions catch issues early.
- **Build often.** Compile after every few functions to catch issues early. Never leave the project in a non-compiling state.
- **Kill stale processes** before each build/run (`killall <app-name>` or equivalent) to avoid testing against old binaries.
- **Signal commit-worthy checkpoints.** When work reaches a stable state — a logical unit of functionality is complete and building cleanly — tell the user it is a good time to commit. The user manages version control; the agent's role is to clearly communicate when code is in a good state to preserve.
- **Leverage assertions liberally.** Add assertions (`ASSERT`, `NSCAssert`, `assert`, or whatever the engine uses) for preconditions, invalid states, and assumptions. Assertions catch problems at the point of origin rather than letting bad data propagate silently through the pipeline. They cost nothing in release builds and are invaluable during development.
- **Never run destructive git commands.** Do not `git checkout --`, `git reset --hard`, or `git clean` on files with uncommitted changes. Use targeted edits to remove debug code. If you need a clean state, `git stash` first.

**Gate: STOP when implementation is complete.** Tell the user: "Milestone implementation complete. Run `/porting-validate` to begin the validation pass." Do NOT start validation yourself. Do NOT blend execute and validate. Do NOT declare completion until the success criterion is verified at runtime — if the app crashes, it is NOT done.

### Phase 3: Validate

**Before the milestone's final commit.** The milestone's work is functionally complete. Mid-milestone commits for stable checkpoints are fine, but this full validation pass should happen before closing out the milestone.

**Reload skills first.** Validation often runs in a fresh session. Reload `porting-methodology`, domain skills used during execution, and — for rendering milestones — `using-gpucapture` and `using-gpudebug`. Do NOT attempt GPU capture or skill-driven review from memory.

Run through this checklist:

1. **The app must run.** From M1 onward, the app must build, launch, and execute the milestone's success criterion. Do not declare a milestone complete based on code review alone — verify at runtime. Run with a debugger attached (lldb) to catch issues that don't surface from terminal launches. If you cannot attach a debugger, ask the user to run from Xcode.
2. **Metal validation layers** — Load `using-metal-validation` for env-var setup, launch rule, and gotchas. Fix errors caused by this milestone's changes. Errors from features not yet implemented can be noted and deferred. Before the final milestone of a goal, all validation errors must be resolved.
3. **Visual correctness** — Take a screenshot and analyze it. Ask the user to visually verify rendering output. Metal validation does not catch wrong-but-valid states (wrong format, wrong color space, wrong blend mode). The user must confirm the visual result matches expectations.
4. **GPU frame capture — MANDATORY for rendering milestones.** YOU MUST capture and analyze a GPU frame for any milestone that touches rendering. Do NOT skip. Load `using-gpucapture` and `using-gpudebug` first. If capture tools are unavailable, ask the user to capture via Xcode. Check bound resources per draw/dispatch, output texture contents, pass structure.
5. **Reference artifact comparison** — If the discovery report includes reference artifacts (translation-layer GPU frame capture, RenderDoc XML), compare the native port's current output against them. Check render pass structure, draw/dispatch counts, and visual output. Use `using-gpudebug` for autonomous comparison. Record findings for the handoff note.
6. **Memory leaks** — Three categories to check:
   - *C/C++ heap leaks* — Use the engine's own memory tracking if available (many engines report leaks on exit). Otherwise use ASan or `MallocStackLogging`. Run ASan at least once per milestone.
   - *ObjC/ARC leaks* — Occur when `id<...>` members in C-allocated structs are not nil'd before `free()`. Every `exit*`/`remove*` function must nil all ObjC members before freeing. If leaks are suspected, ask the user to run Xcode's Leaks instrument or the `leaks` command-line tool.
   - *GPU memory leaks* — Metal resources (`MTLBuffer`, `MTLTexture`, etc.) not released. Monitor the Metal HUD memory counter during development — if it grows continuously, resources are leaking. For deeper analysis, ask the user for Xcode's Memory Graph Debugger.
7. **Skill-driven review** — For each skill loaded this milestone, re-read its guidance sections — look for any of: Anti-Patterns, Common Mistakes, Common Pitfalls, Troubleshooting, Best Practices, Good Practices. Review your code against each item found. Flag any violations. Report findings.
8. **Trace the data** — For every struct member you wrote to, grep for all read sites and verify the value is consumed correctly. For every struct member you read, verify it was written. This catches the storage/consumption mismatch pattern (storing a value in one code path but forgetting to read it in the corresponding path).
9. **Review own code** — Walk through every changed function. Look for: missing nil-before-free, missing error handling, wrong enum mappings, silent fallback defaults that mask bugs, code accidentally removed during edits, trivially fixable deprecated API calls.
10. **Refactor pressure hacks** — If you introduced any shortcuts or hacks during debugging pressure in Phase 2, clean them up now.
11. **Add deferred work markers** — Any known gaps get `STUB(Mx)` or `TODO` comments with clear descriptions.
12. **Request user review** — Present a summary of changes and ask the user to review and provide feedback before the final milestone commit.

**Gate: STOP after presenting validation results.** Wait for the user to review and invoke `/porting-handoff`.

### Phase 4: Handoff

**Before session ends.** Prompt the user to commit any uncommitted work first.

Write a **handoff note** — a structured document the agent reads at the start of the next session. This is the agent's persistent memory between sessions.

**Storage:** `<project-root>/.porting/porting-handoff-<goal-name>-M<x>.md` (e.g., `handoff-basic-rendering-M2.md`)

**Contents:**
- **What was done** — one-paragraph summary of the milestone
- **Ground truth comparison** — full report of reference artifact checks from validation: which artifacts were compared, what matched, what diverged, whether divergences are expected or need investigation. This persists the rendering correctness baseline for the user and future sessions.
- **What's deferred** — specific TODOs and STUBs created, with grep patterns (e.g., `grep "STUB(M3)"`)
- **Known issues** — bugs, artifacts, validation warnings not yet fixed
- **Watch for** — things that will trip you up next milestone (e.g., "removeTexture doesn't nil the ObjC pointer", "mUploadBufferAlignment is hardcoded to 64, should query device")
- **Key decisions made** — why something was done a certain way, so the next session doesn't undo it
- **Skills needed next** — which skills the agent should load for the next milestone

The handoff note also serves as a **supervision checkpoint** — the user can review and correct it before the next session.

**Before writing the handoff note:** Update the agent's `porting-memory.md`:
- **Watch list** — promote any unresolved issues, known risks, or critical notes from this milestone. Remove items that were resolved.
- **Feature status** — update which feature domains were implemented or progressed during this milestone. Mark domains as implemented, partially implemented, or stubbed.

`porting-memory.md` is expected to be in context, and so do the watch list and feature status. If not yet, read it. The handoff note is milestone-specific and may not be read again.

**After writing the handoff:** Request the user to start a fresh session for the next milestone.

---

## Session Model

**One session per milestone.** This is a deliberate design choice:

- Each milestone focuses on one feature, producing a bounded set of changes that can be reviewed and committed as a unit.
- Persistent artifacts (handoff notes, commits, goal documents) are exact and permanent — they survive across sessions without degradation.
- The handoff note ensures nothing is lost at the session boundary.
- The prepare phase ensures the next session starts fully informed.

**Session startup protocol:**
1. Read goal document
2. Read latest handoff note
3. Enter Phase 1: Prepare

**Always validate in a fresh session.** After Phase 2 (Execute) is complete, commit current work and start a new session for `/porting-validate` and `/porting-handoff`. This ensures the validation pass approaches the code with fresh eyes, independent of the implementation session.

---

## Debugging Escalation

When stuck, follow this escalation ladder.

**What counts as an attempt:** An attempt is a hypothesis-driven fix — you have a specific theory for why something is broken, you make a targeted change to test it, and it fails. Normal iterative work (compile fixes, typo corrections, adjusting parameters you know are wrong) does not count. Only count fixes where you had a hypothesis and the result disproved it.

**Count your attempts explicitly.** Each time you test a hypothesis for the same issue, state: "Attempt N of 5 for [issue]: hypothesis is [X]." When you reach attempt 5 and it fails, you MUST escalate. Do not rationalize that the next try is "a different approach" — if the same symptom persists, it is the same issue.

### Before debugging — check your skills

**MUST re-read loaded skills relevant to the failing subsystem before investigating.** Skills contain verified patterns and known pitfalls. The fix may already be documented. Do not exhaust debugging hypotheses before checking skills.

### After 5 failed hypotheses — escalate to user

**Self-check:** If you are trying random permutations of an API call without a clear hypothesis for why each change should work, you have no hypothesis — STOP and escalate immediately.

**Visual bugs (wrong rendering, artifacts, flickering):**
→ Present your findings to the user — what you observed, what self-service diagnostics (frame captures, screenshots, validation layers) revealed, and what you've tried. Ask the user for guidance, a different reproduction scenario, or to inspect the frame capture in Xcode for details the agent couldn't determine autonomously.

**Compute shader issues (black textures, wrong results, silent failures):**
→ Present your frame capture analysis findings to the user. Compute shader debugging often requires inspecting bound resources, dispatch dimensions, and output contents in Xcode's GPU debugger — details that may be beyond what the agent can determine autonomously.

**Undiscoverable conventions (magic numbers, index partitioning, engine-specific constants):**
→ Ask the user for the specific value or pattern. These may exist only in stripped reference code or internal documentation the agent cannot access.

**Build failures after multiple attempts:**
→ Ask the user to review the error output. The agent may be missing context about build system configuration.

### Self-service diagnostics (use at any time, no escalation needed)

- **Metal validation layers** — run them yourself, read the error messages, fix what they report. See `using-metal-validation` for setup and gotchas.
- **Metal HUD** — enable `MTL_HUD_ENABLED=1` for visual overlay, add `MTL_HUD_LOG_ENABLED=1` to log per-frame stats to console for automated analysis
- **GPU frame capture and analysis** — if `using-gpucapture` and `using-gpudebug` skills are available, capture and analyze a frame autonomously whenever it would help diagnose the issue (visual bugs, resource binding questions, pass structure verification). Use your judgment — don't wait for a specific attempt count. If the analysis identifies the issue, fix it. If inconclusive, include the findings when escalating to the user.
- **Screenshots** — take a screenshot (`screencapture` on macOS) and analyze it visually. Useful for quick checks on rendering output without a full frame capture.
- **Debugger (lldb)** — attach to the running process or launch under lldb. Set breakpoints at crash sites, suspect code paths, or resource creation points. Inspect variable state, step through logic, and examine backtraces. Prefer the debugger over log-and-run cycles — it's faster and more precise. Use `breakpoint set`, `watchpoint set`, `frame variable`, `expression` as needed.
- **Console logs** — add targeted debug log statements using whatever logging the engine provides (but remove them before commit). Prefer the debugger when you need to inspect state at a specific point — logging is better for tracing flow across many frames.
- **Process check** — kill stale processes before re-running
- **Debugging skills** — search for available debugging-related skills (e.g., `debugging-rendering-issues`, `using-gpudebug`, `using-gpucapture`) and load any that match the symptom you're investigating. These skills contain targeted diagnostic procedures for specific classes of issues.

### Signs you're stuck in a loop

- You've added and removed the same debug log statement more than twice
- You're trying random permutations of an API call without a clear hypothesis
- The same visual artifact persists after multiple attempted fixes
- You're reading the same header file for the third time looking for something that isn't there
- You're asking the user questions whose answers are in your loaded skills

When you recognize these patterns, **stop and escalate**. Describe what you observe vs. what you expect, and what you've already tried.

---

## Anti-Patterns

Concrete, checkable statements. During Phase 3 (Validate), review your code against each:

1. **Do not take architectural shortcuts to avoid implementing the correct path.** Always use the correct approach for the problem, even if a simpler workaround exists. For example, using `StorageModeShared` for textures that should be `Private` avoids implementing a staging buffer copy, but breaks GPU-optimal tiled format on Apple Silicon. When the correct path seems complex, discuss with the user rather than working around it.

2. **Do not hardcode values without comments.** Every hardcoded constant must have a comment explaining the correct source and which milestone fixes it.

3. **Do not guess at undiscoverable conventions.** If you can't find a value in the codebase (buffer index partitions, magic numbers, engine-specific constants), ask the user. Guessing leads to subtle bugs.

4. **Do not proceed after asking a question.** If you ask the user a question, STOP and WAIT for their answer. Do not continue working while waiting. This is the single most impactful workflow discipline rule.

5. **Do not loop on hypothesis-free debugging.** If you have no clear hypothesis for why a change should fix the issue, stop and form one before making the change. After 5 failed hypotheses, escalate per the debugging escalation section above.

6. **Do not defer debug infrastructure.** Debug markers, resource labels, and validation layers should be implemented as early as possible, not deferred as polish. Implement them first.

7. **Do not store data without consuming it.** If you add a field to a struct and write to it, verify that all corresponding read sites use it (and vice versa). This is the "trace the data" check in Phase 3.

8. **Do not pass consumed range when accessible range is needed.** Metal 4's address-based APIs that take GPU address + length pairs expect the full valid range the GPU may access, not just the bytes this specific operation reads. Getting this wrong causes silent data clamping, not crashes.

9. **Default to using engine systems.** If the engine has allocators, ring buffers, descriptor abstractions, or resource management — use them. Port to the engine's architecture, not around it. If an engine system is inadequate for Metal 4's requirements, discuss alternatives with the user before building something new.

10. **Do not skip Phase 3 validation.** Committing without running validation layers periodically, checking leaks, and reviewing against skill anti-patterns leads to bugs that compound across milestones.

11. **Do not self-transition between phases.** Each phase ends with a STOP gate. Wait for the user to invoke the next phase's skill. Do not blend execute into validate, or validate into handoff.

12. **Do not declare milestone completion while the app crashes.** The success criterion MUST be verified at runtime before declaring implementation complete. Do NOT rationalize crashes as "pre-existing" or "unrelated" without proof. If the app crashes, investigate.
