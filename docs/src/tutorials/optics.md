# Optics

```@meta
DocTestSetup = :(using ChuiCore)
```

An optic points at a part of a value, so you can read that part, or build a **new** value with the
part changed, without writing the reconstruction by hand. ChuiCore has lenses (a part that is
always there: a property, an element) and prisms (one case of a sum type, which may or may not be
there). Nothing here mutates: every update returns a new value.

The optics are public but not exported (ChuiCore's ADR-0004), so this page imports the names it
uses and always writes `ChuiCore.set` and `ChuiCore.modify` qualified.

```jldoctest optics
julia> using ChuiCore: Lens, IndexLens, @lens, Prism, preview, review
```

## Lenses on properties: `Lens`

`Lens{:name}()` focuses the property `name`. Getting is calling the lens; setting is
`ChuiCore.set(x, lens, v)` and updating is `ChuiCore.modify(f, x, lens)`, in **Accessors'
argument order** (the value first for `set`, the function first for `modify`).

```jldoctest optics
julia> struct Point; x::Int; y::Int; end

julia> p = Point(1, 2);

julia> Lens{:x}()(p)
1

julia> ChuiCore.set(p, Lens{:x}(), 10)
Point(10, 2)

julia> ChuiCore.modify(y -> y * 100, p, Lens{:y}())
Point(1, 200)

julia> p                       # unchanged
Point(1, 2)
```

Lenses work the same way on `NamedTuple`s:

```jldoctest optics
julia> ChuiCore.set((a = 1, b = "x"), Lens{:b}(), "y")
(a = 1, b = "y")
```

`set` and `modify` are never exported: Accessors exports functions with the same names and the
same argument order, and a second export would make a bare `set` ambiguous for anyone who loads
both.

## Lenses on elements: `IndexLens`

`IndexLens(i...)` focuses `x[i...]`. Tuples and named tuples are rebuilt; arrays and dictionaries
are **copied** with the element replaced (an array's element type widens when needed).

```jldoctest optics
julia> IndexLens(2)((10, 20, 30))
20

julia> ChuiCore.set((10, 20, 30), IndexLens(2), 99)
(10, 99, 30)

julia> v = [1, 2, 3];

julia> ChuiCore.set(v, IndexLens(3), 0.5)
3-element Vector{Float64}:
 1.0
 2.0
 0.5

julia> v                       # the original array is untouched
3-element Vector{Int64}:
 1
 2
 3

julia> ChuiCore.modify(uppercase, Dict(:k => "a"), IndexLens(:k))
Dict{Symbol, String} with 1 entry:
  :k => "A"
```

## Composing optics: `⨟` and `@lens`

Optics compose like functions. With `⨟` you write them outside-in, in the order you would walk
into the value; with Base's `∘` you write them inside-out.

```jldoctest optics
julia> struct Segment; from::Point; to::Point; end

julia> s = Segment(Point(0, 0), Point(3, 4));

julia> to_x = Lens{:to}() ⨟ Lens{:x}();

julia> to_x(s)
3

julia> ChuiCore.set(s, to_x, 30)
Segment(Point(0, 0), Point(30, 4))

julia> to_x == Lens{:x}() ∘ Lens{:to}()
true
```

`@lens` builds the same compositions from the access syntax you would write by hand, with `_` for
the value:

```jldoctest optics
julia> ChuiCore.modify(x -> x + 1, s, @lens _.to.y)
Segment(Point(0, 0), Point(3, 5))

julia> data = (rows = [(id = 1,), (id = 2,)],);

julia> ChuiCore.set(data, (@lens _.rows[2].id), 20)
(rows = [(id = 1,), (id = 20,)],)
```

Index expressions in `@lens` are evaluated where the macro is written, so a variable works;
`end` and `begin` do not.

```jldoctest optics
julia> i = 1;

julia> (@lens _.rows[i].id)(data)
1
```

## Prisms: one case of a sum type

ChuiCore models a closed sum type as a `Union` of plain structs (ChuiCore's ADR-0002). A prism
focuses one case. `preview(p, x)` is `Some(v)` when `x` is that case and `nothing` otherwise;
`review(p, v)` builds the sum value from the focus. `Prism(T)` is the prism of the variant `T`.

```jldoctest optics
julia> struct Circle; r::Float64; end

julia> struct Rect; w::Float64; h::Float64; end

julia> const Shape = Union{Circle, Rect};

julia> circle = Prism(Circle);

julia> preview(circle, Circle(1.0))
Some(Circle(1.0))

julia> preview(circle, Rect(1.0, 2.0)) === nothing
true

julia> review(circle, Circle(2.0))
Circle(2.0)
```

`set` and `modify` through a prism change the value when it is the prism's case and return it
unchanged otherwise. Composed with a lens, a prism reaches into that case only:

```jldoctest optics
julia> radius = circle ⨟ Lens{:r}();

julia> shapes = Shape[Circle(1.0), Rect(1.0, 2.0)];

julia> [ChuiCore.modify(r -> 2r, sh, radius) for sh in shapes]
2-element Vector{Any}:
 Circle(2.0)
 Rect(1.0, 2.0)
```

A prism is not callable (there may be nothing to get), so a composition that contains one is used
with `set`, `modify` and `preview`-style code only, never called directly.

`Prism(match, build)` makes a prism from two functions, for cases that are not types:

```jldoctest optics
julia> positive = Prism(x -> x > 0 ? Some(x) : nothing, identity);

julia> ChuiCore.modify(sqrt, 16.0, positive), ChuiCore.modify(sqrt, -16.0, positive)
(4.0, -16.0)
```

## Rebuilding immutable structs: ConstructionBase

`set` rebuilds a struct with ConstructionBase's `setproperties`, the same hook Accessors uses
(ChuiCore's ADR-0008). By default it calls `constructorof(T)`, which is the type's name without
parameters, with all the fields. So an inner constructor that checks an invariant still checks it:

```jldoctest optics
julia> struct NonNeg
           v::Int
           NonNeg(v) = v >= 0 ? new(v) : throw(ArgumentError("negative: $v"))
       end

julia> ChuiCore.set(NonNeg(1), Lens{:v}(), 5)
NonNeg(5)

julia> ChuiCore.set(NonNeg(1), Lens{:v}(), -5)
ERROR: ArgumentError: negative: -5
[...]
```

A type parameter that the fields do not determine (a phantom parameter) is lost by the default,
so `set` throws a `MethodError`:

```jldoctest optics
julia> struct Tagged{Unit}; v::Float64; end

julia> ChuiCore.set(Tagged{:m}(1.0), Lens{:v}(), 2.0)
ERROR: MethodError: no method matching Tagged(::Float64)
[...]
```

The type's owner fixes it once by defining `ConstructionBase.constructorof`. Accessors re-exports
that same function, so this page reaches it through Accessors (a package of yours would depend on
ConstructionBase directly and write `ConstructionBase.constructorof`):

```jldoctest optics
julia> using Accessors

julia> parentmodule(Accessors.constructorof)
ConstructionBase

julia> Accessors.constructorof(::Type{<:Tagged{U}}) where {U} = Tagged{U}

julia> ChuiCore.set(Tagged{:m}(1.0), Lens{:v}(), 2.0)
Tagged{:m}(2.0)
```

Types that overload `getproperty`/`propertynames` must implement
`ConstructionBase.setproperties` for `set` to work, exactly as with Accessors.

## Interop with Accessors

Loading Accessors (done above) activates the extension `ChuiCoreAccessorsExt` (ChuiCore's
ADR-0004 §4). Then:

- `Accessors.set` and `Accessors.modify` accept `ChuiCore.Lens`, `ChuiCore.IndexLens` and
  `ChuiCore.Prism`, and the two lenses work inside Accessors compositions;
- `ChuiCore.set` and `ChuiCore.modify` accept Accessors' `PropertyLens` and `IndexLens` (what
  `@optic _.a` and `@optic _[i]` build), alone or composed with ChuiCore optics.

```jldoctest optics
julia> Accessors.set(p, Lens{:x}(), 7)
Point(7, 2)

julia> ChuiCore.set(p, @optic(_.y), 8)
Point(1, 8)

julia> ChuiCore.modify(x -> x + 1, s, @optic(_.to) ⨟ Lens{:x}())
Segment(Point(0, 0), Point(4, 4))

julia> Accessors.set(Rect(1.0, 2.0), circle, Circle(3.0))   # not a circle: unchanged
Rect(1.0, 2.0)
```

Other Accessors optics (`Elements`, `If`, `Properties`, plain functions such as `first`) are not
accepted by `ChuiCore.set`: use `Accessors.set` for those. A prism cannot sit *inside* an
Accessors composition handed to `Accessors.set`; use `ChuiCore.set` for compositions with prisms.

## Checking the laws: `test_lens_laws` and `test_prism_laws`

A lawful lens satisfies three laws: **get-set** (setting what you got changes nothing),
**set-get** (you get back what you set) and **set-set** (the second set wins). A lawful prism
satisfies **review-preview** and **preview-review**. The kits check them on samples you give:
values for the whole, values for the focus. Their methods exist after `using Test`; each law is
recorded as an inner test set of the caller's test set. In a package's `test/runtests.jl`:

```julia
using Test, ChuiCore
using ChuiCore: Lens

@testset "Point.x lens" begin
    test_lens_laws(Lens{:x}(), [Point(1, 2), Point(-3, 0)], [0, 7, -1])
end
```

prints a summary with one pass per law (`get-set`, `set-get`, `set-set`), and on a failure the
first counterexample. Run here, the summary's timing column would change on every build, so
this page sends it to `devnull`; a failing law still throws.

```jldoctest optics
julia> using Test

julia> redirect_stdout(devnull) do
           @testset "Point.x" begin
               test_lens_laws(Lens{:x}(), [Point(1, 2), Point(-3, 0)], [0, 7, -1])
           end
           @testset "circle prism" begin
               test_prism_laws(circle, shapes, [Circle(2.0), Circle(0.5)])
           end
       end;
```

Include values of the prism's case among the samples for the whole, or `preview-review` has
nothing to check. With Supposition loaded too, the kits also accept Supposition generators (see
the law-kits tutorial).

## What it costs

- **Lenses with the name in the type** (`Lens{:a}()`, `@lens` with literal names): get is one
  field access and set one constructor call, type-stable, 0 bytes. Compositions cost the sum of
  their parts and stay at 0 bytes on immutable structs. About 1.4–3 ns per get or set, nested or
  not (BenchmarkTools medians, Julia 1.10.12 and 1.13.2, Apple silicon, on a loaded machine;
  indicative; evidence `.lanes/evidence/p5-optics-costs-{release,lts}-8fbb53f.txt`). `Lens(:a)` with a runtime
  `Symbol` is type-unstable unless the symbol is a constant.
- **`IndexLens`:** a tuple or named tuple is rebuilt (0 bytes with a constant index); an array or
  dictionary is copied in full, O(length): about 8 KB (1–3 allocations) to set one element of a
  1,000-element `Vector{Int}`. In a loop over a large array, mutate it with `setindex!` instead.
- **Prisms:** one call of `match` (an `isa` test for `Prism(T)`), plus one of `build` to update.
  `set`/`modify` through a prism return a `Union` of the input's type and `build`'s result.
- **Passing a composed optic on:** a composition is a `ComposedFunction`, a `Function`, and
  Julia does not specialize on a `Function` argument that is only passed on. Give your own
  function a type parameter for it (`g(x, o::O) where {O} = ChuiCore.set(x, o, 1)`): without it,
  each call dispatches dynamically (measured 20–40 ns and 2–3 allocations against 2.5 ns and
  0 bytes, on Julia 1.10.12 and 1.13.2).
- **Interop:** the extension's methods forward to the other package's `set`/`modify`; no
  conversion between optic types.

Reference: [`ChuiCore.Lens`](@ref ChuiCore.Lens), [`ChuiCore.IndexLens`](@ref ChuiCore.IndexLens),
[`ChuiCore.@lens`](@ref ChuiCore.@lens), [`ChuiCore.Prism`](@ref ChuiCore.Prism),
[`ChuiCore.set`](@ref ChuiCore.set), [`ChuiCore.modify`](@ref ChuiCore.modify),
[`test_lens_laws`](@ref ChuiCore.test_lens_laws), [`test_prism_laws`](@ref ChuiCore.test_prism_laws).
