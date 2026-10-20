# Reference: typeclasses

The constructor classes (ADR-0001 §3): Functor, Applicative, Monad, Alternative, Foldable,
Traversable, Contravariant, Bifunctor, Profunctor, Category and Arrow, encoded as Holy traits on
a **tag** that `constructorclass` maps each type to; the tags, the styles, and the instance types
ChuiCore owns (`Identity`, `ZipVector`, `Predicate`). Tutorial:
[typeclasses and your own instance](../tutorials/typeclasses.md).

No item on this page has a contract ID yet: the typeclass encoding is PROVISIONAL in
`<root>/contracts/chui-core.md`, with its decided part recorded there (ADR-0001).

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = [
    "classes/class_laws.jl", "classes/classes.jl", "classes/core.jl", "classes/instances.jl",
    "classes/owned.jl", "classes/style_docs.jl",
]
```
