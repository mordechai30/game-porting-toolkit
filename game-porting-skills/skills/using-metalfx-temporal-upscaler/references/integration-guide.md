# MetalFX Temporal Scaler Integration Guide

## API Reference

### MTLFXTemporalScalerDescriptor

| Property | Type | Description |
|----------|------|-------------|
| inputWidth/Height | NSUInteger | Render resolution |
| outputWidth/Height | NSUInteger | Display resolution |
| colorTextureFormat | MTLPixelFormat | RGBA16Float recommended |
| depthTextureFormat | MTLPixelFormat | Depth32Float or R32Float |
| motionTextureFormat | MTLPixelFormat | RG16Float |
| outputTextureFormat | MTLPixelFormat | RGBA16Float |

### MTLFXTemporalScalerBase (per-frame properties — shared by Metal 3 and Metal 4)

These properties live on the shared `MTLFXTemporalScalerBase` protocol, inherited by both `MTLFXTemporalScaler` (Metal 3) and `MTL4FXTemporalScaler` (Metal 4).

| Property | Type | Description |
|----------|------|-------------|
| colorTexture | id<MTLTexture> | Input color at render resolution |
| depthTexture | id<MTLTexture> | Depth buffer at render resolution |
| motionTexture | id<MTLTexture> | Motion vectors at render resolution |
| outputTexture | id<MTLTexture> | Upscaled output at display resolution |
| jitterOffsetX/Y | float | Pixel-space jitter (-0.5 to +0.5) |
| motionVectorScaleX/Y | float | Converts raw MV to pixel displacement |
| inputContentWidth/Height | NSUInteger | Active content area within input textures |
| reset | BOOL | Reset temporal history (first frame, scene cuts) |

### Device Support Check
```objc
if (![MTLFXTemporalScalerDescriptor supportsDevice:device]) { /* fallback */ }
```

---

## Texture Format Requirements

| Texture | Format | Usage Flags | Storage |
|---------|--------|-------------|---------|
| Color input | RGBA16Float | RenderTarget \| ShaderRead | Private |
| Depth input | Depth32Float | RenderTarget \| ShaderRead | Private |
| Motion input | RG16Float | RenderTarget \| ShaderRead | Private |
| **Output** | RGBA16Float | **RenderTarget \| ShaderRead \| ShaderWrite** | Private |

The output texture MUST have `MTLTextureUsageShaderWrite` because MTLFXTemporalScaler writes to it via internal compute shaders.

---

## Jitter Sequences

### Halton Sequence
```c
float halton(int index, int base) {
    float result = 0.0f, f = 1.0f / (float)base;
    int i = index;
    while (i > 0) { result += f * (i % base); i /= base; f /= base; }
    return result;
}
// Usage: jitterX = halton(frameIndex + 1, 2) - 0.5f;
//        jitterY = halton(frameIndex + 1, 3) - 0.5f;
```

### Phase Count by Scale Factor
| Scale | Phases | Formula |
|-------|--------|---------|
| 1.0x (AA) | 8 | Anti-alias only |
| 1.5x | 18 | Quality |
| 2.0x | 32 | Performance |
| 3.0x | 72 | Ultra-performance |
| Custom | ceil(8 * n²) | General formula |

### Jitter Coordinate Spaces
- **Pixel space** (for MetalFX): raw Halton values, range (-0.5, +0.5)
- **Clip space** (for vertex shader): `clipJitterX = 2 * pixelJitter / renderWidth`, `clipJitterY = -2 * pixelJitter / renderHeight` (negate Y for Metal's Y-up clip space)
- Apply in vertex shader: `position.xy += jitterOffset * position.w`

---

## Motion Vector Conventions

### What MetalFX expects
- Screen-space pixel displacement
- `pixelMotion = rawMotionVector * motionVectorScale`
- Positive X = rightward, Positive Y = downward

### Computing in the shader
- Output NDC delta: `motion = prevNDC - currentNDC` (where the pixel was in the previous frame)
- `prevNDC = prevClipPos.xy / prevClipPos.w`, `currentNDC = currentClipPos.xy / currentClipPos.w`
- Set `motionVectorScaleX = renderWidth * 0.5`, `motionVectorScaleY = renderHeight * 0.5`
  - This converts NDC delta (range [-2,2]) to render-resolution pixel delta
  - If your engine produces MVs at display resolution instead, substitute `displayWidth` / `displayHeight` so the result is still input-resolution pixels

### Important rules
- Motion vectors may be jittered or unjittered — use whichever matches your engine's convention; MetalFX supports both
- On a completely static scene with static camera, motion should be exactly zero everywhere
- Motion vectors may be at render or display (upscaled) resolution — set `motionVectorScale` so that `rawMV * motionVectorScale` yields input-resolution pixels

---

## Troubleshooting

### Black output
- **Cause**: Output texture missing `MTLTextureUsageShaderWrite`
- **Fix**: Add `ShaderWrite` to the output texture's usage flags
- This is the #1 gotcha — MetalFX writes via compute, no error is reported

### Screen shaking / "screen door" pattern
- **Cause**: Jitter Y sign wrong
- **Fix**: Negate Y when converting to clip space: `clipJitterY = -2 * jitterY / renderHeight`

### Ghosting / smearing on moving objects
- **Cause**: Motion vector scale wrong or signs inverted
- **Fix**: Verify `rawMV * motionVectorScale` yields input-resolution pixels with correct sign

### Blurry output / reduced detail
- **Cause**: Too few jitter phases for the scale factor
- **Fix**: Use correct phase count (32 for 2x, 72 for 3x)

### Blurry textures specifically
- **Cause**: Missing negative mip bias
- **Fix**: Apply `mipBias = log2(renderRes / displayRes) - 1.0` to texture sampling
  - 1.5x → -1.58, 2.0x → -2.00, 3.0x → -2.58

### Scaler returns nil
- **Cause**: Device doesn't support MetalFX, or invalid descriptor configuration
- **Fix**: Check `[MTLFXTemporalScalerDescriptor supportsDevice:]` before creating

### Corruption after scene cuts
- **Cause**: Missing reset flag
- **Fix**: Set `scaler.reset = YES` on first frame, scene transitions, camera teleports

### Motion vectors include jitter when the scaler expects unjittered
- **Cause**: Vertex positions used for MV computation are jittered, but the scaler is configured to expect unjittered MVs
- **Fix**: Either compute MVs from unjittered clip positions (apply jitter separately to `position` output only), or configure the scaler to expect jittered MVs — pick whichever matches your engine

---

## Depth Conventions

| Convention | Near | Far | depthCompareFunction | reversedDepth |
|------------|------|-----|---------------------|---------------|
| Standard | 0.0 | 1.0 | Less | NO |
| Reversed-Z | 1.0 | 0.0 | GreaterEqual | YES |

Reversed-Z provides better depth precision at distance and is recommended for MetalFX, but standard depth works fine.

---

## Scale Factor Reference

| Scale | Render Resolution | Jitter Phases | Use Case |
|-------|-------------------|---------------|----------|
| 1.0x | Native | 8 | Anti-aliasing only |
| 1.5x | 67% | 18 | Quality mode |
| 2.0x | 50% | 32 | Performance (most common) |
| 3.0x | 33% | 72 | Maximum performance |
