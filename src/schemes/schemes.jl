# Recursion schemes (docs/research/recursion-schemes-free-laziness.md §1–2, Recommendations 1–4;
# plan "Recursion schemes"). A scheme runs over any value whose type has a Functor instance
# (`fmap` through `constructorclass`/`FunctorStyle`), reached through `project`. Every scheme is
# recursive: see the stack limit in the docstrings. Costs quoted are the research measurements
# (Apple silicon, shared machine, ±50%): treat them as orders of magnitude.

const _SALT_FIX = 0x4c1e7b9a2d5f3086 % UInt

"""
    Fix(layer)

The fixpoint of a base functor (Haskell `data-fix`'s `Fix`): wraps one layer whose holes hold
further `Fix` values, so `Fix(AddF(Fix(LitF(1)), Fix(LitF(2))))` is a tree. The field `unfix` is
`Any`, never concrete: a concrete field makes every tree shape its own type and recompiles per
shape (research A1). `Fix` registers no functor of its own; its layer's type does.
`==`, `isequal` and `hash` are structural (they compare the layers).

**Cost:** one heap box per node; a scheme over a `Fix` tree pays a dynamic `fmap` dispatch per
node. Measured for `cata` on a 1023-node tree (Julia 1.13.2, `docs/src/performance.md`): ≈77
ns and ≈47 B per node over `Fix`, against ≈18 ns/node and 0 B over a downstream node type that is
its own base functor (no `Fix`, see [`ChuiCore.project`](@ref)); the research measured
≈46–77 against ≈21–34 ns/node, and a hand-written dispatch fold 10–50× faster than `Fix`.

The natural numbers as `Fix` layers of the Maybe functor (`nothing` is zero, `Some(n)` is one
more than `n`):

```jldoctest
julia> using ChuiCore: Fix, cata

julia> two = Fix(Some(Fix(Some(Fix(nothing)))));

julia> cata(x -> x === nothing ? 0 : something(x) + 1, two)
2

julia> cata(Fix, two) == two   # the identity law
true
```
"""
struct Fix
    unfix::Any
end

Base.:(==)(a::Fix, b::Fix) = a.unfix == b.unfix
Base.isequal(a::Fix, b::Fix) = isequal(a.unfix, b.unfix)
Base.hash(a::Fix, h::UInt) = hash(a.unfix, h ⊻ _SALT_FIX)

"""
    project(x) -> layer

The layer a recursion scheme maps over (Haskell's `Recursive.project`): `project(f::Fix) =
f.unfix`, and `project(x) = x` for every other value. So a downstream node type whose `fmap` is
registered (ChuiFrames' plan nodes) **is its own base functor**: the schemes traverse it without
rewrapping it in `Fix`, and its child fields must accept whatever the algebra returns (untyped or
parametric fields). Untyped (`Any`) child fields keep one type for every tree shape; parametric
ones make each shape its own type, which compiles anew per shape (research A1), so prefer `Any`
for data-dependent trees. The owner of a recursive type with a separate base functor adds
`ChuiCore.project(x::MyType) = MyLayer(...)`.

**Cost:** free for the default (an identity call); one field load for `Fix`. A scheme over an
own node type allocates no `Fix` wrappers and is cheaper per node than over `Fix` (measured for
`cata`, Julia 1.13.2: ≈18 against ≈77 ns/node, 0 against ≈47 B/node; `docs/src/performance.md`).

```jldoctest
julia> using ChuiCore: Fix, project

julia> project(Fix(Some(1)))   # one layer of a Fix tree
Some(1)

julia> project([[], []])        # any other value is its own layer
2-element Vector{Vector{Any}}:
 []
 []
```
"""
project(x) = x
project(f::Fix) = f.unfix

# ---------------------------------------------------------------------------------------------
# Hole markers of apo, histo and futu.

"""
    Done(tree)

A hole of an [`ChuiCore.apo`](@ref) coalgebra: `tree` is already finished and is embedded as
is, without unfolding further (Haskell's `Left`). See also [`ChuiCore.More`](@ref).
Cost: a one-field wrapper (no allocation when `tree` is isbits).

Count down from 4 with `Some` layers, but hand over a finished `Some(nothing)` at 2:

```jldoctest
julia> using ChuiCore: apo, Done, More

julia> apo(n -> n == 0 ? nothing : Some(n > 2 ? More(n - 1) : Done(Some(nothing))), 4; embed = identity)
Some(Some(Some(Some(nothing))))
```
"""
struct Done{T}
    tree::T
end

"""
    More(seed)

A hole of an [`ChuiCore.apo`](@ref) or [`ChuiCore.futu`](@ref) coalgebra: keep unfolding from
`seed` (Haskell's `Right` in `apo`, `Pure` in `futu`). Cost: a one-field wrapper.

```jldoctest
julia> using ChuiCore: apo, More

julia> apo(n -> n == 0 ? nothing : Some(More(n - 1)), 2; embed = identity)   # always More: an ana
Some(Some(nothing))
```
"""
struct More{S}
    seed::S
end

"""
    Attr(value, layer)

A hole of a [`ChuiCore.histo`](@ref) algebra (one node of Haskell's `Cofree`): `value` is the
algebra's result for that subtree and `layer` the subtree's layer, whose holes are again `Attr`s.
So the algebra sees the results for all descendants, not only the children. Both fields are
`Any` (the history of a tree is not inferable; research: `histo` infers `Any`). Cost: one heap
object per node of the folded structure, kept alive until `histo` returns.

Fibonacci over the naturals as `Some` layers, reading the two previous results from the `Attr`s:

```jldoctest
julia> using ChuiCore: histo, ana

julia> fib(::Nothing) = 1;

julia> function fib(x::Some)
           a = something(x)                 # an Attr: the previous result and its layer
           a.layer === nothing && return 1
           return a.value + something(a.layer).value
       end;

julia> [histo(fib, ana(k -> k == 0 ? nothing : Some(k - 1), n; embed = identity)) for n in 0:6]
7-element Vector{Int64}:
  1
  1
  2
  3
  5
  8
 13
```
"""
struct Attr
    value::Any
    layer::Any
end

"""
    Emit(layer)

A hole of a [`ChuiCore.futu`](@ref) coalgebra: emit one more layer at once (Haskell's `Free`
constructor in `futu`); its holes are again `More(seed)` or `Emit(layer)`. Cost: a one-field
wrapper.

Build the natural number 5 as `Some` layers, two layers per step:

```jldoctest
julia> using ChuiCore: futu, cata, Emit, More

julia> five = futu(n -> n == 0 ? nothing : n >= 2 ? Some(Emit(Some(More(n - 2)))) : Some(More(n - 1)), 5; embed = identity);

julia> cata(x -> x === nothing ? 0 : something(x) + 1, five)
5
```
"""
struct Emit{L}
    layer::L
end

# ---------------------------------------------------------------------------------------------
# Folds and unfolds. The recursive steps are named callable structs rather than closures, so the
# stack frames stay small and the code specializes on the algebra.

const _COST_STACK = """
**Stack:** recursive, several frames per level. A linear structure (a list) overflows somewhere
between about 10^4 and 4×10^4 levels on the main task (research: 2.5×10^4 on Julia 1.10,
4×10^4 on 1.13; a later run of this implementation: 1.25×10^4 and 2×10^4), and earlier in a
spawned task on 1.10. This is a documented limit: query plans are shallow (tens to hundreds of
levels); for long linear data write a loop.
"""

struct _Cata{A} <: Function
    alg::A
end
(c::_Cata)(x) = c.alg(fmap(c, project(x)))

"""
    cata(alg, x)

Catamorphism (fold): `cata(alg, x) = alg(fmap(c -> cata(alg, c), project(x)))`. The algebra
`alg` receives one layer whose holes already hold the results for the children; write it as one
method per node type. `x` is a `Fix` tree or a value of a node type that is its own base functor
(see [`ChuiCore.project`](@ref)); every layer, leaves included, must be a Functor (an
`ArgumentError` otherwise). Laws: `cata(Fix, x) == x`; fusion (`h ∘ alg₁ == alg₂ ∘ fmap(h)`
implies `h ∘ cata(alg₁) == cata(alg₂)`).

**Cost:** one `fmap` and one rebuilt layer per node. Measured (Julia 1.13.2, 1023-node tree,
`docs/src/performance.md` and `benchmark/allocs.jl`): ≈77 ns and ≈47 B per node over `Fix`;
≈18 ns per node and 0 B per call over an own node type. A hand-written dispatch fold is 10–50×
faster for hot paths (research). The return type infers when the algebra's methods agree.

$_COST_STACK

A rose tree as nested vectors (`Vector` is a Functor; an empty vector is a leaf), counting nodes:

```jldoctest
julia> using ChuiCore: cata

julia> cata(kids -> 1 + sum(kids; init = 0), [[], [[], []]])
5
```
"""
cata(alg, x) = _Cata(alg)(x)

struct _Ana{C, E} <: Function
    coalg::C
    embed::E
end
(a::_Ana)(seed) = a.embed(fmap(a, a.coalg(seed)))

"""
    ana(coalg, seed; embed = Fix)

Anamorphism (unfold): `ana(coalg, s) = embed(fmap(t -> ana(coalg, t), coalg(s)))`. The
coalgebra maps a seed to one layer whose holes hold the next seeds. `embed` wraps each built
layer: `Fix` (the default) builds a `Fix` tree; `embed = identity` builds a tree of bare layers,
i.e. values of a node type that is its own base functor.

**Cost:** one `fmap`, one layer and one `embed` per node. Measured on a 1000-node unfold of a
natural-number functor (phase 5, BenchmarkTools, shared machine): ≈72 B/node with `embed = Fix`
on Julia 1.13.2 and 1.10.12; ≈24 B/node (1.13.2) and ≈72 B/node (1.10.12) with
`embed = identity`. To fold right away, use [`ChuiCore.hylo`](@ref), which builds no tree.

$_COST_STACK

```jldoctest
julia> using ChuiCore: ana, cata

julia> t = ana(n -> fill(n - 1, n), 3; embed = identity);   # node n has n children n - 1

julia> cata(kids -> 1 + sum(kids; init = 0), t)
16
```
"""
ana(coalg, seed; embed = Fix) = _Ana(coalg, embed)(seed)

struct _Hylo{A, C} <: Function
    alg::A
    coalg::C
end
(h::_Hylo)(seed) = h.alg(fmap(h, h.coalg(seed)))

"""
    hylo(alg, coalg, seed)

Hylomorphism: unfold with `coalg`, fold with `alg`, fused, so `hylo(alg, coalg, s) ==
cata(alg, ana(coalg, s))` but no intermediate structure is built:
`hylo(alg, coalg, s) = alg(fmap(t -> hylo(alg, coalg, t), coalg(s)))`. Prefer it for every
unfold-then-fold.

**Cost:** allocates no intermediate tree (0–16 B in total in the research measurement, against
5.2 MB for `cata ∘ ana` on 131,071 nodes) and runs 3–17× faster than `cata ∘ ana`.

$_COST_STACK

```jldoctest
julia> using ChuiCore: hylo

julia> hylo(kids -> 1 + sum(kids; init = 0), n -> fill(n - 1, n), 3)   # the same count, no tree
16
```
"""
hylo(alg, coalg, seed) = _Hylo(alg, coalg)(seed)

struct _Para{A} <: Function
    alg::A
end
(p::_Para)(x) = p.alg(fmap(c -> (c, p(c)), project(x)))

"""
    para(alg, x)

Paramorphism: a fold whose algebra also sees the original children. Each hole of the layer
passed to `alg` is the tuple `(original, result)`, where `original === ` the input subtree (as
stored in `x`: a `Fix` or a node) and `result` its `para` result. Use it for rewrites that must
look at the unrewritten subtree, such as predicate pushdown.

**Cost:** as [`ChuiCore.cata`](@ref) plus one 2-tuple per child (measured ≈45–48 B/node over an
own node type on Julia 1.13.2, ≈76–80 B/node on 1.10.12, `docs/src/performance.md`).

$_COST_STACK

The size of every suffix of a natural number (as `Some` layers), using the original subtrees:

```jldoctest
julia> using ChuiCore: para, cata

julia> depth(x) = x === nothing ? 0 : something(x) + 1;

julia> sizes(::Nothing) = Int[];

julia> sizes(x::Some) = ((orig, res) = something(x); pushfirst!(copy(res), cata(depth, orig)));

julia> para(sizes, Some(Some(Some(nothing))))
3-element Vector{Int64}:
 2
 1
 0
```
"""
para(alg, x) = _Para(alg)(x)

struct _Apo{C, E} <: Function
    coalg::C
    embed::E
end
(a::_Apo)(seed) = a.embed(fmap(_ApoHole(a), a.coalg(seed)))
struct _ApoHole{A} <: Function
    apo::A
end
(h::_ApoHole)(x::Done) = x.tree
(h::_ApoHole)(x::More) = h.apo(x.seed)
(h::_ApoHole)(x) = _badhole(:apo, x, "Done(tree) or More(seed)")

@noinline function _badhole(scheme::Symbol, x, want::String)
    throw(ArgumentError("a $scheme coalgebra must fill every hole with $want, got a $(typeof(x))"))
end

"""
    apo(coalg, seed; embed = Fix)

Apomorphism: an unfold that may stop early. The coalgebra returns a layer whose holes are
[`ChuiCore.Done`](@ref)`(tree)` (embed `tree` as is, unchanged and shared) or
[`ChuiCore.More`](@ref)`(seed)` (continue unfolding from `seed`). Example: inserting into a
sorted list copies only the prefix and shares the rest.

**Cost:** as [`ChuiCore.ana`](@ref) for the unfolded part; a `Done` subtree costs nothing.

$_COST_STACK

```jldoctest
julia> using ChuiCore: apo, Done, More

julia> apo(n -> n == 0 ? nothing : Some(n > 1 ? More(n - 1) : Done(Some(nothing))), 3; embed = identity)
Some(Some(Some(Some(nothing))))
```
"""
apo(coalg, seed; embed = Fix) = _Apo(coalg, embed)(seed)

struct _Histo{A} <: Function
    alg::A
end
function (h::_Histo)(x)
    layer = fmap(h, project(x))
    return Attr(h.alg(layer), layer)
end

"""
    histo(alg, x)

Histomorphism: a fold whose algebra sees the whole history. Each hole of the layer passed to
`alg` is an [`ChuiCore.Attr`](@ref)`(value, layer)`: `value` is the result for that child and
`layer` the child's own layer of `Attr`s, so results for all descendants are reachable (e.g.
Fibonacci from the two previous results in one pass).

**Cost:** as [`ChuiCore.cata`](@ref) plus one `Attr` (two boxed fields) per node, kept until the
end; the result type does not infer (`Any`), and a typed `Cofree` is deferred.

$_COST_STACK

The algebra sees the result for the child (`value`) and, through `layer`, the grandchild:

```jldoctest
julia> using ChuiCore: histo

julia> alg(::Nothing) = 1;

julia> alg(x::Some) = (a = something(x); a.layer === nothing ? 1 : a.value + something(a.layer).value);

julia> histo(alg, Some(Some(Some(Some(nothing)))))   # the 5th Fibonacci number
5
```
"""
histo(alg, x) = _Histo(alg)(x).value

struct _Futu{C, E} <: Function
    coalg::C
    embed::E
end
(f::_Futu)(seed) = f.embed(fmap(_FutuHole(f), f.coalg(seed)))
struct _FutuHole{F} <: Function
    futu::F
end
(h::_FutuHole)(x::More) = h.futu(x.seed)
(h::_FutuHole)(x::Emit) = h.futu.embed(fmap(h, x.layer))
(h::_FutuHole)(x) = _badhole(:futu, x, "More(seed) or Emit(layer)")

"""
    futu(coalg, seed; embed = Fix)

Futumorphism: an unfold that may emit several layers per step. The coalgebra returns a layer
whose holes are [`ChuiCore.More`](@ref)`(seed)` (continue from `seed`) or
[`ChuiCore.Emit`](@ref)`(layer)` (a layer built now, whose holes are again `More`/`Emit`).

**Cost:** as [`ChuiCore.ana`](@ref), plus one marker per hole.

$_COST_STACK

```jldoctest
julia> using ChuiCore: futu, Emit, More

julia> futu(n -> n == 0 ? nothing : Some(Emit(Some(More(n - 1)))), 2; embed = identity)   # 2 layers per step
Some(Some(Some(Some(nothing))))
```
"""
futu(coalg, seed; embed = Fix) = _Futu(coalg, embed)(seed)

# ---------------------------------------------------------------------------------------------
# Monadic variants (data-fix's foldFixM / unfoldFixM / refoldM): the base functor must be
# Traversable, so the children's effects are sequenced with `traverse(tag, f, layer)`.

const _COST_MONADIC = """
**Requires** the base functor to be Traversable (`traverse(::IsTraversable, tag, f, layer)`) and
`tag` to be a Monad. The children of a layer are all run (their effects combined by the
applicative `traverse`) before `chain` continues; with Maybe a `nothing` stops every algebra call
above it, but siblings already started still run.

**Cost:** as the plain scheme plus one `traverse` and one `chain` per node; `traverse` builds the
layer through `ap`, one closure and one effect value per child.
"""

struct _CataM{T, A} <: Function
    tag::T
    alg::A
end
(c::_CataM)(x) = chain(c.alg, traverse(c.tag, c, project(x)))

"""
    cataM(tag, alg, x)

Monadic catamorphism: `alg` maps a layer of results to a monadic value of class `tag`;
`cataM(tag, alg, x) = chain(alg, traverse(tag, c -> cataM(tag, alg, c), project(x)))`. Example:
`cataM(MaybeTag(), safe_eval, expr)` is `nothing` as soon as a division by zero fails.

$_COST_MONADIC

$_COST_STACK

Count the nodes of a rose tree (nested vectors), failing on a node with more than two children:

```jldoctest
julia> using ChuiCore: cataM, MaybeTag

julia> count2(kids) = length(kids) > 2 ? nothing : Some(1 + sum(kids; init = 0));

julia> cataM(MaybeTag(), count2, [[], [[], []]])
Some(5)

julia> cataM(MaybeTag(), count2, [[], [[], [], []]]) === nothing
true
```
"""
cataM(tag, alg, x) = _CataM(tag, alg)(x)

struct _AnaM{T, C, E} <: Function
    tag::T
    coalg::C
    embed::E
end
(a::_AnaM)(seed) = chain(layer -> chain(_EmbedPure(a.tag, a.embed), traverse(a.tag, a, layer)), a.coalg(seed))

struct _EmbedPure{T, E} <: Function
    tag::T
    embed::E
end
(w::_EmbedPure)(layer) = pure(w.tag, w.embed(layer))

"""
    anaM(tag, coalg, seed; embed = Fix)

Monadic anamorphism: `coalg` maps a seed to a monadic value (class `tag`) of a layer of seeds;
the children are unfolded with `traverse` and each layer is wrapped by `embed` (default `Fix`,
`identity` for an own node type).

$_COST_MONADIC

$_COST_STACK

Unfold a binary tree of depth `n` (nested vectors), failing for a depth over 2:

```jldoctest
julia> using ChuiCore: anaM, cata, MaybeTag

julia> grow(n) = n > 2 ? nothing : Some(n == 0 ? Int[] : [n - 1, n - 1]);

julia> t = anaM(MaybeTag(), grow, 2; embed = identity);

julia> cata(kids -> 1 + sum(kids; init = 0), something(t))
7

julia> anaM(MaybeTag(), grow, 3; embed = identity) === nothing
true
```
"""
anaM(tag, coalg, seed; embed = Fix) = _AnaM(tag, coalg, embed)(seed)

struct _HyloM{T, A, C} <: Function
    tag::T
    alg::A
    coalg::C
end
(h::_HyloM)(seed) = chain(layer -> chain(h.alg, traverse(h.tag, h, layer)), h.coalg(seed))

"""
    hyloM(tag, alg, coalg, seed)

Monadic hylomorphism: the fused form of `cataM(tag, alg, ·)` after `anaM(tag, coalg, ·)`,
building no intermediate tree. `coalg` and `alg` both return monadic values of class `tag`.

$_COST_MONADIC

$_COST_STACK

```jldoctest
julia> using ChuiCore: hyloM, MaybeTag

julia> grow(n) = n > 2 ? nothing : Some(n == 0 ? Int[] : [n - 1, n - 1]);

julia> hyloM(MaybeTag(), kids -> Some(1 + sum(kids; init = 0)), grow, 2)
Some(7)

julia> hyloM(MaybeTag(), kids -> Some(1 + sum(kids; init = 0)), grow, 5) === nothing
true
```
"""
hyloM(tag, alg, coalg, seed) = _HyloM(tag, alg, coalg)(seed)
