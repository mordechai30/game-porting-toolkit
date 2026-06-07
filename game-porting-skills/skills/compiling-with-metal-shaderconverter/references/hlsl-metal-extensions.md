# HLSL Metal-language features

Metal shader converter 3.0+ adds Metal-native features to HLSL via the `Metal_HLSL.inc` header (`<install_path>/include/metal_irconverter_ext/Metal_HLSL.inc`): **function constants** for shader specialization and **framebuffer fetch** for programmable blending. Both share the same authoring pattern.

## Authoring

Define a unique register space for each feature you use, then include the header:

```hlsl
#define MTL_FUNCTION_CONSTANT_SPACE 2147420894
#define MTL_FRAMEBUFFER_FETCH_SPACE 2147420893
#include "Metal_HLSL.inc"
```

The same value passed to each `#define` must be passed to Metal shader converter — to locate the feature's resources during compilation. A mismatch produces a shader that compiles but does not bind the feature correctly.

You can pass the defines on the dxc command line instead (`-D MTL_FUNCTION_CONSTANT_SPACE=2147420894`) to keep the values out of shader source.

## Function constants

Declare a function constant with the `MTL_FUNCTION_CONSTANT(variable_type, variable_name, function_constant_index)` macro:

```hlsl
MTL_FUNCTION_CONSTANT(float4, ConstantColor, 0);
```

The `fc_index` is the function constant index used at runtime to bind a value (see `integrating-metal-shaderconverter-shaders`).

Pass the same register space at compile time:
- **CLI**: `--function-constant-register-space 2147420894`
- **Library**: `IRCompilerSetFunctionConstantResourceSpace(compiler, 2147420894)`

Reflection metadata for declared function constants is available via `IRShaderReflectionCopyFunctionConstants` (pair with the matching release call).

## Framebuffer fetch

Read the current color value of a render target attachment with the `MTL_LOAD_FRAMEBUFFER(attachment_index, data_type)` macro:

```hlsl
half4 destColor = MTL_LOAD_FRAMEBUFFER(0, half4);
```

The attachment index must be a compile-time constant. Supported data types are `float4`, `half4`, `int4`, and `uint4` — pick the one that matches the attachment's pixel format channel layout.

Pass the same register space at compile time:
- **CLI**: `--framebuffer-fetch-register-space 2147420893`
- **Library**: `IRCompilerSetFramebufferFetchResourceSpace(compiler, 2147420893)`

Framebuffer fetch has no host-side binding code — see `integrating-metal-shaderconverter-shaders` for the render pass load action requirement.

## Root signature attribute caveat

If the shader uses the `RootSig` attribute, every defined feature space must be listed explicitly in the root signature even though it consumes no slots — Metal shader converter skips them during layout, but the entries must be present. The CBV slot is for function constants (CBV-bound); the SRV slot is for framebuffer fetch (SRV-bound).

```hlsl
#define RootSig \
    "DescriptorTable(CBV(b0), SRV(t0))," \
    "DescriptorTable(Sampler(s0))," \
    "DescriptorTable(CBV(b0, space=MTL_FUNCTION_CONSTANT_SPACE), SRV(t0, space=MTL_FRAMEBUFFER_FETCH_SPACE)),"
```

Include only the spaces you've actually defined — a shader that uses only function constants needs only the CBV entry, not the SRV.
