# Reference: laziness and the conflict banner

`Thunk` (no memo) and the thread-safe memoised `Lazy`, with `force`, `isforced`, `@lazy` and
deferred Functor/Applicative/Monad instances; and the name-conflict banner
(`binding_conflicts`, `conflict_banner`) that Chui packages call from `__init__`. All public,
not exported. Tutorials: [laziness](../tutorials/laziness.md),
[the conflict banner](../tutorials/conflict-banner.md).

No item on this page has a contract ID yet: the banner's former entry CC-009 was withdrawn and is
now the PROVISIONAL item "Name-conflict banner" in `<root>/contracts/chui-core.md`.

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["lazy.jl", "banner.jl"]
```
