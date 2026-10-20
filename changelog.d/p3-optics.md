- Optics (ADR-0004, ADR-0008), all public and not exported: `ChuiCore.Lens{:a}()` (property lens,
  also `Lens(:a)` and `Lens(Val(:a))`), `ChuiCore.IndexLens(i...)`, the `ChuiCore.@lens _.a.b[2]`
  macro, `ChuiCore.Prism(match, build)` and the variant prism `ChuiCore.Prism(T)` for closed sum
  types, `ChuiCore.preview`, `ChuiCore.review`, and `ChuiCore.set(x, optic, v)` /
  `ChuiCore.modify(f, x, optic)` in Accessors' argument order. Lenses compose with Base's `∘`/`⨟`;
  `set`/`modify` also accept compositions that contain a prism. Type-parameterised lenses get and
  set with 0 bytes allocated.
- ConstructionBase (`[compat] 1.6`) is a new hard dependency: structs are rebuilt through
  `ConstructionBase.setproperties`, the same hook Accessors uses. Types with a non-default inner
  constructor or a phantom type parameter need their owner to define
  `ConstructionBase.constructorof`.
- New exported law kits `test_lens_laws(lens, gen_s, gen_v)` (get-set, set-get, set-set) and
  `test_prism_laws(prism, gen_s, gen_v)` (review-preview, preview-review), for sample collections
  and Supposition generators.
- New package extension `ChuiCoreAccessorsExt` (weak dependency Accessors, `[compat] 0.1.45`):
  ChuiCore lenses and prisms work in `Accessors.set`/`Accessors.modify` (lenses also inside
  Accessors compositions and `@set`), and `ChuiCore.set`/`ChuiCore.modify` accept Accessors'
  `PropertyLens` and `IndexLens`, alone or composed with ChuiCore optics.
