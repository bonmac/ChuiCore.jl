# Constructor classes, part 1 (ADR-0001 §3–4): tags, the type → tag mapping, the class styles and
# the dispatching operations. Instances live in `instances.jl` and `owned.jl`.

# ---------------------------------------------------------------------------------------------
# Tags

const _TAG_DOCS = (
    :NoTag => "the fallback tag of [`ChuiCore.constructorclass`](@ref): every class style of it is `Not…`, so operations on an unregistered type throw an `ArgumentError`.",
    :MaybeTag => "Maybe, which is Base's `Some{T}` / `nothing` (ChuiCore defines no `Just`): Functor, Applicative (`pure` = `Some`), Monad, Alternative (`zeroalt` = `nothing`), Traversable.",
    :ArrayTag => "every `Array`, with list semantics: Functor (`map`), Applicative and Monad (all combinations, Haskell list order; results are `Vector`s), Alternative (`vcat`), Foldable, Traversable.",
    :TupleTag => "every `Tuple`: Functor (`map`), Foldable, Traversable; Bifunctor on 2-tuples only.",
    :DictTag => "`Dict` (not every `AbstractDict`): Functor on the values, keys unchanged.",
    :PairTag => "every `Pair`: Bifunctor.",
    :FunctionTag => "every `<:Function`: Profunctor, Category (composition is `⨟`, identity `identity`), Arrow.",
    :IdentityTag => "[`ChuiCore.Identity`](@ref): Functor, Applicative, Monad, Foldable, Traversable.",
    :ZipVectorTag => "[`ChuiCore.ZipVector`](@ref): Functor and the zip Applicative.",
    :PredicateTag => "[`ChuiCore.Predicate`](@ref): Contravariant.",
)

for (T, what) in _TAG_DOCS
    @eval begin
        struct $T end
        @doc $(
            """
                $T()

            Constructor-class tag (ADR-0001 §3) for $what A singleton: dispatch on it costs nothing at
            run time.
            """
        ) $T
    end
end

"""
    constructorclass(::Type{T}) -> tag

The constructor-class tag of the concrete type `T` (ADR-0001 §3): `MaybeTag()` for `Some{T}` and
`Nothing`, `ArrayTag()` for every `Array`, `TupleTag()` for every `Tuple`, `DictTag()` for `Dict`,
`PairTag()` for `Pair`, `FunctionTag()` for every `<:Function`, and the tags of ChuiCore's own
`Identity`, `ZipVector`, `Predicate`. The fallback is `NoTag()`.

Dispatch-only (methods on `Type{…}` returning constants; never `Base.typename`): it folds to a
constant at compile time, so its runtime cost is 0. A downstream package registers its own type with
`ChuiCore.constructorclass(::Type{<:MyType}) = MyTag()` and the class styles of `MyTag`.
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

for C in _CLASSES
    S = Symbol(C, :Style)
    Is = Symbol(:Is, C)
    Not = Symbol(:Not, C)
    @eval begin
        struct $Is end
        struct $Not end
        $S(_) = $Not()
        $S(::Type{T}) where {T} = $S(constructorclass(T))
        @doc $(
            """
                $S(tag) -> $Is() or $Not()
                $S(::Type{T}) = $S(constructorclass(T))

            The $C class trait of a constructor-class tag (ADR-0001 §3). Defaults to `$Not()`
            (including for `NoTag()`); an instance declares `ChuiCore.$S(::MyTag) = ChuiCore.$Is()`.
            Dispatch-only: it folds to a constant, runtime cost 0.
            """
        ) $S
        @doc $("    $Is()\n\nThe value of [`ChuiCore.$S`](@ref) for tags that are instances of $C.") $Is
        @doc $("    $Not()\n\nThe value of [`ChuiCore.$S`](@ref) for tags that are not instances of $C (the default).") $Not
    end
end

# ---------------------------------------------------------------------------------------------
# Errors

@noinline function _notinstance(x, class::Symbol)
    T = typeof(x)
    throw(
        ArgumentError(
            "$T is not a $class: ChuiCore.$(class)Style(ChuiCore.constructorclass($T)) is " *
                "Not$class(). Register the type with ChuiCore.constructorclass and ChuiCore.$(class)Style.",
        ),
    )
end

@noinline function _tagerror(style, tag, class::Symbol, op::Symbol)
    if nameof(typeof(style)) === Symbol(:Not, class)
        throw(ArgumentError("$(repr(tag)) is not a $class tag: ChuiCore.$(class)Style($(repr(tag))) is Not$class()."))
    end
    throw(ArgumentError("$(repr(tag)) is declared Is$class() but defines no method ChuiCore.$op($(repr(tag)), …)."))
end

# ---------------------------------------------------------------------------------------------
# Value operations: dispatch through the trait of the value's tag. Instances add the method with
# the `Is…` style first; the `Not…` method throws an `ArgumentError`.

"""
    fmap(f, x)

Functor map (ADR-0001 §3): applies `f` inside `x`, keeping its shape.
`fmap(f, x) = fmap(FunctorStyle(constructorclass(typeof(x))), f, x)`; instances implement the
3-argument method `fmap(::IsFunctor, f, x::T)`. A type that is not a Functor throws an
`ArgumentError`. Cost: the trait dispatch is free; the instance's own cost (`map` for `Array`,
`Tuple`; one allocation per new `Dict`).
"""
fmap(f, x) = fmap(FunctorStyle(constructorclass(typeof(x))), f, x)
fmap(::NotFunctor, f, x) = _notinstance(x, :Functor)

"""
    ap(ff, fx)

Applicative apply (Haskell `<*>`): applies the functions held by `ff` to the values held by `fx`.
Dispatches on `ff`'s tag: `ap(ApplicativeStyle(constructorclass(typeof(ff))), ff, fx)`. A type
that is not an Applicative throws an `ArgumentError`. Trait dispatch is free; for `Array` the
result allocates one `Vector` of `length(ff) * length(fx)` elements.
"""
ap(ff, fx) = ap(ApplicativeStyle(constructorclass(typeof(ff))), ff, fx)
ap(::NotApplicative, ff, fx) = _notinstance(ff, :Applicative)

"""
    chain(f, m)

Monadic bind (Haskell `>>=`, with the function first so a `do` block works:
`chain(m) do x … end`). `f` maps a plain value to a monadic value of the same class.
Dispatches on `m`'s tag; a type that is not a Monad throws an `ArgumentError`. Trait dispatch is
free; for `Array` the result allocates one `Vector`.
"""
chain(f, m) = chain(MonadStyle(constructorclass(typeof(m))), f, m)
chain(::NotMonad, f, m) = _notinstance(m, :Monad)

"""
    alt(a, b)

The Alternative choice (Haskell `<|>`), a monoid with identity [`zeroalt`](@ref)`(tag)`: for
Maybe the first non-`nothing`, for `Array` `vcat(a, b)`. Dispatches on `a`'s tag; a type that is
not an Alternative throws an `ArgumentError`. Trait dispatch is free.
"""
alt(a, b) = alt(AlternativeStyle(constructorclass(typeof(a))), a, b)
alt(::NotAlternative, a, b) = _notinstance(a, :Alternative)

"""
    contramap(f, p)

Contravariant map: `contramap(f, p)(x) == p(f(x))`. Dispatches on `p`'s tag
([`ChuiCore.Predicate`](@ref) is the built-in instance); a type that is not Contravariant throws
an `ArgumentError`. Cost: one small wrapper, no allocation for isbits closures.
"""
contramap(f, p) = contramap(ContravariantStyle(constructorclass(typeof(p))), f, p)
contramap(::NotContravariant, f, p) = _notinstance(p, :Contravariant)

"""
    bimap(f, g, p)

Bifunctor map: applies `f` to the first component and `g` to the second (`Pair`, 2-`Tuple`).
Dispatches on `p`'s tag; a type that is not a Bifunctor throws an `ArgumentError`, and so does a
`Tuple` whose length is not 2. Cost: one new pair or tuple.
"""
bimap(f, g, p) = bimap(BifunctorStyle(constructorclass(typeof(p))), f, g, p)
bimap(::NotBifunctor, f, g, p) = _notinstance(p, :Bifunctor)

"""
    dimap(f, g, h)

Profunctor map: pre-compose `f` and post-compose `g`, so for functions
`dimap(f, g, h) == f ⨟ h ⨟ g` (`x -> g(h(f(x)))`). Dispatches on `h`'s tag; a type that is not a
Profunctor throws an `ArgumentError`. Cost: one composed callable, no allocation for isbits
closures.
"""
dimap(f, g, h) = dimap(ProfunctorStyle(constructorclass(typeof(h))), f, g, h)
dimap(::NotProfunctor, f, g, h) = _notinstance(h, :Profunctor)

"""
    lmap(f, h)

Profunctor pre-composition: `lmap(f, h) ≡ dimap(f, identity, h)` (for functions `f ⨟ h`).
Instances may override `lmap(::IsProfunctor, f, h::T)`; the default calls `dimap`.
"""
lmap(f, h) = lmap(ProfunctorStyle(constructorclass(typeof(h))), f, h)
lmap(::NotProfunctor, f, h) = _notinstance(h, :Profunctor)
lmap(::IsProfunctor, f, h) = dimap(f, identity, h)

"""
    rmap(g, h)

Profunctor post-composition: `rmap(g, h) ≡ dimap(identity, g, h)` (for functions `h ⨟ g`).
Instances may override `rmap(::IsProfunctor, g, h::T)`; the default calls `dimap`.
"""
rmap(g, h) = rmap(ProfunctorStyle(constructorclass(typeof(h))), g, h)
rmap(::NotProfunctor, g, h) = _notinstance(h, :Profunctor)
rmap(::IsProfunctor, g, h) = dimap(identity, g, h)

"""
    arrfirst(a)

Arrow `first` (Haskell `first`): an arrow on 2-tuples applying `a` to the first component,
`arrfirst(a)((x, c)) == (a(x), c)` for functions. Dispatches on `a`'s tag; a type that is not an
Arrow throws an `ArgumentError`. For functions it returns a small callable `<: Function` (cost:
one wrapper, one tuple per call).
"""
arrfirst(a) = arrfirst(ArrowStyle(constructorclass(typeof(a))), a)
arrfirst(::NotArrow, a) = _notinstance(a, :Arrow)

"""
    arrsecond(a)

Arrow `second`: `arrsecond(a)((c, x)) == (c, a(x))` for functions. The default for an Arrow
instance is `arr(swap) ⨟ arrfirst(a) ⨟ arr(swap)`; functions get a direct callable.
"""
arrsecond(a) = arrsecond(ArrowStyle(constructorclass(typeof(a))), a)
arrsecond(::NotArrow, a) = _notinstance(a, :Arrow)
arrsecond(::IsArrow, a) = (s = arr(constructorclass(typeof(a)), _swap); s ⨟ arrfirst(a) ⨟ s)

"""
    arrsplit(a, b)

Arrow split (Haskell `***`): `arrsplit(a, b)((x, y)) == (a(x), b(y))` for functions. The default
for an Arrow instance is `arrfirst(a) ⨟ arrsecond(b)`. Dispatches on `a`'s tag.
"""
arrsplit(a, b) = arrsplit(ArrowStyle(constructorclass(typeof(a))), a, b)
arrsplit(::NotArrow, a, b) = _notinstance(a, :Arrow)
arrsplit(::IsArrow, a, b) = arrfirst(a) ⨟ arrsecond(b)

"""
    fanout(a, b)

Arrow fanout (Haskell `&&&`): `fanout(a, b)(x) == (a(x), b(x))` for functions. The default for an
Arrow instance is `arr(x -> (x, x)) ⨟ arrsplit(a, b)`. Dispatches on `a`'s tag.
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
infinite repetition of `x`. A tag that is not an Applicative throws an `ArgumentError`. Cost: the
instance's constructor (one 1-element `Vector` for `ArrayTag`).
"""
pure(tag, x) = _tagerror(ApplicativeStyle(tag), tag, :Applicative, :pure)

"""
    zeroalt(tag)

The identity of [`alt`](@ref) for the Alternative class `tag` (Haskell `empty`):
`zeroalt(MaybeTag()) === nothing`, `zeroalt(ArrayTag())` a fresh empty vector of element type
`Union{}` (so `vcat` keeps the other operand's element type). A tag that is not an Alternative
throws an `ArgumentError`.
"""
zeroalt(tag) = _tagerror(AlternativeStyle(tag), tag, :Alternative, :zeroalt)

"""
    idarrow(tag)

The Category identity of `tag` (Haskell `id`): `idarrow(FunctionTag()) === identity`. Category
composition is `⨟`. A tag that is not a Category throws an `ArgumentError`.
"""
idarrow(tag) = _tagerror(CategoryStyle(tag), tag, :Category, :idarrow)

"""
    arr(tag, f)

Lift the plain function `f` into the Arrow class `tag`: `arr(FunctionTag(), f) === f`. A tag that
is not an Arrow throws an `ArgumentError`.
"""
arr(tag, f) = _tagerror(ArrowStyle(tag), tag, :Arrow, :arr)

"""
    traverse(tag, f, xs)

Traversable traverse: map each element of `xs` to an effect `f(x)` of the Applicative class `tag`
and collect the results inside one effect, preserving the shape of `xs`. For example
`traverse(MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, 2]) == Some([1, 2])`. `tag` is the
applicative; the traversable is `xs`'s class, `traverse(TraversableStyle(constructorclass(typeof(xs))),
tag, f, xs)`. Cost: one `ap` per element, each building a new collection (O(n²) copies for
vectors; meant for small containers and for laws, not hot loops).
"""
traverse(tag, f, xs) = traverse(TraversableStyle(constructorclass(typeof(xs))), tag, f, xs)
traverse(::NotTraversable, tag, f, xs) = _notinstance(xs, :Traversable)

"""
    sequence(tag, xs) = traverse(tag, identity, xs)

Turn a traversable of effects of the Applicative class `tag` inside out:
`sequence(MaybeTag(), [Some(1), Some(2)]) == Some([1, 2])`. Cost as [`ChuiCore.traverse`](@ref).
"""
sequence(tag, xs) = traverse(tag, identity, xs)

# Small named helpers, shared by the instances and the law tables.
_swap(p) = (p[2], p[1])
_dup(x) = (x, x)
_fst(p) = p[1]
_assoc(p) = (p[1][1], (p[1][2], p[2]))
