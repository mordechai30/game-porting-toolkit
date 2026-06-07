# Tier 3 — Data Inspection

- [ ] 1. Texture sampling issues
- [ ] 2. UV origin difference
- [ ] 3. Vertex / input buffer data
- [ ] 4. Uniform / constant buffer data
- [ ] 5. HDR headroom / EDR
- [ ] 6. Shader output range assumptions
- [ ] 7. Compute pass feeding render pass

## Gotchas

- **#5:** Apple uses EDR where SDR is 0.0–1.0 and HDR extends above 1.0. D3D12 and Vulkan use different HDR swapchain models.
