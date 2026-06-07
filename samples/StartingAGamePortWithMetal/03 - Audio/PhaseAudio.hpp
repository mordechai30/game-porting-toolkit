/*
<samplecode>
  <abstract>
  Declares the PHASE-based audio engine that loads the sample's MP3 sound
  effects and plays sound events on demand.
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

#ifndef PHASEAUDIO_H
#define PHASEAUDIO_H

// For CFTypeRef
#include <CoreFoundation/CFBase.h>
#include <string>
#include <vector>

#include "NonCopyable.h"

class PhaseAudio : public NonCopyable
{
public:
    PhaseAudio(const std::string& assetSearchPath);
    ~PhaseAudio();
    
    std::string loadStereoSound(const std::string& assetSearchPath, const std::string& assetName);
    void playSoundEvent(const std::string& identifier);
private:
    
    // Track backing data to release:
    struct SoundDatum
    {
        CFTypeRef   asset;
        CFTypeRef   event;
        std::string assetIdentifier;
        std::string eventIdentifier;
    };
    
    std::vector<SoundDatum> soundData;
    CFTypeRef _phaseEngine;
};

#endif // PHASEAUDIO_H
