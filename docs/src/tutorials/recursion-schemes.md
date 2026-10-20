# Recursion schemes

```@meta
DocTestSetup = :(using ChuiCore)
```

A recursion scheme separates *what to do at one node* from *how to walk the tree*. You write the
first, an **algebra** (fold) or **coalgebra** (unfold) with one method per node type, and a scheme
such as [`ChuiCore.cata`](@ref ChuiCore.cata) supplies the second. The only thing a scheme needs
from your type is a Functor instance: a way to apply a function to the children of one node,
`fmap`.

```jldoctest schemes
julia> using ChuiCore: cata, ana, hylo, para, apo, histo, futu, cataM, project, Fix, Done, More, Attr, Emit, MaybeTag
```

## Your own node type

A small arithmetic language. Each node is a plain struct; the child fields are untyped, because
during a fold they hold whatever the algebra returns (numbers, strings, …) rather than nodes.
Untyped fields also keep one type for every tree shape, so nothing recompiles per shape.

```jldoctest schemes
julia> struct Lit; v::Int; end

julia> struct Add; l; r; end

julia> struct Mul; l; r; end

julia> struct Div; l; r; end

julia> const Arith = Union{Lit, Add, Mul, Div};
```

The Functor instance (ADR-0001's encoding): a constructor-class tag for the types, the tag's
`FunctorStyle`, and `fmap` with the style as its first, typed argument. A leaf has no children,
so `fmap` returns it unchanged. The monadic schemes also need Traversable (`traverse`), so add it
now:

```jldoctest schemes
julia> struct ArithTag end

julia> ChuiCore.constructorclass(::Type{<:Arith}) = ArithTag()

julia> ChuiCore.FunctorStyle(::ArithTag) = ChuiCore.IsFunctor()

julia> ChuiCore.TraversableStyle(::ArithTag) = ChuiCore.IsTraversable()

julia> ChuiCore.fmap(::ChuiCore.IsFunctor, f, x::Lit) = x

julia> ChuiCore.traverse(::ChuiCore.IsTraversable, tag, f, x::Lit) = ChuiCore.pure(tag, x)

julia> for T in (:Add, :Mul, :Div)
           @eval ChuiCore.fmap(::ChuiCore.IsFunctor, f, x::$T) = $T(f(x.l), f(x.r))
           @eval ChuiCore.traverse(::ChuiCore.IsTraversable, tag, f, x::$T) =
               ChuiCore.ap(ChuiCore.fmap(l -> (r -> $T(l, r)), f(x.l)), f(x.r))
       end

julia> e = Mul(Add(Lit(1), Lit(2)), Lit(4));   # (1 + 2) * 4
```

This type is **its own base functor**: the schemes reach a node's layer through
[`ChuiCore.project`](@ref ChuiCore.project), which is the identity for every value except a
`Fix`, so the tree is traversed as it is, with no wrapping.

```jldoctest schemes
julia> project(e) === e
true
```

## `cata`: fold

`cata(alg, x)` folds bottom-up: by the time `alg` sees a node, its child fields already hold the
results for the children. Evaluating and pretty-printing are two algebras over the same tree:

```jldoctest schemes
julia> evalalg(x::Lit) = x.v; evalalg(x::Add) = x.l + x.r; evalalg(x::Mul) = x.l * x.r; evalalg(x::Div) = x.l ÷ x.r;

julia> cata(evalalg, e)
12

julia> showalg(x::Lit) = string(x.v); showalg(x::Add) = "($(x.l) + $(x.r))"; showalg(x::Mul) = "$(x.l) * $(x.r)"; showalg(x::Div) = "$(x.l) / $(x.r)";

julia> cata(showalg, e)
"(1 + 2) * 4"
```

Every layer, leaves included, must be a Functor; a value that is not one is an error, not a
silent leaf:

```jldoctest schemes
julia> cata(evalalg, Add(Lit(1), 2))
ERROR: ArgumentError: Int64 is not a Functor: ChuiCore.FunctorStyle(ChuiCore.constructorclass(Int64)) is NotFunctor(). Register the type with ChuiCore.constructorclass and ChuiCore.FunctorStyle.
[...]
```

## `ana`: unfold, and `hylo`: unfold then fold

`ana(coalg, seed)` builds a tree top-down: the coalgebra turns a seed into one layer whose holes
hold the next seeds. Here a range becomes a balanced sum. `embed = identity` keeps the bare nodes
(our type is its own base functor); the default, `embed = Fix`, would wrap each layer in a `Fix`.

```jldoctest schemes
julia> halves(r) = length(r) == 1 ? Lit(only(r)) : Add(r[begin:(begin + length(r) ÷ 2 - 1)], r[(begin + length(r) ÷ 2):end]);

julia> t = ana(halves, 1:4; embed = identity);

julia> cata(showalg, t)
"((1 + 2) + (3 + 4))"
```

When the tree exists only to be folded, [`ChuiCore.hylo`](@ref ChuiCore.hylo) fuses the two
passes and never builds it:

```jldoctest schemes
julia> hylo(evalalg, halves, 1:100) == cata(evalalg, ana(halves, 1:100; embed = identity)) == 5050
true
```

## `para`: a fold that also sees the original children

In `para(alg, x)` each hole holds the pair `(original child, result)`. A pretty-printer that adds
parentheses only where they are needed must look at the original child, not at its string:

```jldoctest schemes
julia> wrap((orig, s)) = orig isa Add ? "($s)" : s;

julia> pp(x::Lit) = string(x.v); pp(x::Add) = "$(x.l[2]) + $(x.r[2])"; pp(x::Mul) = "$(wrap(x.l)) * $(wrap(x.r))"; pp(x::Div) = "$(wrap(x.l)) / $(wrap(x.r))";

julia> para(pp, Add(Mul(Lit(2), Lit(3)), Mul(Add(Lit(1), Lit(2)), Lit(4))))
"2 * 3 + (1 + 2) * 4"
```

## `apo`: an unfold that can stop early

An `apo` coalgebra fills each hole with [`ChuiCore.More`](@ref ChuiCore.More)`(seed)` (keep
unfolding) or [`ChuiCore.Done`](@ref ChuiCore.Done)`(tree)` (embed a finished tree as is). The
finished subtree is shared, not copied:

```jldoctest schemes
julia> shared = Mul(Lit(2), Lit(3));

julia> t = apo(n -> n == 0 ? Lit(0) : Add(Done(shared), More(n - 1)), 3; embed = identity);

julia> cata(showalg, t)
"(2 * 3 + (2 * 3 + (2 * 3 + 0)))"

julia> t.l === shared
true
```

## `histo`: a fold with the whole history

In `histo(alg, x)` each hole is an [`ChuiCore.Attr`](@ref ChuiCore.Attr)`(value, layer)`: the
child's result and the child's own layer of `Attr`s, so the results for every descendant are
reachable. The classic example needs a list-like structure: the natural numbers as layers of
the Maybe functor (`nothing` is zero, `Some(n)` one more than `n`; Maybe is a Functor in
ChuiCore). Fibonacci looks two results back, in one pass:

```jldoctest schemes
julia> nat(n) = ana(k -> k == 0 ? nothing : Some(k - 1), n; embed = identity);

julia> nat(2)
Some(Some(nothing))

julia> fib(::Nothing) = 1;

julia> fib(x::Some) = (a = something(x); a.layer === nothing ? 1 : a.value + something(a.layer).value);

julia> [histo(fib, nat(n)) for n in 0:7]'
1×8 adjoint(::Vector{Int64}) with eltype Int64:
 1  1  2  3  5  8  13  21
```

## `futu`: an unfold that emits several layers at once

A `futu` coalgebra fills holes with `More(seed)` or [`ChuiCore.Emit`](@ref ChuiCore.Emit)`(layer)`, a
layer built right now whose own holes are again `More` or `Emit`. The sum of squares
`n² + (n-1)² + … + 0`, emitting the `n * n` subtree in one step:

```jldoctest schemes
julia> sq(n) = n == 0 ? Lit(0) : Add(Emit(Mul(Emit(Lit(n)), Emit(Lit(n)))), More(n - 1));

julia> t = ChuiCore.futu(sq, 3; embed = identity);

julia> cata(showalg, t), cata(evalalg, t)
("(3 * 3 + (2 * 2 + (1 * 1 + 0)))", 14)
```

## A monadic fold: `cataM`

`cataM(tag, alg, x)` is `cata` with an algebra that returns a monadic value; the children's
effects are sequenced with the type's `traverse` (that is why the instance above defines it).
With Maybe, a division by zero turns the whole evaluation into `nothing`:

```jldoctest schemes
julia> safe(x::Lit) = Some(x.v); safe(x::Add) = Some(x.l + x.r); safe(x::Mul) = Some(x.l * x.r);

julia> safe(x::Div) = x.r == 0 ? nothing : Some(x.l ÷ x.r);

julia> cataM(MaybeTag(), safe, Div(Lit(12), Add(Lit(1), Lit(2))))
Some(4)

julia> cataM(MaybeTag(), safe, Add(Lit(1), Div(Lit(1), Lit(0)))) === nothing
true
```

`anaM` and `hyloM` are the monadic unfold and the fused monadic unfold-then-fold.

## `Fix` for generic code

A type whose children are themselves the recursive type is its own base functor, as above. The
other route is [`ChuiCore.Fix`](@ref ChuiCore.Fix): the fixpoint of a base functor, one `Fix`
wrapper per node, so any Functor can serve as the layer type. `ana` builds `Fix` trees by
default, `project` unwraps one layer, and the same algebras work unchanged:

```jldoctest schemes
julia> f = ana(halves, 1:3);   # embed = Fix

julia> f isa Fix, project(f) isa Add
(true, true)

julia> cata(evalalg, f), cata(showalg, f)
(6, "(1 + (2 + 3))")

julia> cata(Fix, f) == f   # folding with the constructor rebuilds the tree
true
```

Prefer an own node type in hot paths (see the costs below); `Fix` is for generic code and for
functors you do not own. The owner of a recursive type with a separate base functor can instead
add `ChuiCore.project(x::MyType) = MyLayer(...)`.

## What is not there

- **No stack-safe `cata`.** Every scheme recurses on the Julia stack, several frames per level.
  A linear structure (a list as nested layers) overflows somewhere between about 10^4 and
  4×10^4 levels on the main task, earlier in a spawned task. Query plans and expression trees
  are shallow; for long linear data write a loop. A stack-safe `cata` is deferred (HANDOFF,
  "Deferred").
- **No typed `Cofree`**: `histo`'s `Attr` fields are `Any`, so its result does not infer.
- `foldfree` over a strict monad has the same stack limit; see the free-monads tutorial.

## What it costs

Measured in phase 4 on Julia 1.13.2 (`docs/src/performance.md`, `benchmark/allocs.jl`; a loaded
shared machine, trust the ratios):

- `cata` over an own node type: ≈18 ns per node, 0 B per call (1023-node tree).
- `cata` over `Fix`: ≈77 ns and ≈47 B per node, about 4× an own node type: each node is a
  dynamic `fmap` dispatch plus a rebuilt layer.
- `para` over an own node type: ≈45–48 B per node on 1.13.2, ≈76–80 B on 1.10.12 (one tuple
  per child).
- `ana`, measured in phase 5 on a 1000-node natural-number unfold: ≈72 B per node with
  `embed = Fix`; ≈24 B (1.13.2) to ≈72 B (1.10.12) per node with `embed = identity`.
- `hylo` builds no intermediate tree (research: 0–16 B in total against 5.2 MB for `cata ∘ ana`
  on 131,071 nodes, 3–17× faster).
- The monadic variants add one `traverse` and one `chain` per node (closures and effect values
  per child).

A hand-written function with one method per node type is still 10–50× faster than any generic
scheme (research measurement). Use schemes where the separation pays: many algebras over one
type, rewrites, plans.
