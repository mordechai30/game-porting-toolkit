# HDR and Color Space Configuration

Detail on HDR pixel-format / colorspace pairings and EDR headroom queries. The SKILL.md body covers the basic SDR vs HDR choice; load this file when configuring HDR output, switching color spaces at runtime, or tone-mapping against EDR headroom.

## Pixel format and colorspace pairing

The pixel format and colorspace on `CAMetalLayer` must be paired correctly. Set `wantsExtendedDynamicRangeContent = YES` to enable HDR output.

```objc
// SDR — standard sRGB
metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
metalLayer.wantsExtendedDynamicRangeContent = NO;
metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

// HDR — 10-bit PQ (better bandwidth; engine shader writes PQ-encoded values)
metalLayer.pixelFormat = MTLPixelFormatBGR10A2Unorm;
metalLayer.wantsExtendedDynamicRangeContent = YES;
metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3_PQ);

// HDR — 16-bit float (engine shader writes linear values; system applies the transfer; 2x bandwidth vs 10-bit)
metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
metalLayer.wantsExtendedDynamicRangeContent = YES;
metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
```

### Who applies the transfer function

The colorspace name determines whose responsibility it is:

| Colorspace | Engine writes | Transfer function applied by |
|---|---|---|
| `kCGColorSpaceSRGB` (with `_sRGB` pixel format) | linear | hardware (sRGB encoding on write) |
| `kCGColorSpaceDisplayP3_PQ` / `kCGColorSpaceITUR_2100_PQ` | PQ-encoded values | engine shader |
| `kCGColorSpaceExtendedLinearSRGB` / `kCGColorSpaceExtendedLinearDisplayP3` | linear (extended-range) | OS compositor |

If the engine outputs PQ-encoded values into a non-PQ colorspace, output looks crushed. If the engine outputs linear values into a PQ colorspace, highlights blow out. Match the colorspace to what the shader actually writes.

## EDR headroom

Query per-frame after presenting to adapt tone mapping:

```objc
// macOS
CGFloat currentEDR   = window.screen.maximumExtendedDynamicRangeColorComponentValue;
CGFloat potentialEDR = window.screen.maximumPotentialExtendedDynamicRangeColorComponentValue;

// iOS
CGFloat currentEDR   = window.screen.currentEDRHeadroom;
CGFloat potentialEDR = window.screen.potentialEDRHeadroom;
```

- `currentEDR` — what the display can actually show *right now*. Varies with ambient light, content, and brightness setting.
- `potentialEDR` — the maximum the display can achieve. When this drops to `1.0`, EDR is unavailable — switch to SDR.
- EDR headroom is a multiplier relative to SDR white (`1.0` = SDR only, `2.0` = 2× brightness).
- For nits: multiply headroom by 100 (SDR = 0–100 nits, HDR above 100 nits).

Both `screen.maximumExtendedDynamicRangeColorComponentValue` and the iOS equivalents must be read on the main thread.

## Display profile changes

Monitor for display profile changes (e.g., window moved to a different monitor) via `NSWindowDidChangeScreenProfileNotification` and update the layer's format/colorspace accordingly. EDR headroom can also change without a profile change — query each frame from the cached value the main thread maintains.

## Verification

Use Metal HUD (`MTL_HUD_ENABLED=1`) to confirm HDR is active — it reports the layer's pixel format and present mode. Some HDR formats may require vsync enabled to qualify for direct presentation; verify the present mode field shows "Direct" rather than "Composited".
