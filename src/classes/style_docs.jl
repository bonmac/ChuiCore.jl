# Docstrings of the constructor-class tags and styles defined in `core.jl` (docstrings only: no
# definitions here). Kept apart so core.jl stays under the ratchet's line limit.

const _TAG_DOCS = (
    # (tag, the classes it is an instance of, an example type `constructorclass` maps to it)
    (:NoTag, "the fallback tag of [`ChuiCore.constructorclass`](@ref): every class style of it is `Not…`, so operations on an unregistered type throw an `ArgumentError`.", "Int"),
    (:MaybeTag, "Maybe, which is Base's `Some{T}` / `nothing` (ChuiCore defines no `Just`): Functor, Applicative (`pure` = `Some`), Monad, Alternative (`zeroalt` = `nothing`), Traversable.", "Nothing"),
    (:ArrayTag, "every `Array`, with list semantics: Functor (`map`), Applicative and Monad (all combinations, Haskell list order; results are `Vector`s), Alternative (`vcat`), Foldable, Traversable.", "Matrix{Float64}"),
    (:TupleTag, "every `Tuple`: Functor (`map`), Foldable, Traversable; Bifunctor on 2-tuples only.", "Tuple{Int, String}"),
    (:DictTag, "`Dict` (not every `AbstractDict`): Functor on the values, keys unchanged.", "Dict{Symbol, Int}"),
    (:PairTag, "every `Pair`: Bifunctor.", "Pair{Int, String}"),
    (:FunctionTag, "every `<:Function`: Profunctor, Category (composition is `⨟`, identity `identity`), Arrow.", "typeof(sin)"),
    (:IdentityTag, "[`ChuiCore.Identity`](@ref): Functor, Applicative, Monad, Foldable, Traversable.", "ChuiCore.Identity{Int}"),
    (:ZipVectorTag, "[`ChuiCore.ZipVector`](@ref): Functor and the zip Applicative.", "ChuiCore.ZipVector{Int}"),
    (:PredicateTag, "[`ChuiCore.Predicate`](@ref): Contravariant.", "ChuiCore.Predicate{typeof(iseven)}"),
)

for (T, what, example) in _TAG_DOCS
    @eval @doc $(
        """
            $T()

        Constructor-class tag (ADR-0001 §3) for $what

        ```jldoctest
        julia> ChuiCore.constructorclass($example)
        ChuiCore.$T()
        ```

        Cost: free; a singleton with no fields, so dispatch on it is resolved at compile time.
        """
    ) $T
end

# For the docstring examples: one built-in instance tag of each class and a type mapping to it.
const _CLASS_EXAMPLES = (
    Functor = ("DictTag", "Dict{Symbol, Int}"),
    Applicative = ("ZipVectorTag", "ChuiCore.ZipVector{Int}"),
    Monad = ("MaybeTag", "Some{Int}"),
    Alternative = ("ArrayTag", "Vector{Int}"),
    Foldable = ("TupleTag", "Tuple{Int, Int}"),
    Traversable = ("IdentityTag", "ChuiCore.Identity{Int}"),
    Contravariant = ("PredicateTag", "ChuiCore.Predicate{typeof(iseven)}"),
    Bifunctor = ("PairTag", "Pair{Int, Int}"),
    Profunctor = ("FunctionTag", "typeof(sin)"),
    Category = ("FunctionTag", "typeof(sin)"),
    Arrow = ("FunctionTag", "typeof(sin)"),
)

for C in _CLASSES
    S = Symbol(C, :Style)
    Is = Symbol(:Is, C)
    Not = Symbol(:Not, C)
    extag, extype = _CLASS_EXAMPLES[C]
    @eval begin
        @doc $(
            """
                $S(tag) -> $Is() or $Not()
                $S(::Type{T}) = $S(constructorclass(T))

            The $C class trait of a constructor-class tag (ADR-0001 §3). Defaults to `$Not()`
            (including for `NoTag()`); an instance declares `ChuiCore.$S(::MyTag) = ChuiCore.$Is()`.

            ```jldoctest
            julia> ChuiCore.$S(ChuiCore.$extag())
            ChuiCore.$Is()

            julia> ChuiCore.$S($extype)
            ChuiCore.$Is()

            julia> ChuiCore.$S(Int)
            ChuiCore.$Not()
            ```

            Cost: free; it is dispatch-only and folds to a constant at compile time.
            """
        ) $S
        @doc $(
            """
                $Is()

            The value of [`ChuiCore.$S`](@ref) for tags that are instances of $C.

            ```jldoctest
            julia> ChuiCore.$S(ChuiCore.$extag()) === ChuiCore.$Is()
            true
            ```

            Cost: free; a singleton, matched by dispatch at compile time.
            """
        ) $Is
        @doc $(
            """
                $Not()

            The value of [`ChuiCore.$S`](@ref) for tags that are not instances of $C (the default).

            ```jldoctest
            julia> ChuiCore.$S(ChuiCore.NoTag())
            ChuiCore.$Not()
            ```

            Cost: free; a singleton, matched by dispatch at compile time.
            """
        ) $Not
    end
end
