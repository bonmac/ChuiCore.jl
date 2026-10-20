- Laziness (request R5): `ChuiCore.Thunk` (no memo) and `ChuiCore.Lazy{T}(f)` / `Lazy(f)`, a
  memoised deferred value that is thread-safe by default (the body runs at most once, also under
  concurrent `force`; a throwing body's exception is cached and rethrown; a body that forces its own
  `Lazy` throws an `ArgumentError`; the closure is dropped after evaluation). `ChuiCore.force`
  (the identity on non-lazy values), `ChuiCore.isforced`, `ChuiCore.@lazy expr`, and deferred
  Functor/Applicative/Monad instances on `ChuiCore.LazyTag()`. Works on Julia 1.10. All public, not
  exported.
- Name-conflict banner (request R9): `ChuiCore.binding_conflicts(mod)` lists, per name `mod`
  exports, the other loaded modules that export a different binding of it (re-exports and
  `Base` method extensions are not conflicts); `ChuiCore.conflict_banner(io, mod)` prints them,
  silenced by `CHUI_QUIET_CONFLICTS=1` or `true`. Intended for
  `__init__() = isinteractive() && ChuiCore.conflict_banner(stderr, @__MODULE__)`; it covers modules
  loaded before the call. Public, not exported.
