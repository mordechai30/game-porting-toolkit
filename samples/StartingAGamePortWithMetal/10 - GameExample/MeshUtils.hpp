/*
<samplecode>
  <abstract>
  Declares helpers that build the indexed triangle meshes (sprite quads,
  background) the renderer consumes.
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

#ifndef MESHUTILS_H
#define MESHUTILS_H

#include <Metal/Metal.hpp>
#include <vector>
#include "TextureLoader.h"

struct IndexedMesh
{
    MTL::Buffer*   pVertices;
    MTL::Buffer*   pIndices;
    uint32_t       numIndices;
    MTL::IndexType indexType;
    MTL::Winding   winding;
};

namespace mesh_utils
{
    IndexedMesh newCubeMesh(float size, MTL::Device* pDevice);
    IndexedMesh newHorizontalQuad(float size, uint32_t divs, MTL::Device* pDevice);
    IndexedMesh newScreenQuad(MTL::Device* pDevice, float horizontalScale=1.0f, float verticalScale=1.0f);
    void        releaseMesh(IndexedMesh* pIndexedMesh);
    IndexedMesh newTextMesh(const std::string& text, const FontAtlas& fontAtlas, MTL::Device* pDevice);
}

#endif // MESHUTILS_H
