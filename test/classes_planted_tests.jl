# Planted violations (ADR-0007 §5): for every law of every class kit, an unlawful instance that
# breaks that law, run in a capturing test set under both drivers (sample collections and
# Supposition). Each test asserts the exact set of failing law names. Each defective instance is
# a type parameterised by the name of its defect `K`, with its own tag `…Tag{K}`.

@testmodule Planted begin
    using ChuiCore
    using ChuiCore: IsFunctor, IsApplicative, IsMonad, IsAlternative, IsFoldable, IsTraversable,
        IsContravariant, IsBifunctor, IsProfunctor, IsCategory, IsArrow
    import ChuiCore: constructorclass, fmap, ap, pure, chain, alt, zeroalt, traverse, contramap,
        bimap, dimap, lmap, rmap, idarrow, arr, arrfirst
    using Supposition: Data

    # A magma with two-sided identity 0 that is not associative: (1∘1)∘2 = 4, 1∘(1∘2) = 2.
    magma(a, b) = a + b + a * b * (a - b)

    """
        both(captured, kit, tag, samples, gens...) -> ((failing, ran), (failing, ran))

    Run `kit` on `tag` inside `LawCapture.captured`, first with sample collections, then with
    `Data.SampledFrom(samples)` as the first generator (the Supposition driver).
    """
    function both(captured, kit, tag, samples, gens...)
        r1 = captured(() -> kit(tag, samples, gens...))
        r2 = captured(() -> kit(tag, Data.SampledFrom(samples), gens...; max_examples = 60))
        return r1, r2
    end

    # --- Functor: Box{K}(xs) -----------------------------------------------------------------------
    struct BoxTag{K} end
    struct Box{K}
        xs::Vector{Any}
    end
    Base.isequal(a::Box{K}, b::Box{K}) where {K} = isequal(a.xs, b.xs)
    constructorclass(::Type{Box{K}}) where {K} = BoxTag{K}()
    ChuiCore.FunctorStyle(::BoxTag) = IsFunctor()
    fmap(::IsFunctor, f, b::Box{:identity}) = Box{:identity}(Any[])          # drops every element
    fmap(::IsFunctor, f, b::Box{:composition}) = Box{:composition}(map(f ∘ f, b.xs))  # applies f twice
    boxes(K) = [Box{K}(Any[1, 2]), Box{K}(Any[-3])]

    # --- Applicative: W{K}(v, log, ispure) ----------------------------------------------------------
    struct WTag{K} end
    struct W{K}
        v::Any
        log::Int
        ispure::Bool
    end
    W{K}(v, log) where {K} = W{K}(v, log, false)
    Base.isequal(a::W{K}, b::W{K}) where {K} = isequal(a.v, b.v) && a.log == b.log  # ignores ispure
    constructorclass(::Type{W{K}}) where {K} = WTag{K}()
    ChuiCore.FunctorStyle(::WTag) = IsFunctor()
    ChuiCore.ApplicativeStyle(::WTag) = IsApplicative()
    pure(::WTag{K}, x) where {K} = W{K}(x, 0, true)
    fmap(::IsFunctor, f, w::W{K}) where {K} = W{K}(f(w.v), w.log)
    fmap(::IsFunctor, f, w::W{:fmap}) = W{:fmap}(f(w.v), w.log + 1)          # fmap changes the log
    ap(::IsApplicative, wf::W{K}, wx::W{K}) where {K} = W{K}(wf.v(wx.v), wf.log + wx.log)
    function ap(::IsApplicative, wf::W{:identity}, wx::W{:identity})        # wrong for pure(identity)
        wf.v === identity && return W{:identity}(wx.v, wx.log + 1)
        return W{:identity}(wf.v(wx.v), wf.log + wx.log)
    end
    function ap(::IsApplicative, wf::W{:composition}, wx::W{:composition})  # non-associative log
        return W{:composition}(wf.v(wx.v), magma(wf.log, wx.log))
    end
    function ap(::IsApplicative, wf::W{:homomorphism}, wx::W{:homomorphism})  # wrong on two pures
        wf.ispure && wx.ispure && return W{:homomorphism}(wf.v(wx.v) + 1, 0)
        return W{:homomorphism}(wf.v(wx.v), wf.log + wx.log)
    end
    function ap(::IsApplicative, wf::W{:interchange}, wx::W{:interchange})  # wrong on effect <*> pure
        !wf.ispure && wx.ispure && return W{:interchange}(wf.v(wx.v) + 1, wf.log)
        return W{:interchange}(wf.v(wx.v), wf.log + wx.log)
    end
    ws(K) = [W{K}(1, 1), W{K}(2, 2), W{K}(-1, 3)]

    # --- Monad: Mo{K}(v, log, ispure) ---------------------------------------------------------------
    struct MoTag{K} end
    struct Mo{K}
        v::Any
        log::Int
        ispure::Bool
    end
    Mo{K}(v, log) where {K} = Mo{K}(v, log, false)
    Base.isequal(a::Mo{K}, b::Mo{K}) where {K} = isequal(a.v, b.v) && a.log == b.log
    constructorclass(::Type{Mo{K}}) where {K} = MoTag{K}()
    ChuiCore.FunctorStyle(::MoTag) = IsFunctor()
    ChuiCore.ApplicativeStyle(::MoTag) = IsApplicative()
    ChuiCore.MonadStyle(::MoTag) = IsMonad()
    pure(::MoTag{K}, x) where {K} = Mo{K}(x, 0, true)
    fmap(::IsFunctor, f, m::Mo{K}) where {K} = Mo{K}(f(m.v), m.log)
    ap(::IsApplicative, mf::Mo{K}, mx::Mo{K}) where {K} = Mo{K}(mf.v(mx.v), mf.log + mx.log)
    ap(::IsApplicative, mf::Mo{:ap}, mx::Mo{:ap}) = Mo{:ap}(mf.v(mx.v), mf.log + mx.log + 1)  # disagrees
    function chain(::IsMonad, k, m::Mo{K}) where {K}
        r = k(m.v)
        return Mo{K}(r.v, m.log + r.log)
    end
    function chain(::IsMonad, k, m::Mo{:left})        # wrong when binding a pure value
        r = k(m.v)
        return Mo{:left}(r.v, m.log + r.log + (m.ispure ? 1 : 0))
    end
    function chain(::IsMonad, k, m::Mo{:right})       # wrong when the continuation returns pure
        r = k(m.v)
        return Mo{:right}(r.v, m.log + r.log + (r.ispure ? 1 : 0))
    end
    # For :right, `ap` is derived from `chain` so that "ap agrees with chain" holds.
    function ap(::IsApplicative, mf::Mo{:right}, mx::Mo{:right})
        return chain(f -> chain(x -> pure(MoTag{:right}(), f(x)), mx), mf)
    end
    function chain(::IsMonad, k, m::Mo{:assoc})       # non-associative log
        r = k(m.v)
        return Mo{:assoc}(r.v, magma(m.log, r.log))
    end
    ap(::IsApplicative, mf::Mo{:assoc}, mx::Mo{:assoc}) = Mo{:assoc}(mf.v(mx.v), magma(mf.log, mx.log))
    mos(K) = [Mo{K}(1, 1), Mo{K}(2, 2), Mo{K}(-1, 3)]
    moks(K) = [x -> Mo{K}(x + 1, 1), x -> Mo{K}(2x, 2)]

    # --- Alternative: Al{K}(n) ----------------------------------------------------------------------
    struct AlTag{K} end
    struct Al{K}
        n::Int
    end
    constructorclass(::Type{Al{K}}) where {K} = AlTag{K}()
    ChuiCore.AlternativeStyle(::AlTag) = IsAlternative()
    zeroalt(::AlTag{K}) where {K} = Al{K}(0)
    alt(::IsAlternative, a::Al{:left}, b::Al{:left}) = Al{:left}(a.n == 0 ? b.n + 1 : a.n + b.n)
    alt(::IsAlternative, a::Al{:right}, b::Al{:right}) = Al{:right}(b.n == 0 ? a.n + 1 : a.n + b.n)
    alt(::IsAlternative, a::Al{:assoc}, b::Al{:assoc}) = Al{:assoc}(magma(a.n, b.n))
    als(K) = [Al{K}(1), Al{K}(2), Al{K}(5)]   # positive: sums never reach the identity

    # --- Foldable: Fo{K}(xs), iterating forward; one Base fold overridden to run backward -----------
    struct FoTag{K} end
    struct Fo{K}
        xs::Vector{Int}
    end
    constructorclass(::Type{Fo{K}}) where {K} = FoTag{K}()
    ChuiCore.FoldableStyle(::FoTag) = IsFoldable()
    Base.iterate(f::Fo, i = 1) = i > length(f.xs) ? nothing : (f.xs[i], i + 1)
    Base.length(f::Fo) = length(f.xs)
    Base.mapfoldr(g, op, f::Fo; kw...) = mapfoldr(g, op, f.xs; kw...)   # lawful default foldr
    # :foldl reverses all three folds, so they agree with one another but not with iteration.
    Base.foldl(op, f::Fo{:foldl}; kw...) = foldl(op, reverse(f.xs); kw...)
    Base.foldr(op, f::Fo{:foldl}; kw...) = foldr(op, reverse(f.xs); kw...)
    Base.mapreduce(g, op, f::Fo{:foldl}; kw...) = mapreduce(g, op, reverse(f.xs); kw...)
    Base.foldr(op, f::Fo{:foldr}; kw...) = foldr(op, reverse(f.xs); kw...)
    Base.mapreduce(g, op, f::Fo{:mapreduce}; kw...) = mapreduce(g, op, reverse(f.xs); kw...)
    fos(K) = [Fo{K}([1, 2, 3]), Fo{K}([4, 5])]

    # --- Traversable: Tr{K}(a, b), wrong (swapped) for one applicative ---------------------------------
    struct TrTag{K} end
    struct Tr{K}
        a::Any
        b::Any
    end
    Base.isequal(x::Tr{K}, y::Tr{K}) where {K} = isequal(x.a, y.a) && isequal(x.b, y.b)
    constructorclass(::Type{Tr{K}}) where {K} = TrTag{K}()
    ChuiCore.TraversableStyle(::TrTag) = IsTraversable()
    _tr(t::Tr{K}, tag, f) where {K} = ap(fmap(x -> (y -> Tr{K}(x, y)), f(t.a)), f(t.b))
    _swapped(t::Tr{K}, tag, f) where {K} = fmap(r -> Tr{K}(r.b, r.a), _tr(t, tag, f))
    traverse(::IsTraversable, tag, f, t::Tr) = _tr(t, tag, f)
    traverse(::IsTraversable, tag::ChuiCore.IdentityTag, f, t::Tr{:identity}) = _swapped(t, tag, f)
    traverse(::IsTraversable, tag::ChuiCore.ArrayTag, f, t::Tr{:naturality}) = _swapped(t, tag, f)
    traverse(::IsTraversable, tag::ChuiCore.ComposeTag, f, t::Tr{:composition}) = _swapped(t, tag, f)
    trs(K) = [Tr{K}(1, 2), Tr{K}(3, -4)]
    trfs = [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing, x -> Some(2x)]

    # --- Contravariant: Pr{K}(f) --------------------------------------------------------------------
    struct PrTag{K} end
    struct Pr{K}
        f::Any
    end
    (p::Pr)(x) = p.f(x)
    constructorclass(::Type{Pr{K}}) where {K} = PrTag{K}()
    ChuiCore.ContravariantStyle(::PrTag) = IsContravariant()
    contramap(::IsContravariant, g, p::Pr{K}) where {K} = Pr{K}(x -> p.f(g(x)))
    contramap(::IsContravariant, ::typeof(identity), p::Pr{:identity}) = Pr{:identity}(x -> !p.f(x))
    contramap(::IsContravariant, g::ComposedFunction, p::Pr{:composition}) = Pr{:composition}(x -> !p.f(g(x)))
    prs(K) = [Pr{K}(iseven), Pr{K}(x -> x > 0)]

    # --- Bifunctor: BP{K}(a, b) ---------------------------------------------------------------------
    struct BPTag{K} end
    struct BP{K}
        a::Any
        b::Any
    end
    Base.isequal(x::BP{K}, y::BP{K}) where {K} = isequal(x.a, y.a) && isequal(x.b, y.b)
    constructorclass(::Type{BP{K}}) where {K} = BPTag{K}()
    ChuiCore.BifunctorStyle(::BPTag) = IsBifunctor()
    bimap(::IsBifunctor, f, g, p::BP{:identity}) = BP{:identity}(0, 0)                    # constant
    bimap(::IsBifunctor, f, g, p::BP{:composition}) = BP{:composition}(f(f(p.a)), g(g(p.b)))  # twice
    bps(K) = [BP{K}(1, 2), BP{K}(-3, 5)]

    # --- Profunctor: PF{K}(f) -----------------------------------------------------------------------
    struct PFTag{K} end
    struct PF{K}
        f::Any
    end
    (p::PF)(x) = p.f(x)
    constructorclass(::Type{PF{K}}) where {K} = PFTag{K}()
    ChuiCore.ProfunctorStyle(::PFTag) = IsProfunctor()
    dimap(::IsProfunctor, f, g, p::PF{K}) where {K} = PF{K}(x -> g(p.f(f(x))))
    lmap(::IsProfunctor, f, p::PF{K}) where {K} = PF{K}(x -> p.f(f(x)))
    rmap(::IsProfunctor, g, p::PF{K}) where {K} = PF{K}(x -> g(p.f(x)))
    dimap(::IsProfunctor, ::typeof(identity), ::typeof(identity), p::PF{:identity}) = PF{:identity}(x -> p.f(x) + 1)
    dimap(::IsProfunctor, f::ComposedFunction, g, p::PF{:composition}) = PF{:composition}(x -> g(p.f(f(x))) + 1)
    lmap(::IsProfunctor, f, p::PF{:agrees}) = PF{:agrees}(x -> p.f(f(x)) + 1)
    pfs(K) = [PF{K}(x -> x + 1), PF{K}(abs)]

    # --- Category: Ca{K}(f, n, isid), composed with Base.∘ (so with ⨟) -------------------------------
    struct CaTag{K} end
    struct Ca{K}
        f::Any
        n::Int
        isid::Bool
    end
    Ca{K}(f) where {K} = Ca{K}(f, 0, false)
    (a::Ca)(x) = a.f(x)
    ChuiCore.CategoryStyle(::CaTag) = IsCategory()
    idarrow(::CaTag{K}) where {K} = Ca{K}(identity, 0, true)
    # `a ⨟ b == b ∘ a`: in `∘(g, f)`, `f` runs first.
    Base.:∘(g::Ca{:left}, f::Ca{:left}) = Ca{:left}(x -> g.f(f.f(x)) + (f.isid ? 1 : 0))
    Base.:∘(g::Ca{:right}, f::Ca{:right}) = Ca{:right}(x -> g.f(f.f(x)) + (g.isid ? 1 : 0))
    Base.:∘(g::Ca{:assoc}, f::Ca{:assoc}) = Ca{:assoc}(x -> g.f(f.f(x)) + f.n, f.n + g.n + 1, false)
    cas(K) = [Ca{K}(x -> x + 1), Ca{K}(x -> 2x), Ca{K}(abs)]

    # --- Arrow: Ar{K}(f, kind) with kind ∈ (:plain, :pure, :composite) -------------------------------
    struct ArTag{K} end
    struct Ar{K}
        f::Any
        kind::Symbol
    end
    (a::Ar)(x) = a.f(x)
    constructorclass(::Type{Ar{K}}) where {K} = ArTag{K}()
    ChuiCore.CategoryStyle(::ArTag) = IsCategory()
    ChuiCore.ArrowStyle(::ArTag) = IsArrow()
    idarrow(::ArTag{K}) where {K} = Ar{K}(identity, :plain)
    Base.:∘(g::Ar{K}, f::Ar{K}) where {K} = Ar{K}(x -> g.f(f.f(x)), :composite)
    arr(::ArTag{K}, f) where {K} = Ar{K}(f, :pure)
    function arrfirst(::IsArrow, a::Ar{K}) where {K}
        bad = (K === :firstarr && a.kind === :pure) || (K === :firstcomp && a.kind === :composite)
        return Ar{K}(p -> (bad ? a.f(p[1]) + 1 : a.f(p[1]), p[2]), :plain)
    end
    arr(::ArTag{:arrid}, ::typeof(identity)) = Ar{:arrid}(x -> x + 1, :pure)
    arr(::ArTag{:arrcomp}, f::ComposedFunction) = Ar{:arrcomp}(x -> f(x) + 1, :pure)
    arr(::ArTag{:firstfst}, ::typeof(ChuiCore._fst)) = Ar{:firstfst}(p -> p[1] + 1, :pure)
    arr(::ArTag{:firstsecond}, s::ChuiCore._SecondOf) = Ar{:firstsecond}(p -> (p[1] + 1, s.g(p[2])), :pure)
    arr(::ArTag{:firstassoc}, ::typeof(ChuiCore._assoc)) = Ar{:firstassoc}(p -> (p[1][1] + 1, (p[1][2], p[2])), :pure)
    ars(K) = [Ar{K}(x -> 2x, :plain), Ar{K}(x -> x - 1, :plain), Ar{K}(abs, :plain)]

    const FS = [x -> x + 1, x -> 2x, x -> x - 3]   # never `identity` or a composition
    const XS = [-2, 1, 3]
end

@testitem "planted: Functor" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    all_laws = Set(["identity", "composition"])
    for law in ("identity", "composition")
        K = Symbol(law)
        for (failing, ran) in P.both(LawCapture.captured, test_functor_laws, P.BoxTag{K}(), P.boxes(K), P.FS)
            @test failing == Set([law])
            @test ran == all_laws
        end
    end
end

@testitem "planted: Applicative" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("identity", "composition", "homomorphism", "interchange", "fmap agrees with ap")
    defect = Dict(
        "identity" => :identity, "composition" => :composition, "homomorphism" => :homomorphism,
        "interchange" => :interchange, "fmap agrees with ap" => :fmap,
    )
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_applicative_laws, P.WTag{K}(), P.ws(K), P.FS, P.XS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Monad" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("left identity", "right identity", "associativity", "ap agrees with chain")
    defect = Dict(
        "left identity" => :left, "right identity" => :right, "associativity" => :assoc,
        "ap agrees with chain" => :ap,
    )
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_monad_laws, P.MoTag{K}(), P.mos(K), P.moks(K), P.XS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Alternative" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("left identity", "right identity", "associativity")
    defect = Dict("left identity" => :left, "right identity" => :right, "associativity" => :assoc)
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_alternative_laws, P.AlTag{K}(), P.als(K))
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Foldable" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("foldl matches iteration", "foldr matches foldl", "mapreduce matches foldl")
    defect = Dict(
        "foldl matches iteration" => :foldl, "foldr matches foldl" => :foldr,
        "mapreduce matches foldl" => :mapreduce,
    )
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_foldable_laws, P.FoTag{K}(), P.fos(K))
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Traversable" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("identity", "naturality", "composition")
    for law in laws
        K = Symbol(law)
        for (failing, ran) in P.both(LawCapture.captured, test_traversable_laws, P.TrTag{K}(), P.trs(K), P.trfs)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Contravariant" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("identity", "composition")
    for law in laws
        K = Symbol(law)
        for (failing, ran) in P.both(LawCapture.captured, test_contravariant_laws, P.PrTag{K}(), P.prs(K), P.FS, P.XS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Bifunctor" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("identity", "composition")
    for law in laws
        K = Symbol(law)
        for (failing, ran) in P.both(LawCapture.captured, test_bifunctor_laws, P.BPTag{K}(), P.bps(K), P.FS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Profunctor" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("identity", "composition", "dimap agrees with lmap and rmap")
    defect = Dict("identity" => :identity, "composition" => :composition, "dimap agrees with lmap and rmap" => :agrees)
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_profunctor_laws, P.PFTag{K}(), P.pfs(K), P.FS, P.XS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Category" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    laws = ("left identity", "right identity", "associativity")
    defect = Dict("left identity" => :left, "right identity" => :right, "associativity" => :assoc)
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_category_laws, P.CaTag{K}(), P.cas(K), P.XS)
            @test failing == Set([law])
            @test ran == Set(laws)
        end
    end
end

@testitem "planted: Arrow" tags = [:laws] setup = [LawCapture, Planted] begin
    using Test, Supposition
    P = Planted
    category = ("left identity", "right identity", "associativity")
    laws = (
        "arr identity", "arr composition", "first of arr", "first of composition",
        "first then fst", "first commutes with second", "first associates",
    )
    defect = Dict(
        "arr identity" => :arrid, "arr composition" => :arrcomp, "first of arr" => :firstarr,
        "first of composition" => :firstcomp, "first then fst" => :firstfst,
        "first commutes with second" => :firstsecond, "first associates" => :firstassoc,
    )
    for law in laws
        K = defect[law]
        for (failing, ran) in P.both(LawCapture.captured, test_arrow_laws, P.ArTag{K}(), P.ars(K), P.FS, P.XS)
            @test failing == Set([law])
            @test ran == Set((category..., laws...))
        end
    end
end
