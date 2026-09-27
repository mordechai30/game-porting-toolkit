# PresentThread Reference Implementation

This is the complete C++ PresentThread class for dual-threaded frame interpolation presentation. Wrap it in an ObjC class for use from .m files.

## Adaptation Notes

- The `m_library` member stores the MTLLibrary for shader lookup — pass it from the renderer
- Add a zero-dimension guard at the top of `Resize()`: `if (width == 0 || height == 0) return;`

## Metal 3 vs Metal 4

The reference implementation below targets the **Metal 3** frame-interpolation API. Under **Metal 4** (macOS/iOS 26.0+), the following type substitutions apply throughout the class — selectors stay the same where they overlap, but the protocol types change:

| Metal 3 | Metal 4 |
|---------|---------|
| `id<MTLFXFrameInterpolator>` | `id<MTL4FXFrameInterpolator>` |
| `id<MTLCommandBuffer>` (on interpolator encode, `StartFrame`, `Present`) | `id<MTL4CommandBuffer>` |
| `id<MTLCommandQueue>` (`m_presentQueue`, `Present()` param) | `id<MTL4CommandQueue>` (created via `[device makeMTL4CommandQueue]`) |

Additional Metal 4 considerations not covered by simple type substitution:
- **Command buffer lifecycle differs.** Metal 4 command buffers are not obtained via `[queue commandBuffer]` and do not use the same `commit` / `addCompletedHandler` / `encodeSignalEvent` shape as Metal 3. Before porting the `Present()` / `PresentThreadFunction` bodies, consult the `MTL4CommandBuffer` and `MTL4CommandQueue` documentation for the correct allocation, recording, and commit calls.
- **Shared properties.** All per-frame interpolator properties (`colorTexture`, `prevColorTexture`, `outputTexture`, `uiTexture`, `depthTexture`, `motionTexture`, `jitterOffsetX/Y`, `motionVectorScaleX/Y`, `fieldOfView`, `nearPlane`, `farPlane`, `aspectRatio`, `shouldResetHistory`) live on the shared `MTLFXFrameInterpolatorBase` protocol and work identically under both APIs.
- **Encode selector.** `-encodeToCommandBuffer:` exists on both `MTLFXFrameInterpolator` and `MTL4FXFrameInterpolator`, but the argument type is the respective command-buffer protocol.

## ObjC Wrapper Pattern

The header (.h) must use `#import <Metal/Metal.h>` etc., NOT `@import MetalFX;`:
```objc
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <MetalFX/MetalFX.h>
#import <QuartzCore/CAMetalLayer.h>

@interface AAPLPresentThread : NSObject
- (instancetype)initWithMinDuration:(float)minDuration
                         metalLayer:(CAMetalLayer *)layer
                            library:(id<MTLLibrary>)library;
- (void)startFrame:(id<MTLCommandBuffer>)commandBuffer;
- (id<MTLTexture>)getBackBuffer;
- (void)present:(id<MTLFXFrameInterpolator>)interpolator queue:(id<MTLCommandQueue>)queue;
- (void)resize:(uint32_t)width height:(uint32_t)height pixelFormat:(MTLPixelFormat)format;
- (void)drainPendingPresents;
@end
```

The implementation (.mm) owns a `PresentThread*` and delegates to it:
```objc
@implementation AAPLPresentThread { PresentThread *_impl; }
- (instancetype)initWithMinDuration:(float)d metalLayer:(CAMetalLayer *)l library:(id<MTLLibrary>)lib {
    self = [super init];
    if (self) _impl = new PresentThread(d, l, lib);
    return self;
}
- (void)dealloc { delete _impl; }
- (void)startFrame:(id<MTLCommandBuffer>)cb { _impl->StartFrame(cb); }
- (id<MTLTexture>)getBackBuffer { return _impl->GetBackBuffer(); }
- (void)present:(id<MTLFXFrameInterpolator>)fi queue:(id<MTLCommandQueue>)q { _impl->Present(fi, q); }
- (void)resize:(uint32_t)w height:(uint32_t)h pixelFormat:(MTLPixelFormat)f { _impl->Resize(w, h, f); }
- (void)drainPendingPresents { _impl->DrainPendingPresents(); }
@end
```

## Complete C++ Implementation

```cpp
#include <thread>
#include <mutex>
#include <sys/event.h>
#include <mach/mach_time.h>

class PresentThread
{
    int m_timerQueue;
    std::thread m_encodingThread, m_pacingThread;
    std::mutex m_mutex;
    std::condition_variable m_scheduleCV, m_threadCV, m_pacingCV;
    float m_minDuration;
    
    uint32_t m_width, m_height;
    MTLPixelFormat m_pixelFormat;
    
    const static uint32_t kNumBuffers = 3;
    uint32_t m_bufferIndex, m_inputIndex;
    bool m_renderingUI, m_presentsPending;
    
    CAMetalLayer *m_metalLayer;
    id<MTLCommandQueue> m_presentQueue;
    id<MTLLibrary> m_library;

    id<MTLEvent> m_event;
    id<MTLSharedEvent> m_paceEvent, m_paceEvent2;
    uint64_t m_eventValue;
    uint32_t m_paceCount;
    
    int32_t m_numQueued, m_framesInFlight;
    
    id<MTLTexture> m_backBuffers[kNumBuffers];
    id<MTLTexture> m_interpolationOutputs[kNumBuffers];
    id<MTLTexture> m_interpolationInputs[2];
    id<MTLRenderPipelineState> m_copyPipeline;
    
    void PresentThreadFunction();
    void PacingThreadFunction();
    void CopyTexture(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> dest,
                     id<MTLTexture> src, NSString *label);

public:
    PresentThread(float minDuration, CAMetalLayer *metalLayer, id<MTLLibrary> library);
    ~PresentThread() {
        { std::unique_lock<std::mutex> lock(m_mutex); m_numQueued = -1; m_threadCV.notify_one(); }
        if (m_encodingThread.joinable()) m_encodingThread.join();
    }

    void StartFrame(id<MTLCommandBuffer> commandBuffer) {
        [commandBuffer encodeWaitForEvent:m_event value:m_eventValue++];
    }

    void Present(id<MTLFXFrameInterpolator> frameInterpolator, id<MTLCommandQueue> queue);
    id<MTLTexture> GetBackBuffer() { return m_backBuffers[m_bufferIndex]; }
    void Resize(uint32_t width, uint32_t height, MTLPixelFormat pixelFormat);
    void DrainPendingPresents() {
        std::unique_lock<std::mutex> lock(m_mutex);
        while(m_presentsPending) m_scheduleCV.wait(lock);
    }
};

// --- Constructor ---
PresentThread::PresentThread(float minDuration, CAMetalLayer *metalLayer, id<MTLLibrary> library)
    : m_encodingThread(&PresentThread::PresentThreadFunction, this)
    , m_pacingThread(&PresentThread::PacingThreadFunction, this)
    , m_minDuration(minDuration), m_numQueued(0), m_metalLayer(metalLayer), m_library(library)
    , m_inputIndex(0u), m_bufferIndex(0u), m_width(0), m_height(0)
    , m_pixelFormat(MTLPixelFormatInvalid), m_renderingUI(false), m_presentsPending(false)
    , m_framesInFlight(0), m_paceCount(0), m_eventValue(0)
{
    id<MTLDevice> device = metalLayer.device;
    m_presentQueue = [device newCommandQueue];
    m_presentQueue.label = @"presentQ";
    m_timerQueue = kqueue();
    metalLayer.maximumDrawableCount = 3;
    Resize(metalLayer.drawableSize.width, metalLayer.drawableSize.height, metalLayer.pixelFormat);
    m_event = [device newEvent];
    m_paceEvent = [device newSharedEvent];
    m_paceEvent2 = [device newSharedEvent];
}

// --- Present (called from render thread) ---
void PresentThread::Present(id<MTLFXFrameInterpolator> frameInterpolator, id<MTLCommandQueue> queue)
{
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

    // No UI in this integration — use back buffers directly
    frameInterpolator.colorTexture = m_backBuffers[m_bufferIndex];
    frameInterpolator.prevColorTexture = m_backBuffers[(m_bufferIndex + kNumBuffers - 1) % kNumBuffers];
    frameInterpolator.uiTexture = nil;
    frameInterpolator.outputTexture = m_interpolationOutputs[m_bufferIndex];

    [frameInterpolator encodeToCommandBuffer:commandBuffer];
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
        std::unique_lock<std::mutex> lock(m_mutex);
        m_framesInFlight--;
        m_scheduleCV.notify_one();
        m_paceCount++;
        m_pacingCV.notify_one();
    }];
    [commandBuffer encodeSignalEvent:m_event value:m_eventValue++];
    [commandBuffer commit];

    std::unique_lock<std::mutex> lock(m_mutex);
    m_framesInFlight++;
    m_numQueued++;
    m_presentsPending = true;
    m_threadCV.notify_one();
    while((m_framesInFlight >= 2) || (m_numQueued >= 2))
        m_scheduleCV.wait(lock);

    m_bufferIndex = (m_bufferIndex + 1) % kNumBuffers;
    m_inputIndex = m_inputIndex ^ 1u;
    m_renderingUI = false;
}

// --- CopyTexture (fullscreen blit) ---
void PresentThread::CopyTexture(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> dest,
                                id<MTLTexture> src, NSString *label)
{
    MTLRenderPassDescriptor *desc = [MTLRenderPassDescriptor new];
    desc.colorAttachments[0].texture = dest;
    desc.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    desc.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:desc];
    [renderEncoder setFragmentTexture:src atIndex:0];
    [renderEncoder setRenderPipelineState:m_copyPipeline];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    renderEncoder.label = label;
    [renderEncoder endEncoding];
}

// --- Pacing Thread (kevent64 precision timer) ---
void PresentThread::PacingThreadFunction()
{
    NSThread *thread = [NSThread currentThread];
    [thread setName:@"PacingThread"];
    [thread setQualityOfService:NSQualityOfServiceUserInteractive];
    [thread setThreadPriority:1.f];

    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    const uint64_t maxDeltaInNanoSecs = 100000000; // 0.1s max
    const uint64_t maxDelta = maxDeltaInNanoSecs * info.denom / info.numer;
    uint64_t time = mach_absolute_time();
    uint64_t paceEventValue = 0;

    for(;;) {
        std::unique_lock<std::mutex> lock(m_mutex);
        while(m_paceCount == 0) m_pacingCV.wait(lock);
        m_paceCount--;
        lock.unlock();

        const uint64_t prevTime = time;
        time = mach_absolute_time();
        m_paceEvent.signaledValue = ++paceEventValue;

        const uint64_t delta = std::min(time - prevTime, maxDelta);
        const uint64_t timeStamp = time + ((delta * 31) >> 6); // ~48% of frame time

        struct kevent64_s timerEvent, eventOut;
        struct timespec timeout = { .tv_sec = 0, .tv_nsec = (long)maxDeltaInNanoSecs };
        EV_SET64(&timerEvent, 0, EVFILT_TIMER, EV_ADD | EV_ONESHOT | EV_ENABLE,
                 NOTE_CRITICAL | NOTE_LEEWAY | NOTE_MACHTIME | NOTE_ABSOLUTE,
                 timeStamp, 0, 0, 0);
        kevent64(m_timerQueue, &timerEvent, 1, &eventOut, 1, 0, &timeout);

        m_paceEvent2.signaledValue = ++paceEventValue;
    }
}

// --- Present Thread (acquires drawables, copies, presents) ---
void PresentThread::PresentThreadFunction()
{
    NSThread *thread = [NSThread currentThread];
    [thread setName:@"PresentThread"];
    [thread setQualityOfService:NSQualityOfServiceUserInteractive];
    [thread setThreadPriority:1.f];

    uint64_t eventValue = 0;
    uint32_t bufferIndex = 0;
    uint64_t paceEventValue = 0;

    for(;;) {
        std::unique_lock<std::mutex> lock(m_mutex);
        if(m_numQueued == 0) { m_presentsPending = false; m_scheduleCV.notify_one(); }
        while(m_numQueued == 0) m_threadCV.wait(lock);
        if(m_numQueued < 0) break;
        lock.unlock();

        // Present interpolated frame
        @autoreleasepool {
            id<CAMetalDrawable> drawable = [m_metalLayer nextDrawable];
            lock.lock(); m_numQueued--; m_scheduleCV.notify_one(); lock.unlock();

            id<MTLCommandBuffer> cb = [m_presentQueue commandBuffer];
            [cb encodeWaitForEvent:m_event value:++eventValue];
            CopyTexture(cb, drawable.texture, m_interpolationOutputs[bufferIndex], @"Copy Interpolated");
            [cb encodeSignalEvent:m_event value:++eventValue];
            [cb encodeWaitForEvent:m_paceEvent value:++paceEventValue];
            if(m_minDuration > 0.f) [cb presentDrawable:drawable afterMinimumDuration:m_minDuration];
            else [cb presentDrawable:drawable];
            [cb commit];
        }

        // Present real (rendered) frame
        @autoreleasepool {
            id<MTLCommandBuffer> cb = [m_presentQueue commandBuffer];
            id<CAMetalDrawable> drawable = [m_metalLayer nextDrawable];
            CopyTexture(cb, drawable.texture, m_backBuffers[bufferIndex], @"Copy Rendered");
            [cb encodeWaitForEvent:m_paceEvent2 value:++paceEventValue];
            if(m_minDuration > 0.f) [cb presentDrawable:drawable afterMinimumDuration:m_minDuration];
            else [cb presentDrawable:drawable];
            [cb commit];
        }

        bufferIndex = (bufferIndex + 1) % kNumBuffers;
    }
}

// --- Resize ---
void PresentThread::Resize(uint32_t width, uint32_t height, MTLPixelFormat pixelFormat)
{
    if (width == 0 || height == 0) return; // Guard against pre-layout calls

    if((m_width != width) || (m_height != height) || (m_pixelFormat != pixelFormat)) {
        id<MTLDevice> device = m_metalLayer.device;

        if(m_pixelFormat != pixelFormat) {
            MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
            pipelineDesc.vertexFunction = [m_library newFunctionWithName:@"fullscreenVertex"];
            pipelineDesc.fragmentFunction = [m_library newFunctionWithName:@"fullscreenFragment"];
            pipelineDesc.colorAttachments[0].pixelFormat = pixelFormat;
            m_copyPipeline = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:nil];
            m_pixelFormat = pixelFormat;
        }

        DrainPendingPresents();
        m_width = width; m_height = height;

        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
            width:width height:height mipmapped:NO];
        texDesc.storageMode = MTLStorageModePrivate;

        for(uint32_t i = 0; i < kNumBuffers; i++) {
            texDesc.usage = MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;
            m_backBuffers[i] = [device newTextureWithDescriptor:texDesc];
            texDesc.usage = MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
            m_interpolationOutputs[i] = [device newTextureWithDescriptor:texDesc];
        }
        texDesc.usage = MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
        m_interpolationInputs[0] = [device newTextureWithDescriptor:texDesc];
        m_interpolationInputs[1] = [device newTextureWithDescriptor:texDesc];
    }
}
```

## Required Metal Shader

The PresentThread needs a fullscreen blit shader for copying textures to drawables. If the app already has one from MetalFX temporal integration, reuse it. Otherwise add:

```metal
struct FullscreenInOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex FullscreenInOut fullscreenVertex(uint vid [[vertex_id]]) {
    FullscreenInOut out;
    out.texCoord = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.texCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return out;
}

fragment float4 fullscreenFragment(FullscreenInOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    return tex.sample(s, in.texCoord);
}
```
