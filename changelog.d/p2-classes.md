- Constructor classes (ADR-0001 §3–4): `constructorclass` tags, dispatch-only `*Style` traits for
  Functor through Arrow, the operations (`fmap`, `ap`, `chain`, `alt`, `contramap`, `bimap`,
  `dimap`, `lmap`, `rmap`, `arrfirst`, `arrsecond`, `arrsplit`, `fanout`; tag-first `pure`,
  `zeroalt`, `idarrow`, `arr`, `traverse`, `sequence`), instances on Maybe (`Some`/`nothing`),
  `Array`, `Tuple`, `Dict`, `Pair` and `Function`, and the owned types `Identity`, `ZipVector`
  and `Predicate`.
- Law tables for the eleven class kits, with law tests for every instance and a planted
  violation for every law under both drivers (sample collections and Supposition).
