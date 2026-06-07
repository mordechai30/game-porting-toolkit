---
name: managing-metal-cpp-lifetimes
description: ALWAYS use when writing or porting Metal object lifetime management code in metal-cpp — including crashes on release, use-after-free, memory leaks, autorelease pool placement, NS::TransferPtr vs NS::RetainPtr ownership, bridge casts at ARC/metal-cpp boundaries, or any question about when and how Metal objects are retained, released, or destroyed.
---

# Metal C/C++ Lifetime Management

metal-cpp types like `MTL::Buffer*` wrap ObjC Metal objects, so the underlying ObjC retain/release rules still apply. Getting ownership wrong causes leaks, use-after-free, or double-free.

## Ownership Decision (metal-cpp)

Methods starting with `new`, `alloc`, `copy`, `mutableCopy`, or `Create` return **owned** (+1) objects. Everything else returns **autoreleased** objects.

```
Returned from new/alloc/copy/mutableCopy/Create?
  YES → NS::TransferPtr(ptr)          // you already own it
  NO  → need AutoreleasePool in scope
        Want to keep beyond pool scope?
          YES → NS::RetainPtr(ptr)     // retains; survives pool drain
          NO  → use raw pointer        // pool drains it
```

### Quick Reference

| API Pattern | Returns | Wrap With |
|---|---|---|
| `device->new*()` | Owned | `NS::TransferPtr()` |
| `alloc()->init()` | Owned | `NS::TransferPtr()` |
| `*CommandEncoder()` | Autoreleased | Raw pointer within pool scope |
| `::descriptor()` / `::string()` | Autoreleased | `NS::RetainPtr()` if keeping |
| `MTL::CreateSystemDefaultDevice()` | Owned | `NS::TransferPtr()` |

### TransferPtr vs RetainPtr

- **`NS::TransferPtr(ptr)`** — Takes ownership without additional retain. For objects you already own.
- **`NS::RetainPtr(ptr)`** — Takes ownership with additional retain. For autoreleased objects you want to keep beyond pool scope.

## Autorelease Pools (metal-cpp)

Pools are required in these contexts — without them, autoreleased objects accumulate indefinitely:

1. **Frame tick** — drain at end of each frame (pool persists, `drain()` releases contents)
2. **Worker threads** — engine-spawned threads (pthread, std::thread) have no pool by default. GCD dispatch queues manage their own automatically.
3. **Resource creation loops** — temporary objects accumulate across iterations without periodic drain
4. **Encoder creation** — encoders are autoreleased

```cpp
// Frame pool — create once, drain per frame
auto framePool = NS::TransferPtr(NS::AutoreleasePool::alloc()->init());
// ... each frame:
framePool->drain();  // releases autoreleased objects, pool stays alive for reuse
```

`drain()` releases contents but keeps the pool alive. `reset()` on the SharedPtr destroys the pool.

## Bridging from ARC into metal-cpp

When porting a project that has ARC translation units alongside metal-cpp, use bridge casts to hand ownership across the boundary:

| Cast | Effect | Use When |
|---|---|---|
| `(__bridge T)` | No retain/release | Temporary access, no ownership change |
| `(__bridge_retained T)` | +1 retain | Handing an owned object to metal-cpp — wrap result in `NS::TransferPtr` |
| `(__bridge_transfer T)` | C++ releases its +1 | Handing back to ARC from a metal-cpp `+1` object |

A `__bridge_retained` cast produces a `+1` object suitable for `NS::TransferPtr`. Every `__bridge_retained` must be balanced by a `__bridge_transfer` or explicit `release()`.

## Thread Safety

- Each thread needs its own autorelease pool (thread-local)
- `NS::SharedPtr` copy across threads is safe (atomic retain)
- Retain before cross-thread handoff; release on receiving thread when done

## Metal 4 Resource Lifetimes

`MTL4::CommandBuffer` does not retain resources. `MTL::CommandBuffer` retains by default but can be configured via its descriptor to not retain. When resources are not retained by the command buffer, you must keep them alive (via SharedPtr, deferred destruction queue, or residency set) until the GPU is done with them — a fence or event signals completion. The deferred destruction queue pattern is canonicalised in `managing-metal4-resources` (frame-delayed release with mutex-protected residency removal).

## Anti-Patterns / Common Mistakes

1. **Manually calling `release()` on an autoreleased object** — Autoreleased objects (encoders, descriptors, etc.) are released when the pool drains. An explicit `release()` causes a double-free.
2. **`TransferPtr` on autoreleased object** — `TransferPtr` calls `release()` on destruction → same double-free as above. Use `RetainPtr` if you need to keep it past pool scope, otherwise raw pointer within scope.
3. **No autorelease pool around encoder creation** — Autoreleased encoders accumulate without a pool. Silent leak.
4. **Pool scope too narrow** — Pool drains on scope exit. Using the autoreleased object after drain without retaining → use-after-free.
5. **Pool scope too wide** — Long-running frame loop with one pool → temporaries accumulate for entire frame.
6. **Forgetting pools on worker threads** — Engine-spawned threads have no pool (GCD dispatch queues manage their own pools automatically).
7. **Not draining pools in tight loops** — Creating many temporary objects without periodic pool drain causes unbounded memory growth.
8. **Retaining encoders unnecessarily** — Encoders are short-lived (create, encode, end). Use as raw pointers within pool scope — no need to retain or wrap in SharedPtr.

## Debugging

- **`OBJC_DEBUG_MISSING_POOLS=YES`** — runtime warning when no pool exists on current thread
- **ASan** — catches use-after-free (crashes during pool drain = TransferPtr on autoreleased)
- **`leaks --autoreleasePools`** — inspect pool contents in a memgraph
- **Metal HUD** (`MTL_HUD_ENABLED=1`) — continuously growing memory counter = resource leak
- **Double-free** — check for incorrect bridge casts between ObjC and metal-cpp types

## References

**Read the relevant metal-cpp header before writing lifetime code** — the headers are the source of truth for the ownership helpers and their exact semantics.

- metal-cpp Foundation headers - `Foundation/NSSharedPtr.hpp` (`NS::SharedPtr`, `NS::TransferPtr`, `NS::RetainPtr`), `Foundation/NSAutoreleasePool.hpp` (`NS::AutoreleasePool`)
- metal-cpp source - [apple/metal-cpp](https://github.com/apple/metal-cpp)
- Apple documentation - [metal-cpp](https://developer.apple.com/metal/cpp/)
