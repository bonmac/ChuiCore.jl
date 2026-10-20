# Constructor classes, part 1 (ADR-0001 §3–4): tags, the type → tag mapping, the class styles and
# the dispatching operations. Instances live in `instances.jl` and `owned.jl`.

# ---------------------------------------------------------------------------------------------
# Tags

# The tags; their docstrings (and examples) are in `style_docs.jl`.
for T in (
        :NoTag, :MaybeTag, :ArrayTag, :TupleTag, :DictTag, :PairTag, :FunctionTag, :IdentityTag,
        :ZipVectorTag, :PredicateTag,
    )
    @eval struct $T end
end

"""
    constructorclass(::Type{T}) -> tag

The constructor-class tag of the concrete type `T` (ADR-0001 §3): `MaybeTag()` for `Some{T}` and
`Nothing`, `ArrayTag()` for every `Array`, `TupleTag()` for every `Tuple`, `DictTag()` for `Dict`,
`PairTag()` for `Pair`, `FunctionTag()` for every `<:Function`, and the tags of ChuiCore's own
`Identity`, `ZipVector`, `Predicate`. The fallback is `NoTag()`.

A downstream package registers its own type with
`ChuiCore.constructorclass(::Type{<:MyType}) = MyTag()` and the class styles of `MyTag`
(tutorial: [Typeclasses and your own instance](@ref)).

```jldoctest
julia> ChuiCore.constructorclass(Vector{Int})
ChuiCore.ArrayTag()

julia> ChuiCore.constructorclass(typeof(Some(1)))
ChuiCore.MaybeTag()

julia> ChuiCore.constructorclass(Int)
ChuiCore.NoTag()
```

Cost: free. It is dispatch-only (methods on `Type{…}` returning constants; never
`Base.typename`), so it folds to a constant at compile time.
"""
constructorclass(::Type) = NoTag()
constructorclass(::Type{<:Some}) = MaybeTag()
constructorclass(::Type{Nothing}) = MaybeTag()
constructorclass(::Type{<:Array}) = ArrayTag()
constructorclass(::Type{<:Tuple}) = TupleTag()
constructorclass(::Type{<:Dict}) = DictTag()
constructorclass(::Type{<:Pair}) = PairTag()
constructorclass(::Type{<:Function}) = FunctionTag()

# ---------------------------------------------------------------------------------------------
# Styles: one Holy trait per class, defined on tags.

const _CLASSES = (
    :Functor, :Applicative, :Monad, :Alternative, :Foldable, :Traversable,
    :Contravariant, :Bifunctor, :Profunctor, :Category, :Arrow,
)

# The styles; their docstrings are in `style_docs.jl`.
for C in _CLASSES
    S = Symbol(C, :Style)
    Is = Symbol(:Is, C)
    Not = Symbol(:Not, C)
    @eval begin
        struct $Is end
        struct $Not end
        $S(_) = $Not()
        $S(::Type{T}) where {T} = $S(constructorclass(T))
    end
end

# ---------------------------------------------------------------------------------------------
# Errors

# "an Applicative", "a Functor": the indefinite article for a class name in error messages.
_article(class::Symbol) = first(string(class)) in "AEIOU" ? "an" : "a"

@noinline function _notinstance(x, class::Symbol)
    T = typeof(x)
    throw(
        ArgumentError(
            "$T is not $(_article(class)) $class: ChuiCore.$(class)Style(ChuiCore.constructorclass($T)) is " *
                "Not$class(). Register the type with ChuiCore.constructorclass and ChuiCore.$(class)Style.",
        ),
    )
end

@noinline function _tagerror(style, tag, class::Symbol, op::Symbol)
    if nameof(typeof(style)) === Symbol(:Not, class)
        throw(ArgumentError("$(repr(tag)) is not $(_article(class)) $class tag: ChuiCore.$(class)Style($(repr(tag))) is Not$class()."))
    end
    throw(ArgumentError("$(repr(tag)) is declared Is$class() but defines no method ChuiCore.$op($(repr(tag)), …)."))
end

@noinline function _mismatch(op::Symbol, a, b)
    A, B = typeof(a), typeof(b)
    throw(
        ArgumentError(
            "ChuiCore.$op has no instance method for a $A with a $B (tags " *
                "$(repr(constructorclass(A))) and $(repr(constructorclass(B)))): both operands must " *
                "belong to the same constructor class.",
        ),
    )
end

# ---------------------------------------------------------------------------------------------
# Value operations: dispatch through the trait of the value's tag. Instances add the method with
# the `Is…` style first; the `Not…` method throws an `ArgumentError`.

"""
    fmap(f, x)

Functor map (ADR-0001 §3): applies `f` inside `x`, keeping its shape.
`fmap(f, x) = fmap(FunctorStyle(constructorclass(typeof(x))), f, x)`; instances implement the
3-argument method `fmap(::IsFunctor, f, x::T)`. A type that is not a Functor throws an
`ArgumentError`. Pure when `f` is: it only calls `f`.

```jldoctest
julia> ChuiCore.fmap(x -> x + 1, [1, 2, 3])
3-element Vector{Int64}:
 2
 3
 4

julia> ChuiCore.fmap(x -> x + 1, Some(1))
Some(2)

julia> ChuiCore.fmap(x -> x + 1, nothing) === nothing
true

julia> ChuiCore.fmap(string, (1, 2))
("1", "2")

julia> ChuiCore.fmap(x -> 2x, Dict(:a => 1))
Dict{Symbol, Int64} with 1 entry:
  :a => 2

julia> ChuiCore.fmap(identity, :a)
ERROR: ArgumentError: Symbol is not a Functor: ChuiCore.FunctorStyle(ChuiCore.constructorclass(Symbol)) is NotFunctor(). Register the type with ChuiCore.constructorclass and ChuiCore.FunctorStyle.
```

Cost: the trait dispatch is free (resolved at compile time). Then the instance's own work: `map`
for `Array` (one new `Array`) and `Tuple` (no heap allocation for isbits elements); a new `Some` or
[`ChuiCore.Identity`](@ref) (no heap allocation for an isbits value); for `Dict` a new `Dict` built
from a generator, without a size hint.
"""
fmap(f, x) = fmap(FunctorStyle(constructorclass(typeof(x))), f, x)
fmap(::NotFunctor, f, x) = _notinstance(x, :Functor)

"""
    ap(ff, fx)

Applicative apply (Haskell `<*>`): applies the functions held by `ff` to the values held by `fx`.
Dispatches on `ff`'s tag: `ap(ApplicativeStyle(constructorclass(typeof(ff))), ff, fx)`. A type
that is not an Applicative throws an `ArgumentError`, and so do operands of two different classes
(`ap([f], Some(1))`). Instance methods **must type the style argument**,
`ap(::IsApplicative, ff::T, fx::T)`: one written `ap(_, ff::T, fx::T)` is ambiguous with that
mismatch fallback `ap(::IsApplicative, ff, fx)`. Pure when the held functions are.

```jldoctest
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

julia> ChuiCore.ap([identity], Some(1))
ERROR: ArgumentError: ChuiCore.ap has no instance method for a Vector{typeof(identity)} with a Some{Int64} (tags ChuiCore.ArrayTag() and ChuiCore.MaybeTag()): both operands must belong to the same constructor class.
```

Cost: trait dispatch is free. Maybe and [`ChuiCore.Identity`](@ref): one new box, no heap
allocation for isbits values. `Array`: one new `Vector` of `length(ff) * length(fx)` elements,
built by a nested comprehension (its length is not known up front, so it grows as it fills; a
`Vector{Function}` of differently typed closures adds a dynamic call per element).
"""
ap(ff, fx) = ap(ApplicativeStyle(constructorclass(typeof(ff))), ff, fx)
ap(::NotApplicative, ff, fx) = _notinstance(ff, :Applicative)
# Both operands' instance methods are typed, so any other pairing (two different classes) lands
# here instead of in a `MethodError` (phase-2 review nit N5).
ap(::IsApplicative, ff, fx) = _mismatch(:ap, ff, fx)

"""
    chain(f, m)

Monadic bind (Haskell `>>=`, with the function first so a `do` block works:
`chain(m) do x … end`). `f` maps a plain value to a monadic value of the same class.
Dispatches on `m`'s tag; a type that is not a Monad throws an `ArgumentError`. Pure when `f` is.

```jldoctest
julia> chain(x -> x > 0 ? Some(sqrt(x)) : nothing, Some(4.0))
Some(2.0)

julia> chain(x -> x > 0 ? Some(sqrt(x)) : nothing, Some(-4.0)) === nothing
true

julia> chain(x -> [x, -x], [1, 2])
4-element Vector{Int64}:
  1
 -1
  2
 -2

julia> chain(Some(3)) do x
           Some(x + 1)
       end
Some(4)
```

Cost: trait dispatch is free. Maybe and [`ChuiCore.Identity`](@ref) only call `f`. `Array`: one
new `Vector` built by a nested comprehension (grown as it fills), plus whatever `f` allocates.
"""
chain(f, m) = chain(MonadStyle(constructorclass(typeof(m))), f, m)
chain(::NotMonad, f, m) = _notinstance(m, :Monad)

"""
    alt(a, b)

The Alternative choice (Haskell `<|>`), a monoid with identity [`zeroalt`](@ref)`(tag)`: for
Maybe the first non-`nothing`, for `Array` `vcat(a, b)`. Dispatches on `a`'s tag; a type that is
not an Alternative throws an `ArgumentError`, and so do operands of two different classes
(`alt([1], Some(1))`). Instance methods must type the style argument,
`alt(::IsAlternative, a::T, b::T)`: an untyped style is ambiguous with the mismatch fallback
`alt(::IsAlternative, a, b)`.

```jldoctest
julia> alt(nothing, Some(2))
Some(2)

julia> alt(Some(1), Some(2))
Some(1)

julia> alt([1], [2, 3])
3-element Vector{Int64}:
 1
 2
 3
```

Cost: trait dispatch is free. Maybe returns one of its operands (no allocation); `Array` allocates
one new `Vector` of `length(a) + length(b)` elements (`vcat`).
"""
alt(a, b) = alt(AlternativeStyle(constructorclass(typeof(a))), a, b)
alt(::NotAlternative, a, b) = _notinstance(a, :Alternative)
alt(::IsAlternative, a, b) = _mismatch(:alt, a, b)

"""
    contramap(f, p)

Contravariant map: `contramap(f, p)(x) == p(f(x))`. Dispatches on `p`'s tag
([`ChuiCore.Predicate`](@ref) is the built-in instance); a type that is not Contravariant throws
an `ArgumentError`.

```jldoctest
julia> isshort = contramap(length, ChuiCore.Predicate(<(4)));

julia> isshort("abc")
true

julia> isshort("abcdef")
false
```

Cost: one new `Predicate` around the composition `f ⨟ p.f`; no heap allocation when `f` and the
wrapped function are isbits (e.g. top-level functions, closures without mutable captures).
"""
contramap(f, p) = contramap(ContravariantStyle(constructorclass(typeof(p))), f, p)
contramap(::NotContravariant, f, p) = _notinstance(p, :Contravariant)

"""
    bimap(f, g, p)

Bifunctor map: applies `f` to the first component and `g` to the second (`Pair`, 2-`Tuple`).
Dispatches on `p`'s tag; a type that is not a Bifunctor throws an `ArgumentError`, and so does a
`Tuple` whose length is not 2. Pure when `f` and `g` are.

```jldoctest
julia> bimap(uppercase, x -> x + 1, "a" => 1)
"A" => 2

julia> bimap(string, float, (1, 2))
("1", 2.0)

julia> bimap(identity, identity, (1, 2, 3))
ERROR: ArgumentError: bimap needs a 2-tuple, got a tuple of length 3
```

Cost: one new `Pair` or 2-tuple; no heap allocation when both components are isbits.
"""
bimap(f, g, p) = bimap(BifunctorStyle(constructorclass(typeof(p))), f, g, p)
bimap(::NotBifunctor, f, g, p) = _notinstance(p, :Bifunctor)

"""
    dimap(f, g, h)

Profunctor map: pre-compose `f` and post-compose `g`, so for functions
`dimap(f, g, h) == f ⨟ h ⨟ g` (`x -> g(h(f(x)))`). Dispatches on `h`'s tag; a type that is not a
Profunctor throws an `ArgumentError`.

```jldoctest
julia> h = dimap(x -> x + 1, string, x -> 2x);

julia> h(3)
"8"
```

Cost: one composed callable (`ComposedFunction`), no heap allocation when the three functions are
isbits; calling it costs the three calls.
"""
dimap(f, g, h) = dimap(ProfunctorStyle(constructorclass(typeof(h))), f, g, h)
dimap(::NotProfunctor, f, g, h) = _notinstance(h, :Profunctor)

"""
    lmap(f, h)

Profunctor pre-composition: `lmap(f, h) ≡ dimap(f, identity, h)` (for functions `f ⨟ h`).
Instances may override `lmap(::IsProfunctor, f, h::T)`; the default calls `dimap`.

```jldoctest
julia> lmap(x -> x + 1, x -> 2x)(3)
8
```

Cost: as [`dimap`](@ref): for functions one composed callable, no heap allocation when both are
isbits.
"""
lmap(f, h) = lmap(ProfunctorStyle(constructorclass(typeof(h))), f, h)
lmap(::NotProfunctor, f, h) = _notinstance(h, :Profunctor)
lmap(::IsProfunctor, f, h) = dimap(f, identity, h)

"""
    rmap(g, h)

Profunctor post-composition: `rmap(g, h) ≡ dimap(identity, g, h)` (for functions `h ⨟ g`).
Instances may override `rmap(::IsProfunctor, g, h::T)`; the default calls `dimap`.

```jldoctest
julia> rmap(string, x -> 2x)(3)
"6"
```

Cost: as [`dimap`](@ref): for functions one composed callable, no heap allocation when both are
isbits.
"""
rmap(g, h) = rmap(ProfunctorStyle(constructorclass(typeof(h))), g, h)
rmap(::NotProfunctor, g, h) = _notinstance(h, :Profunctor)
rmap(::IsProfunctor, g, h) = dimap(identity, g, h)

"""
    arrfirst(a)

Arrow `first` (Haskell `first`): an arrow on 2-tuples applying `a` to the first component,
`arrfirst(a)((x, c)) == (a(x), c)` for functions. Dispatches on `a`'s tag; a type that is not an
Arrow throws an `ArgumentError`.

```jldoctest
julia> arrfirst(x -> x + 1)((1, "a"))
(2, "a")
```

Cost: for functions, one small immutable callable `<: Function` (no heap allocation when `a` is
isbits); each call builds one 2-tuple, not heap-allocated for isbits components.
"""
arrfirst(a) = arrfirst(ArrowStyle(constructorclass(typeof(a))), a)
arrfirst(::NotArrow, a) = _notinstance(a, :Arrow)

"""
    arrsecond(a)

Arrow `second`: `arrsecond(a)((c, x)) == (c, a(x))` for functions. The default for an Arrow
instance is `arr(swap) ⨟ arrfirst(a) ⨟ arr(swap)`; functions get a direct callable.

```jldoctest
julia> arrsecond(x -> x + 1)(("a", 1))
("a", 2)
```

Cost: for functions as [`arrfirst`](@ref); the default for other Arrow instances composes three
arrows.
"""
arrsecond(a) = arrsecond(ArrowStyle(constructorclass(typeof(a))), a)
arrsecond(::NotArrow, a) = _notinstance(a, :Arrow)
arrsecond(::IsArrow, a) = (s = arr(constructorclass(typeof(a)), _swap); s ⨟ arrfirst(a) ⨟ s)

"""
    arrsplit(a, b)

Arrow split (Haskell `***`): `arrsplit(a, b)((x, y)) == (a(x), b(y))` for functions. The default
for an Arrow instance is `arrfirst(a) ⨟ arrsecond(b)`. Dispatches on `a`'s tag.

```jldoctest
julia> arrsplit(x -> x + 1, string)((1, 2))
(2, "2")
```

Cost: for functions one small immutable callable (no heap allocation when `a` and `b` are isbits);
each call builds one 2-tuple.
"""
arrsplit(a, b) = arrsplit(ArrowStyle(constructorclass(typeof(a))), a, b)
arrsplit(::NotArrow, a, b) = _notinstance(a, :Arrow)
arrsplit(::IsArrow, a, b) = arrfirst(a) ⨟ arrsecond(b)

"""
    fanout(a, b)

Arrow fanout (Haskell `&&&`): `fanout(a, b)(x) == (a(x), b(x))` for functions. The default for an
Arrow instance is `arr(x -> (x, x)) ⨟ arrsplit(a, b)`. Dispatches on `a`'s tag.

```jldoctest
julia> fanout(x -> x + 1, string)(1)
(2, "1")
```

Cost: for functions one small immutable callable (no heap allocation when `a` and `b` are isbits);
each call builds one 2-tuple.
"""
fanout(a, b) = fanout(ArrowStyle(constructorclass(typeof(a))), a, b)
fanout(::NotArrow, a, b) = _notinstance(a, :Arrow)
fanout(::IsArrow, a, b) = arr(constructorclass(typeof(a)), _dup) ⨟ arrsplit(a, b)

# ---------------------------------------------------------------------------------------------
# Tag-first operations (no value to dispatch on). Instances add `pure(::MyTag, x)` etc.; the
# fallbacks below throw an `ArgumentError`.

"""
    pure(tag, x)

The Applicative unit of the class `tag`: `pure(MaybeTag(), x) == Some(x)`,
`pure(ArrayTag(), x) == [x]`, `pure(IdentityTag(), x) == Identity(x)`; for `ZipVectorTag()` an
infinite repetition of `x`. A tag that is not an Applicative throws an `ArgumentError`.

```jldoctest
julia> ChuiCore.pure(ChuiCore.MaybeTag(), 1)
Some(1)

julia> ChuiCore.pure(ChuiCore.ArrayTag(), 1)
1-element Vector{Int64}:
 1

julia> ChuiCore.pure(ChuiCore.IdentityTag(), 1) == ChuiCore.Identity(1)
true

julia> ChuiCore.pure(ChuiCore.PairTag(), 1)
ERROR: ArgumentError: ChuiCore.PairTag() is not an Applicative tag: ChuiCore.ApplicativeStyle(ChuiCore.PairTag()) is NotApplicative().
```

Cost: the instance's constructor: no heap allocation for `Some` and `Identity` of an isbits
value; one 1-element `Vector` for `ArrayTag` and for `ZipVectorTag`.
"""
pure(tag, x) = _tagerror(ApplicativeStyle(tag), tag, :Applicative, :pure)

"""
    zeroalt(tag)

The identity of [`alt`](@ref) for the Alternative class `tag` (Haskell `empty`):
`zeroalt(MaybeTag()) === nothing`, `zeroalt(ArrayTag())` a fresh empty vector of element type
`Union{}` (so `vcat` keeps the other operand's element type). A tag that is not an Alternative
throws an `ArgumentError`.

```jldoctest
julia> zeroalt(ChuiCore.MaybeTag()) === nothing
true

julia> alt(zeroalt(ChuiCore.ArrayTag()), [1, 2])
2-element Vector{Int64}:
 1
 2
```

Cost: free for `MaybeTag`; one new empty `Vector` for `ArrayTag` (fresh on every call).
"""
zeroalt(tag) = _tagerror(AlternativeStyle(tag), tag, :Alternative, :zeroalt)

"""
    idarrow(tag)

The Category identity of `tag` (Haskell `id`): `idarrow(FunctionTag()) === identity`. Category
composition is `⨟`. A tag that is not a Category throws an `ArgumentError`.

```jldoctest
julia> idarrow(ChuiCore.FunctionTag()) === identity
true

julia> (idarrow(ChuiCore.FunctionTag()) ⨟ string)(1)
"1"
```

Cost: free; it returns a constant.
"""
idarrow(tag) = _tagerror(CategoryStyle(tag), tag, :Category, :idarrow)

"""
    arr(tag, f)

Lift the plain function `f` into the Arrow class `tag`: `arr(FunctionTag(), f) === f`. A tag that
is not an Arrow throws an `ArgumentError`.

```jldoctest
julia> arr(ChuiCore.FunctionTag(), sin) === sin
true
```

Cost: free for `FunctionTag` (it returns `f`); otherwise the instance's constructor.
"""
arr(tag, f) = _tagerror(ArrowStyle(tag), tag, :Arrow, :arr)

"""
    traverse(tag, f, xs)

Traversable traverse: map each element of `xs` to an effect `f(x)` of the Applicative class `tag`
and collect the results inside one effect, preserving the shape of `xs`. For example
`traverse(MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, 2]) == Some([1, 2])`. `tag` is the
applicative; the traversable is `xs`'s class, `traverse(TraversableStyle(constructorclass(typeof(xs))),
tag, f, xs)`. Pure when `f` is: it calls `f` once per element, in order.

```jldoctest
julia> ChuiCore.traverse(ChuiCore.MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, 2])
Some([1, 2])

julia> ChuiCore.traverse(ChuiCore.MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, -2]) === nothing
true

julia> ChuiCore.traverse(ChuiCore.MaybeTag(), x -> Some(2x), (1, 2))
Some((2, 4))
```

Cost: one `fmap` and one `ap` per element, each building a new collection: O(n²) element copies
for vectors (the accumulator is re-concatenated at every step). Meant for small containers and for
laws, not hot loops.
"""
traverse(tag, f, xs) = traverse(TraversableStyle(constructorclass(typeof(xs))), tag, f, xs)
traverse(::NotTraversable, tag, f, xs) = _notinstance(xs, :Traversable)

"""
    sequence(tag, xs) = traverse(tag, identity, xs)

Turn a traversable of effects of the Applicative class `tag` inside out:
`sequence(MaybeTag(), [Some(1), Some(2)]) == Some([1, 2])`.

```jldoctest
julia> ChuiCore.sequence(ChuiCore.MaybeTag(), [Some(1), Some(2)])
Some([1, 2])

julia> ChuiCore.sequence(ChuiCore.MaybeTag(), [Some(1), nothing]) === nothing
true

julia> ChuiCore.sequence(ChuiCore.ArrayTag(), ([1, 2], [3]))
2-element Vector{Tuple{Int64, Int64}}:
 (1, 3)
 (2, 3)
```

Cost: as [`ChuiCore.traverse`](@ref) (O(n²) element copies for vectors).
"""
sequence(tag, xs) = traverse(tag, identity, xs)

# Small named helpers, shared by the instances and the law tables.
_swap(p) = (p[2], p[1])
_dup(x) = (x, x)
_fst(p) = p[1]
_assoc(p) = (p[1][1], (p[1][2], p[2]))
