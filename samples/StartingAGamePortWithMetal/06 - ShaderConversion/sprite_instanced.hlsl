/*
<samplecode>
  <abstract>
  Sprite-instancing pipeline: vertex stage transforms per-instance positions
  from the top-level argument buffer; fragment stage samples the appropriate
  sprite via the bindless texture table.
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
};

struct InstancePositions
{
    float4 position;
};

struct VertexIn
{
    float4 position : POSITION;
    float4 texcoord : TEXCOORD;
};

struct v2f
{
    float4 position                  : SV_Position;
    float4 color                     : COLOR;
    float2 uv0                       : TEXCOORD;
    nointerpolation float arrayIndex : USER;
};

ConstantBuffer<FrameData>                frameData    : register(b0, space0);
StructuredBuffer<InstancePositions> instancePositions : register(t0, space0);
Texture2DArray<float4>                   texture      : register(t1, space0);
SamplerState                             samp         : register(s0, space1);

#define RootSig "CBV(b0, space=0)," \
                "SRV(t0, space=0)," \
                "DescriptorTable(SRV(t1, space=0))," \
                "DescriptorTable(Sampler(s0, space=1))"

[RootSignature(RootSig)]
v2f MainVS(uint instanceID : SV_InstanceID,
           VertexIn vin)
{
    v2f o;
    
    float3 instancePosition = instancePositions[instanceID].position.xyz;
    o.position = mul(frameData.projectionMx, float4(vin.position.xy + instancePosition.xy, 0.0, 1.0));
    o.color    = float4(1.0, 1.0, 1.0, 1.0);
    o.uv0      = vin.texcoord.xy;
    o.arrayIndex = instancePosition.z;
    return o;
}

[RootSignature(RootSig)]
half4 MainFS(v2f vin) : SV_Target
{
    float arrayIndex = vin.arrayIndex;
    half4 texel = texture.Sample(samp, float3(vin.uv0, arrayIndex));
    texel.rgb = texel.rgb * texel.a;
    return texel;
}
