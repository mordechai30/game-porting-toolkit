# Metal AI Skill

This repository provides Metal GPU debugging assets for Codex.

## Skills

Use `metal-gpu-debug` for Metal profiling, validation, shader compilation, frame
capture, or MoltenVK debugging. Read its relevant reference file only when the
task needs a detailed command or recipe.

## MCP server

The project MCP server is `metal-tools`. It runs local Apple development tools
and can create traces, captures, and build outputs. Confirm the target app,
output path, duration, and device before starting a capture or profiling run.
Do not delete traces or captures unless the user asks.

`metal_command` is disabled in the project configuration. Use a specialized
Metal tool instead. Enable it only when the user needs a command that no
specialized tool supports.

## Requirements

Use macOS with full Xcode. Check `xcode-select -p`, `xcrun xctrace version`,
and `xcrun -sdk macosx metal --version` before a Metal debugging session.
