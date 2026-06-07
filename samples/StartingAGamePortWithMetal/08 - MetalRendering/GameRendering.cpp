/*
<samplecode>
  <abstract>
  Implements `Game::draw`, which encodes per-frame draw calls for background,
  enemies, player bullets, the player, and explosions, using the bump
  allocator for top-level argument buffers.
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

#include <Metal/Metal.hpp>

#define IR_RUNTIME_METALCPP
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

#include "MathUtils.hpp"
#include "MeshUtils.hpp"

#include "UI.hpp"
#include "Game.hpp"
#include "GameCoordinator.hpp"

// This buffer of GPU addresses binds resources to Metal shader converter pipelines.
// Its layout matches the root signature in `sprite_instanced.hlsl`. Keep them in sync
// when adding new global resources to your shaders.
struct TLAB
{
    uint64_t frameDataAddr;
    uint64_t instancedPositionsAddr;
    uint64_t textureTableAddr;
    uint64_t samplerTableAddr;
};

// Draw the game using a BumpAllocator to avoid transient allocations of
// small buffers for Metal shader converter pipelines' top-level argument
// buffers. The renderer issues every draw as instanced, calling
// `IRRuntimeDrawIndexedPrimitives` once per sprite type to avoid issuing
// more than one draw command for the same-looking sprite.
void Game::draw(MTL::RenderCommandEncoder* pRenderCmd, uint8_t frameID)
{
    assert(frameID < kMaxFramesInFlight);
    
    // Get, reset and install allocator for this frame's top-level argument buffers.
    // This enables the draw function to allocate all transient resource-binding buffers
    // from the bump allocator. At draw-call time, it simply adjusts the offset within
    // the base buffer, which is more efficient than binding a different buffer, or
    // copying bytes.
    BumpAllocator* pBufferAllocator = _renderData.bufferAllocator[frameID].get();
    pRenderCmd->setVertexBuffer(pBufferAllocator->baseBuffer(), 0, kIRArgumentBufferBindPoint);
    pRenderCmd->setFragmentBuffer(pBufferAllocator->baseBuffer(), 0, kIRArgumentBufferBindPoint);
    pBufferAllocator->reset();

    pRenderCmd->setRenderPipelineState(_gameConfig.spritePso.get());
    
    // When using residency sets, Metal makes these resources resident for all work
    // the renderer submits to its command queue, so the sample doesn't need to request
    // residency again. When not using residency sets, however, every encoder needs to
    // make its own residency requests.
    if(!_renderData.residencySet)
    {
        MTL::Resource* pFragReadResources[] = {
            _gameConfig.enemyTexture.get(),
            _gameConfig.playerTexture.get(),
            _gameConfig.playerBulletTexture.get(),
            _gameConfig.backgroundTexture.get(),
            _gameConfig.explosionTexture.get(),
            _renderData.textureTable.get(),
            _renderData.samplerTable.get()
            
            // Intentionally avoiding resources suballocated from
            // the resource heap for this frame. The sample makes
            // them all resident in a single call to useHeap() below.
        };
        
        pRenderCmd->useResources(pFragReadResources, sizeof(pFragReadResources)/sizeof(MTL::Resource*), MTL::ResourceUsageRead, MTL::RenderStageFragment);
        
        // Mark all position buffers resident at once by using the MTLHeap backing them:
        pRenderCmd->useHeap(_renderData.resourceHeaps[frameID].get());
    }
    
    // Draw background
    {
        const IndexedMesh& bgMesh = _renderData.backgroundMesh;
        pRenderCmd->setVertexBuffer(bgMesh.pVertices, 0, kIRVertexBufferBindPoint);
        
        auto [pBGTlab, bgTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pBGTlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pBGTlab->instancedPositionsAddr = _renderData.backgroundPositionBuf[frameID]->gpuAddress();
        pBGTlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kBackgroundTextureIndex * sizeof(IRDescriptorTableEntry);
        pBGTlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();
        
        pRenderCmd->setVertexBufferOffset(bgTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(bgTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       bgMesh.numIndices,
                                       bgMesh.indexType,
                                       bgMesh.pIndices,
                                       0,
                                       1);
    }
    
    // Get mesh for drawing sprites:
    const IndexedMesh& spriteMesh = _renderData.spriteMesh;
    pRenderCmd->setVertexBuffer(spriteMesh.pVertices, 0, kIRVertexBufferBindPoint);
    
    // Draw enemies:
    if (_gameState.enemiesAlive > 0)
    {
        auto [pEnemyTlab, enemyTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pEnemyTlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pEnemyTlab->instancedPositionsAddr = _renderData.enemyPositionBuf[frameID]->gpuAddress();
        pEnemyTlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kEnemyTextureIndex * sizeof(IRDescriptorTableEntry);
        pEnemyTlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();

        
            pRenderCmd->setVertexBufferOffset(enemyTlabOff, kIRArgumentBufferBindPoint);
            pRenderCmd->setFragmentBufferOffset(enemyTlabOff, kIRArgumentBufferBindPoint);
            
            IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                           spriteMesh.numIndices,
                                           spriteMesh.indexType,
                                           spriteMesh.pIndices,
                                           0,
                                           _gameState.enemiesAlive);
    }
    
    // Draw player bullets (if any):
    if ( _gameState.playerBulletsAlive > 0 )
    {
        auto [pBulletTlab, bulletTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pBulletTlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pBulletTlab->instancedPositionsAddr = _renderData.playerBulletPositionBuf[frameID]->gpuAddress();
        pBulletTlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kPlayerBulletTextureIndex * sizeof(IRDescriptorTableEntry);
        pBulletTlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();

        pRenderCmd->setVertexBufferOffset(bulletTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(bulletTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       spriteMesh.numIndices,
                                       spriteMesh.indexType,
                                       spriteMesh.pIndices,
                                       0,
                                       _gameState.playerBulletsAlive);
    }

    // Draw player:
    {
        auto [pPlayerTlab, playerTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pPlayerTlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pPlayerTlab->instancedPositionsAddr = _renderData.playerPositionBuf[frameID]->gpuAddress();
        pPlayerTlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kPlayerTextureIndex * sizeof(IRDescriptorTableEntry);
        pPlayerTlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();

        pRenderCmd->setVertexBufferOffset(playerTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(playerTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       spriteMesh.numIndices,
                                       spriteMesh.indexType,
                                       spriteMesh.pIndices,
                                       0,
                                       1);
    }
    
    
    // Draw explosions (if any):
    if ( _gameState.explosionsAlive > 0 )
    {
        auto [pExplosionTlab, explosionTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pExplosionTlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pExplosionTlab->instancedPositionsAddr = _renderData.explosionPositionBuf[frameID]->gpuAddress();
        pExplosionTlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kExplosionTextureIndex * sizeof(IRDescriptorTableEntry);
        pExplosionTlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();
        
        pRenderCmd->setVertexBufferOffset(explosionTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(explosionTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       spriteMesh.numIndices,
                                       spriteMesh.indexType,
                                       spriteMesh.pIndices,
                                       0,
                                       _gameState.explosionsAlive);
    }
}

void UI::draw(MTL::RenderCommandEncoder* pRenderCmd, uint8_t frameID)
{
    BumpAllocator* pBufferAllocator = _renderData.bufferAllocator[frameID].get();
    pBufferAllocator->reset();
    
    pRenderCmd->setVertexBuffer(pBufferAllocator->baseBuffer(), 0, kIRArgumentBufferBindPoint);
    pRenderCmd->setFragmentBuffer(pBufferAllocator->baseBuffer(), 0, kIRArgumentBufferBindPoint);

    pRenderCmd->setRenderPipelineState(_uiConfig.uiPso.get());
    
    // Fallback path for devices that don't support residency sets:
    if (!_renderData.pResidencySet)
    {
        MTL::Resource* pFragReadResources[] = {
            _renderData.textureTable.get(),
            _renderData.samplerTable.get(),
            _uiConfig.fontAtlas.texture.get()
        };
        
        pRenderCmd->useHeap(_renderData.resourceHeaps[frameID].get());
        pRenderCmd->useResources(pFragReadResources, sizeof(pFragReadResources)/sizeof(MTL::Resource*), MTL::ResourceUsageRead, MTL::RenderStageFragment);
    }

    {
        auto [pUITlab, uiTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pUITlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pUITlab->instancedPositionsAddr = _renderData.highScorePositionBuf[frameID]->gpuAddress();
        pUITlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kFontAtlasTextureIndex * sizeof(IRDescriptorTableEntry);
        pUITlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();
        
        const IndexedMesh& ui = _highScoreMesh;
        
        pRenderCmd->setVertexBuffer(ui.pVertices, 0, kIRVertexBufferBindPoint);
        
        pRenderCmd->setVertexBufferOffset(uiTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(uiTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       ui.numIndices,
                                       ui.indexType,
                                       ui.pIndices,
                                       0,
                                       1);
    }
    {
        auto [pUITlab, uiTlabOff] = pBufferAllocator->allocate<TLAB>();
        
        pUITlab->frameDataAddr = _renderData.frameDataBuf[frameID]->gpuAddress();
        pUITlab->instancedPositionsAddr = _renderData.currentScorePositionBuf[frameID]->gpuAddress();
        pUITlab->textureTableAddr = _renderData.textureTable->gpuAddress() + kFontAtlasTextureIndex * sizeof(IRDescriptorTableEntry);
        pUITlab->samplerTableAddr = _renderData.samplerTable->gpuAddress();
        
        const IndexedMesh& ui = _currentScoreMesh;
        
        pRenderCmd->setVertexBuffer(ui.pVertices, 0, kIRVertexBufferBindPoint);
        
        pRenderCmd->setVertexBufferOffset(uiTlabOff, kIRArgumentBufferBindPoint);
        pRenderCmd->setFragmentBufferOffset(uiTlabOff, kIRArgumentBufferBindPoint);
        
        IRRuntimeDrawIndexedPrimitives(pRenderCmd, MTL::PrimitiveTypeTriangle,
                                       ui.numIndices,
                                       ui.indexType,
                                       ui.pIndices,
                                       0,
                                       1);
    }
}

void GameCoordinator::resizeDrawable(float width, float height)
{
    constexpr float kMetalNDCLength = 2.0f;
    
    // Handle resizing events, such as creating a new texture into which to trace rays
    mesh_utils::releaseMesh(&_screenMesh);
    
    float imgAspect = 1920.f / 1080.f;
    
    float aspect = width / (float)height;
    
    if (imgAspect <= aspect)
    {
        _screenMesh = mesh_utils::newScreenQuad(_pDevice, kMetalNDCLength * imgAspect, kMetalNDCLength);
        _presentOrtho = math::makeOrtho(-1.0 * aspect, 1.0 * aspect,
                                        1.0, -1.0,
                                        -1, 1);
    }
    else
    {
        _screenMesh = mesh_utils::newScreenQuad(_pDevice, kMetalNDCLength, kMetalNDCLength / imgAspect);
        _presentOrtho = math::makeOrtho(-1.0, 1.0,
                                        1.0 / aspect, -1.0 / aspect,
                                        -1, 1);
    }
}
