# metal-shaderconverter CLI — Supplemental Reference

## Multi-shader workflow

One invocation produces one metallib. Two approaches for combining many shaders:

**Merge** — convert each DXIL separately, then combine metallibs. Simpler; no shared IR-level optimization across shaders.

```sh
metal-shaderconverter a.dxil -o a.metallib
metal-shaderconverter b.dxil -o b.metallib
xcrun metal-pack a.metallib b.metallib -o combined.metallib
```

**Link** — compile each DXIL to an object file (`-c`), then link together. Allows the Metal linker to optimize across shader boundaries.

```sh
metal-shaderconverter -c a.dxil -o a.o
metal-shaderconverter -c b.dxil -o b.o
xcrun metal a.o b.o -o combined.metallib
```

---

## Debug information

DXC embeds debug info when compiled with `-Zi -Qembed_debug`. metal-shaderconverter carries this through automatically. To control it downstream:

```sh
# Strip debug info from the metallib binary (extracts to .metallibsym)
xcrun -sdk macosx metal-dsymutil -flat -remove-source shader.metallib

# Strip debug symbols from the binary entirely
xcrun -sdk macosx metal-strip -S shader.metallib

# Drop debug info at conversion time
metal-shaderconverter shader.dxil -o shader.metallib --ignore-debug-information
```

For `#line` directives in HLSL, add `--ignore-line-directives` to the DXC invocation.

---

## Geometry/tessellation emulation

```sh
metal-shaderconverter shader.dxil -o shader.metallib \
    --enable-gs-ts-emulation \
    --vertex-input-layout-file=layout.json
```

Starter `layout.json`:

```sh
metal-shaderconverter shader.dxil --generate-vertex-input-template > layout.json
```

For the per-stage policy (which stages need the flag) and the stage-in metallib emitted alongside, see `references/library.md` § "Geometry/tessellation emulation compilation".

