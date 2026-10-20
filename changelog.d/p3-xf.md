- Transducer substrate (ADR-0003), public and not exported: `ChuiCore.Transducer` and the v1
  transducers `Map`, `Filter`, `MapCat`, `Take`, `TakeWhile`, `Scan(op, init)`, `Partition{T}(n)`
  (`Partition(n) = Partition{Any}(n)`; flushes its remainder on completion unless the downstream
  has stopped) and `Composed`; `a ⨟ b` means "a, then b" and equals `b ∘ a`. Transducers have no
  call method.
- Reducing functions are structs built by `asrf(xf, op)` (`R`, `Bottom`), driven by the protocol
  `start`, `next`, `complete` (completion runs exactly once per fold, also after early
  termination); early termination by `Reduced`, `reduced`, `unreduced`, `isreduced`. Per-fold state
  lives in the accumulator, so a transducer such as `Take(3)` can be reused across folds.
- Folds: `foldxl(op, xf, itr; init)` (sequential, any iterable); `foldparts(op, xf, parts; init,
  merge)` over pre-partitioned input (`init` a factory, `merge` required, merged in partition
  order, one task per partition); `foldxt(op, xf, v::AbstractVector; init, merge, ntasks)` over
  contiguous views (no input copy; other iterables throw `ArgumentError`); `aggregate(agg, xf,
  parts)` over the CC-004 aggregator protocol.
- `isstateless(xf)` is fail-closed (`false` by default; `true` only for `Map`, `Filter`, `MapCat`
  and their compositions): any other pipeline runs sequentially in `foldparts`, `foldxt` and
  `aggregate`.
- Stateless `foldxl` over a vector is inferred and allocates 0 bytes on Julia 1.10 and 1.13.
