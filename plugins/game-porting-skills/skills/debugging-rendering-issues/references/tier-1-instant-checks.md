# Tier 1 — Instant Checks

- [ ] 1. No frame presented
- [ ] 2. No rendering work encoded
- [ ] 3. Load action / clear color
- [ ] 4. Store action
- [ ] 5. Viewport / scissor rect
- [ ] 6. Backface culling / winding order
- [ ] 7. Color write mask

## Gotchas

- **#3:** Quick test — `.clear` with non-black color and you see that color? Nothing drew. Problem is draw calls, not the pass.
- **#6:** Y-axis flip in projection reverses winding — apply only one correction. Quick test — geometry appears with `cullMode: .none` but disappears with `.back`? Winding is wrong.
- **#7:** D3D `D3D12_COLOR_WRITE_ENABLE` and Vulkan `VkColorComponentFlags` to `MTLColorWriteMask` — naive cast can drop channels.
