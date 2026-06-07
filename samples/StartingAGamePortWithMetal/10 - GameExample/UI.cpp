/*
<samplecode>
  <abstract>
  Implements the in-game HUD renderer — score, high-score banner, win / lose
  screens — using the bitmap-font sprite atlas.
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

#include "UI.hpp"

#define IR_RUNTIME_METALCPP
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

UI::UI()
{
    memset(&_highScoreMesh, 0x0, sizeof(IndexedMesh));
    memset(&_currentScoreMesh, 0x0, sizeof(IndexedMesh));
}

UI::~UI()
{
    mesh_utils::releaseMesh(&_highScoreMesh);
    mesh_utils::releaseMesh(&_currentScoreMesh);
}

void UI::initialize(const UIConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue)
{
    _uiConfig = config;
    createBuffers(pDevice);
    createResidencySet(pDevice, pCommandQueue);
    showHighScore("HIGH SCORE:", 0, pDevice);
    showCurrentScore("SCORE:", 0, pDevice);
}

void UI::showHighScore(const char* label, int highscore, MTL::Device* pDevice)
{
    _bannerCountdownSecs = 5.0f;
    
    float startY = _uiConfig.virtualCanvasHeight * 0.5 * 0.9;
    _highScorePosition = simd_make_float4(0.0, startY, 0, 1);
    
    std::stringstream ss;
    ss << label << highscore;
    
    mesh_utils::releaseMesh(&_highScoreMesh);
    _highScoreMesh = mesh_utils::newTextMesh(ss.str(), _uiConfig.fontAtlas, pDevice);
}

void UI::showCurrentScore(const char* label, int score, MTL::Device* pDevice)
{
    std::stringstream ss;
    ss << label << score;
    
    const std::string& str = ss.str();
    
    const float strWidth = (float)str.size() * 1.0f;
    
    const float leftSide = (float)_uiConfig.virtualCanvasWidth * -0.5f;
    const float leftMargin = (float)_uiConfig.virtualCanvasWidth * 0.025f;
    
    const float bottomSide = (float)_uiConfig.virtualCanvasHeight * -0.5f;
    const float bottomMargin = leftMargin;
    _currentScorePosition = simd_make_float4(leftSide + leftMargin + strWidth*0.5f,
                                             bottomSide + bottomMargin,
                                             0, 1);
    

    mesh_utils::releaseMesh(&_currentScoreMesh);
    _currentScoreMesh = mesh_utils::newTextMesh(str, _uiConfig.fontAtlas, pDevice);
}

void UI::update(double targetTimestamp, uint8_t frameID)
{
    if (_lastTimestamp != 0.0)
    {
        double deltat = targetTimestamp - _lastTimestamp;
        _bannerCountdownSecs = std::max(_bannerCountdownSecs - deltat, 0.0);
        
        if (_bannerCountdownSecs <= 0.0 && _highScorePosition.y < _uiConfig.virtualCanvasHeight * 0.5 * 1.2)
        {
            _highScorePosition.y += 1.f * deltat;
        }
    }
    
    _lastTimestamp = targetTimestamp;
    memcpy(_renderData.highScorePositionBuf[frameID]->contents(), &_highScorePosition, sizeof(simd::float4));
    memcpy(_renderData.currentScorePositionBuf[frameID]->contents(), &_currentScorePosition, sizeof(simd::float4));
}

void UI::createBuffers(MTL::Device* pDevice)
{
    // Mutable resources (shadowed 3 times):
    
    const uint64_t kScratchSize = 1 * 1024; // in KiB;
    
    auto pHeapDesc = NS::TransferPtr(MTL::HeapDescriptor::alloc()->init());
    pHeapDesc->setSize(sizeof(FrameData) + 2 * sizeof(simd::float4));
    pHeapDesc->setStorageMode(MTL::StorageModeShared);
    
    const float canvasW = _uiConfig.virtualCanvasWidth;
    const float canvasH = _uiConfig.virtualCanvasHeight;
    
    for (uint8_t i = 0; i < kMaxFramesInFlight; ++i)
    {
        _renderData.bufferAllocator[i] = std::make_unique<BumpAllocator>(pDevice, kScratchSize, MTL::ResourceStorageModeShared);
        
        _renderData.resourceHeaps[i] = NS::TransferPtr(pDevice->newHeap(pHeapDesc.get()));
        
        _renderData.frameDataBuf[i] = NS::TransferPtr(_renderData.resourceHeaps[i]->newBuffer(sizeof(FrameData), MTL::ResourceStorageModeShared));
        _renderData.frameDataBuf[i]->setLabel(MTLSTR("UI Frame Data Buffer"));
        auto pFrameData = (FrameData *)_renderData.frameDataBuf[i]->contents();
        pFrameData->projectionMatrix = math::makeOrtho(-canvasW/2, canvasW/2, canvasH/2, -canvasH/2, -1, 1);
        
        _renderData.highScorePositionBuf[i] = NS::TransferPtr(_renderData.resourceHeaps[i]->newBuffer(sizeof(simd::float4), MTL::ResourceStorageModeShared));
        _renderData.highScorePositionBuf[i]->setLabel(MTLSTR("UI HighScore Position Buffer"));
        
        _renderData.currentScorePositionBuf[i] = NS::TransferPtr(_renderData.resourceHeaps[i]->newBuffer(sizeof(simd::float4), MTL::ResourceStorageModeShared));
        _renderData.currentScorePositionBuf[i]->setLabel(MTLSTR("UI Current Score Position Buffer"));
    }
    
    // Immutable texture and sampler tables:
    constexpr uint32_t kNumUITextures = 1;
    constexpr uint32_t kNumUISamplers = 1;
    
    const size_t textureTableBufSize         = sizeof(IRDescriptorTableEntry) * kNumUITextures;
    const size_t samplerTableBufSize         = sizeof(IRDescriptorTableEntry) * kNumUISamplers;

    // Texture table:
    _renderData.textureTable = NS::TransferPtr(pDevice->newBuffer(textureTableBufSize, MTL::ResourceStorageModeShared));
    _renderData.textureTable->setLabel(MTLSTR("UI Texture Table"));
    auto pTextureTableContents = (IRDescriptorTableEntry *)_renderData.textureTable->contents();
    
    IRDescriptorTableSetTexture(&(pTextureTableContents[kFontAtlasTextureIndex]), _uiConfig.fontAtlas.texture.get(), 0, 0);
    
    // Sampler table:
    auto pSamplerDesc = NS::TransferPtr(MTL::SamplerDescriptor::alloc()->init());
    pSamplerDesc->setSupportArgumentBuffers(true);
    pSamplerDesc->setMagFilter(MTL::SamplerMinMagFilterLinear);
    pSamplerDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    pSamplerDesc->setRAddressMode(MTL::SamplerAddressModeClampToEdge);
    pSamplerDesc->setSAddressMode(MTL::SamplerAddressModeClampToEdge);
    pSamplerDesc->setTAddressMode(MTL::SamplerAddressModeClampToEdge);
    
    _renderData.pSampler = NS::TransferPtr(pDevice->newSamplerState(pSamplerDesc.get()));
    _renderData.samplerTable = NS::TransferPtr(pDevice->newBuffer(samplerTableBufSize, MTL::ResourceStorageModeShared));
    _renderData.samplerTable->setLabel(MTLSTR("UI Sampler Table"));
    
    auto pSamplerTableContents = (IRDescriptorTableEntry *)_renderData.samplerTable->contents();
    IRDescriptorTableSetSampler(pSamplerTableContents, _renderData.pSampler.get(), 0);
}

void UI::createResidencySet(MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue)
{
    assert(_uiConfig.fontAtlas.texture && "UI config needs to be configured before creating residency set");
    
    if (deviceSupportsResidencySets(pDevice))
    {
        NS::Error* pError = nullptr;
        
        auto pResidencySetDesc = NS::TransferPtr(MTL::ResidencySetDescriptor::alloc()->init());
        pResidencySetDesc->setLabel(MTLSTR("UI Residency Set"));
        
        _renderData.pResidencySet = NS::TransferPtr(pDevice->newResidencySet(pResidencySetDesc.get(), &pError));
        
        // Check for success. Residency sets require an Apple silicon Mac or iOS device,
        // returning nullptr when unavailable.
        if(_renderData.pResidencySet)
        {
            _renderData.pResidencySet->requestResidency();
            pCommandQueue->addResidencySet(_renderData.pResidencySet.get());
            
            for (uint8_t i = 0; i < kMaxFramesInFlight; ++i)
            {
                _renderData.pResidencySet->addAllocation(_renderData.resourceHeaps[i].get());
                _renderData.pResidencySet->addAllocation(_renderData.frameDataBuf[i].get());
                _renderData.pResidencySet->addAllocation(_renderData.highScorePositionBuf[i].get());
                _renderData.pResidencySet->addAllocation(_renderData.textureTable.get());
                _renderData.pResidencySet->addAllocation(_renderData.samplerTable.get());
                _renderData.pResidencySet->addAllocation(_renderData.bufferAllocator[i]->baseBuffer());
                _renderData.pResidencySet->addAllocation(_uiConfig.fontAtlas.texture.get());
            }
            
            _renderData.pResidencySet->commit();
        }
        else
        {
            printf("Error creating residency set: %s\n", pError->localizedDescription()->utf8String());
            assert(_renderData.pResidencySet);
        }
    }
}
