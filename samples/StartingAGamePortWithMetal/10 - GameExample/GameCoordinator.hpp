/*
<samplecode>
  <abstract>
  Declares the per-app coordinator that owns the `Game` instance, manages
  frame pacing via Metal shared events, and applies MetalFX upscaling.
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


#ifndef RenderCore_hpp
#define RenderCore_hpp

#include <Foundation/Foundation.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <Metal/Metal.hpp>
#include <MetalFX/MetalFX.hpp>

//#define IR_RUNTIME_METALCPP
//#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

#include "BumpAllocator.hpp"
#include "MeshUtils.hpp"
#include "Game.hpp"
#include "UI.hpp"
#include <string>
#include <unordered_map>

#include "TextureLoader.h"

class GameCoordinator : public NonCopyable
{
public:
    GameCoordinator(MTL::Device* pDevice,
                    MTL::PixelFormat layerPixelFormat,
                    NS::UInteger width,
                    NS::UInteger height,
                    NS::UInteger gameUICanvasSize,
                    const std::string& assetSearchPath);
    
    ~GameCoordinator();

    // Set up the scene.
    void buildRenderPipelines(const std::string& shaderSearchPath);
    void buildComputePipelines(const std::string& shaderSearchPath);
    void buildRenderTextures(NS::UInteger nativeWidth, NS::UInteger nativeHeight,
                             NS::UInteger presentWidth, NS::UInteger presentHeight);
    void loadGameTextures(const std::string& textureSearchPath);
    void loadGameSounds(const std::string& assetSearchPath, PhaseAudio* pAudioEngine);
    void buildSamplers();
    void buildMetalFXUpscaler(NS::UInteger inputWidth, NS::UInteger inputHeight,
                              NS::UInteger outputWidth, NS::UInteger outputHeight);

    // Call every frame to produce the animations.
    void presentTexture(MTL::RenderCommandEncoder* pRenderEnc, MTL::Texture* pTexture);
    void draw(CA::MetalDrawable* pDrawable, double targetTimestamp);

    // Respond to configuration changes.
    void resizeDrawable(float width, float height);
    void setMaxEDRValue(float value)     { _maxEDRValue = value; }
    void setBrightness(float brightness) { _brightness = brightness; }
    void setEDRBias(float edrBias)       { _edrBias = edrBias; }

    enum class HighScoreSource {
        Local,
        Cloud
    };
    
    void setHighScore(int highScore, HighScoreSource scoreSource);
    int highScore() const                { return _highScore; }
    
private:
    GameConfig                           standardGameConfig();

    Game                                 _game;
    UI                                   _ui;

    MTL::PixelFormat                    _layerPixelFormat;
    NS::SharedPtr<MTL::Texture>         _pBackbuffer;
    NS::SharedPtr<MTL::Texture>         _pUpscaledbuffer;
    NS::SharedPtr<MTL::Texture>         _pBackbufferAdapter;
    NS::SharedPtr<MTL::Texture>         _pUpscaledbufferAdapter;
    FontAtlas                           _fontAtlas;
    MTL::Device*                        _pDevice;
    MTL::CommandQueue*                  _pCommandQueue;
    
    NS::SharedPtr<MTL::SharedEvent>     _pPacingEvent;
    uint64_t                            _pacingTimeStampIndex;

    MTL::RenderPipelineState*           _pPresentPipeline;
    MTL::RenderPipelineState*           _pInstancedSpritePipeline;
    NS::SharedPtr<MTLFX::SpatialScaler> _pSpatialScaler;

    // Assets:
    MTL::SamplerState*          _pSampler;
    IndexedMesh                 _quadMesh;
    IndexedMesh                 _screenMesh;
    std::unordered_map<std::string, NS::SharedPtr<MTL::Texture>> _textureAssets;

    // Per-frame data:
    std::array<std::unique_ptr<BumpAllocator>, kMaxFramesInFlight> _bufferAllocator;

    // Animation data:
    int _frame;
    
    simd::float4x4 _presentOrtho;
    float          _maxEDRValue;
    float          _brightness;
    float          _edrBias;
    
    std::unique_ptr<PhaseAudio> _pAudioEngine;
    
    int            _highScore;
    int            _prevScore;
};

#endif /* RenderCore_hpp */
