# Reference: laziness and the conflict banner

`Thunk` (no memo) and the thread-safe memoised `Lazy`, with `force`, `isforced`, `@lazy` and
deferred Functor/Applicative/Monad instances; and the name-conflict banner
(`binding_conflicts`, `conflict_banner`) that Chui packages call from `__init__`. All public,
not exported.

```@autodocs
Modules = [ChuiCore]
Private = false
Pages = ["lazy.jl", "banner.jl"]
```
