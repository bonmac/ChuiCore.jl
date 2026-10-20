# Reference: optics

Lenses and prisms (ADR-0004): `Lens`, `IndexLens`, `@lens`, `Prism`, `preview`, `review`,
`ChuiCore.set` and `ChuiCore.modify` (Accessors' argument order). Structs are rebuilt through
ConstructionBase (ADR-0008). Loading Accessors adds interop through `ChuiCoreAccessorsExt`.
All public, not exported; the law kits `test_lens_laws` and `test_prism_laws` are on the
[core page](api.md).

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["optics/optics.jl"]
```
