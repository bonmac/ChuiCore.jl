# Laws of the recursion schemes (research Recommendations 1–2, R6): cata identity (Lambek), cata
# fusion, para's original, hylo = cata ∘ ana; and the Functor laws of the test base functors the
# schemes rely on.

@testitem "scheme laws: cata(Fix, x) == x" tags = [:laws] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: TREES, fromlist, nat
    C = ChuiCore
    for t in TREES
        @test C.cata(C.Fix, t) == t
    end
    for v in ([1, 2, 3], Int[], collect(1:20))
        @test C.cata(C.Fix, fromlist(v)) == fromlist(v)
    end
    @test C.cata(C.Fix, nat(5)) == nat(5)
    # The own-type form: embed = identity.
    @test all(t -> C.cata(identity, C.cata(C.project, t)) == C.cata(C.project, t), TREES)
end

@testitem "scheme laws: cata fusion" tags = [:laws] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: TREES, LitF, AddF, MulF, evalalg
    C = ChuiCore
    # h ∘ alg1 == alg2 ∘ fmap(h) on every layer  ⟹  h ∘ cata(alg1) == cata(alg2).
    # Pair 1: h doubles; alg2 doubles literals and adds, and on MulF halves one doubled factor.
    h1(x) = 2x
    alg2(x::LitF) = 2x.v
    alg2(x::AddF) = x.l + x.r
    alg2(x::MulF) = div(x.l * x.r, 2)
    # Pair 2: h = parity; alg2 computes in Z/2.
    h2(x) = mod(x, 2)
    par(x::LitF) = mod(x.v, 2)
    par(x::AddF) = mod(x.l + x.r, 2)
    par(x::MulF) = mod(x.l * x.r, 2)
    for (h, a2) in ((h1, alg2), (h2, par))
        # Premise on sample layers.
        for l in (LitF(-3), LitF(4), AddF(2, 5), MulF(-2, 7), AddF(0, 0), MulF(3, 3))
            @test h(evalalg(l)) == a2(C.fmap(h, l))
        end
        for t in TREES
            @test h(C.cata(evalalg, t)) == C.cata(a2, t)
        end
    end
end

@testitem "scheme laws: para's original is the input" tags = [:laws] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: TREES, LitF, AddF, MulF, evalalg
    C = ChuiCore
    # Each pair's original is a child of the input (===) and its result is cata of that child.
    ok = Ref(true)
    function check(layer)
        layer isa LitF && return layer.v
        for (orig, res) in (layer.l, layer.r)
            ok[] &= orig isa C.Fix && res == C.cata(evalalg, orig)
        end
        return evalalg(C.fmap(last, layer))
    end
    for t in TREES
        @test C.para(check, t) == C.cata(evalalg, t)
    end
    @test ok[]
    for t in TREES
        t.unfix isa LitF && continue
        @test C.para(l -> l, t).l[1] === t.unfix.l
    end
end

@testitem "scheme laws: hylo == cata ∘ ana" tags = [:laws] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: LitF, AddF, MulF, NilF, ConsF, evalalg, listalg
    C = ChuiCore
    treecoalg(n) = n < 2 ? LitF(n + 1) : (iseven(n) ? AddF(n - 1, n - 2) : MulF(n ÷ 2, n - 2))
    for n in 0:14
        @test C.hylo(evalalg, treecoalg, n) == C.cata(evalalg, C.ana(treecoalg, n))
        @test C.hylo(evalalg, treecoalg, n) == C.cata(evalalg, C.ana(treecoalg, n; embed = identity))
    end
    rangecoalg(n) = n == 0 ? NilF() : ConsF(n, n - 1)
    for n in (0, 1, 10, 100)
        @test C.hylo(listalg, rangecoalg, n) == C.cata(listalg, C.ana(rangecoalg, n))
    end
end

@testitem "scheme laws: Functor laws of the test base functors" tags = [:laws] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: LitF, AddF, MulF, NilF, ConsF, ExprTag, ListTag
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(ExprTag(), [LitF(1), AddF(1, -2), MulF(3, 4)], fs)
    test_functor_laws(ListTag(), [NilF(), ConsF(1, -5)], fs)
    gf = [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing]
    test_traversable_laws(ExprTag(), [LitF(1), AddF(1, -2), MulF(3, 4)], gf)
    test_traversable_laws(ListTag(), [NilF(), ConsF(1, -5), ConsF(2, 3)], gf)
end
