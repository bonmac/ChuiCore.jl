"""
    ChuiCoreAccessorsExt

Interop between ChuiCore's optics and Accessors.jl (ADR-0004 §4). Loaded with `using Accessors`.

- ChuiCore optics inside Accessors: `Accessors.set`/`Accessors.modify` accept `ChuiCore.Lens`,
  `ChuiCore.IndexLens` and `ChuiCore.Prism`; the two lenses also work inside Accessors
  compositions (`∘`, `⨟`, `@set x |> lens |> _.b = v`). A prism is not callable, so inside an
  Accessors composition it works only through `ChuiCore.set`/`ChuiCore.modify` (which accept the
  Accessors lenses below): declaring it `Accessors.ModifyBased` would need Accessors'
  non-public `OpticStyle`.
- Accessors optics inside ChuiCore: `ChuiCore.set`/`ChuiCore.modify` accept exactly
  `Accessors.PropertyLens` and `Accessors.IndexLens`, alone or in a `ComposedFunction` with
  ChuiCore optics. Other Accessors optics (`Elements`, `If`, `Properties`, functions such as
  `first`, …) are not accepted: use `Accessors.set`/`Accessors.modify` for them.

Every method has a ChuiCore type or function in its signature, so there is no type piracy.
"""
module ChuiCoreAccessorsExt

using ChuiCore: ChuiCore, Lens, IndexLens, Prism
using Accessors: Accessors, PropertyLens

# ChuiCore optics in Accessors.
Accessors.set(x, l::Union{Lens, IndexLens}, v) = ChuiCore.set(x, l, v)
Accessors.modify(f, x, l::Union{Lens, IndexLens}) = ChuiCore.modify(f, x, l)
Accessors.set(x, p::Prism, v) = ChuiCore.set(x, p, v)
Accessors.modify(f, x, p::Prism) = ChuiCore.modify(f, x, p)

# Accessors' property and index lenses in ChuiCore.
ChuiCore.set(x, l::Union{PropertyLens, Accessors.IndexLens}, v) = Accessors.set(x, l, v)
ChuiCore.modify(f, x, l::Union{PropertyLens, Accessors.IndexLens}) = Accessors.modify(f, x, l)

end # module ChuiCoreAccessorsExt
