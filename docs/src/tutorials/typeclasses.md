# Typeclasses and your own instance

```@meta
DocTestSetup = :(using ChuiCore)
```

ChuiCore has the usual constructor classes of functional programming: Functor, Applicative,
Monad, Alternative, Foldable, Traversable, Contravariant, Bifunctor, Profunctor, Category and
Arrow. This tutorial shows how they are encoded, uses the built-in instances, and then makes a new
container type an instance and checks it with the law kits.

## The encoding: type, tag, style, operation

Julia has no typeclasses, so ChuiCore encodes them in three steps (ADR-0001 §3):

1. [`ChuiCore.constructorclass`](@ref ChuiCore.constructorclass) maps a concrete type to a singleton **tag**. Every `Array`
   maps to `ArrayTag()`, `Some{T}` and `Nothing` both map to `MaybeTag()` (Maybe is Base's
   `Some` / `nothing`), and any type nobody registered maps to `NoTag()`.
2. Each class has a **style** trait on the tag: [`ChuiCore.FunctorStyle`](@ref ChuiCore.FunctorStyle)`(tag)` returns
   `IsFunctor()` or `NotFunctor()`, and likewise for the other ten classes.
3. Each operation **dispatches on the style**. `fmap(f, x)` is
   `fmap(FunctorStyle(constructorclass(typeof(x))), f, x)`, and an instance adds the method
   `fmap(::IsFunctor, f, x::MyType)`.

```jldoctest typeclasses
julia> ChuiCore.constructorclass(Vector{Int})
ChuiCore.ArrayTag()

julia> ChuiCore.constructorclass(typeof(nothing))
ChuiCore.MaybeTag()

julia> ChuiCore.FunctorStyle(ChuiCore.ArrayTag())
ChuiCore.IsFunctor()

julia> ChuiCore.MonadStyle(Tuple{Int, Int})
ChuiCore.NotMonad()

julia> ChuiCore.constructorclass(Symbol)
ChuiCore.NoTag()
```

A type that is not an instance of a class gets an `ArgumentError` that says how to register it,
not a `MethodError`:

```jldoctest typeclasses
julia> ChuiCore.fmap(identity, :a)
ERROR: ArgumentError: Symbol is not a Functor: ChuiCore.FunctorStyle(ChuiCore.constructorclass(Symbol)) is NotFunctor(). Register the type with ChuiCore.constructorclass and ChuiCore.FunctorStyle.
```

Operations that have no value to dispatch on take the tag first: `pure(tag, x)`,
`zeroalt(tag)`, `idarrow(tag)`, `arr(tag, f)` and `traverse(tag, f, xs)` (there `tag` names the
applicative the effects belong to).

## Why `fmap`, `pure` and `ap` are written qualified

`chain`, `alt`, `zeroalt`, `contramap`, `bimap`, `dimap`, `lmap`, `rmap` and the arrow operations
are exported. `fmap`, `pure` and `ap` are public but not exported: ChuiCore exports a name only
if no package on its clash list exports a different binding of it (ADR-0005 §2), and Functors.jl
exports `fmap` while TypeClasses.jl exports `pure`, `ap`, `neutral` and `curry`. So you write
`ChuiCore.fmap` or bring the names in with `using ChuiCore: fmap, pure, ap`. The rules are on
[Export tiers and the clash list](../explanation/export-tiers.md).

## Functor: `fmap`

`fmap(f, x)` applies `f` inside `x` and keeps its shape.

```jldoctest typeclasses
julia> ChuiCore.fmap(x -> x + 1, [1, 2, 3])
3-element Vector{Int64}:
 2
 3
 4

julia> ChuiCore.fmap(x -> x + 1, (1, 2))
(2, 3)

julia> ChuiCore.fmap(x -> x + 1, Some(1))
Some(2)

julia> ChuiCore.fmap(x -> x + 1, nothing) === nothing
true

julia> ChuiCore.fmap(uppercase, Dict(:a => "x"))
Dict{Symbol, String} with 1 entry:
  :a => "X"

julia> ChuiCore.fmap(x -> 10x, ChuiCore.Identity(4)).value
40
```

A `Dict` is a Functor on its values; its keys stay as they are.

## Applicative: `pure` and `ap`

`pure(tag, x)` puts a plain value into the class, and `ap(ff, fx)` applies the functions held by
`ff` to the values held by `fx`. For Maybe a missing side gives `nothing`; for arrays every
function meets every value, in Haskell list order.

```jldoctest typeclasses
julia> ChuiCore.pure(ChuiCore.MaybeTag(), 3)
Some(3)

julia> ChuiCore.ap(Some(x -> 2x), Some(21))
Some(42)

julia> ChuiCore.ap(Some(x -> 2x), nothing) === nothing
true

julia> ChuiCore.ap([x -> x + 1, x -> 10x], [1, 2])
4-element Vector{Int64}:
  2
  3
 10
 20
```

Vectors have a second lawful Applicative, which pairs functions and values position by position.
It lives on its own wrapper type, [`ChuiCore.ZipVector`](@ref ChuiCore.ZipVector), with its own tag, so the choice is
made by the type and never by an extra argument. Its `pure` is an infinite repetition:

```jldoctest typeclasses
julia> ChuiCore.ap(ChuiCore.ZipVector([x -> x + 1, x -> 10x]), ChuiCore.ZipVector([1, 2, 3]))
ChuiCore.ZipVector([2, 20])

julia> ChuiCore.ap(ChuiCore.pure(ChuiCore.ZipVectorTag(), x -> 2x), ChuiCore.ZipVector([1, 2]))
ChuiCore.ZipVector([2, 4])
```

Both operands of `ap` must belong to the same class:

```jldoctest typeclasses
julia> ChuiCore.ap([identity], Some(1))
ERROR: ArgumentError: ChuiCore.ap has no instance method for a Vector{typeof(identity)} with a Some{Int64} (tags ChuiCore.ArrayTag() and ChuiCore.MaybeTag()): both operands must belong to the same constructor class.
```

## Monad: `chain`

`chain(f, m)` is monadic bind with the function first, so a `do` block reads like sequential
code. Here each step may fail:

```jldoctest typeclasses
julia> safesqrt(x) = x >= 0 ? Some(sqrt(x)) : nothing;

julia> chain(safesqrt, Some(16.0))
Some(4.0)

julia> chain(Some(16.0)) do x
           chain(safesqrt, Some(x - 7))
       end
Some(3.0)

julia> chain(Some(1.0)) do x
           chain(safesqrt, Some(x - 7))
       end === nothing
true

julia> chain(x -> [x, -x], [1, 2])
4-element Vector{Int64}:
  1
 -1
  2
 -2
```

## Alternative: `alt` and `zeroalt`

`alt(a, b)` is a choice with identity `zeroalt(tag)`: the first non-`nothing` for Maybe, `vcat`
for arrays.

```jldoctest typeclasses
julia> alt(nothing, Some(2))
Some(2)

julia> alt(Some(1), zeroalt(ChuiCore.MaybeTag()))
Some(1)

julia> alt([1], [2, 3])
3-element Vector{Int64}:
 1
 2
 3
```

## Traversable: `traverse` and `sequence`

`traverse(tag, f, xs)` runs `f` on each element, where `f` returns an effect of the applicative
`tag`, and collects the results inside one effect. With Maybe it is "all or nothing":

```jldoctest typeclasses
julia> ChuiCore.traverse(ChuiCore.MaybeTag(), safesqrt, [4.0, 9.0])
Some([2.0, 3.0])

julia> ChuiCore.traverse(ChuiCore.MaybeTag(), safesqrt, [4.0, -1.0]) === nothing
true

julia> ChuiCore.sequence(ChuiCore.MaybeTag(), (Some(1), Some("a")))
Some((1, "a"))
```

## Contravariant, Bifunctor, Profunctor

A [`ChuiCore.Predicate`](@ref ChuiCore.Predicate) consumes values, so it maps contravariantly: `contramap(f, p)`
runs `f` before `p`. `bimap` maps both sides of a `Pair` or a 2-tuple. Functions are
Profunctors: `dimap(f, g, h)` runs `f`, then `h`, then `g`.

```jldoctest typeclasses
julia> isshort = contramap(length, ChuiCore.Predicate(<(4)));

julia> isshort("abc"), isshort("abcdef")
(true, false)

julia> bimap(uppercase, x -> x + 1, "a" => 1)
"A" => 2

julia> bimap(string, float, (1, 2))
("1", 2.0)

julia> dimap(x -> x + 1, string, x -> 2x)(3)
"8"

julia> lmap(x -> x + 1, x -> 2x)(3), rmap(string, x -> 2x)(3)
(8, "6")
```

## Category and Arrow on functions

Functions form a Category whose composition is `⨟` (left to right) and whose identity is
`idarrow(FunctionTag())`. The Arrow operations act on 2-tuples:

```jldoctest typeclasses
julia> (idarrow(ChuiCore.FunctionTag()) ⨟ string)(1)
"1"

julia> arr(ChuiCore.FunctionTag(), sin) === sin
true

julia> arrfirst(x -> x + 1)((1, "a"))
(2, "a")

julia> arrsecond(x -> x + 1)(("a", 1))
("a", 2)

julia> arrsplit(x -> x + 1, string)((1, 2))
(2, "2")

julia> fanout(x -> x + 1, string)(1)
(2, "1")
```

## Write your own instance

Take a small writer monad: a value together with a log of messages. Functor maps the value,
Applicative and Monad concatenate the logs.

```jldoctest typeclasses
julia> struct Logged{T}
           value::T
           log::Vector{String}
       end

julia> Base.:(==)(a::Logged, b::Logged) = a.value == b.value && a.log == b.log;

julia> Base.isequal(a::Logged, b::Logged) = isequal(a.value, b.value) && isequal(a.log, b.log);

julia> Base.hash(a::Logged, h::UInt) = hash(a.log, hash(a.value, hash(:Logged, h)));
```

The `log` field is a `Vector`, so the default `==` would compare it by identity: an instance
needs value equality, because the law kits compare with `isequal`.

**Step 1: the tag and the mapping.** A new singleton tag, and a `constructorclass` method for the
type (dispatch on `Type{<:Logged}`, so every `Logged{T}` maps to it):

```jldoctest typeclasses
julia> struct LoggedTag end

julia> ChuiCore.constructorclass(::Type{<:Logged}) = LoggedTag();
```

**Step 2: the styles.** Declare which classes the tag is an instance of:

```jldoctest typeclasses
julia> ChuiCore.FunctorStyle(::LoggedTag) = ChuiCore.IsFunctor();

julia> ChuiCore.ApplicativeStyle(::LoggedTag) = ChuiCore.IsApplicative();

julia> ChuiCore.MonadStyle(::LoggedTag) = ChuiCore.IsMonad();
```

**Step 3: the instance methods.** Each value operation gets a method whose first argument is the
style, **typed**, and whose operands are your type:

```jldoctest typeclasses
julia> ChuiCore.fmap(::ChuiCore.IsFunctor, f, x::Logged) = Logged(f(x.value), x.log);

julia> ChuiCore.pure(::LoggedTag, x) = Logged(x, String[]);

julia> ChuiCore.ap(::ChuiCore.IsApplicative, ff::Logged, fx::Logged) =
           Logged(ff.value(fx.value), vcat(ff.log, fx.log));

julia> function ChuiCore.chain(::ChuiCore.IsMonad, f, m::Logged)
           r = f(m.value)
           return Logged(r.value, vcat(m.log, r.log))
       end;
```

Type the style argument: write `ap(::IsApplicative, ff::Logged, fx::Logged)`, never
`ap(_, ff::Logged, fx::Logged)`. ChuiCore defines a fallback `ap(::IsApplicative, ff, fx)` that
reports operands of two different classes; a method with an untyped style is neither more nor
less specific than that fallback, so a call would be ambiguous. The same holds for `alt`.

Now every operation works on `Logged`, including a `do` block:

```jldoctest typeclasses
julia> logstep(msg, f) = x -> Logged(f(x), [msg]);

julia> r = chain(Logged(3, ["start"])) do x
           chain(logstep("double", y -> 2y), logstep("add one", y -> y + 1)(x))
       end;

julia> r.value, r.log
(8, ["start", "add one", "double"])

julia> ChuiCore.fmap(string, Logged(1, ["one"])) == Logged("1", ["one"])
true

julia> ChuiCore.ap(ChuiCore.pure(LoggedTag(), x -> x + 1), Logged(1, ["a"])) == Logged(2, ["a"])
true
```

Mixing `Logged` with another class lands in ChuiCore's mismatch fallback, an `ArgumentError`:

```jldoctest typeclasses; filter = r"Main\.[^ ]*\."
julia> ChuiCore.ap(Logged(identity, String[]), Some(1))
ERROR: ArgumentError: ChuiCore.ap has no instance method for a Logged{typeof(identity)} with a Some{Int64} (tags LoggedTag() and ChuiCore.MaybeTag()): both operands must belong to the same constructor class.
```

### Check the laws

An instance is only useful if it is lawful. The law kits `test_functor_laws`,
`test_applicative_laws` and `test_monad_laws` (and one per other class; see
[Law kits for downstream packages](law-kits.md)) take the tag first, then sample collections,
and record one inner `@testset` per law in the current test set. They have methods once `Test`
is loaded:

```jldoctest typeclasses
julia> using Test

julia> samples = [Logged(1, String[]), Logged(2, ["two"]), Logged(3, ["a", "b"])];

julia> fs = [x -> x + 1, x -> 2x];

julia> ks = [x -> Logged(x + 1, ["inc"]), x -> Logged(2x, ["dbl"])];

julia> ts = redirect_stdout(devnull) do
           @testset "Logged laws" begin
               test_functor_laws(LoggedTag(), samples, fs)
               test_applicative_laws(LoggedTag(), samples, fs, [0, 5])
               test_monad_laws(LoggedTag(), samples, ks, [0, 5])
           end
       end;

julia> Test.anynonpass(ts), sum(length(kit.results) for kit in ts.results)   # no failure, 11 laws
(false, 11)
```

In a package you write only the `@testset`, in a `@testitem` of its test suite; it prints a
summary and throws `Test.TestSetException` if a law fails. The summary has a timing column, so
this page sends it to `devnull` and checks the returned test set. A failing law still throws
here, so a broken instance fails the doctest.

## What it costs

- **The encoding is free.** `constructorclass` and the styles are methods returning constants,
  so the compiler folds `FunctorStyle(constructorclass(typeof(x)))` away: `code_typed` of
  `v -> ChuiCore.fmap(f, v)` on a `Vector{Int}` contains no trait call. Calling `fmap` costs what
  the instance method costs.
- **Built-in instances** cost what their implementation does: `fmap` on an `Array` is one `map`;
  `ap` and `chain` on arrays build one new `Vector` (with growth, since the length is not known up
  front); Maybe, `Identity`, `Pair`, 2-tuples and the function instances (`dimap`, `contramap`,
  the arrows) allocate nothing on the heap for isbits contents; `ZipVector` makes one new
  `Vector` per operation.
- **`traverse` and `sequence` are quadratic on vectors**: one `fmap` and one `ap` per element,
  each re-building the accumulated collection. Use them for small containers and laws, not hot
  loops.
- **Your instance** costs what its methods cost: `Logged`'s `ap` and `chain` allocate one new log
  `Vector` per call.
