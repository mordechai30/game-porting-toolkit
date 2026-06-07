# Implementing physics simulation middleware

Include accurate physics simulations to ground your game in realism and drive events that make your game more engaging.

## Overview

Games typically use third-party middleware for implementing complex physics. Popular middleware is available in both macOS and iOS, allowing you to target both types of devices and deliver great simulations.

## Port your physics

Generally, you initialize your physics engine and run one or more steps of its simulation every frame as part of your game's update loop. You then use the results of the simulation to update your game entities.

Examples of popular physics engines that support Apple devices include:

* [Havok](https://www.havok.com/)
* [NVIDIA PhysX](https://developer.nvidia.com/physx-sdk)
* [Box2D](https://github.com/erincatto/box2d)
* [Jolt Physics](https://github.com/jrouwe/JoltPhysics)

You can integrate these middleware solutions into your project as a library or framework, making it easy to port your physics code to the Apple platform. Check your middleware's manual and make sure to use the latest version for broader support.

## Accelerate computations on Apple devices

If your engine uses a custom physics solution, Apple offers frameworks that dramatically accelerate heavy computations, reducing CPU usage and saving power.

The [Accelerate framework](https://developer.apple.com/documentation/accelerate?language=objc) provides high-performance, energy-efficient computation on the CPU by using its vector-processing capabilities.

This sample's `GameCollisions.cpp` file incorporates the Accelerate framework's [SIMD](https://developer.apple.com/documentation/accelerate/simd?language=objc) capabilities to speed up computing collisions between small vectors representing player bullet positions and enemy rocks.

If your game engine relies on GPU-accelerated computations, the [Metal](https://developer.apple.com/metal) framework offers full compute shader support, allowing you to offload work to the device's GPU and massively parallelize it.

## See also

* [Accelerate framework](https://developer.apple.com/documentation/accelerate?language=objc) developer documentation
* [SIMD](https://developer.apple.com/documentation/accelerate/simd?language=objc) developer documentation
* [Metal](https://developer.apple.com/metal) developer site

## Test your knowledge

1. Integrate any of these physics engines into `Game.cpp` to implement more-precise collision detection.
2. Measure the CPU performance difference between this physics solution and the current custom implementation in `Game.cpp`.
3. Offload collision detection in `Game.cpp` to a Metal compute shader and measure the computation time difference compared to the CPU-based solution.
