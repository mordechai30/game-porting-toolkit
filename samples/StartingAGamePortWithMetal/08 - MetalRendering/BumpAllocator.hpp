/*
<samplecode>
  <abstract>
  A linear allocator that suballocates Metal shader converter top-level
  argument buffers from a single backing `MTL::Buffer`. Single-threaded —
  create one instance per thread per frame.
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

#ifndef BUMPALLOCATOR_HPP
#define BUMPALLOCATOR_HPP

#include <Metal/Metal.hpp>
#include <cassert>
#include <cstdint>
#include <tuple>

namespace mem
{
constexpr uint64_t alignUp(uint64_t n, uint64_t alignment)
{
    return (n + alignment - 1) & ~(alignment - 1);
}
}

/// A linear allocator that hands out small, aligned slices of a single backing
/// `MTL::Buffer` for use as Metal shader converter top-level argument buffers.
///
/// This allocator isn't thread-safe. For multithreading encoding,
/// create one of these instances per thread per frame.
class BumpAllocator
{
public:
    BumpAllocator(MTL::Device* pDevice, size_t capacityInBytes, MTL::ResourceOptions resourceOptions);
    ~BumpAllocator();

    void reset() { _offset = 0; }

    template <typename T>
    std::pair<T*, uint64_t> allocate(uint64_t count = 1) noexcept
    {
        // Metal shader converter top-level argument buffers require 8-byte alignment.
        // See "Metal shader converter binding model" in the Metal shader converter documentation.
        uint64_t allocSize = mem::alignUp(sizeof(T) * count, 8);
        
        // If you hit this assert, the allocation data doesn't fit in
        // the amount estimated.
        assert((_offset + allocSize) <= _capacity);

        T* dataPtr          = reinterpret_cast<T*>(_contents + _offset);
        uint64_t dataOffset = _offset;

        _offset += allocSize;

        return { dataPtr, dataOffset };
    }

    MTL::Buffer* baseBuffer() const noexcept
    {
        return _pBuffer;
    }

private:
    MTL::Buffer* _pBuffer;
    uint64_t _offset;
    uint64_t _capacity;
    uint8_t* _contents;
};

#endif // BUMPALLOCATOR_HPP
