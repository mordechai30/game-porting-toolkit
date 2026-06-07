/*
<samplecode>
  <abstract>
  Implements game initialization, the per-frame simulation step, and Metal
  resource setup (heaps, residency sets, triple-buffered position buffers).
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

#include "Game.hpp"

#include "MathUtils.hpp"

#define IR_RUNTIME_METALCPP
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

#include <TargetConditionals.h>

bool deviceSupportsResidencySets(MTL::Device* pDevice)
{
    static bool result = false;
    
    static std::once_flag flag;
    std::call_once(flag, [&](){
        NS::OperatingSystemVersion minimumVersion;
#if TARGET_OS_OSX
        minimumVersion.majorVersion = 15;
        minimumVersion.minorVersion = 0;
        minimumVersion.patchVersion = 0;
#elif TARGET_OS_IOS
        minimumVersion.majorVersion = 18;
        minimumVersion.minorVersion = 0;
        minimumVersion.patchVersion = 0;
#endif
        result = NS::ProcessInfo::processInfo()->isOperatingSystemAtLeastVersion(minimumVersion) && pDevice->supportsFamily(MTL::GPUFamilyApple6);
    });
    
    return result;
}

Game::Game()
: _gameConfig()
, _level(0)
, _prevTargetTimestamp(0.0f)
, _firstFrame(true)
{
    
}

Game::~Game()
{
    mesh_utils::releaseMesh(&_renderData.spriteMesh);
    mesh_utils::releaseMesh(&_renderData.backgroundMesh);
}

void Game::initializeGameState(const GameConfig& config)
{
    auto sw = config.screenWidth;
    auto sh = config.screenHeight;
    
    // The simulation runs in a virtual world-space canvas (canvasW = 10 units wide)
    // independent of the render resolution. The orthographic projection maps this
    // canvas onto the 1920x1080 render target; Core Animation letterboxes from
    // 1920x1080 to the player's display. This decouples gameplay coordinates from
    // device pixels — sprite sizes and movement constants stay consistent across
    // macOS, iPad, and iPhone.
    const float canvasW = 10;
    const float canvasH = canvasW * sh / (float)sw;
    
    const float spriteSize = kSpriteSize;
    
    // Ortho projection:
    for (uint8_t i = 0; i < kMaxFramesInFlight; ++i)
    {
        assert(_renderData.frameDataBuf[i]);
        auto pFrameData = (FrameData *)_renderData.frameDataBuf[i]->contents();
        pFrameData->projectionMatrix = math::makeOrtho(-canvasW/2, canvasW/2, canvasH/2, -canvasH/2, -1, 1);
    }
    
    // Pack enemies together (leave some empty space):
    const float enemyPackW = canvasW;
    const float enemyPackH = canvasH/2.25;

    _gameState.enemyPositions.resize(config.enemyRows * config.enemyCols);
    for (uint8_t y = 0; y < config.enemyRows; ++y)
    {
        for (uint8_t x = 0; x < config.enemyCols; ++x)
        {

            const float xx = (enemyPackW * x / config.enemyCols) - (enemyPackW / 2) + (2 * spriteSize);
            const float yy = (enemyPackH * y / config.enemyRows) - (enemyPackH / 2) + (2 * spriteSize);
            const int zz = rand() % 3;
            _gameState.enemyPositions[y * config.enemyCols + x] = simd_make_float4(xx, yy, zz, 1);
        }
    }

    _gameState.playerPosition = simd_make_float4(0, -canvasH/2 + spriteSize * 2, 0, 1);

    _gameState.playerBulletsAlive = 0;
    _gameState.playerBulletPositions.resize(_gameConfig.maxPlayerBullets); // automatically init'd to 0

    _gameState.explosionsAlive = 0;
    _gameState.explosionPositions.resize(_gameConfig.maxExplosions); // automatically init'd to 0
    _gameState.explosionCooldownsRemaining.resize(_gameConfig.maxExplosions); // automatically init'd to 0
 
    _gameState.rumbleCountdownRemaining = 0.0f;
    _gameState.enemyMovedownRemaining = 0.0f;
}

void Game::createBuffers(const GameConfig& config, MTL::Device* pDevice)
{
    // Sprite mesh:
    _renderData.spriteMesh = mesh_utils::newScreenQuad(pDevice, kSpriteSize, kSpriteSize);
    _renderData.backgroundMesh = mesh_utils::newScreenQuad(pDevice, 10*1920/1080.0, 10);
    
    // Allocate a Metal heap for all resources:
    
    const size_t enemyPositionBufSize        = config.enemyRows * config.enemyCols * sizeof(simd::float4);
    const size_t playerPositionBufSize       = sizeof(simd::float4);
    const size_t frameDataBufSize            = sizeof(FrameData);
    const size_t playerBulletPositionBufSize = sizeof(simd::float4) * config.maxPlayerBullets;
    const size_t backgroundPositionBufSize   = sizeof(simd::float4);
    const size_t explosionPositionBufSize    = sizeof(simd::float4) * config.maxExplosions;
    
    auto pHeapDesc = NS::TransferPtr(MTL::HeapDescriptor::alloc()->init());
    pHeapDesc->setSize(enemyPositionBufSize +
                       playerPositionBufSize +
                       frameDataBufSize +
                       playerBulletPositionBufSize +
                       backgroundPositionBufSize +
                       explosionPositionBufSize);
    pHeapDesc->setResourceOptions(MTL::ResourceStorageModeShared);
    pHeapDesc->setHazardTrackingMode(MTL::HazardTrackingModeUntracked);
    
    
    for (uint8_t i = 0u; i < kMaxFramesInFlight; ++i)
    {
        auto pHeap = NS::TransferPtr(pDevice->newHeap(pHeapDesc.get()));
        _renderData.resourceHeaps[i] = pHeap;
        
        _renderData.enemyPositionBuf[i] = NS::TransferPtr(pHeap->newBuffer(enemyPositionBufSize, MTL::ResourceStorageModeShared));
        _renderData.enemyPositionBuf[i]->setLabel(MTLSTR("enemyPositionBuf"));
        
        _renderData.playerPositionBuf[i] = NS::TransferPtr(pHeap->newBuffer(playerPositionBufSize, MTL::ResourceStorageModeShared));
        _renderData.playerPositionBuf[i]->setLabel(MTLSTR("playerPositionBuf"));
        
        _renderData.frameDataBuf[i] = NS::TransferPtr(pHeap->newBuffer(frameDataBufSize, MTL::ResourceStorageModeShared));
        _renderData.frameDataBuf[i]->setLabel(MTLSTR("frameDataBuf"));
        
        _renderData.playerBulletPositionBuf[i] = NS::TransferPtr(pHeap->newBuffer(playerBulletPositionBufSize, MTL::ResourceStorageModeShared));
        _renderData.playerBulletPositionBuf[i]->setLabel(MTLSTR("playerBulletPositionBuf"));
        
        _renderData.backgroundPositionBuf[i] = NS::TransferPtr(pHeap->newBuffer(backgroundPositionBufSize, MTL::ResourceStorageModeShared));
        _renderData.backgroundPositionBuf[i]->setLabel(MTLSTR("backgroundPositionBuf"));
        
        _renderData.explosionPositionBuf[i] = NS::TransferPtr(pHeap->newBuffer(explosionPositionBufSize, MTL::ResourceStorageModeShared));
        _renderData.explosionPositionBuf[i]->setLabel(MTLSTR("explosionPositionBuf"));
        
        constexpr uint64_t bumpAllocatorCapacity = 1024; // 1 KiB
        _renderData.bufferAllocator[i] = std::make_unique<BumpAllocator>(pDevice, bumpAllocatorCapacity, MTL::ResourceStorageModeShared);
    }
    
    // Texture and sampler tables:
    
    const size_t textureTableBufSize         = sizeof(IRDescriptorTableEntry) * kNumTextures;
    const size_t samplerTableBufSize         = sizeof(IRDescriptorTableEntry) * 1;

    // Texture table:
    _renderData.textureTable = NS::TransferPtr(pDevice->newBuffer(textureTableBufSize, MTL::ResourceStorageModeShared));
    _renderData.textureTable->setLabel(MTLSTR("Sprite Texture Table"));
    auto pTextureTableContents = (IRDescriptorTableEntry *)_renderData.textureTable->contents();
    
    IRDescriptorTableSetTexture(&(pTextureTableContents[kEnemyTextureIndex]), config.enemyTexture.get(), 0, 0);
    IRDescriptorTableSetTexture(&(pTextureTableContents[kPlayerTextureIndex]), config.playerTexture.get(), 0, 0);
    IRDescriptorTableSetTexture(&(pTextureTableContents[kPlayerBulletTextureIndex]), config.playerBulletTexture.get(), 0, 0);
    IRDescriptorTableSetTexture(&(pTextureTableContents[kBackgroundTextureIndex]), config.backgroundTexture.get(), 0, 0);
    IRDescriptorTableSetTexture(&(pTextureTableContents[kExplosionTextureIndex]), config.explosionTexture.get(), 0, 0);
    
    // Sampler table:
    auto pSamplerDesc = NS::TransferPtr(MTL::SamplerDescriptor::alloc()->init());
    pSamplerDesc->setSupportArgumentBuffers(true);
    pSamplerDesc->setMagFilter(MTL::SamplerMinMagFilterLinear);
    pSamplerDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    pSamplerDesc->setRAddressMode(MTL::SamplerAddressModeClampToEdge);
    pSamplerDesc->setSAddressMode(MTL::SamplerAddressModeClampToEdge);
    pSamplerDesc->setTAddressMode(MTL::SamplerAddressModeClampToEdge);
    
    _renderData.sampler = NS::TransferPtr(pDevice->newSamplerState(pSamplerDesc.get()));
    _renderData.samplerTable = NS::TransferPtr(pDevice->newBuffer(samplerTableBufSize, MTL::ResourceStorageModeShared));
    _renderData.samplerTable->setLabel(MTLSTR("Sprite Sampler Table"));
    
    // Set LOD bias to to account for image scaling by MetalFX.
    auto pSamplerTableContents = (IRDescriptorTableEntry *)_renderData.samplerTable->contents();
    IRDescriptorTableSetSampler(pSamplerTableContents, _renderData.sampler.get(), -0.5);
}

void Game::initializeResidencySet(const GameConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue)
{
    if(deviceSupportsResidencySets(pDevice))
    {
        NS::Error* pError = nullptr;
        
        auto pResidencySetDesc = NS::TransferPtr(MTL::ResidencySetDescriptor::alloc()->init());
        pResidencySetDesc->setLabel(MTLSTR("Game Residency Set"));
        
        _renderData.residencySet = NS::TransferPtr(pDevice->newResidencySet(pResidencySetDesc.get(), &pError));
        
        // Check for success. Residency sets require an Apple silicon Mac or iOS device,
        // returning nullptr when unavailable.
        if(_renderData.residencySet)
        {
            // Call requestResidency() to make allocations resident for this command queue.
            // After committing the residency set, all subsequent work the sample submits to
            // this command queue can automatically assume these resources are resident.
            _renderData.residencySet->requestResidency();
            pCommandQueue->addResidencySet(_renderData.residencySet.get());
            
            for (uint8_t i = 0u; i < kMaxFramesInFlight; ++i)
            {
                _renderData.residencySet->addAllocation(_renderData.resourceHeaps[i].get());
                _renderData.residencySet->addAllocation(_renderData.enemyPositionBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.playerPositionBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.frameDataBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.playerBulletPositionBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.backgroundPositionBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.explosionPositionBuf[i].get());
                _renderData.residencySet->addAllocation(_renderData.bufferAllocator[i]->baseBuffer());
            }
            
            _renderData.residencySet->addAllocation(config.enemyTexture.get());
            _renderData.residencySet->addAllocation(config.playerTexture.get());
            _renderData.residencySet->addAllocation(config.playerBulletTexture.get());
            _renderData.residencySet->addAllocation(config.backgroundTexture.get());
            _renderData.residencySet->addAllocation(config.explosionTexture.get());
            
            _renderData.residencySet->addAllocation(_renderData.textureTable.get());
            _renderData.residencySet->addAllocation(_renderData.samplerTable.get());
            
            _renderData.residencySet->commit();
        }
        else
        {
            printf("Error creating residency set: %s\n", pError->localizedDescription()->utf8String());
            assert(_renderData.residencySet);
        }
    }
}

void Game::initialize(const GameConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue)
{
    createBuffers(config, pDevice);
    initializeResidencySet(config, pDevice, pCommandQueue);
}

void GameState::reset()
{
    enemiesAlive                = 0;
    playerBulletsAlive          = 0;
    playerFireCooldownRemaining = 0;
    explosionsAlive             = 0;
    playerPosition              = simd_make_float4(0,0,0,1);
    currentEnemyDirection       = EnemyDirection::Right;
    nextEnemyDirection          = EnemyDirection::Right;
    backgroundPosition          = simd_make_float4(0,0,0,1);
    gameStatus                  = GameStatus::Ongoing;
    rumbleCountdownRemaining    = 0;
    enemyMovedownRemaining      = 0;
}

void Game::restartGame(const GameConfig &config, float startingScore)
{
    assert(_renderData.spriteMesh.pIndices || !"Attempt to restart game without calling initialize() first");
    
    _gameConfig = config;
    _gameConfig.enemySpeed *= (1 + _level * 0.25f); // game gets harder as the player progresses
    
    const uint32_t cols = _gameConfig.enemyCols;
    const uint32_t rows = _gameConfig.enemyRows;
    
    _gameState.reset();
    _gameState.enemiesAlive = rows * cols;
    _gameState.enemyPositions.resize(_gameState.enemiesAlive);
    _gameState.gameStatus = GameStatus::Ongoing;
    _gameState.playerScore = startingScore;
    
    initializeGameState(config);
}

const GameState* Game::update(double targetTimestamp, uint8_t frameID)
{
    assert(frameID < kMaxFramesInFlight);
    
    float deltat = targetTimestamp - _prevTargetTimestamp;
    deltat = std::fminf(deltat, 0.033); // protect from large updates after backgrounding
    _prevTargetTimestamp = targetTimestamp;
    
    if (_firstFrame)
    {
        _firstFrame = false;
        return &_gameState;
    }
    
    if (_gameState.rumbleCountdownRemaining >= 0.0f)
    {
        _gameState.rumbleCountdownRemaining -= deltat;
        if (_gameState.rumbleCountdownRemaining <= 0.0f)
        {
            _gameController.setHapticIntensity(0.0f);
        }
    }
    
    const size_t numEnemies = _gameState.enemiesAlive;
    
    // Update game state:
    const float enemySpeed = _gameConfig.enemySpeed;
    
    if (_gameState.enemyMovedownRemaining > 0.0f)
    {
        for (uint32_t i = 0; i < numEnemies; ++i)
        {
            _gameState.enemyPositions[i].y -= enemySpeed * 2 * deltat;
        }
    }
    
    // enemies
    if (_gameState.currentEnemyDirection == EnemyDirection::Right)
    {
        for (uint32_t i = 0; i < numEnemies; ++i)
        {
            _gameState.enemyPositions[i].x += enemySpeed * deltat;
        }
    }
    else if (_gameState.currentEnemyDirection == EnemyDirection::Left)
    {
        for (uint32_t i = 0; i < numEnemies; ++i)
        {
            _gameState.enemyPositions[i].x -= enemySpeed * deltat;
        }
    }
    else if (_gameState.currentEnemyDirection == EnemyDirection::Down)
    {
        for (uint32_t i = 0; i < numEnemies; ++i)
        {
            _gameState.enemyPositions[i].y -= enemySpeed * 2.0f * deltat;
        }
    }
    
    // determine next direction:
    if (_gameState.currentEnemyDirection == EnemyDirection::Left || _gameState.currentEnemyDirection == EnemyDirection::Right)
    {
        const bool goingRight = (_gameState.currentEnemyDirection == EnemyDirection::Right);
        const bool goingLeft =  (_gameState.currentEnemyDirection == EnemyDirection::Left);
        for (uint32_t i = 0; i < numEnemies; ++i)
        {
            const float canvasW = 10;
            if ((_gameState.enemyPositions[i].x > canvasW/2 - 0.25) && goingRight)
            {
                _gameState.currentEnemyDirection = EnemyDirection::Down;
                _gameState.nextEnemyDirection = EnemyDirection::Left;
                _gameState.enemyMovedownRemaining = _gameConfig.enemyMoveDownStep;
                break;
            }
            else if ((_gameState.enemyPositions[i].x < -canvasW/2 + 0.25) && goingLeft)
            {
                _gameState.currentEnemyDirection = EnemyDirection::Down;
                _gameState.nextEnemyDirection = EnemyDirection::Right;
                _gameState.enemyMovedownRemaining = _gameConfig.enemyMoveDownStep;
                break;
            }
        }
    }
    else if (_gameState.currentEnemyDirection == EnemyDirection::Down)
    {
        _gameState.enemyMovedownRemaining = std::max(_gameState.enemyMovedownRemaining - 10.f * deltat, 0.0f);
        if (_gameState.enemyMovedownRemaining <= 0)
        {
            _gameState.currentEnemyDirection = _gameState.nextEnemyDirection;
        }
    }

    // player (based on inputs):
    const float playerSpeed = _gameConfig.playerSpeed;
    
    if (_gameController.isLeftArrowDown())
    {
        _gameState.playerPosition.x -= playerSpeed * deltat;
    }
    else if (_gameController.isRightArrowDown())
    {
        _gameState.playerPosition.x += playerSpeed * deltat;
    }
    else
    {
        _gameState.playerPosition.x += playerSpeed * deltat * _gameController.leftThumbstickX();
    }
    
    // player firing:
    _gameState.playerFireCooldownRemaining -= deltat;
    
    if (_gameState.playerFireCooldownRemaining <= 0)
    {
        if (_gameController.isSpacebarDown() || (_gameController.isButtonADown()))
        {
            if (_gameState.playerBulletsAlive < _gameConfig.maxPlayerBullets)
            {
                _gameState.playerBulletPositions[_gameState.playerBulletsAlive++] = _gameState.playerPosition;
                _gameState.playerFireCooldownRemaining = _gameConfig.playerFireCooldownSecs;
                _gameConfig.pAudioEngine->playSoundEvent("laser2.mp3");
            }
        }
    }
    
    // player bullets
    for (size_t i = 0; i < _gameState.playerBulletsAlive; ++i)
    {
        //_gameState.playerBulletPositions[i].y -= playerSpeed * deltat;
        _gameState.playerBulletPositions[i].y += playerSpeed * deltat;
        
        // bullet is now offscreen:
        if (_gameState.playerBulletPositions[i].y > 2.5)
        {
            std::swap(_gameState.playerBulletPositions[i],
                      _gameState.playerBulletPositions[_gameState.playerBulletsAlive-1]);
            _gameState.playerBulletsAlive--;
        }
    }
    
    updateCollisions();
    
    // Update explosions currently on screen:
    uint32_t explosionsToDecay = _gameState.explosionsAlive;
    for (uint32_t i = 0; i < explosionsToDecay; ++i)
    {
        _gameState.explosionCooldownsRemaining[i] -= deltat;
        if (_gameState.explosionCooldownsRemaining[i] <= 0)
        {
            std::swap(_gameState.explosionPositions[i], _gameState.explosionPositions[_gameState.explosionsAlive-1]);
            std::swap(_gameState.explosionCooldownsRemaining[i], _gameState.explosionCooldownsRemaining[_gameState.explosionsAlive-1]);
            --_gameState.explosionsAlive;
        }
    }
    
    // Update render data:
    
    assert(_renderData.enemyPositionBuf[frameID]);
    assert(_renderData.playerPositionBuf[frameID]);
    assert(_renderData.playerBulletPositionBuf[frameID]);
    assert(_renderData.explosionPositionBuf[frameID]);
    
    // bullets
    if (_gameState.playerBulletsAlive > 0)
    {
        memcpy(_renderData.playerBulletPositionBuf[frameID]->contents(),
               _gameState.playerBulletPositions.data(),
               _gameState.playerBulletsAlive * sizeof(simd::float4));
    }
    
    // enemies
    if (_gameState.enemiesAlive > 0)
    {
        memcpy(_renderData.enemyPositionBuf[frameID]->contents(),
               _gameState.enemyPositions.data(),
               _gameState.enemiesAlive * sizeof(simd::float4));
    }
    
    // player
    auto pPlayerPositionBufContents = (simd::float4 *)(_renderData.playerPositionBuf[frameID]->contents());
    *pPlayerPositionBufContents = _gameState.playerPosition;
    
    
    // parallax background
    simd::float3 accel = _gameController.accelerometerData();
    _gameState.backgroundPosition.x -= accel.y/8;
    _gameState.backgroundPosition.y -= accel.z/8;
    _gameState.backgroundPosition.x = (_gameState.backgroundPosition.x > 0.2)? 0.2 : _gameState.backgroundPosition.x;
    _gameState.backgroundPosition.x = (_gameState.backgroundPosition.x < -0.2)? -0.2 : _gameState.backgroundPosition.x;
    _gameState.backgroundPosition.y = (_gameState.backgroundPosition.y > 0.2)? 0.2 : _gameState.backgroundPosition.y;
    _gameState.backgroundPosition.y = (_gameState.backgroundPosition.y < -0.2)? -0.2 : _gameState.backgroundPosition.y;
    
    auto pBackgroundPositionBufContents = (simd::float4 *)(_renderData.backgroundPositionBuf[frameID]->contents());
    *pBackgroundPositionBufContents = _gameState.backgroundPosition;

    // explosion positions
    if (_gameState.explosionsAlive > 0)
    {
        memcpy(_renderData.explosionPositionBuf[frameID]->contents(),
               _gameState.explosionPositions.data(),
               _gameState.explosionsAlive * sizeof(simd::float4));
    }
    
    // check end-game condition:
    if (_gameState.enemiesAlive == 0)
    {
        ++_level;
        _gameState.gameStatus = GameStatus::PlayerWon;
        _gameConfig.pAudioEngine->playSoundEvent("success.mp3");
    }
    
    return &_gameState;
}
