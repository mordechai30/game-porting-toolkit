/*
<samplecode>
  <abstract>
  Declares helpers that load Metal libraries from the application bundle and
  build the present and instanced-sprite pipeline state objects.
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


#ifndef SHADERPIPELINEBUILDER_HPP
#define SHADERPIPELINEBUILDER_HPP

#include <Metal/Metal.hpp>

namespace shader_pipeline
{

MTL::RenderPipelineState* newPresentPipeline(bool alphaBlending, const std::string& shaderSearchPath, MTL::Device* pDevice);
MTL::RenderPipelineState* newInstancedSpritePipeline(const std::string& shaderSearchpath, MTL::Device* pDevice, MTL::PixelFormat pixelFormat);

}

#endif // SHADERPIPELINEBUILDER_HPP
