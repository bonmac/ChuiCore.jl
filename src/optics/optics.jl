# Optics (ADR-0004, ADR-0008): property and index lenses, prisms for closed sum types, `set` and
# `modify` with Accessors' argument order, composition through Base's `ComposedFunction`, and the
# law tables of `test_lens_laws` / `test_prism_laws`. Struct rebuilding goes through
# ConstructionBase's `setproperties` (the hook Accessors uses), never through a rule of our own.

"""
    Lens{L}()
    Lens(L::Symbol)
    Lens(Val(L))

A lens focusing the **property** `L` of a value: getting is calling the lens,
`Lens{:a}()(x) == x.a` (`getproperty`); [`ChuiCore.set`](@ref) and [`ChuiCore.modify`](@ref)
rebuild the value through `ConstructionBase.setproperties` (ADR-0008), exactly like Accessors'
`PropertyLens`. Works on structs and `NamedTuple`s; the input is never mutated.

Compose lenses with Base's `∘` (`Lens{:x}() ∘ Lens{:a}()` focuses `x.a.x`) or `⨟`, or build them
with [`ChuiCore.@lens`](@ref).

Rebuilding uses ConstructionBase's `constructorof(T)`, which defaults to `Base.typename(T).wrapper`.
Types with a non-default inner constructor or a phantom type parameter need their owner to define
`ConstructionBase.constructorof` (otherwise `set` throws a `MethodError`); types that overload
`propertynames`/`getproperty` must implement `ConstructionBase.setproperties` for `set` to work,
as with Accessors.

**Cost:** with the property name in the type (`Lens{:a}()`, `Lens(Val(:a))`, a literal in
`@lens`), get is one field access and set is one constructor call: type-stable, 0 bytes, no
dynamic dispatch (about 2 ns either way, BenchmarkTools median on Julia 1.13.2, Apple silicon,
2026-10-20; indicative). `Lens(:a)` with a runtime `Symbol` is type-unstable unless the compiler
constant-folds the symbol; it is not the default form.

```jldoctest
julia> using ChuiCore: Lens

julia> struct Point; x::Int; y::Int; end

julia> p = Point(1, 2);

julia> Lens{:x}()(p)
1

julia> ChuiCore.set(p, Lens{:x}(), 10)
Point(10, 2)

julia> ChuiCore.modify(v -> v + 1, (a = 1, b = 2), Lens(:b))
(a = 1, b = 3)

julia> p                                  # never mutated
Point(1, 2)
```
"""
struct Lens{L}
    function Lens{L}() where {L}
        L isa Symbol || throw(ArgumentError("Lens{L}: the property name L must be a Symbol, got $(repr(L))"))
        return new{L}()
    end
end
Lens(name::Symbol) = Lens{name}()
Lens(::Val{L}) where {L} = Lens{L}()

(::Lens{L})(x) where {L} = getproperty(x, L)

"""
    IndexLens(i...)

A lens focusing the element `x[i...]`: getting is calling the lens (`getindex`). Setting builds a
new value and never mutates the input:

- `Tuple`: a new tuple (the index must be an integer in bounds);
- `NamedTuple`: a new named tuple, the index an integer position or a `Symbol` name;
- `AbstractArray`: a **copy** with the element replaced (`similar` + `copyto!`), widening the
  element type with `promote_type` when the new value does not fit;
- `AbstractDict`: a `copy` with the entry replaced; the value type is **not** widened, so a value
  that does not convert throws (`set(Dict(:a => 1), IndexLens(:a), 1.5)` is an `InexactError`).

`IndexLens((1, 2))` focuses the element at the index `(1, 2)` (one tuple-valued index);
`IndexLens(1, 2)` focuses `x[1, 2]`.

**Cost:** get is one `getindex`. Set on a `Tuple` or `NamedTuple` rebuilds it (0 bytes when the
index is a constant); on an array or dictionary it allocates a full copy, O(length) (for a
1,000-element `Vector{Int}`: 3 allocations, 8,256 bytes on Julia 1.13.2).

```jldoctest
julia> using ChuiCore: IndexLens

julia> IndexLens(2)((10, 20, 30))
20

julia> ChuiCore.set((10, 20, 30), IndexLens(2), 99)
(10, 99, 30)

julia> v = [1, 2, 3];

julia> ChuiCore.set(v, IndexLens(1), 0.5)   # a widened copy
3-element Vector{Float64}:
 0.5
 2.0
 3.0

julia> v
3-element Vector{Int64}:
 1
 2
 3

julia> ChuiCore.set((a = 1, b = 2), IndexLens(:b), 5)
(a = 1, b = 5)
```
"""
struct IndexLens{I <: Tuple}
    indices::I
    IndexLens{I}(indices::I) where {I <: Tuple} = new{I}(indices)
end
IndexLens(indices...) = IndexLens{typeof(indices)}(indices)

(l::IndexLens)(x) = x[l.indices...]

"""
    Prism(match, build)
    Prism(T::Type)

A prism focuses one case of a sum: [`ChuiCore.preview`](@ref)`(p, x)` is `match(x)`, which must
return `Some(v)` when `x` is that case and `nothing` otherwise; [`ChuiCore.review`](@ref)`(p, v)` is
`build(v)`, which builds the sum value back from the focus.

`Prism(T)` is the **variant prism** of the variant `T` of a closed sum type (ADR-0002: a `Union`
alias of plain structs): `preview(p, x)` is `Some(x)` exactly when `x isa T`, and `review(p, v)`
returns `v` itself (an `ArgumentError` when `v` is not a `T`).

Prisms are not callable: getting through a prism is `preview`. [`ChuiCore.set`](@ref) and
[`ChuiCore.modify`](@ref) change the focus when `preview` matches and return `x` unchanged
otherwise. A prism composes with lenses through `∘`/`⨟` for `set`/`modify`.

**Cost:** one call of `match` (plus one of `build` for `set`/`modify`); a variant prism's match
is one `isa` test, type-stable, 0 bytes. `set`/`modify` return a `Union` of the input's type and
`build`'s result type.

```jldoctest
julia> using ChuiCore: Prism, preview, review

julia> struct Circle; r::Float64; end

julia> struct Square; side::Float64; end

julia> const Shape = Union{Circle, Square};

julia> pc = Prism(Circle);

julia> preview(pc, Circle(1.0))
Some(Circle(1.0))

julia> preview(pc, Square(2.0)) === nothing
true

julia> ChuiCore.modify(c -> Circle(2c.r), Square(2.0), pc)   # not the case: unchanged
Square(2.0)

julia> pos = Prism(x -> x > 0 ? Some(x) : nothing, identity);   # a hand-written prism

julia> preview(pos, -3) === nothing
true
```
"""
struct Prism{M, B}
    match::M
    build::B
end

struct _VariantMatch{T} end
(::_VariantMatch{T})(x) where {T} = x isa T ? Some(x) : nothing
struct _VariantBuild{T} end
(::_VariantBuild{T})(v::T) where {T} = v
(::_VariantBuild{T})(v) where {T} = throw(ArgumentError("review: $(repr(v)) is not a $T"))

Prism(::Type{T}) where {T} = Prism(_VariantMatch{T}(), _VariantBuild{T}())

"""
    preview(p::Prism, x)

`Some(v)` with the focus `v` when `x` is the prism's case, else `nothing`.

**Cost:** one call of the prism's `match` (for a variant prism, one `isa` test, 0 bytes).

```jldoctest
julia> using ChuiCore: Prism, preview

julia> preview(Prism(Int), 3)
Some(3)

julia> preview(Prism(Int), "three") === nothing
true
```
"""
preview(p::Prism, x) = p.match(x)

"""
    review(p::Prism, v)

Build the sum value of the prism's case from the focus `v`.

**Cost:** one call of the prism's `build` (for a variant prism, the identity after a type check).

```jldoctest
julia> using ChuiCore: Prism, review

julia> review(Prism(Int), 3)
3

julia> review(Prism(x -> x > 0 ? Some(x) : nothing, abs), -4)   # `build` is `abs`
4

julia> review(Prism(Int), 1.5)
ERROR: ArgumentError: review: 1.5 is not a Int64
[...]
```
"""
review(p::Prism, v) = p.build(v)

"""
    ChuiCore.set(x, optic, v)

A copy of `x` with the focus of `optic` replaced by `v` (Accessors' argument order). `optic` is a
[`ChuiCore.Lens`](@ref), an [`ChuiCore.IndexLens`](@ref), a [`ChuiCore.Prism`](@ref) (no change when
`x` is not the prism's case), or a `ComposedFunction` of those (`l₂ ∘ l₁`, `l₁ ⨟ l₂`). With
Accessors loaded, also Accessors' `PropertyLens` and `IndexLens` (`ChuiCoreAccessorsExt`).

Public, never exported (ADR-0004): a bare `set` would clash with Accessors' export.

**Cost:** see the optic; for a composition, the costs of its parts (0 bytes for type-parameterised
lenses on immutable structs). A composed optic is a `ComposedFunction`, a `Function`: a function
of yours that only passes it on is not specialized on it unless the argument has a type parameter
(`g(x, o::O) where {O} = set(x, o, 1)`); without one, each call dispatches dynamically and
allocates (measured on Julia 1.10.12 and 1.13.2: for `@lens _.a.x` on a nested struct, through a
`@noinline` function, 2–3 allocations and about 18–20 ns without the type parameter, 0 bytes and
about 2.5 ns with it; BenchmarkTools medians, Apple silicon, 2026-10-20).

```jldoctest
julia> using ChuiCore: Lens, IndexLens, @lens

julia> x = (a = (b = 1, c = 2), d = [1, 2]);

julia> ChuiCore.set(x, @lens(_.a.b), 10)
(a = (b = 10, c = 2), d = [1, 2])

julia> ChuiCore.set(x, Lens{:d}() ⨟ IndexLens(2), 20)   # `⨟`: outer focus first
(a = (b = 1, c = 2), d = [1, 20])
```
"""
set(x, l::Lens{L}, v) where {L} = setproperties(x, NamedTuple{(L,)}((v,)))
set(x, l::IndexLens, v) = _setindex(x, v, l.indices...)
function set(x, p::Prism, v)
    preview(p, x) === nothing && return x
    return review(p, v)
end
# `where {O, I}` forces specialization: `ComposedFunction <: Function`, and Julia does not
# specialize a method on a `Function` argument that the body only passes on (Julia performance
# tips, "Be aware of when Julia avoids specializing").
set(x, o::ComposedFunction{O, I}, v) where {O, I} = modify(y -> set(y, o.outer, v), x, o.inner)

"""
    ChuiCore.modify(f, x, optic)

A copy of `x` with the focus `a` of `optic` replaced by `f(a)` (Accessors' argument order). Optics
as for [`ChuiCore.set`](@ref). For a prism, `f` is applied when `preview` matches; otherwise `x` is
returned unchanged. For a composition `o = outer ∘ inner`:
`modify(f, x, o) == modify(y -> modify(f, y, outer), x, inner)`.

Getting through a composition by calling it works only when every part is callable (lenses); a
composition containing a prism is used with `set`/`modify` only.

Public, never exported (ADR-0004).

**Cost:** one get, one call of `f`, one set (per part, for a composition).

```jldoctest
julia> using ChuiCore: Lens, IndexLens, Prism

julia> ChuiCore.modify(x -> 10x, (a = 1, b = 2), Lens{:b}())
(a = 1, b = 20)

julia> ChuiCore.modify(uppercase, ("x", "y"), IndexLens(1))
("X", "y")

julia> ChuiCore.modify(x -> x + 1, 1.5, Prism(Int))   # not an Int: unchanged
1.5
```
"""
modify(f::F, x, l::Union{Lens, IndexLens}) where {F} = set(x, l, f(l(x)))
function modify(f::F, x, p::Prism) where {F}
    m = preview(p, x)
    m === nothing && return x
    return review(p, f(m.value))
end
function modify(f::F, x, o::ComposedFunction{O, I}) where {F, O, I}
    return modify(y -> modify(f, y, o.outer), x, o.inner)
end

# --- index setting (never mutates the input) ------------------------------------------------------

function _setindex(t::NTuple{N, Any}, v, i::Integer) where {N}
    1 <= i <= N || throw(BoundsError(t, i))
    return ntuple(j -> j == i ? v : t[j], Val(N))
end
_setindex(nt::NamedTuple{K}, v, i::Integer) where {K} = NamedTuple{K}(_setindex(Tuple(nt), v, i))
function _setindex(nt::NamedTuple{K}, v, k::Symbol) where {K}
    i = findfirst(==(k), K)
    i === nothing && throw(BoundsError(nt, k))
    return _setindex(nt, v, i)
end
function _setindex(a::AbstractArray, v, i...)
    b = similar(a, promote_type(eltype(a), typeof(v)))
    copyto!(b, a)
    b[i...] = v
    return b
end
function _setindex(d::AbstractDict, v, k)
    e = copy(d)
    e[k] = v
    return e
end

# --- @lens -----------------------------------------------------------------------------------------

"""
    @lens _.a.b[i]

Build the composed optic of a chain of property accesses `_.name` and indexings `_[i, …]` on the
placeholder `_`: `@lens _.a.b[2]` is `IndexLens(2) ∘ (Lens{:b}() ∘ Lens{:a}())` (the same optic
as the left-nested `IndexLens(2) ∘ Lens{:b}() ∘ Lens{:a}()`, though not `==` to it). Property names
become type parameters (`Lens{:a}()`); index expressions are evaluated where the macro is used
(literals or variables; `end` and `begin` are not supported).

**Cost:** none at run time beyond building the lenses (the result is the same value as writing
the composition by hand); the expansion happens at macro-expansion time.

```jldoctest
julia> using ChuiCore: Lens, IndexLens, @lens

julia> o = @lens _.a.b[2];

julia> o == IndexLens(2) ∘ (Lens{:b}() ∘ Lens{:a}())   # nested to the right
true

julia> o((a = (b = (10, 20),),))
20

julia> ChuiCore.set((a = (b = (10, 20),),), o, 99)
(a = (b = (10, 99),),)
```
"""
macro lens(ex)
    steps = _lens_steps(ex)
    isempty(steps) && throw(ArgumentError("@lens: expected at least one step after `_`, got `$ex`"))
    acc = steps[1]
    for s in steps[2:end]
        acc = :($(Base.:∘)($s, $acc))
    end
    return acc
end

# Steps of a `@lens` chain, innermost (applied first) first.
function _lens_steps(ex)
    ex === :_ && return Any[]
    if Meta.isexpr(ex, :., 2) && ex.args[2] isa QuoteNode && ex.args[2].value isa Symbol
        return push!(_lens_steps(ex.args[1]), :($Lens{$(QuoteNode(ex.args[2].value))}()))
    elseif Meta.isexpr(ex, :ref) && length(ex.args) >= 2
        idx = ex.args[2:end]
        any(i -> i === :end || i === :begin || _has_end(i), idx) &&
            throw(ArgumentError("@lens: `end`/`begin` indices are not supported in `$ex`"))
        return push!(_lens_steps(ex.args[1]), :($IndexLens($(map(esc, idx)...))))
    end
    throw(ArgumentError("@lens: expected a chain of `_.name` and `_[i]` steps on `_`, got `$ex`"))
end
_has_end(ex::Expr) = any(a -> a === :end || a === :begin || _has_end(a), ex.args)
_has_end(_) = false

# --- law tables (ADR-0004 §2, ADR-0007) -----------------------------------------------------------

# test_lens_laws(lens, gen_s, gen_v)
function _lens_laws(lens, eq)
    return (
        Law("get-set", (1,), s -> eq(set(s, lens, lens(s)), s)),
        Law("set-get", (1, 2), (s, v) -> eq(lens(set(s, lens, v)), v)),
        Law("set-set", (1, 2, 2), (s, v1, v2) -> eq(set(set(s, lens, v1), lens, v2), set(s, lens, v2))),
    )
end

# test_prism_laws(prism, gen_s, gen_v)
function _prism_laws(prism, eq)
    return (
        # `eq` compares foci, never `Some` wrappers, so a user `eq` such as `≈` works (review N4).
        Law(
            "review-preview", (2,), function (v)
                m = preview(prism, review(prism, v))
                return m !== nothing && eq(m.value, v)
            end
        ),
        Law(
            "preview-review", (1,), function (s)
                m = preview(prism, s)
                return m === nothing || eq(review(prism, m.value), s)
            end
        ),
    )
end
