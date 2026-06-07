/*
<samplecode>
  <abstract>
  Declares the input layer that subscribes to `GCController` connect /
  disconnect notifications and surfaces unified game-controller state to the
  C++ game core.
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

#ifndef CONTROLLER_H
#define CONTROLLER_H

// For `CFIndex` and `CFTypeRef`.
#include <CoreFoundation/CFBase.h>
#include <unordered_map>

#include <simd/simd.h>
#include "NonCopyable.h"

namespace MTL
{
    class RenderCommandEncoder;
}

class GameController : public NonCopyable
{
public:
    GameController();
    ~GameController();
    
    bool isLeftArrowDown() const;
    bool isRightArrowDown() const;
    bool isSpacebarDown() const;
    
    float leftThumbstickX() const;
    float rightThumbstickX() const;
    bool isButtonADown() const;
    
    void setHapticIntensity(float intensity) const;
    
    void  renderOverlay(MTL::RenderCommandEncoder* pEnc);
    
    simd::float3 accelerometerData() const;
private:
    CFTypeRef                         _haptics;
    CFTypeRef                         _motionManager;
};

#endif // CONTROLLER_H
