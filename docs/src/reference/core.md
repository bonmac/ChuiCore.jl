# Reference: composition and law kits

Composition helpers and the law-test kits. `⨟` and `opcompose` are CompositionsBase's bindings,
re-exported (their docstrings live in CompositionsBase; see the
[composition tutorial](../tutorials/composition.md)). The other areas have their own pages:
[monoids and aggregators](algebra.md), [typeclasses](classes.md),
[transducers](transducers.md), [recursion schemes and free monads](schemes.md),
[optics](optics.md), [laziness and the conflict banner](lazy.md), [internals](internals.md).

**Contract items** (`<root>/contracts/chui-core.md`, ADR-0010 of the ecosystem):

| ID | Item | Names |
|---|---|---|
| CC-001, CC-002, CC-003, CC-012 | `⨟` composes left to right; one binding, CompositionsBase's | `⨟`, `opcompose` |
| CC-011 | Law kits are never hard dependencies of ChuiCore | the `test_*_laws` kits |
| CC-013 | Export tiers | every name (see [export tiers](../explanation/export-tiers.md)) |

Everything else on this page is PROVISIONAL in the contract (no ID yet).

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["compose.jl", "laws.jl"]
Filter = t -> t !== ChuiCore
```
