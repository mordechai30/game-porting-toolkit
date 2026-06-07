/*
<samplecode>
  <abstract>
  Shared compile-time configuration — `kMaxFramesInFlight`, the `FrameData`
  shader-side struct mirror, and Metal capability queries.
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

#ifndef CONFIG_H
#define CONFIG_H

constexpr size_t kMaxFramesInFlight = 3;

bool deviceSupportsResidencySets(MTL::Device* pDevice);

// Keep in sync with the `FrameData` struct in `sprite_instanced.hlsl`.
struct FrameData
{
    simd::float4x4 projectionMatrix;
};

#endif // CONFIG_H
