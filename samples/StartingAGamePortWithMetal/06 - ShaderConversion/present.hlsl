/*
<samplecode>
  <abstract>
  Final-pass present shader that samples the offscreen render target and
  stretches SDR content into EDR by multiplying by the current display
  brightness.
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

struct FrameData
{
    float4x4 projectionMx;
    float    maxEDRValue;
    float    brightness;
    float    currentEDRBias;
};

ConstantBuffer<FrameData> frameData : register(b0, space0);
Texture2D<float4> inTexture : register(t0, space1);
SamplerState samp : register(s0, space2);

struct VertexIn
{
    float4 position : POSITION;
    float4 texcoord : TEXCOORD;
};

struct v2f
{
    float4 position : SV_Position;
    float2 uv0 : TEXCOORD0;
};

#define RootSig "CBV(b0, space=0)," \
                "DescriptorTable(SRV(t0, space=1))," \
                "DescriptorTable(Sampler(s0, space=2))"

[RootSignature(RootSig)]
v2f MainVS(VertexIn vin)
{
    v2f o = (v2f)0;
    o.position = mul(frameData.projectionMx, vin.position);
    o.uv0 = vin.texcoord.xy;
    return o;
}

#include "ACES.hlsl"

[RootSignature(RootSig)]
float4 MainFS(v2f vin) : SV_Target
{
    // This sample demonstrates EDR support by stretching SDR content
    // to EDR (multiplying the input color by the brightness).
    // In practice, keep SDR content in the [0,1] range and only use
    // values above 1.0 for content authored for HDR content.
    
    float4 color = inTexture.Sample(samp, vin.uv0);
    
    color.rgb = ACESFitted(color.rgb);
    
    color.rgb = pow(color.rgb, 2.2) * frameData.brightness;
    
    color.rgb = lerp(color.rgb, color.rgb * frameData.maxEDRValue, frameData.currentEDRBias);
    
    return float4(pow(color.rgb, 1/2.2), 1.0);
}
