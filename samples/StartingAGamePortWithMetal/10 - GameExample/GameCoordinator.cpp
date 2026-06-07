/*
<samplecode>
  <abstract>
  Implements frame pacing, render-pass encoding, MetalFX upscaling, and the
  platform-independent draw entry point the display link calls each vsync.
  </abstract>
</samplecode>
*/

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
//
// Copyright 2026 Apple Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-------------------------------------------------------------------------------------------------------------------------------------------------------------


#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define MTLFX_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <Metal/Metal.hpp>
#include <MetalFX/MetalFX.hpp>

#define IR_RUNTIME_METALCPP
#define IR_PRIVATE_IMPLEMENTATION
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

#include <simd/simd.h>
#include <utility>
#include <variant>
#include <vector>

// Include RenderCore after metal-cpp and metal-irconverter to generate
// their implementations inline in this file.
#include "GameCoordinator.hpp"
#include "ShaderPipelineBuilder.hpp"
#include "MathUtils.hpp"

#define NUM_ELEMS(arr) (sizeof(arr) / sizeof(arr[0]))

static constexpr uint64_t kPerFrameBumpAllocatorCapacity = 1024; // 1 KiB

GameCoordinator::GameCoordinator(MTL::Device* pDevice,
                                 MTL::PixelFormat layerPixelFormat,
                                 NS::UInteger width,
                                 NS::UInteger height,
                                 NS::UInteger gameUICanvasSize,
                                 const std::string& assetSearchPath)
    : _layerPixelFormat(layerPixelFormat)
    , _pDevice(pDevice->retain())
    , _frame(0)
    , _maxEDRValue(1.0f)
    , _brightness(500)
    , _edrBias(0)
    , _highScore(0)
    , _prevScore(0)
{
    memset(&_screenMesh, 0x0, sizeof(IndexedMesh));
    memset(&_quadMesh, 0x0, sizeof(IndexedMesh));
    
    _pCommandQueue = _pDevice->newCommandQueue();
    buildRenderPipelines(assetSearchPath);
    buildComputePipelines(assetSearchPath);
    buildSamplers();
    
    const NS::UInteger nativeWidth = (NS::UInteger)(width/1.2);
    const NS::UInteger nativeHeight = (NS::UInteger)(height/1.2);
    buildRenderTextures(nativeWidth, nativeHeight, width, height);
    buildMetalFXUpscaler(nativeWidth, nativeHeight, width, height);
    
    resizeDrawable(width, height);

    for (size_t i = 0; i < kMaxFramesInFlight; ++i)
    {
        _bufferAllocator[i] = std::make_unique<BumpAllocator>(pDevice, kPerFrameBumpAllocatorCapacity, MTL::ResourceStorageModeShared);
    }
    
    _pPacingEvent = NS::TransferPtr( pDevice->newSharedEvent() );
    _pacingTimeStampIndex = 0;
    
    assert(_pBackbuffer);
    loadGameTextures(assetSearchPath);
    
    _pAudioEngine = std::make_unique<PhaseAudio>(assetSearchPath);
    loadGameSounds(assetSearchPath, _pAudioEngine.get());
    
    GameConfig config = this->standardGameConfig();
    _game.initialize(config, pDevice, _pCommandQueue);
    _game.restartGame(config, /* startingScore */ 0.0f);
    
    UIConfig uiConfig {
        .screenWidth = width,
        .screenHeight = height,
        .virtualCanvasWidth = (NS::UInteger)(gameUICanvasSize * width/(float)height),
        .virtualCanvasHeight = gameUICanvasSize,
        .fontAtlas = _fontAtlas,
        .uiPso = NS::RetainPtr(_pInstancedSpritePipeline)
    };
    
    _ui.initialize(uiConfig, pDevice, _pCommandQueue);
}

GameConfig GameCoordinator::standardGameConfig()
{
    assert(_textureAssets.size() != 0 || !"You need to load the textures before configuring a game");

    return GameConfig {
        .enemyRows = 5,
        .enemyCols = 8,
        .screenWidth = (uint32_t)_pBackbuffer->width(),
        .screenHeight = (uint32_t)_pBackbuffer->height(),
        .spritePso = NS::RetainPtr(_pInstancedSpritePipeline),
        .enemySpeed = 0.3f,
        .enemyMoveDownStep = 0.8f,
        .playerSpeed = 2.0f,
        .maxPlayerBullets = 3,
        .maxExplosions = 10,
        .explosionDurationSecs = 0.5,
        .playerFireCooldownSecs = 0.5f,
        .enemyTexture = _textureAssets["enemy0.png"],
        .playerTexture = _textureAssets["player.png"],
        .playerBulletTexture = _textureAssets["bullet0.png"],
        .backgroundTexture = _textureAssets["background.png"],
        .explosionTexture = _textureAssets["explosion0.png"],
        .fontAtlasTexture = _textureAssets["fontAtlas"],
        .pAudioEngine = _pAudioEngine.get()
    };
}

GameCoordinator::~GameCoordinator()
{
    _pSampler->release();

    _pPresentPipeline->release();
    _pInstancedSpritePipeline->release();
    
    mesh_utils::releaseMesh(&_quadMesh);
    mesh_utils::releaseMesh(&_screenMesh);
    _pCommandQueue->release();
    _pDevice->release();
}

void GameCoordinator::buildRenderPipelines(const std::string& shaderSearchPath)
{
    bool alphaBlending        = false;
    _pPresentPipeline         = shader_pipeline::newPresentPipeline(alphaBlending, shaderSearchPath, _pDevice);
    _pInstancedSpritePipeline = shader_pipeline::newInstancedSpritePipeline(shaderSearchPath, _pDevice, _layerPixelFormat);
    
    assert(_pPresentPipeline);
    assert(_pInstancedSpritePipeline);
}

void GameCoordinator::buildComputePipelines(const std::string& shaderSearchPath)
{
    // Build any compute pipelines
}

void GameCoordinator::buildRenderTextures(NS::UInteger nativeWidth, NS::UInteger nativeHeight,
                                          NS::UInteger presentWidth, NS::UInteger presentHeight)
{
    assert(_pDevice);
    
    {
        auto pTextureDesc = NS::TransferPtr(MTL::TextureDescriptor::alloc()->init());
        pTextureDesc->setUsage(MTL::TextureUsageRenderTarget|MTL::TextureUsageShaderRead);
        pTextureDesc->setStorageMode(MTL::StorageModePrivate);
        pTextureDesc->setTextureType(MTL::TextureType2DArray);
        pTextureDesc->setPixelFormat(_layerPixelFormat);
        
        
        // Texture into which the renderer natively renders:
        pTextureDesc->setWidth(nativeWidth);
        pTextureDesc->setHeight(nativeHeight);
        _pBackbuffer = NS::TransferPtr(_pDevice->newTexture(pTextureDesc.get()));
        
        // Upscaled texture into which MetalFX upscales:
        pTextureDesc->setWidth(presentWidth);
        pTextureDesc->setHeight(presentHeight);
        pTextureDesc->setTextureType(MTL::TextureType2D);
        _pUpscaledbuffer = NS::TransferPtr(_pDevice->newTexture(pTextureDesc.get()));
        
        // Metal shader converter pipelines use TextureArrays to provide compatible behavior,
        // however, MetalFX expects non-TextureArray inputs. This sample creates texture views
        // to use as TextureArray <-> Texture adapters to upscale the backbuffer.
        _pBackbufferAdapter = NS::TransferPtr(_pBackbuffer->newTextureView(_layerPixelFormat, MTL::TextureType2D, NS::Range(0, 1), NS::Range(0,1)));
        _pUpscaledbufferAdapter = NS::TransferPtr(_pUpscaledbuffer->newTextureView(_layerPixelFormat, MTL::TextureType2DArray, NS::Range(0, 1), NS::Range(0,1)));
        }
}

void GameCoordinator::buildMetalFXUpscaler(NS::UInteger inputWidth, NS::UInteger inputHeight,
                                           NS::UInteger outputWidth, NS::UInteger outputHeight)
{
    assert(_pDevice);
    
    // Because this sample consists of a 2D game with no depth information,
    // it uses the MetalFX spatial scaler. More elaborate games with depth
    // information can take advantage of the MetalFX temporal upscaler to
    // produce higher-quality visuals.
    
    auto pScalerDesc = NS::TransferPtr(MTLFX::SpatialScalerDescriptor::alloc()->init());
    
    pScalerDesc->setInputWidth(inputWidth);
    pScalerDesc->setInputHeight(inputHeight);
    pScalerDesc->setColorTextureFormat(_layerPixelFormat);
    pScalerDesc->setColorProcessingMode(MTLFX::SpatialScalerColorProcessingModeHDR);

    pScalerDesc->setOutputWidth(outputWidth);
    pScalerDesc->setOutputHeight(outputHeight);
    pScalerDesc->setOutputTextureFormat(_layerPixelFormat);
    
    _pSpatialScaler = NS::TransferPtr(pScalerDesc->newSpatialScaler(_pDevice));
}

void GameCoordinator::loadGameTextures(const std::string& textureSearchPath)
{
    assert(_pDevice);
    
    auto pCommandQueue = NS::TransferPtr(_pDevice->newCommandQueue());
    auto pCommandBuffer = pCommandQueue->commandBuffer();
    
    std::vector<std::string> enemyTextures {
        textureSearchPath + "/enemy0.png",
        textureSearchPath + "/enemy1.png",
        textureSearchPath + "/enemy2.png"
    };
    _textureAssets["enemy0.png"] = NS::TransferPtr(newTextureArrayFromFiles(enemyTextures, _pDevice, pCommandBuffer));
    
    std::vector<std::string> explosionTextures {
        textureSearchPath + "/explosion0.png",
        textureSearchPath + "/explosion1.png"
    };
    _textureAssets["explosion0.png"] = NS::TransferPtr(newTextureArrayFromFiles(explosionTextures, _pDevice, pCommandBuffer));
    
    pCommandBuffer->commit();

    _textureAssets["player.png"] = NS::TransferPtr(newTextureFromFile(textureSearchPath + "/player.png", _pDevice));
    _textureAssets["bullet0.png"] = NS::TransferPtr(newTextureFromFile(textureSearchPath + "/bullet0.png", _pDevice));
    _textureAssets["background.png"] = NS::TransferPtr(newTextureFromFile(textureSearchPath + "/background.png", _pDevice));
    
    // Build font atlas
    _fontAtlas = newFontAtlas(_pDevice);
    _textureAssets["fontAtlas"] = _fontAtlas.texture;
    
    assert(_textureAssets["enemy0.png"]);
    assert(_textureAssets["player.png"]);
    assert(_textureAssets["bullet0.png"]);
    assert(_textureAssets["background.png"]);
    assert(_textureAssets["explosion0.png"]);
    assert(_textureAssets["fontAtlas"]);
    
    pCommandBuffer->waitUntilCompleted();
}

void GameCoordinator::loadGameSounds(const std::string& assetSearchPath, PhaseAudio* pAudioEngine)
{
    pAudioEngine->loadStereoSound(assetSearchPath, "laser2.mp3");
    pAudioEngine->loadStereoSound(assetSearchPath, "impact2.mp3");
    pAudioEngine->loadStereoSound(assetSearchPath, "failure.mp3");
    pAudioEngine->loadStereoSound(assetSearchPath, "success.mp3");
}


void GameCoordinator::buildSamplers()
{
    MTL::SamplerDescriptor* pSampDesc = MTL::SamplerDescriptor::alloc()->init()->autorelease();
    pSampDesc->setSupportArgumentBuffers(true);
    pSampDesc->setMagFilter(MTL::SamplerMinMagFilterLinear);
    pSampDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    pSampDesc->setRAddressMode(MTL::SamplerAddressModeRepeat);
    pSampDesc->setSAddressMode(MTL::SamplerAddressModeRepeat);
    pSampDesc->setTAddressMode(MTL::SamplerAddressModeRepeat);
    _pSampler = _pDevice->newSamplerState(pSampDesc);
    assert(_pSampler);
}

void GameCoordinator::presentTexture(MTL::RenderCommandEncoder* pRenderEnc, MTL::Texture* pTexture)
{
    assert(pTexture);
    assert(_pSampler);
    
    struct PresentTLAB
    {
        uint64_t cbv;
        uint64_t srvTable;
        uint64_t smpTable;
    };
    
    struct FrameDataAB
    {
        simd::float4x4 projectionMx;
        float          maxEDRValue;
        float          brightness;
        float          edrBias;
    };
    
    auto [cbvPtr, cbvOff] = _bufferAllocator[_frame]->allocate<FrameDataAB>();
    auto [srvPtr, srvOff] = _bufferAllocator[_frame]->allocate<IRDescriptorTableEntry>();
    auto [smpPtr, smpOff] = _bufferAllocator[_frame]->allocate<IRDescriptorTableEntry>();
    
    cbvPtr->projectionMx    = _presentOrtho;
    cbvPtr->maxEDRValue     = _maxEDRValue;
    cbvPtr->brightness      = _brightness;
    cbvPtr->edrBias         = _edrBias;
    
    IRDescriptorTableSetTexture(srvPtr, pTexture, 0, 0);
    IRDescriptorTableSetSampler(smpPtr, _pSampler, 0);
    
    auto [presentTlabPtr, presentTlabOff] = _bufferAllocator[_frame]->allocate<PresentTLAB>();
    presentTlabPtr->cbv      = _bufferAllocator[_frame]->baseBuffer()->gpuAddress() + cbvOff;
    presentTlabPtr->srvTable = _bufferAllocator[_frame]->baseBuffer()->gpuAddress() + srvOff;
    presentTlabPtr->smpTable = _bufferAllocator[_frame]->baseBuffer()->gpuAddress() + smpOff;
    
    pRenderEnc->useResource(pTexture, MTL::ResourceUsageRead);
    pRenderEnc->setVertexBuffer(_screenMesh.pVertices, 0, kIRVertexBufferBindPoint);
    pRenderEnc->setVertexBuffer(_bufferAllocator[_frame]->baseBuffer(), presentTlabOff, kIRArgumentBufferBindPoint);
    pRenderEnc->setFragmentBuffer(_bufferAllocator[_frame]->baseBuffer(), presentTlabOff, kIRArgumentBufferBindPoint);
    
    pRenderEnc->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, _screenMesh.numIndices, _screenMesh.indexType, _screenMesh.pIndices, 0);
}

void GameCoordinator::draw(CA::MetalDrawable* pDrawable, double targetTimestamp)
{
    assert(pDrawable);
    NS::AutoreleasePool* pPool = NS::AutoreleasePool::alloc()->init();
    
    //#define CAPTURE
    #ifdef CAPTURE
        MTL::CaptureDescriptor* pCapDesc = MTL::CaptureDescriptor::alloc()->init()->autorelease();
        pCapDesc->setDestination(MTL::CaptureDestinationDeveloperTools);
        pCapDesc->setCaptureObject(_pDevice);
        
        NS::Error* pError = nullptr;
        MTL::CaptureManager* pCapMan = MTL::CaptureManager::sharedCaptureManager();
        if (!pCapMan->startCapture(pCapDesc, &pError))
        {
            printf("%s\n", pError->localizedDescription()->utf8String());
            __builtin_trap();
        }
    #endif
    
    ++_pacingTimeStampIndex;
    _frame = (_frame + 1) % kMaxFramesInFlight;
    
    // Wait for the frame "MaxFramesInFlight" behind to finish before reusing transient buffers.
    // Unlike with dispatch_semaphores, when the GPU signals the MTL::SharedEvent value, the
    // scheduler directly wakes up any blocked threads, reducing overhead and thread hops.
    if (_pacingTimeStampIndex > kMaxFramesInFlight)
    {
        uint64_t const timeStampToWait = _pacingTimeStampIndex - kMaxFramesInFlight;
        _pPacingEvent->waitUntilSignaledValue(timeStampToWait, DISPATCH_TIME_FOREVER);
    }
    
    // Reset the bump allocator for this new frame.
    _bufferAllocator[_frame]->reset();
    
    MTL::CommandBuffer* pCmd = _pCommandQueue->commandBuffer();

    // Game render pass
    {
        // Render pass configuration:
        MTL::RenderPassDescriptor* pRenderPass = MTL::RenderPassDescriptor::renderPassDescriptor();
        auto pColorAttachment0 = pRenderPass->colorAttachments()->object(0);
        pColorAttachment0->setTexture(_pBackbuffer.get());
        pColorAttachment0->setLoadAction(MTL::LoadActionClear);
        pColorAttachment0->setStoreAction(MTL::StoreActionStore);
        pColorAttachment0->setClearColor(MTL::ClearColor(0.15, 0.15, 0.15, 1.0));
        MTL::RenderCommandEncoder* pRenderEnc = pCmd->renderCommandEncoder(pRenderPass);
        
        // Update game and encode its rendering work:
        const GameState* pGameState = _game.update(targetTimestamp, _frame);
        _game.draw(pRenderEnc, _frame);
        pRenderEnc->endEncoding();
        
        
        // Update score text mesh (if needed):
        if (_prevScore != pGameState->playerScore) [[unlikely]]
        {
            _ui.showCurrentScore("SCORE:", pGameState->playerScore, _pDevice);
            _prevScore = pGameState->playerScore;
        }
        
        // Test for end-game condition:
        bool isFinished = pGameState->gameStatus == GameStatus::PlayerWon
                       || pGameState->gameStatus == GameStatus::PlayerLost;
        
        if (isFinished) [[unlikely]]
        {
            bool haveNewScore = (pGameState->playerScore > _highScore);
            if (haveNewScore)
            {
                _highScore = std::max(pGameState->playerScore, _highScore);
                _ui.showHighScore("NEW HIGH SCORE:", _highScore, _pDevice);
            }
            
            GameConfig config = this->standardGameConfig();
            
            float startingScore = pGameState->playerScore;
            if (pGameState->gameStatus == GameStatus::PlayerLost)
            {
                startingScore = 0.0f;
            }
            
            _game.restartGame(config, startingScore);
        }
    }
    
    // Upscale the image with MetalFX
    {
        _pSpatialScaler->setInputContentWidth(_pBackbufferAdapter->width());
        _pSpatialScaler->setInputContentHeight(_pBackbufferAdapter->height());
        _pSpatialScaler->setColorTexture(_pBackbufferAdapter.get());
        
        _pSpatialScaler->setOutputTexture(_pUpscaledbuffer.get());
        _pSpatialScaler->encodeToCommandBuffer(pCmd);
    }
    
    // Present backbuffer render pass
    {
        MTL::RenderPassDescriptor* pRenderPass = MTL::RenderPassDescriptor::renderPassDescriptor();
        auto pColorAttachment0 = pRenderPass->colorAttachments()->object(0);
        pColorAttachment0->setTexture(pDrawable->texture());
        pColorAttachment0->setLoadAction(MTL::LoadActionClear);
        pColorAttachment0->setStoreAction(MTL::StoreActionStore);
        pColorAttachment0->setClearColor(MTL::ClearColor(0., 0., 0., 1.0));
        
        MTL::RenderCommandEncoder* pRenderEnc = pCmd->renderCommandEncoder(pRenderPass);
        pRenderEnc->setRenderPipelineState(_pPresentPipeline);
        presentTexture(pRenderEnc, _pUpscaledbufferAdapter.get());
        
        // Render UI on top of upscaled image
        _ui.update(targetTimestamp, _frame);
        _ui.draw(pRenderEnc, _frame);
        
        pRenderEnc->endEncoding();

        pCmd->presentDrawable(pDrawable);
    }
    
    // Signal timestamp completion so event waiting logic has a GPU marker to wait on from the CPU
    pCmd->encodeSignalEvent(_pPacingEvent.get(), _pacingTimeStampIndex);
    pCmd->commit();

#ifdef CAPTURE
    pCapMan->stopCapture();
#endif
    
    
    pPool->release();
}

void GameCoordinator::setHighScore(int highScore, HighScoreSource scoreSource)
{
    _highScore = highScore;
    
    const char* label = (scoreSource == HighScoreSource::Local) ? "LOCAL HIGH SCORE:" : "CLOUD HIGH SCORE:";
    _ui.showHighScore(label, _highScore, _pDevice);
}
