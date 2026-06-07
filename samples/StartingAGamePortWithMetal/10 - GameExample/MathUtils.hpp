/*
<samplecode>
  <abstract>
  Declares 2D linear-algebra helpers — orthographic projection construction
  and small matrix utilities used by the sprite renderer.
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


#ifndef MathUtils_hpp
#define MathUtils_hpp

#include <simd/simd.h>

namespace math
{
    simd::float3 add( const simd::float3& a, const simd::float3& b );
    simd::float4x4 makeIdentity();
    simd::float4x4 makeOrtho(float left, float right, float top, float bottom, float near, float far);
    simd::float4x4 makePerspective( float fovRadians, float aspect, float znear, float zfar );
    simd::float4x4 makeXRotate( float angleRadians );
    simd::float4x4 makeYRotate( float angleRadians );
    simd::float4x4 makeZRotate( float angleRadians );
    simd::float4x4 makeTranslate( const simd::float3& v );
    simd::float4x4 makeScale( const simd::float3& v );
    simd::float4x3 discardTranslation( const simd::float4x4& m );
}

#endif /* MathUtils_hpp */
