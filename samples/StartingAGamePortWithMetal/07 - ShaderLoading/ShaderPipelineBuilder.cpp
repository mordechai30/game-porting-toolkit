/*
<samplecode>
  <abstract>
  Loads converted Metal libraries via `dispatch_data_t`, resolves vertex /
  fragment entry points, and assembles the render pipeline state objects the
  renderer uses each frame.
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


#include "ShaderPipelineBuilder.hpp"

#define IR_RUNTIME_METALCPP
#include <metal_irconverter_runtime/metal_irconverter_runtime.h>

#include <simd/simd.h>
#include <fstream>

static std::vector<uint8_t> readBytecode(const std::string& path)
{
    std::ifstream in(path);
    assert(in);
    if (in)
    {
        in.seekg(0, std::ios::end);
        size_t siz = in.tellg();
        in.seekg(0, std::ios::beg);
        
        std::vector<uint8_t> bytecode(siz);
        in.read((char *)bytecode.data(), siz);
        
        return bytecode;
    }
    
    return {};
}

static MTL::Library* newLibraryFromBytecode(const std::vector<uint8_t>& bytecode, MTL::Device* pDevice)
{
    NS::Error* pError = nullptr;
    dispatch_data_t data = dispatch_data_create(bytecode.data(), bytecode.size(), dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    MTL::Library* pLib = pDevice->newLibrary(data, &pError);
    if (!pLib)
    {
        printf("Error building Metal library: %s\n", pError->localizedDescription()->utf8String());
        assert(pLib);
    }
    CFRelease(data);
    return pLib;
}

MTL::RenderPipelineState* shader_pipeline::newPresentPipeline(bool alphaBlending, const std::string& shaderSearchPath, MTL::Device* pDevice)
{
    NS::SharedPtr<MTL::Library> pVtxLib = NS::TransferPtr(newLibraryFromBytecode(readBytecode(shaderSearchPath + "/present_vs.metallib"), pDevice));
    assert(pVtxLib);
    
    NS::SharedPtr<MTL::Library> pFragLib = NS::TransferPtr(newLibraryFromBytecode(readBytecode(shaderSearchPath + "/present_fs.metallib"), pDevice));
    assert(pFragLib);
    
    NS::SharedPtr<MTL::Function> pVFn = NS::TransferPtr(pVtxLib->newFunction(MTLSTR("MainVS")));
    NS::SharedPtr<MTL::Function> pFFn = NS::TransferPtr(pFragLib->newFunction(MTLSTR("MainFS")));
    assert(pVFn);
    assert(pFFn);
    
    NS::SharedPtr<MTL::VertexDescriptor> pVtxDesc = NS::TransferPtr(MTL::VertexDescriptor::alloc()->init());
    auto pAttrib0 = pVtxDesc->attributes()->object(kIRStageInAttributeStartIndex + 0);
    auto pAttrib1 = pVtxDesc->attributes()->object(kIRStageInAttributeStartIndex + 1);
    auto pLayout  = pVtxDesc->layouts()->object(kIRVertexBufferBindPoint);
    
    pAttrib0->setFormat(MTL::VertexFormatFloat4);
    pAttrib0->setOffset(0);
    pAttrib0->setBufferIndex(kIRVertexBufferBindPoint);
    
    pAttrib1->setFormat(MTL::VertexFormatFloat2);
    pAttrib1->setOffset(sizeof(simd::float4));
    pAttrib1->setBufferIndex(kIRVertexBufferBindPoint);
    
    pLayout->setStride(sizeof(simd::float4) + sizeof(simd::float4)); // clang pads the VertexData struct to 32 bytes, so that's the stride (16+16)
    pLayout->setStepRate(1);
    pLayout->setStepFunction(MTL::VertexStepFunctionPerVertex);
    
    NS::SharedPtr<MTL::RenderPipelineDescriptor> pPsoDesc = NS::TransferPtr(MTL::RenderPipelineDescriptor::alloc()->init());
    pPsoDesc->setVertexDescriptor(pVtxDesc.get());
    pPsoDesc->setVertexFunction(pVFn.get());
    pPsoDesc->setFragmentFunction(pFFn.get());
    
    auto pColorDesc = pPsoDesc->colorAttachments()->object(0);
    pColorDesc->setPixelFormat(MTL::PixelFormatRGBA16Float);
    if (alphaBlending)
    {
        pColorDesc->setBlendingEnabled(true);
        pColorDesc->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        pColorDesc->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
        pColorDesc->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        pColorDesc->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    }
    
    NS::Error* pMtlError = nullptr;
    MTL::RenderPipelineState* pPso = pDevice->newRenderPipelineState(pPsoDesc.get(), &pMtlError);
    assert(pPso);
    
    return pPso;
}

MTL::RenderPipelineState* shader_pipeline::newInstancedSpritePipeline(const std::string& shaderSearchpath, MTL::Device* pDevice, MTL::PixelFormat pixelFormat)
{
    // Load shaders:
    
    std::vector<uint8_t> vtxBytecode = readBytecode(shaderSearchpath + "/sprite_instanced_vs.metallib");
    std::vector<uint8_t> fragBytecode = readBytecode(shaderSearchpath + "/sprite_instanced_fs.metallib" );
    auto pVtxLib = NS::TransferPtr(newLibraryFromBytecode(vtxBytecode, pDevice));
    auto pFragLib = NS::TransferPtr(newLibraryFromBytecode(fragBytecode, pDevice));
    
    auto pVfn = NS::TransferPtr(pVtxLib->newFunction(MTLSTR("MainVS")));
    auto pFfn = NS::TransferPtr(pFragLib->newFunction(MTLSTR("MainFS")));
    
    assert(pVtxLib);
    assert(pFragLib);
    assert(pVfn);
    assert(pFfn);
    
    // Make vertex layout:
    
    auto pVtxDesc = NS::TransferPtr(MTL::VertexDescriptor::alloc()->init());
    
    auto pAttrib0 = pVtxDesc->attributes()->object(kIRStageInAttributeStartIndex + 1);
    pAttrib0->setFormat(MTL::VertexFormatFloat2);
    pAttrib0->setOffset(0);
    pAttrib0->setBufferIndex(kIRVertexBufferBindPoint);
    
    auto pAttrib1 = pVtxDesc->attributes()->object(kIRStageInAttributeStartIndex + 2);
    pAttrib1->setFormat(MTL::VertexFormatFloat2);
    pAttrib1->setOffset(sizeof(simd::float4));
    pAttrib1->setBufferIndex(kIRVertexBufferBindPoint);
    
    auto pLayout = pVtxDesc->layouts()->object(kIRVertexBufferBindPoint);
    pLayout->setStride(2 * sizeof(simd::float4));
    pLayout->setStepRate(1);
    pLayout->setStepFunction(MTL::VertexStepFunctionPerVertex);
    
    // Make render pipeline
    
    auto pRpd = NS::TransferPtr(MTL::RenderPipelineDescriptor::alloc()->init());
    pRpd->setVertexDescriptor(pVtxDesc.get());
    pRpd->setVertexFunction(pVfn.get());
    pRpd->setFragmentFunction(pFfn.get());
    
    auto pColor0 = pRpd->colorAttachments()->object(0);
    pColor0->setPixelFormat(pixelFormat);
    pColor0->setBlendingEnabled(true);
    pColor0->setSourceRGBBlendFactor(MTL::BlendFactorOne);
    pColor0->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    
    NS::Error* pMtlError = nullptr;
    MTL::RenderPipelineState* pPso = pDevice->newRenderPipelineState(pRpd.get(), &pMtlError);
    
    if (!pPso)
    {
        printf("%s\n", pMtlError->localizedDescription()->utf8String());
        assert(pPso);
    }
    
    return pPso;
}
