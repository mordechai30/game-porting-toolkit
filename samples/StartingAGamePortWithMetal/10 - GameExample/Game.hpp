/*
<samplecode>
  <abstract>
  Declares the core C++ `Game` type, its `RenderData` and `GameState`
  structures, and the public update / draw entry points.
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

#ifndef GAME_HPP
#define GAME_HPP

#include <cstdint>
#include <vector>
#include <array>
#include <simd/simd.h>
#include <Metal/Metal.hpp>

#include "Controller.h"
#include "MeshUtils.hpp"
#include "PhaseAudio.hpp"
#include "BumpAllocator.hpp"

#include "Config.h"

// Texture table indices:

constexpr uint64_t kEnemyTextureIndex        = 0;
constexpr uint64_t kPlayerTextureIndex       = 1;
constexpr uint64_t kPlayerBulletTextureIndex = 2;
constexpr uint64_t kBackgroundTextureIndex   = 3;
constexpr uint64_t kExplosionTextureIndex    = 4;
constexpr uint64_t kNumTextures              = 5;

constexpr float kSpriteSize                  = 0.5f;
constexpr float kRumbleDurationSecs          = 0.1f;
constexpr float kRumbleIntensity             = 1.0f;

struct GameConfig
{
    uint8_t                                 enemyRows;
    uint8_t                                 enemyCols;
    uint32_t                                screenWidth;
    uint32_t                                screenHeight;
    NS::SharedPtr<MTL::Texture>             enemyTexture;
    NS::SharedPtr<MTL::Texture>             playerTexture;
    NS::SharedPtr<MTL::Texture>             playerBulletTexture;
    NS::SharedPtr<MTL::Texture>             backgroundTexture;
    NS::SharedPtr<MTL::Texture>             explosionTexture;
    NS::SharedPtr<MTL::Texture>             fontAtlasTexture;
    NS::SharedPtr<MTL::RenderPipelineState> spritePso;
    float                                   enemySpeed;
    float                                   enemyMoveDownStep;
    float                                   playerSpeed;
    float                                   playerFireCooldownSecs;
    uint8_t                                 maxPlayerBullets;
    uint8_t                                 maxExplosions;
    float                                   explosionDurationSecs;
    PhaseAudio*                             pAudioEngine;
};

/**
 * Holds resources the GPU accesses when drawing the game from GameRendering.cpp.
 * This structure triple-shadows all data that changes frame-to-frame to avoid
 * race conditions between the CPU and GPU as the CPU may update buffers while the
 * GPU reads from them.
 */
struct RenderData
{
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> frameDataBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> enemyPositionBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> playerPositionBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> playerBulletPositionBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> backgroundPositionBuf;
    std::array<NS::SharedPtr<MTL::Buffer>, kMaxFramesInFlight> explosionPositionBuf;
    
    NS::SharedPtr<MTL::Buffer>  textureTable;
    NS::SharedPtr<MTL::Buffer>  samplerTable;
    
    NS::SharedPtr<MTL::SamplerState> sampler;
    IndexedMesh                      spriteMesh;
    IndexedMesh                      backgroundMesh;
    
    std::array<std::unique_ptr<BumpAllocator>, kMaxFramesInFlight> bufferAllocator;
    std::array<NS::SharedPtr<MTL::Heap>, kMaxFramesInFlight>       resourceHeaps;
    
    NS::SharedPtr<MTL::ResidencySet> residencySet;
};

enum class EnemyDirection
{
    Right,
    Left,
    Down
};

enum class GameStatus
{
    Ongoing,
    PlayerWon,
    PlayerLost
};

/**
 * Hold the current state of a game. This structure holds the
 * ground truth for the game. The game's update() loop adjusts and
 * copies position data vectors into Metal buffers to ensure
 * the draw() function draws them in the correct position on screen.
 * Initialize in initializeGameState() for each new game or level.
 */
struct GameState
{
    uint32_t                    enemiesAlive;
    std::vector<simd::float4>   enemyPositions;
    
    uint8_t                     playerBulletsAlive;
    std::vector<simd::float4>   playerBulletPositions;
    float                       playerFireCooldownRemaining;
    
    uint8_t                     explosionsAlive;
    std::vector<simd::float4>   explosionPositions;
    std::vector<float>          explosionCooldownsRemaining;
    
    simd::float4                playerPosition;
    EnemyDirection              currentEnemyDirection;
    EnemyDirection              nextEnemyDirection;
    simd::float4                backgroundPosition;

    GameStatus                  gameStatus;
    
    float                       rumbleCountdownRemaining;
    float                       enemyMovedownRemaining;
    
    void                        reset();
    int                         playerScore;
};

/**
 * A game instance that the GameCooordinator starts, updates,
 * and restarts as the player clears levels (or loses).
 */
class Game : public NonCopyable
{
public:
    Game();
    ~Game();
    
    void             initialize(const GameConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue);
    void             restartGame(const GameConfig& config, float startingScore);
    const GameState* update(double targetTimestamp, uint8_t frameID);
    void             draw(MTL::RenderCommandEncoder* pRenderCmd, uint8_t frameID);
    void             drawUI(MTL::RenderCommandEncoder* pRenderCmd, uint8_t frameID, const FontAtlas&, const IndexedMesh&);

    
private:
    void createBuffers(const GameConfig& config, MTL::Device* pDevice);
    void initializeResidencySet(const GameConfig& config, MTL::Device* pDevice, MTL::CommandQueue* pCommandQueue);
    void initializeGameState(const GameConfig& config);
    void updateCollisions();

    GameController _gameController;
    GameConfig     _gameConfig;
    RenderData     _renderData;
    GameState      _gameState;
    
    uint32_t       _level;
    double         _prevTargetTimestamp;
    bool           _firstFrame;
};

#endif // GAME_HPP
