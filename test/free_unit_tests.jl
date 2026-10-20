# Data types à la carte (Coproduct, inj, prj) and the freer monad (Pure, Impure, liftF,
# interpret, foldfree): research §4 and Recommendations 5–6.

@testitem "à la carte: inj and prj" tags = [:unit] setup = [FreeFx] begin
    using Test
    using .FreeFx: KV, Log, Err, Get, Tell, Throw, Sig
    C = ChuiCore
    g = C.inj(Sig, Get(:a))
    t = C.inj(Sig, Tell("hi"))
    @test g isa C.Inl{KV, Log} && g isa C.Coproduct{KV, Log}
    @test t isa C.Inr{KV, Log}
    @test g.x === Get(:a) && t.x === Tell("hi")
    # Reflexive.
    @test C.inj(Get, Get(:a)) === Get(:a)
    @test C.inj(KV, Get(:a)) === Get(:a)
    @test C.inj(Sig, g) === g
    # Nested right: Coproduct{F, Coproduct{G, H}}.
    S3 = C.Coproduct{KV, C.Coproduct{Log, Err}}
    e = C.inj(S3, Throw("boom"))
    @test e isa C.Inr{KV, C.Coproduct{Log, Err}}
    @test e.x isa C.Inr{Log, Err} && e.x.x === Throw("boom")
    @test C.inj(S3, Tell("x")).x isa C.Inl{Log, Err}
    @test C.inj(S3, Get(:k)) isa C.Inl{KV, C.Coproduct{Log, Err}}
    # Not part of the signature: an ArgumentError.
    @test_throws ArgumentError C.inj(Sig, Throw("no"))
    @test_throws ArgumentError C.inj(KV, Tell("no"))
    # prj: Some(x) or nothing.
    @test C.prj(Get, g) == Some(Get(:a))
    @test C.prj(KV, g) == Some(Get(:a))
    @test C.prj(Get, t) === nothing
    @test C.prj(Tell, t) == Some(Tell("hi"))
    @test C.prj(Throw, e) == Some(Throw("boom"))
    @test C.prj(Get, e) === nothing
    @test C.prj(Get, Get(:z)) == Some(Get(:z))
    @test C.prj(Sig, g) == Some(g)
    # Structural equality.
    @test C.inj(Sig, Get(:a)) == C.inj(Sig, Get(:a))
    @test isequal(C.inj(Sig, Get(:a)), C.inj(Sig, Get(:a)))
    @test hash(C.inj(Sig, Get(:a))) == hash(C.inj(Sig, Get(:a)))
    @test C.Inl{KV, Log}(Get(:a)) != C.Inr{KV, Log}(Get(:a))
end

@testitem "à la carte: no method ambiguities" tags = [:unit] begin
    using Test
    @test isempty(Test.detect_ambiguities(ChuiCore))
end

@testitem "à la carte: cata over a Coproduct of base functors" tags = [:unit] begin
    using Test
    C = ChuiCore
    # Swierstra's expression example: Val :+: Add, each its own functor.
    struct Val
        v::Int
    end
    struct Plus{T}
        l::T
        r::T
    end
    struct ValTag end
    struct PlusTag end
    C.constructorclass(::Type{Val}) = ValTag()
    C.constructorclass(::Type{<:Plus}) = PlusTag()
    C.FunctorStyle(::ValTag) = C.IsFunctor()
    C.FunctorStyle(::PlusTag) = C.IsFunctor()
    C.fmap(::C.IsFunctor, f, x::Val) = x
    C.fmap(::C.IsFunctor, f, x::Plus) = Plus(f(x.l), f(x.r))
    C.TraversableStyle(::ValTag) = C.IsTraversable()
    C.TraversableStyle(::PlusTag) = C.IsTraversable()
    C.traverse(::C.IsTraversable, tag, f, x::Val) = C.pure(tag, x)
    C.traverse(::C.IsTraversable, tag, f, x::Plus) = C.ap(C.fmap(l -> (r -> Plus(l, r)), f(x.l)), f(x.r))
    E = C.Coproduct{Val, Plus}
    val(v) = C.Fix(C.inj(E, Val(v)))
    plus(a, b) = C.Fix(C.inj(E, Plus(a, b)))
    evalv(x::Val) = x.v
    evalv(x::Plus) = x.l + x.r
    evalv(x::C.Coproduct) = evalv(x.x)
    @test C.cata(evalv, plus(val(30_000), plus(val(1330), val(7)))) == 31337
    @test C.FunctorStyle(C.constructorclass(C.Inl{Val, Plus})) === C.IsFunctor()
    @test C.fmap(x -> x + 1, C.inj(E, Plus(1, 2))) == C.inj(E, Plus(2, 3))
    samples = [C.inj(E, Val(1)), C.inj(E, Plus(1, -2)), C.inj(E, Plus(3, 4))]
    test_functor_laws(C.CoproductTag(), samples, [x -> x + 1, abs])
    test_traversable_laws(C.CoproductTag(), samples, [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing])
    # cataM over the coproduct (Traversable delegates to the payload).
    safe(x::Val) = x.v < 0 ? nothing : Some(x.v)
    safe(x::Plus) = Some(x.l + x.r)
    safe(x::C.Coproduct) = safe(x.x)
    @test C.cataM(C.MaybeTag(), safe, plus(val(1), val(2))) == Some(3)
    @test C.cataM(C.MaybeTag(), safe, plus(val(1), val(-2))) === nothing
end

@testitem "free: Pure, Impure, liftF" tags = [:unit] setup = [FreeFx] begin
    using Test
    using .FreeFx: Ask, Twice, answer, ask
    C = ChuiCore
    @test C.Pure(1) isa C.Free
    m = C.liftF(Ask())
    @test m isa C.Impure && m isa C.Free
    @test m.op === Ask()
    @test C.constructorclass(typeof(m)) === C.FreeTag()
    @test C.constructorclass(C.Pure{Int}) === C.FreeTag()
    @test C.pure(C.FreeTag(), 3) == C.Pure(3)
    @test C.interpret(answer, C.Pure(5)) == 5
    @test C.interpret(answer, m) == 7
    @test C.interpret(answer, chain(x -> C.liftF(Twice(x)), m)) == 14
    @test C.interpret(answer, C.fmap(x -> x - 1, m)) == 6
    @test C.interpret(answer, C.ap(C.fmap(x -> (y -> (x, y)), m), C.liftF(Twice(1)))) == (7, 2)
    # chain on Pure applies the continuation at once.
    @test chain(x -> C.Pure(x + 1), C.Pure(1)) == C.Pure(2)
    # A Coproduct-injected instruction.
    @test C.liftF(FreeFx.Sig, FreeFx.Get(:a)).op === C.inj(FreeFx.Sig, FreeFx.Get(:a))
end

@testitem "free: key-value + log program over a Coproduct signature" tags = [:unit] setup = [FreeFx] begin
    using Test
    using .FreeFx: Sig, Get, Put, Tell, KVHandler, LogHandler, Throw
    C = ChuiCore
    get_(k) = C.liftF(Sig, Get(k))
    put_(k, v) = C.liftF(Sig, Put(k, v))
    tell(s) = C.liftF(Sig, Tell(s))
    prog = chain(put_(:n, 1)) do _
        chain(get_(:n)) do n
            chain(tell("n is $n")) do _
                chain(put_(:n, n + 41)) do _
                    chain(get_(:n)) do m
                        C.Pure(n + m)
                    end
                end
            end
        end
    end
    kv = KVHandler(Dict{Symbol, Int}())
    log = LogHandler(String[])
    h = C.cohandler(kv, log)
    @test C.interpret(h, prog) == 43
    @test kv.store == Dict(:n => 42)
    @test log.lines == ["n is 1"]
    # Three components; cohandler nests to the right.
    S3 = C.Coproduct{FreeFx.KV, C.Coproduct{FreeFx.Log, FreeFx.Err}}
    errs = String[]
    h3 = C.cohandler(kv, log, op -> (push!(errs, op.msg); -1))
    p3 = chain(x -> C.liftF(S3, Tell("got $x")), C.liftF(S3, Throw("bad")))
    @test C.interpret(h3, p3) === nothing
    @test errs == ["bad"] && log.lines[end] == "got -1"
    @test C.cohandler(kv, log, identity) == C.cohandler(kv, C.cohandler(log, identity))
    # An unhandled instruction is a MethodError from the handler.
    @test_throws MethodError C.interpret(h, C.liftF(:raw))
end

@testitem "free: foldfree into a target monad" tags = [:unit] setup = [FreeFx] begin
    using Test
    using .FreeFx: Ask, Twice, answer, program
    C = ChuiCore
    toId(op) = C.Identity(answer(op))
    @test C.foldfree(C.IdentityTag(), toId, program(4)) == C.Identity(56)
    @test C.foldfree(C.IdentityTag(), toId, C.Pure(3)) == C.Identity(3)
    toMaybe(op::Ask) = Some(7)
    toMaybe(op::Twice) = op.x > 20 ? nothing : Some(2op.x)
    @test C.foldfree(C.MaybeTag(), toMaybe, program(2)) == Some(14)
    @test C.foldfree(C.MaybeTag(), toMaybe, program(3)) == Some(28)
    @test C.foldfree(C.MaybeTag(), toMaybe, program(4)) === nothing
    # Nondeterminism: Ask answers 1 or 2.
    toList(op::Ask) = [1, 2]
    toList(op::Twice) = [2op.x]
    @test C.foldfree(C.ArrayTag(), toList, program(3)) == [4, 8]
    # A moderately long program (stack depth grows with the instruction count for strict monads).
    @test C.foldfree(C.IdentityTag(), op -> C.Identity(op.x + 1), FreeFx.leftprog(1000)) == C.Identity(1000)
end

@testitem "free: linear in left-associated binds, stack-safe" tags = [:unit] setup = [FreeFx] begin
    using Test
    using .FreeFx: leftprog, incr, countdown
    C = ChuiCore
    @test C.interpret(incr, leftprog(10)) == 10
    run(n) = C.interpret(incr, leftprog(n))
    run(1000)
    t(n) = minimum(@elapsed(run(n)) for _ in 1:5)
    t3, t4 = t(1_000), t(10_000)
    ratio = t4 / t3
    @info "free: left-associated binds" t3 t4 ratio
    @test ratio < 40     # quadratic would be ≈ 100
    # Deep programs never overflow the stack: the interpreter is a loop.
    @test C.interpret(incr, leftprog(100_000)) == 100_000
    @test C.interpret(_ -> nothing, countdown(1_000_000)) === :done
end
