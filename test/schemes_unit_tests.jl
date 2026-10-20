# Recursion schemes (docs/research/recursion-schemes-free-laziness.md §1–2, plan "Recursion
# schemes"): cata, ana, hylo, para, apo, histo, futu and the monadic variants.

@testitem "schemes: names are defined (R6)" tags = [:unit] begin
    using Test
    @test all(n -> isdefined(ChuiCore, n), (:cata, :ana, :para, :Fix))
    @test all(
        n -> isdefined(ChuiCore, n),
        (:project, :hylo, :apo, :histo, :futu, :cataM, :anaM, :hyloM, :Done, :More, :Attr, :Emit),
    )
end

@testitem "schemes: Fix" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: LitF, AddF, lit, add
    C = ChuiCore
    # The field is never concrete (research A1: a concrete field recompiles per tree shape).
    @test fieldtype(C.Fix, :unfix) === Any
    @test fieldnames(C.Fix) == (:unfix,)
    # Structural equality and hashing.
    @test add(lit(1), lit(2)) == add(lit(1), lit(2))
    @test isequal(add(lit(1), lit(2)), add(lit(1), lit(2)))
    @test hash(add(lit(1), lit(2))) == hash(add(lit(1), lit(2)))
    @test add(lit(1), lit(2)) != add(lit(2), lit(1))
    @test !isequal(lit(1), lit(2))
    # project unwraps a Fix; any other value is its own layer.
    @test C.project(lit(3)) === LitF(3)
    l = AddF(1, 2)
    @test C.project(l) === l
    # Fix registers no functor of its own.
    @test C.FunctorStyle(C.constructorclass(C.Fix)) === C.NotFunctor()
end

@testitem "schemes: cata" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: lit, add, mul, evalalg, fromlist, tolist, LitF, AddF
    C = ChuiCore
    t = add(lit(2), mul(lit(3), lit(4)))
    @test C.cata(evalalg, t) == 14
    @test tolist(fromlist([1, 2, 3])) == [1, 2, 3]
    @test tolist(fromlist(Int[])) == Int[]
    # A tree of bare layers (no Fix) is its own fixpoint through `project(x) = x`.
    @test C.cata(evalalg, AddF(LitF(1), AddF(LitF(2), LitF(3)))) == 6
    # A leaf that is not a Functor is an ArgumentError from fmap.
    @test_throws ArgumentError C.cata(evalalg, C.Fix(AddF(1, 2)))
end

@testitem "schemes: ana and hylo" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: LitF, AddF, NilF, ConsF, evalalg, tolist, lit, add
    C = ChuiCore
    fibcoalg(n) = n < 2 ? LitF(n) : AddF(n - 1, n - 2)
    @test C.ana(fibcoalg, 3) == add(add(lit(1), lit(0)), lit(1))
    # embed = identity builds bare layers (an own node type), not Fix.
    @test C.ana(fibcoalg, 2; embed = identity) == AddF(LitF(1), LitF(0))
    rangecoalg(n) = n == 0 ? NilF() : ConsF(n, n - 1)
    @test tolist(C.ana(rangecoalg, 4)) == [4, 3, 2, 1]
    fibs = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]
    @test [C.hylo(evalalg, fibcoalg, n) for n in 0:12] == fibs
end

@testitem "schemes: para" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: NilF, ConsF, fromlist, tolist, lit, add, mul, LitF, AddF, MulF
    C = ChuiCore
    # suffixes: the algebra sees each original tail next to its result.
    suffixalg(::NilF) = Vector{Int}[]
    suffixalg(x::ConsF) = pushfirst!(copy(x.t[2]), tolist(x.t[1]))
    @test C.para(suffixalg, fromlist([1, 2, 3])) == [[2, 3], [3], Int[]]
    # The original in each pair is the input subtree itself (===).
    t = add(lit(1), mul(lit(2), lit(3)))
    seen = Any[]
    recalg(x::LitF) = x.v
    recalg(x::Union{AddF, MulF}) = (push!(seen, x.l[1], x.r[1]); x.l[2] + x.r[2])
    @test C.para(recalg, t) == 6
    @test seen[end - 1] === t.unfix.l
    @test seen[end] === t.unfix.r
    @test seen[1] === t.unfix.r.unfix.l
    @test seen[2] === t.unfix.r.unfix.r
end

@testitem "schemes: apo insert into a sorted list" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: NilF, ConsF, fromlist, tolist
    C = ChuiCore
    function insertcoalg(x)
        return function (l)
            layer = C.project(l)
            layer isa NilF && return ConsF(x, C.Done(l))
            x <= layer.h && return ConsF(x, C.Done(l))
            return ConsF(layer.h, C.More(layer.t))
        end
    end
    @test tolist(C.apo(insertcoalg(4), fromlist([1, 3, 5, 7]))) == [1, 3, 4, 5, 7]
    @test tolist(C.apo(insertcoalg(9), fromlist([1, 3]))) == [1, 3, 9]
    @test tolist(C.apo(insertcoalg(0), fromlist(Int[]))) == [0]
    # The untouched tail is reused as is (Done embeds it without copying).
    tail = fromlist([5, 7])
    l = C.Fix(ConsF(1, tail))
    r = C.apo(insertcoalg(2), l)
    @test r.unfix.t.unfix.t === tail
    @test C.Done(1) == C.Done(1) && C.More(2) == C.More(2)
    # A hole that is neither Done nor More is an ArgumentError (no silent misreading of seeds).
    @test_throws ArgumentError C.apo(n -> n == 0 ? NilF() : ConsF(n, n - 1), 2)
    # A seed that is itself a Done is a seed, not a marker.
    @test tolist(C.apo(s -> s isa C.Done ? ConsF(1, C.More(0)) : NilF(), C.Done(:x))) == [1]
end

@testitem "schemes: histo fib" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: ZeroF, SuccF, nat
    C = ChuiCore
    fibalg(::ZeroF) = 0
    fibalg(x::SuccF) = x.p.layer isa ZeroF ? 1 : x.p.value + x.p.layer.p.value
    @test [C.histo(fibalg, nat(n)) for n in 0:10] == [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
    a = C.Attr(1, ZeroF())
    @test a.value == 1 && a.layer === ZeroF()
end

@testitem "schemes: futu dup" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: NilF, ConsF, tolist
    C = ChuiCore
    dupcoalg(n) = n == 0 ? NilF() : ConsF(n, C.Emit(ConsF(n, C.More(n - 1))))
    @test tolist(C.futu(dupcoalg, 3)) == [3, 3, 2, 2, 1, 1]
    @test tolist(C.futu(dupcoalg, 0)) == Int[]
    @test C.Emit(NilF()).layer === NilF()
    @test_throws ArgumentError C.futu(n -> n == 0 ? NilF() : ConsF(n, n - 1), 2)
end

@testitem "schemes: cataM, anaM, hyloM with Maybe" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: LitF, AddF, DivF, NilF, ConsF, lit, add, divide, tolist
    C = ChuiCore
    M = C.MaybeTag()
    safealg(x::LitF) = Some(x.v)
    safealg(x::AddF) = Some(x.l + x.r)
    safealg(x::DivF) = x.r == 0 ? nothing : Some(div(x.l, x.r))
    @test C.cataM(M, safealg, add(lit(4), divide(lit(32), lit(2)))) == Some(20)
    @test C.cataM(M, safealg, add(lit(4), divide(lit(32), lit(0)))) === nothing
    # nothing short-circuits: the algebra is not called above a failed subtree.
    calls = Ref(0)
    countalg(x) = (calls[] += 1; safealg(x))
    @test C.cataM(M, countalg, add(divide(lit(1), lit(0)), lit(2))) === nothing
    @test calls[] == 4   # the 3 leaves and the DivF; never the AddF
    # anaM: a coalgebra that may fail.
    rangeM(n) = n < 0 ? nothing : Some(n == 0 ? NilF() : ConsF(n, n - 1))
    r = C.anaM(M, rangeM, 3)
    @test r isa Some && tolist(something(r)) == [3, 2, 1]
    stopM(n) = n == 2 ? nothing : Some(n == 0 ? NilF() : ConsF(n, n - 1))
    @test C.anaM(M, stopM, 3) === nothing
    @test C.anaM(M, rangeM, 1; embed = identity) == Some(ConsF(1, NilF()))
    sumalgM(::NilF) = Some(0)
    sumalgM(x::ConsF) = Some(x.h + x.t)
    @test C.hyloM(M, sumalgM, rangeM, 4) == Some(10)
    @test C.hyloM(M, sumalgM, stopM, 4) === nothing
    # Array as the monad: every combination.
    A = C.ArrayTag()
    choose(x::LitF) = [x.v, -x.v]
    choose(x::AddF) = [x.l + x.r]
    @test sort(C.cataM(A, choose, add(lit(1), lit(2)))) == [-3, -1, 1, 3]
end

@testitem "schemes: R6 owned plan nodes, cata and para" tags = [:unit] setup = [SchemeFx] begin
    using Test
    using .SchemeFx: Source, Where, Select, evalplan, pushdown
    C = ChuiCore
    @test all(n -> isdefined(ChuiCore, n), (:cata, :ana, :para, :Fix))
    p1 = r -> r.a > 1
    p2 = r -> r.a < 5
    plan = Where(p1, Select((:a,), Source(:t)))
    # Evaluated by cata without any Fix wrapper.
    @test C.cata(evalplan, plan) == [(a = 3,), (a = 5,)]
    # Identity rebuild of an own node type (the own-type form of `cata(Fix, x) == x`).
    @test C.cata(identity, plan) == plan
    # Pushdown by para: the Where moves below the Select, results unchanged.
    pushed = C.para(pushdown, plan)
    @test pushed == Select((:a,), Where(p1, Source(:t)))
    @test C.cata(evalplan, pushed) == C.cata(evalplan, plan)
    # The rule decides on the ORIGINAL child: one step per para pass.
    plan2 = Where(p2, Where(p1, Select((:a,), Source(:t))))
    once = C.para(pushdown, plan2)
    @test once == Where(p2, Select((:a,), Where(p1, Source(:t))))
    @test C.para(pushdown, once) == Select((:a,), Where(p2, Where(p1, Source(:t))))
    @test C.cata(evalplan, once) == C.cata(evalplan, plan2) == [(a = 3,)]
    # The original handed to the algebra is the input subtree itself.
    seen = Any[]
    C.para(x -> (x isa Where && push!(seen, x.child[1]); pushdown(x)), plan)
    @test only(seen) === plan.child
end
