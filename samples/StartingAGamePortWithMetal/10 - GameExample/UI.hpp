/*
<samplecode>
  <abstract>
  Declares the in-game HUD renderer — score, high-score banner, win / lose
  screens — built on a small bitmap-font sprite atlas.
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

#ifndef UI_HPP
#define UI_HPP

#include "TextureLoader.h"
#include "MeshUtils.hpp"
#include "MathUtils.hpp"
#include "BumpAllocator.hpp"
#include "Config.h"
#include "NonCopyable.h"
#include <memory>

constexpr uint64_t kFontAtlasTextureIndex = 0;

struct UIConfig
{
    NS::UInteger                            screenWidth;
    NS::UInteger                            screenHeight;
    NS::UInteger                            virtualCanvasWidth;
    NS::UInteger                            virtualCanvasHeight;
    FontAtlas                               fontAtlas;
    NS::SharedPtr<MTL::RenderPipelineState> uiPso;
};

struct UIRenderData
{
    std::array<std::unique_ptr<BumpAllocator>, kMaxFramesInFlight> bufferAllocator;
    std::array<NS::SharedPtr<MTL::Heap>, kMaxFramesInFlight>       resourceHeaps;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight>     frameDataBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight>     highScorePositionBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight>     currentScorePositionBuf;
    NS::SharedPtr<MTL::Buffer>                                     textureTable;
    NS::SharedPtr<MTL::Buffer>                                     samplerTable;
    NS::SharedPtr<MTL::SamplerState>                               pSampler;
    NS::SharedPtr<MTL::ResidencySet>                               pResidencySet;
};

class UI : public NonCopyable
{
public:
    UI();
    ~UI();
    void initialize(const UIConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue);
    void showHighScore(const char* label, int highscore, MTL::Device* pDevice);
    void showCurrentScore(const char* label, int score, MTL::Device* pDevice);
    void update(double targetTimestamp, uint8_t frameID);
    void draw(MTL::RenderCommandEncoder* pRenderCmd, uint8_t frameID);
private:
    void createBuffers(MTL::Device* pDevice);
    void createResidencySet(MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue);
    
    UIConfig _uiConfig;
    UIRenderData _renderData;
    IndexedMesh _highScoreMesh;
    IndexedMesh _currentScoreMesh;
    
    simd::float4 _highScorePosition;
    simd::float4 _currentScorePosition;
    double _lastTimestamp = 0.0;
    double _bannerCountdownSecs = 0.0;
};

#endif // UI_HPP
