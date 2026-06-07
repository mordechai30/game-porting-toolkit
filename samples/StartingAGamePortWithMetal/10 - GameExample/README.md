# Bringing it all together

Combine techniques from the previous chapters into a runnable 2D game that builds for macOS and iOS in one step.

## Overview

The sample shows you how to:

* **Set up your project** to target macOS and port your game to iOS in one step.
* Create and manage the **app life cycle** in both macOS and iOS, abstracting away platform differences and reusing common code, saving development time.
* Handle input through the Game Controller framework, in particular, managing iOS input using an on-demand virtual game controller that appears and disappears as the player connects or disconnects physical game controllers.
* Produce haptic events using Core Haptics to drive immersion.
* Render graphics efficiently using Metal and using your existing HLSL shaders.

### Initialize the game

The game's entry point is function `applicationDidFinishLaunching:`. For macOS, the sample implements this function in file `macOS/GameApplication.m`, whereas for iOS, it implements it in `iOS/GameApplication.m`.

Both classes have a similar role of creating the `GameCoordinatorController` instance, which in turn creates the `GameCoordinator`. From there, the sample unifies code for both platforms, allowing you to develop for both of them simultaneously.

### Update the game and draw

After the sample sets up the game, the `CAMetalDisplayLink` instance in `GameCoordinatorController` starts each frame in response to a display *vsync* event. The `GameCoordinatorController` instance then calls `GameCoordinator` and, through it, the `Game` instance runs the game update loop that updates the simulation and draws the game.

Because the run loop the `CAMetalDisplayLink` uses runs on a high-priority thread with a round-robin scheduling policy, the system scheduler assigns extra priority to this path-critical callback so it can quickly update the state of the game and encode GPU commands.

The `Game` instance's `update()` function checks and responds to the player's input using an instance of the `GameController` class to retrieve and respond to keyboard and game controller events.

Next, the `update()` function runs a simulation step based on the update *delta time*, adjusting the positions of entities, finding collisions, removing any destroyed ones, and triggering haptic events accordingly through an instance of the `LongRunningHaptics` class.

The game’s update function tracks and updates the game's current state in C++ standard vectors in the `GameState` structure. After updating them, but before drawing, it efficiently copies all vector data into GPU-visible Metal buffers in the `RenderData` structure.

The `RenderData` structure triple-shadows all buffers whose data changes frame-to-frame to avoid race conditions between the CPU and GPU, as the CPU may update buffers while the GPU concurrently reads from them:

```cpp
if (_gameState.enemiesAlive > 0)
{
    memcpy(_renderData.enemyPositionBuf[frameID]->contents(),
           _gameState.enemyPositions.data(),
           _gameState.enemiesAlive * sizeof(simd::float4));
}
```

The sample’s `Game::initializeBuffers` function allocates these buffers from three instances of `MTL::Heap`. Allocating the buffers from Metal heaps allows the `draw()` function to later make all the resources for the current frame resident in a single call to `useHeap()`.

Additionally, marking the Metal heaps as untracked, by calling `setHazardTrackingMode` with the argument `MTL::HazardTrackingModeUntracked`, provides additional CPU savings by having the Metal driver skip any resource dependency tracking for these buffers, which only the CPU writes.

After updating the game, the `GameCoordinator` instance calls the `Game` instance's draw function, prompting the game to render the world using *Metal*.

All rendering is *instanced*, using an instancing overload of function `IRRuntimeDrawIndexedPrimitives` in the Metal shader converter's runtime header. Instanced rendering helps avoid issuing more than one draw command for the same sprite.

An additional optimization is using a *bump allocator* to avoid transient allocations of small buffers for the top-level argument buffers Metal shader converter uses. Not only does the allocator save multiple buffer allocations, but it also allows binding its base buffer once and then inexpensively adjusting offsets into it when binding data.

See the [Metal shader converter documentation](https://developer.apple.com/metal/shader-converter) for more details on using a bump allocator to avoid allocating and binding several small distinct buffers when feeding your pipelines.

> Note: To make a working game, the sample introduces a few supporting files, including a convenience texture loader (`TextureLoader.h`), responsible for loading the game's images, and linear algebra and 2D mesh utilities (`MathUtils.hpp` and `MeshUtils.hpp`, respectively).
