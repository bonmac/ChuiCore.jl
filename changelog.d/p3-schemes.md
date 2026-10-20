- Recursion schemes (public, not exported): `ChuiCore.cata`, `ana`, `hylo` (fused, no
  intermediate structure), `para` (each child is `(original, result)`, `original ===` the input
  subtree), `apo` (holes `Done(tree)` / `More(seed)`), `histo` (holes `Attr(value, layer)`),
  `futu` (holes `More(seed)` / `Emit(layer)`) and the monadic `cataM`, `anaM`, `hyloM` (the base
  functor must be Traversable). They run over any value whose type has a Functor instance,
  through `project(x)`: a downstream node type is its own base functor and is traversed without
  rewrapping (R6); `Fix(layer)` (field `Any`, structural equality) wraps layers for generic code,
  and the unfolds take `embed = Fix` (or `identity`). Every docstring states its cost and the
  stack limit (recursive: a linear structure overflows between about 10^4 and 4×10^4 levels).
- Data types à la carte: `ChuiCore.Coproduct{F,G}` with `Inl`/`Inr`, `inj(S, x)` (reflexive,
  nested right; one method, no ambiguities) and `prj(T, x)` (`Some(x)` or `nothing`); a
  Functor and Traversable instance (`CoproductTag()`) delegating to the payload.
- A freer monad: `ChuiCore.Free` programs `Pure(x)` / `Impure(op, k)` with an O(1)-bind
  continuation tree, `liftF(op)` and `liftF(S, op)`, Functor/Applicative/Monad instances on
  `FreeTag()`; `interpret(handler, m)` is a loop (stack-safe at 10^6 instructions, linear in
  left-associated binds), `cohandler(hf, hg, ...)` combines handlers for a `Coproduct`
  signature, and `foldfree(tag, nt, m)` interprets into a target monad (recursive: documented
  stack depth). For describing programs, not inner loops (≈0.2–1.2 µs per instruction).
