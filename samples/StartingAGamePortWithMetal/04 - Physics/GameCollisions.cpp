/*
<samplecode>
  <abstract>
  Implements `Game::updateCollisions`, using SIMD distance tests to detect
  bullet-enemy and enemy-player collisions and to maintain the alive-entity
  invariant via swap-and-shrink.
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

void Game::updateCollisions()
{
    // Scan for enemy hits.

    // Loop over enemies. If hit, kill the bullet and kill the enemy by
    // swapping them to the end and reducing the count of alive entities.
    
    for (uint8_t b = 0; b < _gameState.playerBulletsAlive; ++b)
    {
        for (uint32_t e = 0; e < _gameState.enemiesAlive; ++e)
        {
            if ( simd_distance( _gameState.enemyPositions[e].xy, _gameState.playerBulletPositions[b].xy ) < 0.5f)
            {
                // bullet 'b' collides with enemy 'e'. Remove both:
                assert(_gameState.playerBulletsAlive > 0);
                assert(_gameState.playerBulletsAlive <= _gameState.playerBulletPositions.size());
                
                assert(_gameState.enemiesAlive > 0);
                assert(_gameState.enemiesAlive <= _gameState.enemyPositions.size());
                
                // Destroy bullet
                std::swap(_gameState.playerBulletPositions[b],
                          _gameState.playerBulletPositions[_gameState.playerBulletsAlive-1]);
                _gameState.playerBulletsAlive--;
                
                // Create explosion
                assert(_gameState.explosionsAlive < _gameConfig.maxExplosions);
                uint32_t currentExplosion = _gameState.explosionsAlive++;
                _gameState.explosionPositions[currentExplosion].xy = _gameState.enemyPositions[e].xy;
                _gameState.explosionPositions[currentExplosion].z = (rand() & 0x1); // pick random asset
                _gameState.explosionCooldownsRemaining[currentExplosion] = _gameConfig.explosionDurationSecs;
                
                // Destroy enemy
                std::swap(_gameState.enemyPositions[e],
                          _gameState.enemyPositions[_gameState.enemiesAlive-1]);
                _gameState.enemiesAlive--;                
                _gameState.playerScore += 10 * (1 + _level);
                
                // Play gentle rumble
                _gameState.rumbleCountdownRemaining = kRumbleDurationSecs;
                _gameController.setHapticIntensity(kRumbleIntensity);
                
                // Play audio
                _gameConfig.pAudioEngine->playSoundEvent("impact2.mp3");
                
                if (_gameState.playerBulletsAlive == 0 || _gameState.enemiesAlive == 0)
                {
                    // all bullets (or enemies) consumed
                    goto bullet_collision_end;
                }
            }
        }
    }
    bullet_collision_end:
    
    // Check enemy-player and enemy-screen bottom collisions (game over):
    const float screenBottom = _gameState.playerPosition.y - kSpriteSize;
    for (uint32_t e = 0; e < _gameState.enemiesAlive; ++e)
    {
        const simd_float4 enemyPosition = _gameState.enemyPositions[e];
        bool collided = false;
        collided = (simd_distance( enemyPosition.xy, _gameState.playerPosition.xy ) < 0.45f) // provide a small tolerance
                 || (enemyPosition.y <= screenBottom);
        
        if (collided)
        {
            _gameState.rumbleCountdownRemaining = kRumbleDurationSecs;
            _gameController.setHapticIntensity(kRumbleIntensity);
            _gameConfig.pAudioEngine->playSoundEvent("impact2.mp3");
            _gameConfig.pAudioEngine->playSoundEvent("failure.mp3");
            
            _gameState.gameStatus = GameStatus::PlayerLost;
            _level = 0;
            break;
        }
    }

}
