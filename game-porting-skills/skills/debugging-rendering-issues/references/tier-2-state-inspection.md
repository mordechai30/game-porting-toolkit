# Tier 2 — State Inspection

- [ ] 1. Render target / attachment mismatch
- [ ] 2. Depth / stencil state
- [ ] 3. Depth format mismatch
- [ ] 4. Depth bias / polygon offset
- [ ] 5. Blend state
- [ ] 6. sRGB / color space
- [ ] 7. Pixel format translation errors
- [ ] 8. Pipeline state object
- [ ] 9. Resource bindings
- [ ] 10. Resource residency
- [ ] 11. Sampler state translation
- [ ] 12. Double/triple buffering race
- [ ] 13. Render pass ordering
- [ ] 14. Transparency draw order

## Gotchas

- **#3:** `DXGI_FORMAT_D24_UNORM_S8_UINT` not universally supported on Apple GPUs — query `MTLDevice.isDepth24Stencil8PixelFormatSupported`. Default to `MTLPixelFormatDepth32Float_Stencil8`.
- **#4:** Depth bias units differ across APIs and change between D24 and D32F formats. Bias values need rescaling after porting.
- **#5:** D3D blend enum integer values differ from Metal — don't cast directly.
