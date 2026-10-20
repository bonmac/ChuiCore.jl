# Constructor classes (ADR-0001 §3–4): tags, styles, operations and instances. Unit tests.

@testitem "classes: constructorclass maps types to tags" tags = [:unit] begin
    using ChuiCore: constructorclass, NoTag, MaybeTag, ArrayTag, TupleTag, DictTag, PairTag,
        FunctionTag, IdentityTag, ZipVectorTag, PredicateTag, Identity, ZipVector, Predicate
    @test constructorclass(Some{Int}) === MaybeTag()
    @test constructorclass(Some{Any}) === MaybeTag()
    @test constructorclass(Nothing) === MaybeTag()
    @test constructorclass(Vector{Int}) === ArrayTag()
    @test constructorclass(Matrix{Float64}) === ArrayTag()
    @test constructorclass(Array{String, 3}) === ArrayTag()
    @test constructorclass(Tuple{}) === TupleTag()
    @test constructorclass(Tuple{Int, String}) === TupleTag()
    @test constructorclass(Dict{Symbol, Int}) === DictTag()
    @test constructorclass(Pair{Int, Int}) === PairTag()
    @test constructorclass(typeof(abs)) === FunctionTag()
    @test constructorclass(typeof(x -> x)) === FunctionTag()
    @test constructorclass(typeof(abs ∘ sin)) === FunctionTag()
    @test constructorclass(Identity{Int}) === IdentityTag()
    @test constructorclass(ZipVector{Int}) === ZipVectorTag()
    @test constructorclass(Predicate{typeof(iseven)}) === PredicateTag()
    # Not registered: the fallback.
    @test constructorclass(UnitRange{Int}) === NoTag()
    @test constructorclass(Int) === NoTag()
    @test constructorclass(Base.ImmutableDict{Int, Int}) === NoTag()  # an AbstractDict, not a Dict
    @test constructorclass(Union{Some{Int}, Nothing}) === NoTag()     # not concrete
end

@testitem "classes: styles of every tag" tags = [:unit] begin
    using ChuiCore: constructorclass
    C = ChuiCore
    expected = Dict(
        C.NoTag() => (),
        C.MaybeTag() => (:Functor, :Applicative, :Monad, :Alternative, :Traversable),
        C.ArrayTag() => (:Functor, :Applicative, :Monad, :Alternative, :Foldable, :Traversable),
        C.TupleTag() => (:Functor, :Foldable, :Traversable, :Bifunctor),
        C.DictTag() => (:Functor,),
        C.PairTag() => (:Bifunctor,),
        C.FunctionTag() => (:Profunctor, :Category, :Arrow),
        C.IdentityTag() => (:Functor, :Applicative, :Monad, :Foldable, :Traversable),
        C.ZipVectorTag() => (:Functor, :Applicative),
        C.PredicateTag() => (:Contravariant,),
    )
    classes = (
        :Functor, :Applicative, :Monad, :Alternative, :Foldable, :Traversable,
        :Contravariant, :Bifunctor, :Profunctor, :Category, :Arrow,
    )
    for (tag, yes) in expected, c in classes
        S = getfield(C, Symbol(c, :Style))
        want = getfield(C, Symbol(c in yes ? :Is : :Not, c))()
        @test S(tag) === want
    end
    @test C.FunctorStyle(Vector{Int}) === C.IsFunctor()
    @test C.ArrowStyle(typeof(abs)) === C.IsArrow()
    @test C.MonadStyle(UnitRange{Int}) === C.NotMonad()
end

@testitem "classes: traits are dispatch-only (@inferred, ADR-0001 §4)" tags = [:unit] begin
    using Test: @inferred
    C = ChuiCore
    types = (
        Some{Int}, Nothing, Vector{Int}, Matrix{Float64}, Tuple{Int, Int}, Tuple{}, Dict{Int, Int},
        Pair{Int, Int}, typeof(abs), C.Identity{Int}, C.ZipVector{Int},
        C.Predicate{typeof(iseven)}, UnitRange{Int}, Int, String,
    )
    styles = (
        C.FunctorStyle, C.ApplicativeStyle, C.MonadStyle, C.AlternativeStyle, C.FoldableStyle,
        C.TraversableStyle, C.ContravariantStyle, C.BifunctorStyle, C.ProfunctorStyle,
        C.CategoryStyle, C.ArrowStyle,
    )
    for T in types
        tag = @inferred C.constructorclass(T)
        @test tag isa Union{C.NoTag, C.MaybeTag, C.ArrayTag, C.TupleTag, C.DictTag, C.PairTag, C.FunctionTag, C.IdentityTag, C.ZipVectorTag, C.PredicateTag}
        for S in styles
            @test (@inferred S(T)) === (@inferred S(tag))
        end
    end
end

@testitem "classes: code_typed of a caller holds no trait call (ADR-0001 §4)" tags = [:unit] begin
    # `ChuiCore` is a constant binding here (a global `C = ChuiCore` would not be).
    inc(x) = x + 1
    style_of(x) = ChuiCore.FunctorStyle(ChuiCore.constructorclass(typeof(x)))
    for (f, argtypes) in ((ChuiCore.fmap, Tuple{typeof(inc), Vector{Int}}), (style_of, Tuple{Vector{Int}}))
        ci = only(code_typed(f, argtypes))[1]
        s = sprint(show, ci)
        @test !occursin("constructorclass", s)
        @test !occursin("FunctorStyle", s)
    end
    # The trait folds to the constant style.
    ci = only(code_typed(style_of, Tuple{Vector{Int}}))[1]
    @test length(ci.code) == 1 && ci.code[1] isa Core.ReturnNode
    rv = ci.code[1].val
    @test (rv isa QuoteNode ? rv.value : rv) === ChuiCore.IsFunctor()   # 1.10 wraps it in a QuoteNode
end

@testitem "classes: unregistered types throw ArgumentError" tags = [:unit] begin
    C = ChuiCore
    struct NotAClassUser
        x::Int
    end
    u = NotAClassUser(1)
    for x in (1:3, u)
        @test_throws ArgumentError C.fmap(identity, x)
        err = try
            C.fmap(identity, x)
        catch e
            e
        end
        @test occursin(string(typeof(x)), err.msg) && occursin("Functor", err.msg)
    end
    @test_throws ArgumentError C.ap(1:3, 1:3)
    @test_throws ArgumentError chain(x -> [x], 1:3)
    @test_throws ArgumentError alt(u, u)
    @test_throws ArgumentError contramap(identity, u)
    @test_throws ArgumentError bimap(identity, identity, u)
    @test_throws ArgumentError dimap(identity, identity, u)
    @test_throws ArgumentError lmap(identity, u)
    @test_throws ArgumentError rmap(identity, u)
    @test_throws ArgumentError arrfirst(u)
    @test_throws ArgumentError arrsecond(u)
    @test_throws ArgumentError arrsplit(u, u)
    @test_throws ArgumentError fanout(u, u)
    @test_throws ArgumentError C.traverse(C.MaybeTag(), Some, 1:3)
    @test_throws ArgumentError C.sequence(C.MaybeTag(), u)
    # Tag-first operations on tags that are not instances.
    @test_throws ArgumentError C.pure(C.NoTag(), 1)
    @test_throws ArgumentError C.pure(C.DictTag(), 1)
    @test_throws ArgumentError zeroalt(C.TupleTag())
    @test_throws ArgumentError idarrow(C.MaybeTag())
    @test_throws ArgumentError arr(C.ArrayTag(), identity)
    # Wrong class for an existing instance.
    @test_throws ArgumentError chain(x -> x, (1, 2))
    @test_throws ArgumentError C.fmap(identity, 1 => 2)
    @test_throws ArgumentError bimap(identity, identity, (1, 2, 3))
end

@testitem "classes: Maybe (Some / nothing)" tags = [:unit] begin
    C = ChuiCore
    @test C.fmap(x -> x + 1, Some(1)) == Some(2)
    @test C.fmap(x -> x + 1, nothing) === nothing
    @test C.fmap(identity, Some(nothing)) == Some(nothing)
    @test C.pure(C.MaybeTag(), 3) == Some(3)
    @test C.ap(Some(x -> 2x), Some(4)) == Some(8)
    @test C.ap(Some(x -> 2x), nothing) === nothing
    @test C.ap(nothing, Some(4)) === nothing
    @test chain(x -> x > 0 ? Some(x) : nothing, Some(1)) == Some(1)
    @test chain(x -> x > 0 ? Some(x) : nothing, Some(-1)) === nothing
    @test chain(x -> Some(x), nothing) === nothing
    r = chain(Some(2)) do x
        Some(x + 10)
    end
    @test r == Some(12)
    @test zeroalt(C.MaybeTag()) === nothing
    @test alt(Some(1), Some(2)) == Some(1)
    @test alt(nothing, Some(2)) == Some(2)
    @test alt(nothing, nothing) === nothing
    @test C.traverse(C.ArrayTag(), x -> [x, -x], Some(1)) == [Some(1), Some(-1)]
    @test C.traverse(C.ArrayTag(), x -> [x], nothing) == [nothing]
end

@testitem "classes: Array (list semantics)" tags = [:unit] begin
    C = ChuiCore
    @test C.fmap(x -> x + 1, [1, 2]) == [2, 3]
    @test C.fmap(x -> x + 1, [1 2; 3 4]) == [2 3; 4 5]
    @test C.pure(C.ArrayTag(), 5) == [5]
    @test C.ap([x -> x + 1, x -> 10x], [1, 2]) == [2, 3, 10, 20]   # Haskell list order
    @test C.ap(Function[], [1]) == []
    @test chain(x -> [x, x], [1, 2]) == [1, 1, 2, 2]
    @test chain(x -> Int[], [1, 2]) == []
    @test isempty(zeroalt(C.ArrayTag()))
    @test zeroalt(C.ArrayTag()) !== zeroalt(C.ArrayTag())   # fresh
    @test alt([1], [2, 3]) == [1, 2, 3]
    @test eltype(alt(zeroalt(C.ArrayTag()), [1, 2])) === Int
    @test foldl(+, [1, 2, 3]) == 6                          # Foldable is Base iteration
    @test C.FoldableStyle(Vector{Int}) === C.IsFoldable()
    # `something` unwraps: Julia 1.10 compares `Some` with `===`.
    r = C.traverse(C.MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, 2])
    @test r isa Some && something(r) == [1, 2] && eltype(something(r)) === Int
    @test C.traverse(C.MaybeTag(), x -> x > 0 ? Some(x) : nothing, [1, -2]) === nothing
    @test something(C.traverse(C.MaybeTag(), Some, Int[])) == []
    @test something(C.sequence(C.MaybeTag(), [Some(1), Some(2)])) == [1, 2]
    @test C.sequence(C.ArrayTag(), [[1, 2], [3]]) == [[1, 3], [2, 3]]
    @test something(C.traverse(C.MaybeTag(), Some, [1 2; 3 4])) == [1 2; 3 4]
end

@testitem "classes: Tuple, Dict, Pair" tags = [:unit] begin
    C = ChuiCore
    @test C.fmap(x -> x + 1, (1, 2)) === (2, 3)
    @test C.fmap(string, ()) === ()
    @test foldl(+, (1, 2, 3)) == 6
    @test C.traverse(C.MaybeTag(), Some, (1, "a")) == Some((1, "a"))
    @test C.traverse(C.MaybeTag(), x -> nothing, (1,)) === nothing
    @test C.traverse(C.ArrayTag(), x -> [x, 0], (1, 2)) == [(1, 2), (1, 0), (0, 2), (0, 0)]
    @test bimap(x -> x + 1, string, (1, 2)) === (2, "2")
    @test_throws ArgumentError bimap(identity, identity, (1,))
    d = C.fmap(x -> 2x, Dict(:a => 1, :b => 2))
    @test d == Dict(:a => 2, :b => 4) && d isa Dict{Symbol, Int}
    @test C.fmap(x -> x, Dict{Int, Int}()) == Dict{Int, Int}()
    @test bimap(x -> x + 1, string, 1 => 2) === (2 => "2")
end

@testitem "classes: Function (Profunctor, Category, Arrow)" tags = [:unit] begin
    C = ChuiCore
    inc(x) = x + 1
    dbl(x) = 2x
    @test dimap(inc, dbl, abs)(-5) == dbl(abs(inc(-5)))
    @test lmap(inc, abs)(-5) == abs(inc(-5))
    @test rmap(dbl, abs)(-5) == dbl(abs(-5))
    @test idarrow(C.FunctionTag()) === identity
    @test arr(C.FunctionTag(), inc) === inc
    @test (idarrow(C.FunctionTag()) ⨟ inc)(1) == 2
    f1 = arrfirst(inc)
    @test f1 isa Function && C.constructorclass(typeof(f1)) === C.FunctionTag()
    @test f1((1, "c")) == (2, "c")
    @test arrsecond(inc)(("c", 1)) == ("c", 2)
    @test arrsplit(inc, dbl)((1, 5)) == (2, 10)
    @test fanout(inc, dbl)(3) == (4, 6)
    @test arrfirst(arrfirst(inc))(((1, 2), 3)) == ((2, 2), 3)
end

@testitem "classes: Identity" tags = [:unit] begin
    C = ChuiCore
    I = C.Identity
    @test I(1) == I(1) && isequal(I(1), I(1)) && hash(I(1)) == hash(I(1))
    @test I(1) != I(2) && I([1]) == I([1]) && isequal(I(NaN), I(NaN))
    @test C.fmap(x -> x + 1, I(1)) == I(2)
    @test map(x -> x + 1, I(1)) == I(2)
    @test C.pure(C.IdentityTag(), 3) == I(3)
    @test C.ap(I(x -> 2x), I(4)) == I(8)
    @test chain(x -> I(x + 1), I(1)) == I(2)
    @test collect(I(7)) == [7] && length(I(7)) == 1 && eltype(I{Int}) === Int
    @test foldl(+, I(5); init = 1) == 6
    @test C.traverse(C.MaybeTag(), x -> Some(x + 1), I(1)) == Some(I(2))
    @test C.traverse(C.IdentityTag(), I, [1, 2]) == I([1, 2])
end

@testitem "classes: ZipVector (zip Applicative)" tags = [:unit] begin
    C = ChuiCore
    Z = C.ZipVector
    @test Z([1, 2]) == Z([1, 2]) && isequal(Z([1, 2]), Z(1:2)) && hash(Z([1])) == hash(Z([1]))
    @test Z([1]) != C.pure(C.ZipVectorTag(), 1)
    @test C.fmap(x -> x + 1, Z([1, 2])) == Z([2, 3])
    @test C.fmap(x -> x + 1, C.pure(C.ZipVectorTag(), 1)) == C.pure(C.ZipVectorTag(), 2)
    @test C.ap(Z([x -> x + 1, x -> 10x]), Z([1, 2, 3])) == Z([2, 20])   # zips, shorter wins
    @test C.ap(C.pure(C.ZipVectorTag(), x -> -x), Z([1, 2])) == Z([-1, -2])
    @test C.ap(Z([x -> x + 1, x -> 10x]), C.pure(C.ZipVectorTag(), 3)) == Z([4, 30])
    @test C.ap(C.pure(C.ZipVectorTag(), x -> -x), C.pure(C.ZipVectorTag(), 3)) == C.pure(C.ZipVectorTag(), -3)
    @test sprint(show, Z([1, 2])) == "ChuiCore.ZipVector([1, 2])"
    @test sprint(show, C.pure(C.ZipVectorTag(), 1)) == "ChuiCore.pure(ChuiCore.ZipVectorTag(), 1)"
end

@testitem "classes: Predicate (Contravariant)" tags = [:unit] begin
    C = ChuiCore
    P = C.Predicate
    p = P(iseven)
    @test p(2) && !p(3)
    @test_throws TypeError P(x -> x)(1)
    @test P(iseven) == P(iseven) && isequal(P(iseven), P(iseven)) && hash(P(iseven)) == hash(P(iseven))
    q = contramap(x -> x + 1, p)
    @test q isa P && q(1) && !q(2)
end

@testitem "classes: a downstream instance" tags = [:unit, :laws] begin
    using Test
    struct DownBox{T}
        x::T
    end
    struct DownBoxTag end
    Base.isequal(a::DownBox, b::DownBox) = isequal(a.x, b.x)
    ChuiCore.constructorclass(::Type{<:DownBox}) = DownBoxTag()
    ChuiCore.FunctorStyle(::DownBoxTag) = ChuiCore.IsFunctor()
    ChuiCore.fmap(::ChuiCore.IsFunctor, f, b::DownBox) = DownBox(f(b.x))
    @test isequal(ChuiCore.fmap(x -> x + 1, DownBox(1)), DownBox(2))
    @test_throws ArgumentError chain(x -> DownBox(x), DownBox(1))
    test_functor_laws(DownBoxTag(), [DownBox(1), DownBox(-2)], [x -> x + 1, abs])
end
