---
name: porting-execute
description: Begin writing code for the current milestone. This is the explicit go-signal after /porting-start-milestone preparation has been reviewed and approved by the user.
disable-model-invocation: false
---

You are entering Phase 2: Execute for the current milestone. The user has reviewed and approved the preparation summary from `/porting-start-milestone`.

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there. Load the `porting-methodology` skill if not already in context.

## Begin Implementation

Implement the approved work items from the preparation summary. Follow the Phase 2 conventions from the methodology (matching engine patterns, leveraging existing systems, consulting loaded skills, stub/hardcoded conventions, building often, assertions).

The approved prep summary is the **scope contract**. Focus exclusively on the listed work items.

If you discover unexpected work that wasn't identified during preparation, **stop and tell the user** before implementing it. Present what you found and collaborate on the right response:

- Does it fit naturally into an existing future milestone? → Stub it with the appropriate `STUB(Mx)` marker.
- Does the goal's milestone plan need new milestones to accommodate it? → Propose specific additions to the plan.
- Is it a small prerequisite that blocks the current work item? → Ask the user to approve adding it to the current scope.

Do not silently expand scope. Do not blindly defer everything — think about where the work belongs.

## During Implementation

- **Re-read relevant skills before implementing each major subsystem.** Do not rely on memory from the preparation phase. Before writing code for a subsystem (e.g., argument buffer binding, render pass descriptors, barrier synchronization), actually open and re-read the specific skill that covers it — including any reference files you loaded for the current subsystem. Specifically look for **Anti-Patterns, Common Mistakes, Common Pitfalls, and Best Practices** sections and apply them as you write the code — do not defer these to validation. The answer to your next question is probably already in a loaded skill. Do NOT ask the user questions that are answered in your skills.
- **Label everything.** Every buffer, texture, render target, and pipeline should have a meaningful `.label`. Every render pass should have `pushDebugGroup`/`popDebugGroup` markers. This is not polish — it's infrastructure that makes all debugging possible.
- **Write comments that explain why, not what.** `// Must be called once per encoder — calling twice causes a crash` is useful. `// Call the function` is not.
- **Take screenshots frequently** (`screencapture` on macOS) during rendering work. Use them to verify correctness and catch regressions as you work — don't wait until the milestone is "done" to check visual output.
- **Test with the simplest reproduction.** When debugging, reduce to the simplest case that shows the bug. Disable UI, disable post-processing, render a single object — whatever isolates the issue.
- **Run with Metal validation periodically.** Load `using-metal-validation` for env-var setup, launch rule, and gotchas. Fix errors caused by your changes. Errors from unimplemented features can be noted and deferred.
- **Use Metal HUD** (`MTL_HUD_ENABLED=1`, `MTL_HUD_LOG_ENABLED=1`) when debugging presentation or frame pacing.

When debugging, **re-read the loaded skills relevant to the failing subsystem before investigating.** Skills contain verified patterns and known pitfalls — the fix may already be documented. Do not exhaust debugging hypotheses before checking skills. Follow the escalation rules from the methodology. Count attempts explicitly. Use the right diagnostic for the problem — code review and the debugger for CPU-side issues, GPU frame capture and analysis (load `/using-gpucapture` and `/using-gpudebug` skills) when the issue is on the GPU side or involves resource binding, and `debugging-rendering-issues` when you need a structured diagnostic workflow for visual bugs.

## Rendering Milestone Completion Check

For milestones that touch rendering, before declaring the milestone done:

1. **Verify the success criterion is met.** The app MUST run without crashing and produce the expected output. If the app crashes, it is NOT done — investigate before claiming completion. Do NOT rationalize crashes as "pre-existing" or "unrelated" without proof.
2. **Take a final screenshot** and verify the output matches the milestone's success criterion.
3. **Capture and analyze at least one GPU frame.** Load the `/using-gpucapture` skill (for capturing) and `/using-gpudebug` skill (for analysis) — these contain the required environment variables, API calls, and procedures. Attempt this autonomously to confirm resource bindings, pass structure, and output are correct. This catches issues invisible to screenshots alone — wrong textures bound, empty buffers, missing descriptor entries. If GPU capture tools are unavailable or the capture fails, ask the user to capture a frame via Xcode and share the `.gputrace` for analysis.
4. If the frame capture reveals issues from **unimplemented features** (belonging to future milestones), note them as deferred work — do not expand scope to fix them.

## macOS Environment Quirks

These can block app relaunches from the terminal:

- **Crash reporter dialogs** block re-launch. Suppress with: `defaults write com.apple.CrashReporter DialogType none`
- **Window restoration prompts** block re-launch. Suppress with: `defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false`
- **Permission dialogs** (file access, network) may appear on first launch. Ask the user to grant them manually if they block progress.
- **Stale processes** may hold resources (GPU, window server connections). Always `killall` before re-running.

## Do NOT

- Do not proceed after asking the user a question — STOP and wait for their answer.
- Do not silently implement work outside the approved prep summary — stop and discuss with the user.
- Do not self-transition to Phase 3 (Validate). Wait for the user.
- Do not declare completion until the success criterion is verified at runtime. App crashes = NOT done.

## When Done

When all work items for this milestone are implemented and building cleanly, tell the user:

> "Milestone implementation complete. I recommend committing current work and starting a fresh session for validation. Run `/porting-validate` to begin the validation pass."

**STOP.** Do NOT begin validation yourself. Do NOT blend execute and validate. The user will invoke `/porting-validate` when ready.
