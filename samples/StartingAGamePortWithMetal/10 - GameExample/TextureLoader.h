/*
<samplecode>
  <abstract>
  Declares helpers that load PNG sprite assets from the application bundle
  into `MTL::Texture` instances.
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

#ifndef TEXTURELOADER_H
#define TEXTURELOADER_H

#include <Metal/Metal.hpp>
#include <string>
#include <simd/simd.h>

MTL::Texture* newTextureFromFile(const std::string& texturePath, MTL::Device* pDevice);
MTL::Texture* newTextureArrayFromFiles(const std::vector<std::string>& texturePaths, MTL::Device* pDevice, MTL::CommandBuffer* pCommandBuffer);

static char g_chars[] = {
    '!', '\"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
    '0', '1',  '2', '3', '4', '5', '6',  '7', '8', '9', ':', ';', '<', '=', '>',
    '?', '@',  'A', 'B', 'C', 'D', 'E',  'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O',  'P', 'Q', 'R', 'S', 'T',  'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\',
    ']', '^',  '_'
};

constexpr size_t kNumCharacters = sizeof(g_chars) / sizeof(g_chars[0]);

struct FontAtlas
{
    struct CharUVs
    {
        simd::float2 nw;
        simd::float2 ne;
        simd::float2 se;
        simd::float2 sw;
    };
    
    NS::SharedPtr<MTL::Texture> texture;
    CharUVs charToUVs[kNumCharacters];
};

FontAtlas newFontAtlas(MTL::Device* pDevice);

#endif // TEXTURELOADER_H
