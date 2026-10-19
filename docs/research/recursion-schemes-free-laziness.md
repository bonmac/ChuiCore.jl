# Recursion schemes, free monads, data types à la carte and laziness in Julia

Recorded 2026-10-20 by the phase-1 `researcher` lane (ChuiCore, Research and ADRs). Status: research
note, input to the phase-1 ADRs. Nothing here is a decision.

Julia versions used: `julia +lts` = **1.10.12** (the floor) and `julia +release` = **1.13.2** (stable),
both via juliaup, `--startup-file=no`, one throwaway project env per version holding only
BenchmarkTools. Machine: Apple silicon (aarch64, macOS 26 / Darwin 25.6). **Benchmark caveat:** other
Julia processes from parallel lanes were running on the same machine, so absolute timings carry
roughly ±50% run-to-run noise (the same script run twice on 1.10 moved `cata` from 64.9 to
45.8 ns/node). Treat ratios, allocation counts, inference results and pass/fail outcomes as the
evidence; treat single nanosecond figures as indicative only.

The prototype scripts (`schemes.jl`, `more_schemes.jl`, `free.jl`, `lazy_effects.jl`) were run from
the lane's session scratchpad, which is not kept. The definitions that matter are reproduced below,
so the results can be re-derived.

## Questions

1. What do Haskell `recursion-schemes` / `data-fix` and Milewski's F-algebra chapter define, with
   which types (Fix, Base functor, cata/ana/hylo/para/apo/histo/futu, monadic variants)?
2. Is this feasible in Julia? (a) Type stability and cost of `cata` over a `Fix` wrapper, over the
   user's own recursive type with `project`/`embed`, and over plain dispatch; stack depth on a
   10^5-deep list; an iterative cata. (b) `fmap` by dispatch per node type. (c) Does `hylo` fuse away
   the intermediate structure?
3. Which Julia packages already cover recursion schemes, free monads, effects and laziness, and how
   well maintained are they?
4. Free monads in Julia: `Pure`/`Impure`, an interpreter, a coproduct `Sum{F,G}` with `inj`/`prj`
   (Swierstra 2008); type stability; stack safety of deep binds (Bjarnason 2012); a freer encoding.
5. Laziness: thunk vs memoized `Lazy{T}`; thread-safe memoization and which Julia versions have
   `OncePerProcess`/`OncePerThread`/`OncePerTask`/`Base.Lockable`; type stability and cost of
   `force`; `Base.Iterators` as Julia's lazy sequence model.

## 1. The reference definitions (verified)

### Haskell `recursion-schemes` 5.2.3, module `Data.Functor.Foldable`

Source: <https://hackage.haskell.org/package/recursion-schemes/docs/Data-Functor-Foldable.html>,
page reports `recursion-schemes-5.2.3`, fetched 2026-10-20. Signatures as printed there (hyperlinks
removed):

```haskell
type family Base t :: * -> *
class Functor (Base t) => Recursive t   where project :: t -> Base t t
class Functor (Base t) => Corecursive t where embed   :: Base t t -> t

cata  :: Recursive t   => (Base t a -> a) -> t -> a                       -- alias: fold
ana   :: Corecursive t => (a -> Base t a) -> a -> t                       -- alias: unfold
hylo  :: Functor f     => (f b -> b) -> (a -> f a) -> a -> b              -- alias: refold
para  :: Recursive t   => (Base t (t, a) -> a) -> t -> a
apo   :: Corecursive t => (a -> Base t (Either t a)) -> a -> t
histo :: Recursive t   => (Base t (Cofree (Base t) a) -> a) -> t -> a
futu  :: Corecursive t => (a -> Base t (Free (Base t) a)) -> a -> t
zygo  :: Recursive t   => (Base t b -> b) -> (Base t (b, a) -> a) -> t -> a
chrono :: Functor f    => (f (Cofree f b) -> b) -> (a -> f (Free f a)) -> a -> b
cataA :: Recursive t   => (Base t (f a) -> f a) -> t -> f a
prepro / postpro / gpara / gprepro / gpostpro: generalised variants (comonad/monad distributive laws)
```

- `project` is the only method of `Recursive`; `embed` the only method of `Corecursive`. The schemes
  are top-level functions over those two methods.
- **No `cataM`, `anaM` or `hyloM` exists in this module** (the page has no `…M` names). The monadic
  and comonadic generalisations are `gana`, `gunfold`, `gfutu`, `gpostpro` (taking `Monad m`) and the
  `g*` folds; Mendler-style variants (`mcata`, `mhisto`, …) work on `Fix f` directly.
- `cataA` (fold into an applicative/functor `f`) is the closest thing to a monadic cata here.
- `Fix` itself is re-exported from the `data-fix` package (`type Base (Fix f) = f`).

### Haskell `data-fix` 0.3.4, module `Data.Fix`

Source: <https://hackage.haskell.org/package/data-fix/docs/Data-Fix.html>, page reports
`data-fix-0.3.4`, fetched 2026-10-20 (the recursion-schemes page links data-fix-0.3.3).

```haskell
newtype Fix f = Fix { unFix :: f (Fix f) }
newtype Mu f  = Mu { unMu :: forall a. (f a -> a) -> a }      -- Church-encoded least fixpoint
data    Nu f  = forall a. Nu (a -> f a) a                    -- greatest fixpoint (unfold state)
foldFix    :: Functor f => (f a -> a) -> Fix f -> a
unfoldFix  :: Functor f => (a -> f a) -> a -> Fix f
refold     :: Functor f => (f b -> b) -> (a -> f a) -> a -> b
foldFixM   :: (Monad m, Traversable t) => (t a -> m a) -> Fix t -> m a          -- this is "cataM"
unfoldFixM :: (Monad m, Traversable t) => (a -> m (t a)) -> a -> m (Fix t)      -- "anaM"
refoldM    :: (Monad m, Traversable t) => (t b -> m b) -> (a -> m (t a)) -> a -> m b  -- "hyloM"
hoistFix   :: Functor f => (forall a. f a -> g a) -> Fix f -> Fix g
```

So the monadic variants the brief calls `cataM`/`anaM`/`hyloM` exist in the Haskell ecosystem as
`foldFixM`/`unfoldFixM`/`refoldM`, and they need **`Traversable`** on the base functor (to sequence
the effects of the children), not only `Functor`.

### Milewski, *Category Theory for Programmers*, ch. 24 "F-Algebras"

Source: <https://bartoszmilewski.com/2017/02/28/f-algebras/>, posted 2017-02-28, part 24 of the
series; fetched 2026-10-20.

- An F-algebra is a triple: an endofunctor `F`, a carrier object `a`, and a structure map
  `F a -> a`. Haskell: `type Algebra f a = f a -> a`.
- `newtype Fix f = Fix (f (Fix f))`, `unFix :: Fix f -> f (Fix f)`.
- `cata alg = alg . fmap (cata alg) . unFix`; `ana coalg = Fix . fmap (ana coalg) . coalg`.
- The initial algebra is the initial object of the category of F-algebras; **Lambek's lemma**: its
  structure map `j` is an isomorphism (so `Fix`/`unFix` are inverse).
- Example functors: `MonF` (`MEmpty | MAppend a a`), `NatF` (`ZeroF | SuccF a`), `ListF e a`
  (`NilF | ConsF e a`), `StreamF e a`, and a `RingF` whose fixpoint is the expression type `Expr`.

## 2. Julia feasibility (prototypes, run on 1.10.12 and 1.13.2)

### Definitions used

```julia
abstract type ExprF{R} end                          # base functor; R = carrier ("hole") type
struct LitF{R} <: ExprF{R}; v::Int end
struct AddF{R} <: ExprF{R}; l::R; r::R end
struct MulF{R} <: ExprF{R}; l::R; r::R end
# (ListF: NilF{R}, ConsF{R}(h::Int, t::R) likewise)

fmap(f, x::LitF) = x                                # (b) fmap = one method per node type
fmap(f, x::AddF) = AddF(f(x.l), f(x.r))
fmap(f, x::MulF) = MulF(f(x.l), f(x.r))

evalalg(x::LitF) = x.v                              # an algebra = one method per node type
evalalg(x::AddF{Int}) = mod(x.l + x.r, 1_000_003)
evalalg(x::MulF{Int}) = mod(x.l * x.r, 1_000_003)

# A: Fix wrapper (the field is necessarily abstract, see A1 below)
struct Fix; unfix::Any end
cata(alg, x::Fix)   = alg(fmap(c -> cata(alg, c), x.unfix))
ana(coalg, s)       = Fix(fmap(t -> ana(coalg, t), coalg(s)))
hylo(alg, coalg, s) = alg(fmap(t -> hylo(alg, coalg, t), coalg(s)))
para(alg, x::Fix)   = alg(fmap(c -> (c, para(alg, c)), x.unfix))

# A1: fully parametric Fix: concrete field, so the TYPE encodes the whole tree shape
struct FixP{F}; unfix::F end

# B: user's own recursive type + project/embed (Haskell's Recursive/Corecursive, as two functions)
abstract type Ex end
struct Lit <: Ex; v::Int end
struct Add <: Ex; l::Ex; r::Ex end
struct Mul <: Ex; l::Ex; r::Ex end
project(x::Add) = AddF{Ex}(x.l, x.r)   # etc.;  embed(x::AddF) = Add(x.l, x.r)
cataB(alg, x::Ex) = alg(fmap(c -> cataB(alg, c), project(x)))

# C: no scheme at all: plain dispatch on the abstract type
evalC(x::Add) = mod(evalC(x.l) + evalC(x.r), 1_000_003)   # etc.

# D: one concrete tagged node (what a sum-type package generates), small-Union children
struct Node; tag::UInt8; v::Int; l::Union{Node,Nothing}; r::Union{Node,Nothing} end
cataD(alg, n) = n.tag == 0 ? alg(LitF(n.v)) :
                n.tag == 1 ? alg(AddF{Int}(cataD(alg, n.l::Node), cataD(alg, n.r::Node))) : …

# Iterative cata (stack-safe): cata_iter = explicit post-order work stack driven by fmap;
# cata_iter2 = pre-order collection + reverse sweep using a children/rebuild pair
children(x::AddF) = (x.l, x.r);  rebuild(::AddF, (l, r)) = AddF(l, r)   # etc.
```

Test data: a balanced expression tree of depth 16 (131,071 nodes, `Mul` every third level, leaves
`2`), and `ListF` lists of length up to 10^6, built iteratively so that building never overflows.
All seven implementations returned the same value (`506014`) on both versions.

### (a) Inference

Command: `Base.return_types(...)` and `code_warntype(cata, (typeof(evalalg), Fix))`. Output,
identical on 1.10.12 and 1.13.2:

```
Base.return_types(cata,      (typeof(evalalg), Fix))            = Any[Int64]
Base.return_types(cataB,     (typeof(evalalg), Ex))             = Any[Int64]
Base.return_types(evalC,     (Ex,))                             = Any[Int64, Int64, Int64]
Base.return_types(cataD,     (typeof(evalalg), Node))           = Any[Int64]
Base.return_types(hylo,      (typeof(evalalg), typeof(treecoalg), Int)) = Any[Int64]
Base.return_types(cata_iter, (typeof(evalalg), Fix, Type{Int})) = Any[Int64]
Base.return_types(cata_iter2,(typeof(evalalg), Fix, Type{Int})) = Any[Int64]
code_warntype cata(evalalg, ::Fix): Body::Int64
```

So the **return type** of a recursive `cata` over `Fix{Any}` is inferred concretely: the algebra's
methods all return `Int`, and inference sees that through the recursion. What is *not* static is the
per-node work: `x.unfix::Any` means `fmap` is a dynamic dispatch at every node, and the rebuilt layer
`AddF{Int}` is heap-allocated. The cost shows up in time and allocation, not in `Body::`.

### (a) Cost: balanced tree, 131,071 nodes

Command: second-call `@allocated`, then `median(@benchmark f() samples=200 evals=1 seconds=3)`.

| Variant | 1.10.12 alloc | 1.10.12 median (ns/node) | 1.13.2 alloc | 1.13.2 median (ns/node) |
|---|---:|---:|---:|---:|
| A `cata` over `Fix` (`Any` field) | 2,097,136 B | 6.0 ms (45.8) | 2,097,120 B | 10.1 ms (76.7) |
| A `cata_iter` (explicit stack, fmap-driven) | 14,681,472 B | 31.8 ms (242.5) | 14,682,048 B | 23.6 ms (180.2) |
| A `cata_iter2` (children/rebuild) | 14,500,464 B | 65.9 ms (502.5) | 15,810,640 B | 71.0 ms (541.9) |
| B `cata_iter2` via `project` | 10,830,480 B | 15.6 ms (118.8) | 12,140,656 B | 20.8 ms (159.0) |
| B `cataB` via `project`/`fmap` | 32,768 B | 4.4 ms (33.8) | 32,768 B | 2.8 ms (21.1) |
| C plain dispatch `evalC` | 16 B | 0.50 ms (3.8) | 0 B | 0.35 ms (2.6) |
| D tagged concrete `Node`, `cataD` | 16 B | 0.73 ms (5.5) | 0 B | 0.53 ms (4.0) |
| H `cata ∘ ana` (builds the tree) | 5,242,768 B | 13.0 ms (98.9) | 5,242,752 B | 12.3 ms (93.8) |
| H `hylo` (fused) | 16 B | 0.91 ms (6.9) | 0 B | 0.71 ms (5.4) |

(The first run of the script, before the iterative variants were added, gave A 64.9 / 87.5 ns/node,
B 24.9 / 23.9, C 2.5 / 1.6, D 4.4 / 3.8, hylo 5.0 / 5.2 on 1.10 / 1.13: same ordering.)

Reading:

- **Fix-based cata costs about 12–30× plain dispatch** (45–77 vs 2.6–3.8 ns/node in this run; up to
  55× in the first run) and allocates
  16 B/node. The user's-own-type route (B) is cheaper than Fix (21–34 ns/node, almost no
  allocation) because `project` returns a concretely-typed layer `AddF{Ex}` after one dispatch.
- **Plain dispatch (C) and a tagged concrete node (D) are an order of magnitude faster** than any
  generic scheme: no layer is materialised, and in D the algebra receives a concrete `AddF{Int}`.
- The **iterative cata** prototypes are 4–10× slower than the recursive Fix cata (the work stacks
  hold `Any`, every layer is boxed, closures capture `Ref`s). They were written for stack safety,
  not tuned; a tuned version is future work and its cost is UNVERIFIED.

### (a) Parametric `FixP{F}` (concrete field): compile cost grows with the shape

Command: build a `FixP` list of length n, time the first and the second `cataP(sumalg, l)`.

```
1.10.12: n=5 first=0.214 s  n=10 first=0.051 s  n=20 first=0.075 s  n=40 first=0.332 s   (second calls 4–17 µs)
1.13.2:  n=5 first=0.010 s  n=10 first=0.010 s  n=20 first=0.037 s  n=40 first=0.062 s   (second calls 2–5 µs)
typeof string length: 84, 149, 279, 539 chars for n = 5, 10, 20, 40
Base.return_types(cataP, (typeof(sumalg), typeof(buildlistP(3)))) = Any[Int64]
```

A concretely-typed `Fix{F}` makes every distinct tree shape a distinct type, so every new shape
recompiles. That is unusable for data-dependent trees such as query plans; the `Fix` field must be
abstract (`Any` or an abstract functor type). This answers the brief's `struct Fix{F}; unfix::F end`
question: it is type-stable only in the degenerate sense that each shape gets its own compiled
method.

### (a) Stack depth

Command: catch `StackOverflowError` over a ladder of list lengths (one run each; the boundary is
approximate). Main task, default stack:

| Recursion | 1.10.12 | 1.13.2 |
|---|---|---|
| plain recursion `psum(::PCons) = h + psum(t)` | ok at 10^5, fails at 10^6 | ok at 10^5, fails at 10^6 |
| naive `cata` over a `Fix` list | ok at 20,000, **fails at 25,000** | ok at 35,000, **fails at 40,000** |
| `hylo` list sum (no list built) | ok at 50,000, fails at 10^5 | ok at 50,000, fails at 10^5 |
| `cata_iter`, `cata_iter2` (explicit stack) | ok at 10^5 and 10^6 | ok at 10^5 and 10^6 |
| naive `cata` inside `Threads.@spawn` | ok at 10,000, **fails at 15,000** | ok at 35,000, fails at 40,000 |
| naive `cata` inside `Task(f, 256 MiB)` | ok at 10^5, fails at 10^6 | ok at 10^5 and 10^6 |

So: **a naive cata over a 10^5-deep list overflows the stack on both versions**; each cata level
uses several frames (`cata` → closure → `fmap` → closure), about 3–4× the stack of plain recursion.
Spawned tasks have less stack on 1.10 than the main task. The explicit-stack cata is stack-safe to
10^6. `Task(f, reserved_stack)` is an undocumented constructor (UNVERIFIED as public API); do not
rely on it.

Query plans (ChuiFrames' use case) are shallow, tens to hundreds of nodes deep, so recursive
schemes are safe there. Long linear structures (lists, streams) need the iterative form or a
different representation.

### (b) `fmap` by dispatch

One `fmap` method per node type works and is how every variant above is built. With a `Fix{Any}`
field the call is a dynamic dispatch per node (see costs); with a concretely-typed layer (B, D) it
is static. An algebra is likewise one method per node type (`evalalg(::AddF{Int})`), which is the
Julian replacement for a Haskell `case`. A `children`/`rebuild` pair (cf. TermInterface.jl's
`arguments`/`maketerm`) is the dispatch-friendly alternative to `fmap` when the traversal must be
iterative.

### (c) hylo fusion

Balanced tree (table above): `cata ∘ ana` allocates 5.24 MB, `hylo` 0–16 B, and `hylo` is 14–17×
faster. Lists of 10^4 (`hylo fusion on lists`):

```
1.10.12: ana+cata alloc=640016 B median=861.2 us   hylo alloc=16 B median=259.6 us
1.13.2:  ana+cata alloc=640000 B median=721.0 us   hylo alloc=0 B  median=235.9 us
```

Fusion is verified: no intermediate structure, and about 3–17× faster.

### The other schemes (apo, histo, futu, para, cataM)

Command: `julia +lts / +release --startup-file=no more_schemes.jl`. Output, identical on both:

```
apo insert: [1, 3, 4, 5, 7]                       # insert into sorted list, stops early via Left
histo fib(0:10): [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]   # Cofree history
futu dup 3: [3, 3, 2, 2, 1, 1]                     # emits two layers per step via Free
cataM ok: 20   cataM div-by-zero: nothing          # Maybe = Union{Nothing,Int}, short-circuit
return_types cataM: Any[Union{Nothing, Int64}]
return_types histo: Any[Any]
return_types apo:   Any[Fix]
```

`para` returned 3 for a 3-element list on both versions. All schemes are expressible in a few lines
each. `histo` loses inference (its `Cofree` has `Any` fields). The monadic cata needs a per-functor
`traverse`, which is the `Traversable` requirement from `foldFixM`.

## 3. Existing Julia packages

Registry: local `~/.julia/registries/General.tar.zst` (git-tree-sha1 `3909358acc0fb535…`, 14,577
package directories). Command: list `*/Package.toml` names, grep FP keywords, then extract
`Package.toml`/`Versions.toml`/`Deps.toml`. Maintenance data: `gh api repos/<owner>/<repo>`
(read-only GET), 2026-10-20. "Deps" is the union over the latest version range in `Deps.toml`.

| Package | Latest | Deps (latest range) | Last push | Stars | Relevance |
|---|---|---|---|---:|---|
| (none) | – | – | – | – | **No recursion-scheme package found** in General (no name matching recursion/scheme/cata/Fix) or by web search |
| Lazy.jl (MikeInnes) | 0.15.1 | MacroTools | 2021-06-01 | 485 | lazy lists, `@>` threading; the repo description says it is not maintained |
| Thunks.jl (tbenst) | 0.3.2 | none | 2021-09-12 | 9 | memoized thunks (`thunk`, `reify`, `@lazy`), call-by-need |
| TypeClasses.jl (JuliaFunctional) | 1.1.0 | Compat, DataTypesBasic, Distributed, ExprParsers, Monadic, ProxyInterfaces, Reexport, Requires, Revise, StructEquality, Suppressor | 2023-05-07 | 18 | Functor/Monad/… traits; depends on Revise and Suppressor |
| DataTypesBasic.jl | 2.0.3 | Compat | 2023-07-01 | 13 | Option/Try/Either |
| Monadic.jl | 1.0.0 | Compat | 2022-07-18 | 8 | `@monadic` do-notation macro |
| ExtensibleEffects.jl | 1.1.1 | Compat, DataTypesBasic, Distributed, ExprParsers, Monadic, Reexport, TypeClasses | 2026-03-14 | 12 | freer-monad extensible effects, after Kiselyov & Ishii 2015 (README) |
| Monads.jl (ulysses4ever) | 0.2.5 | none | 2025-11-30 | 34 | monadic expressions |
| HolyMonads.jl | 0.1.0 | none | 2026-09-12 | 1 | monads via Holy traits |
| MonadFunctions.jl | 0.1.0 | none | 2020-12-14 | 13 | small monad implementation |
| Continuables.jl | 1.0.3 | BenchmarkTools, Compat, DataTypesBasic, ExprParsers, OrderedCollections, SimpleMatch | 2023-07-01 | 40 | CPS generators |
| Functors.jl (FluxML) | 0.5.4 | Compat, ConstructionBase, LinearAlgebra, MacroTools, Random | 2026-10-15 | 123 | `fmap` over nested structs (generic traversal, not a base functor) |
| TermInterface.jl (JuliaSymbolics) | 2.0.1 | (not extracted) | 2026-10-17 | 42 | `arguments`/`maketerm` tree interface; the children/rebuild idea |
| Metatheory.jl | 2.1.0 | 14 incl. ThreadsX, TimerOutputs, StaticArrays | 2026-10-19 | 404 | e-graphs/term rewriting: relevant to plan rewrites |
| Moshi.jl, SumTypes.jl, LightSumTypes.jl, MLStyle.jl | 0.3.13, 0.5.9, 5.2.2, 0.4.17 | – | 2026-09-27, 2026-09-03, 2026-10-18, 2025-09-09 | 114, 122, 62, 422 | ADT/pattern-matching lane; variant D above is what they generate |

Not a match despite the name: `Effects.jl` (beacon-biosignals) is about regression effects
(StatsModels/GLM), not computational effects.

## 4. Free monads and data types à la carte

### Definitions used

```julia
# Classic Free (Haskell: data Free f a = Pure a | Free (f (Free f a)))
struct Pure <: Free; value::Any end
struct Impure <: Free; fa::Any end                 # functor value whose holes hold Free
struct GetF <: KVF; key::Symbol; k::Any end        # continuation Int -> Free
struct PutF <: KVF; key::Symbol; v::Int; next::Any end
struct TellF <: LogF; msg::String; next::Any end
bind(m::Pure, f)   = f(m.value)
bind(m::Impure, f) = Impure(fmap(x -> bind(x, f), m.fa))

# Coproduct à la Swierstra
abstract type Sum{F,G} end
struct InL{F,G} <: Sum{F,G}; x::Any end
struct InR{F,G} <: Sum{F,G}; x::Any end
inj(::Type{F}, x::F) where {F} = x                                   -- reflexivity
inj(::Type{Sum{F,G}}, x::F) where {F,G} = InL{F,G}(x)                -- F :<: F :+: G
inj(::Type{Sum{F,G}}, x) where {F,G} = InR{F,G}(inj(G, x))           -- F :<: G => F :<: H :+: G
prj(::Type{T}, x::T) where {T} = x;  prj(T, x::Union{InL,InR}) = prj(T, x.x);  prj(T, x) = nothing

# Interpreter = an explicit loop (the trampoline); handlers by dispatch
step(s::Sum, st) = step(s.x, st)
step(x::GetF, st) = x.k(get(st.kv, x.key, 0))  # etc.
run(m, st) = (while m isa Impure; m = step(m.fa, st); end; m.value)

# Freer (operational) encoding: bare instruction + type-aligned continuation tree (FTCQueue)
struct Impure <: Free; op::Any; k::Q end           # Q = Leaf(f) | Node(l::Q, r::Q)
bind(m::Impure, f) = Impure(m.op, Node(m.k, Leaf(f)))   # O(1)
# qapply(q, x) rotates left-nested Nodes and applies continuations in a loop
handle(op::Get, st) = …;  run(m, st) = while m isa Impure; m = qapply(m.k, handle(m.op, st)); end
```

### Results

Both versions printed the same functional results: `Classic.run(progC, st) = 1`,
`st = (kv = Dict(:n => 1), log = ["hi"])`, same for `Freer.run`. Coproduct, both versions:

```
typeof(inj(Sig, GetF(...)))  = InL{KVF, LogF}
typeof(inj(Sig, TellF(...))) = InR{KVF, LogF}
prj(GetF, g) !== nothing = true ;  prj(GetF, t) = nothing
typeof(inj(Sum{KVF, Sum{LogF, ErrF}}, ThrowF("boom"))) = InR{KVF, Sum{LogF, ErrF}}
```

Inference, both versions:

```
Base.return_types(Classic.run, (Classic.Free, NamedTuple…)) = Any[Any]
Base.return_types(Freer.run,   (Freer.Free,   NamedTuple…)) = Any[Any]
Base.return_types(Classic.bind, (Classic.Impure, Function)) = Any[Classic.Impure]
```

Scaling, build + run, one run (includes compile at n=10):

| n | classic right | freer right | classic **left** | freer left |
|---:|---:|---:|---:|---:|
| 1,000 (1.10 / 1.13) | 1.4 / 0.9 ms | 0.6 / 0.9 ms | **0.32 / 0.62 s** | 0.7 / 0.6 ms |
| 4,000 | 3.3 / 4.9 ms | 2.6 / 2.0 ms | **5.8 / 7.3 s** | 1.1 / 3.1 ms |
| 10,000 | 5.7 / 9.6 ms | 2.6 / 2.9 ms | **43.2 / 46.8 s** | 5.3 / 12.2 ms |
| 100,000 | 0.25 / 0.14 s | 0.08 / 0.06 s | not run (quadratic) | 0.06 / 0.06 s |
| 1,000,000 | 2.06 / 2.01 s | 1.24 / 0.88 s | not run | 2.04 / 1.88 s |

No `StackOverflowError` occurred in any of these (right-nested programs are built lazily inside
continuations, and the interpreter is a loop).

Cost per instruction, `median(@benchmark …)` of build + run:

```
                         1.10.12                               1.13.2
classic right n=10000   1217 ns/incr  557 B/incr              1089 ns/incr  509 B/incr
freer   right n=10000    485 ns/incr  414 B/incr               913 ns/incr  414 B/incr
freer   left  n=10000    576 ns/incr  510 B/incr               807 ns/incr  510 B/incr
classic left  n=1000  539916 ns/incr 90061 B/incr           403452 ns/incr 82069 B/incr
freer   left  n=1000     733 ns/incr  488 B/incr              1199 ns/incr  487 B/incr
plain Dict loop, 10_000 increments: 60.6 us (≈6 ns/incr)      59.2 us (≈6 ns/incr)
```

Findings:

- **Left-associated binds make the classic encoding quadratic** (0.32 s → 43 s for 1k → 10k, about
  n^2.1). Each `bind` re-wraps the whole remaining continuation chain. This is exactly the problem
  Bjarnason's paper and Kiselyov & Ishii's FTCQueue solve. The freer encoding with a continuation
  tree stays linear in both associations.
- **Julia has no general tail-call elimination**, so the interpreter must be an explicit loop: a
  trampoline. Written that way, neither encoding overflowed at 10^6 instructions. The stack risk in
  Julia is in a recursive interpreter or a recursive `bind`, not in the data structure.
- The interpreters are not inferable (`Any`), and an interpreted instruction costs about
  0.5–1.2 µs and 400–550 B, versus about 6 ns for the same work in a plain loop: **roughly 80–200×
  overhead**. Free monads are for describing programs and plans (data that gets inspected,
  optimised and interpreted), not for inner loops.
- **À la carte in Julia:** `Sum`/`InL`/`InR` with `inj`/`prj` works by dispatch, including the
  nested three-way case. Dispatch already gives an open sum, though: instructions can be plain
  structs, the "signature" is the set of `handle` methods, and `prj` reduces to `x isa T`. The
  explicit `Sum` mainly adds a closed, nameable signature type, which has value for documentation
  and for checking that an interpreter covers a signature. The `inj` methods here were not checked
  for ambiguity with `Test.detect_ambiguities` (UNVERIFIED).

Sources:
- W. Swierstra, "Data types à la carte", *Journal of Functional Programming* 18(4):423–436, 2008,
  doi:10.1017/S0956796808006758 (bibliographic data via web search 2026-10-20; author PDF
  <https://webspace.science.uu.nl/~swier004/publications/2008-jfp.pdf>). Abstract: assembles data
  types and functions from components; the same technique combines free monads to structure IO.
- R. Ó. Bjarnason, "Stackless Scala With Free Monads", submitted to The Third Scala Workshop,
  London, 17 Apr 2012, <https://blog.higher-order.com/assets/trampolines.pdf> (pages 1–3 read
  2026-10-20). Trampolines (`Done`/`More`) trade stack for heap. A `FlatMap` constructor makes every
  call a tail call. `resume` reassociates left-nested `FlatMap`s, which is the "subtle detail" in
  §4.3. Trampoline = Free over `Function0`.
- O. Kiselyov, H. Ishii, "Freer monads, more extensible effects", Haskell Symposium 2015, SIGPLAN
  Notices 50(12):94–105 (bibliographic data via web search 2026-10-20). Freer monad plus a
  type-aligned continuation queue (FTCQueue).
- cats-free docs, <https://github.com/typelevel/cats/blob/main/docs/datatypes/freemonad.md> (Context7
  `/typelevel/cats`, 2026-10-20): `foldMap[M[_]](f: FunctionK[S,M])(M: Monad[M]): M[A]`; `foldMap`
  is stack-safe by trampolining "as long as your natural transformation is stack-safe"; algebras
  combine with `EitherK` + `InjectK` (`Free.liftInject`). This is the Scala version of Swierstra's
  `:+:`/`:<:`.

## 5. Laziness

### Definitions used

```julia
struct Thunk{F}; f::F end;  force(t::Thunk) = t.f()            # no memo

mutable struct Lazy{T,F}                                       # memoized, single-threaded
    f::Union{F,Nothing}; done::Bool; value::T
    Lazy{T}(f::F) where {T,F} = new{T,F}(f, false)
end
Lazy(f) = Lazy{Base.promote_op(f)}(f)
force(l::Lazy{T}) where {T} = (l.done || (l.value = convert(T, l.f()); l.done = true; l.f = nothing); l.value)

mutable struct SyncLazy{T,F}                                    # memoized, thread-safe
    @atomic done::Bool; f::Union{F,Nothing}; const lock::ReentrantLock; value::T
end
function force(l::SyncLazy{T}) where {T}                        # double-checked locking
    (@atomic :acquire l.done) && return l.value
    @lock l.lock if !(@atomic :monotonic l.done)
        l.value = convert(T, l.f()); l.f = nothing; @atomic :release l.done = true
    end
    return l.value
end
```

### Results (run with `-t 4`)

API availability, `isdefined(Base, …)`:

```
                          1.10.12   1.13.2
Base.OncePerProcess       false     true
Base.OncePerThread        false     true
Base.OncePerTask          false     true
Base.Lockable             false     true
Base.@atomiconce          false     true
Base.ScopedValues         false     true
```

Documented compat (Context7 `/websites/julialang_en_v1`, 2026-10-20): `OncePerProcess`,
`OncePerThread`, `OncePerTask` "require Julia 1.12 or later"; `Base.Lockable` "requires at least
Julia 1.11". `OncePerThread` carries a warning: it "may get deprecated in the future" and can alias
values because a Task may migrate between threads.

Inference of `force`, both versions: `Thunk`, `Lazy{Float64}` and `SyncLazy{Float64}` all infer
`Float64`. But `Lazy(mixed_f)`, with `mixed_f() = rand() < 2 ? 1 : 1.0`, has type
`Lazy{Union{Float64, Int64}, …}`: `promote_op` passes through whatever inference says, so a
type-unstable initializer gives a `Union` cell.

Memoization: one `Lazy` forced twice ran its initializer once (`cnt[] = 1`) on both versions.

Thread race, 1000 trials, 4 tasks forcing one fresh value at once:

```
1.10.12: Lazy (unsynchronized): (multi_init = 11, wrong_or_threw = 0)   SyncLazy: (multi_init = 0, wrong_or_threw = 0)
1.13.2:  Lazy (unsynchronized): (multi_init = 42, wrong_or_threw = 0)   SyncLazy: (multi_init = 0, wrong_or_threw = 0)
```

An earlier run of the same race on 1.10.12, without the per-task `try`, crashed:
`TypeError: in typeassert, expected Function, got a value of type Nothing`. A second task read
`l.f` after the first had cleared it. **The unsynchronized memo cell is unsafe under threads**: it
runs the initializer more than once and can throw.

Cost per `force` of an already-forced value (`median(@benchmark force($x))`):

```
                                1.10.12    1.13.2
Thunk (recomputes trivial f)    1.17 ns    1.54 ns
Lazy  (unsynchronized)          2.29 ns    2.00 ns
SyncLazy (atomic acquire)       6.17 ns    5.67 ns
Base.OncePerProcess call        n/a        3.42 ns   (return_types = Any[Float64])
Base.Lockable @lock deref       n/a       10.72 ns
```

(`@allocated` of `Lazy` construction/first force at top level: 74,136 B / 870,568 B on 1.10, which
is first-call compilation measured in global scope; 0 B / 0 B on 1.13.)

`Base.Iterators` as the lazy sequence model, both versions:

```
collect(take(filter(iseven, map(x -> x^2, countfrom(1))), 5)) = [4, 16, 36, 64, 100]
typeof(it) = Take{Filter{typeof(iseven), Generator{Count{Int64, Int64}, var"#…"}}}
f_it(10^6) = sum(take(filter(iseven, map(x->x^2, 1:typemax(Int))), 10^6)) = 1333335333334000000
@allocated f_it(10^6) = 0
```

Julia's lazy sequences are **iterator types that fuse at compile time**: zero allocation, fully
inferred, infinite sequences allowed. A Haskell-style lazy cons list (Lazy.jl) is not needed for
streaming. A memoized lazy *structure*, such as a lazily evaluated tree that is shared between
consumers, is the case iterators do not cover.

## Recommendations (each with its measured cost)

1. **Schemes over the user's own types, not over `Fix`.** Offer `project`/`embed` as two generic
   functions (Haskell's `Recursive`/`Corecursive`) that a type opts into, plus `fmap` per base
   functor; implement `cata`/`ana`/`hylo`/`para`/`apo`/`histo`/`futu` against them. Cost (B):
   21–34 ns/node and about 0.25 B/node allocation, 8–15× slower than hand-written dispatch.
   Also ship `Fix` (`unfix::Any`) for tutorials and generic code. Cost (A): 46–77 ns/node, 16 B/node.
   Document that a hand-written dispatch fold (2.6–3.8 ns/node) or a tagged concrete node
   (4–5.5 ns/node) is 10–50× faster than `Fix` for hot paths. Never make `Fix`'s field concrete (A1): it
   recompiles per tree shape.
2. **Make `hylo` the default for unfold-then-fold.** It allocates nothing and runs 3–17× faster than
   `cata ∘ ana` (measured on both versions).
3. **Stack safety is a documented limit, not a promise.** A recursive scheme over a linear structure
   overflows between 2×10^4 and 4×10^4 levels on the main task, and from about 1.5×10^4 in a
   spawned task on 1.10. Provide an explicit-stack `cata` for deep, linear data; it is stack-safe to
   10^6, but at 120–540 ns/node as prototyped, so it needs tuning before release. Query-plan trees
   are shallow and can use the recursive versions.
4. **Monadic variants need `traverse`.** `cataM`/`anaM`/`hyloM` require a Traversable base functor
   (as `foldFixM` does). Implementing them waits on the phase-2 Traversable trait. The Maybe/Union
   prototype inferred `Union{Nothing, Int64}`.
5. **Free monads: use the freer encoding** (bare instruction + continuation tree + loop
   interpreter). It is linear in both bind associations; classic `Free` is quadratic when
   left-associated (43–47 s vs 5–12 ms at 10^4). The cost is about 0.5–1.2 µs and about 0.4–0.5 KB
   per interpreted instruction, 80–200× a plain loop, so document it as "for describing programs,
   not inner loops". The interpreter is a `while` loop (the trampoline); never a recursive `run`.
6. **À la carte:** open dispatch on instruction structs is the primary mechanism (`inj` = identity,
   `prj` = `isa`). An explicit `Sum{F,G}`/`inj`/`prj` is optional and serves as a closed, checkable
   signature. ChuiTypes owns the effect runtime, so the free-monad interpreter pattern ChuiCore ships
   should stay minimal.
7. **Laziness:** ship `Thunk` (no memo, about 1.2–1.5 ns per force plus the work) and a memoized
   `Lazy{T}` that is **thread-safe by default** (`@atomic` flag + `ReentrantLock`, double-checked;
   5.7–6.2 ns per forced read, and it works on 1.10). An unsynchronized cell is about 2 ns but is
   provably racy; offer it only under an explicit name, if at all. Do not depend on
   `OncePerProcess`/`OncePerTask` (1.12+) or `Lockable` (1.11+) while the floor is 1.10; they can
   back a `VERSION`-gated path later. Ask for `T` explicitly (`Lazy{T}(f)`) or warn when
   `promote_op` yields a non-concrete type. For sequences, point users at `Base.Iterators`
   (0 allocations); do not ship a lazy cons list.

## UNVERIFIED

- Absolute timings beyond ±50% (a shared machine with concurrent Julia processes); stack-overflow
  thresholds come from a single run and depend on frame sizes, which can change between builds.
- Why `Threads.@spawn` tasks overflow earlier than the main task on 1.10 but not on 1.13 (default
  task stack size per version not looked up).
- `Task(f, reserved_stack::Int)` as a supported public constructor (only observed to work).
- Cost of a tuned iterative cata; cost of a `histo` with typed `Cofree`.
- Ambiguity-freedom of the prototype `inj` methods (no `detect_ambiguities` run).
- Swierstra 2008 and Kiselyov & Ishii 2015 page/volume data come from search results and the
  publisher landing page, not from reading the papers.
- `gpara`/`gprepro`/`gpostpro` signatures are quoted, not studied; Mendler-style schemes not
  evaluated.
- Deps for TermInterface.jl not extracted; "Deps" columns are the latest range in `Deps.toml`, not
  a resolved manifest.

## Also noticed

- On 1.10.12 the `Effects` printer shows 7 flags `(c,e,n,t,s,m,i)`; on 1.13.2 it shows 9
  `(c,e,n,t,s,m,u,o,r)`. See `inspiration-effects.md`.
- Metatheory.jl (e-graphs, 2.1.0, active) is the obvious comparison point for ChuiFrames'
  plan-rewrite optimizer. Rewriting via recursion schemes and equality saturation are different
  tools, and the ChuiFrames optimizer ADR should weigh both.
