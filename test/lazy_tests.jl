# Laziness (plan "Laziness (R5)"; research recursion-schemes-free-laziness.md §5, recommendation 7):
# `Thunk`, the memoised thread-safe `Lazy`, `force`, `isforced`, `@lazy`, and the deferred
# Functor/Applicative/Monad instances on `LazyTag()`.

@testitem "lazy: Thunk recomputes on every force" tags = [:unit] begin
    using Test
    C = ChuiCore
    n = Ref(0)
    t = C.Thunk(() -> (n[] += 1; 7))
    @test n[] == 0
    @test C.force(t) == 7
    @test C.force(t) == 7
    @test n[] == 2
    @test (@inferred C.force(C.Thunk(() -> 1.5))) === 1.5
end

@testitem "lazy: force of a plain value is the value" tags = [:unit] begin
    using Test
    C = ChuiCore
    @test C.force(3) === 3
    @test C.force("a") === "a"
    @test C.force(nothing) === nothing
    v = [1, 2]
    @test C.force(v) === v
end

@testitem "lazy: R5 reproducer, memoised (body runs once)" tags = [:unit] begin
    using Test
    # Request R5, verbatim apart from `exit(1)`.
    n = Ref(0)
    t = ChuiCore.Lazy(() -> (n[] += 1; 42))
    @test (ChuiCore.force(t), ChuiCore.force(t), n[]) == (42, 42, 1)
end

@testitem "lazy: Lazy{T}, Lazy, isforced, @lazy, inference" tags = [:unit] begin
    using Test
    C = ChuiCore
    l = C.Lazy{Float64}(() -> 1)          # converted to T
    @test !C.isforced(l)
    @test (@inferred C.force(l)) === 1.0
    @test C.isforced(l)
    @test C.Lazy(() -> 2.5) isa C.Lazy{Float64}
    # A type-unstable body gives a non-concrete T (documented); `Lazy{T}` fixes it.
    unstable() = rand() < 2 ? 1 : 1.0
    @test !isconcretetype(typeof(C.Lazy(unstable)).parameters[1])
    @test C.Lazy{Float64}(unstable) isa C.Lazy{Float64}
    n = Ref(0)
    m = C.@lazy (n[] += 1; n[] * 10)
    @test m isa C.Lazy
    @test n[] == 0
    @test C.force(m) == 10
    @test C.force(m) == 10
    @test n[] == 1
    # show does not force
    s = C.Lazy(() -> 5)
    @test occursin("unevaluated", sprint(show, s))
    C.force(s)
    @test occursin("5", sprint(show, s))
end

@testitem "lazy: the closure is dropped after evaluation" tags = [:unit] begin
    using Test
    C = ChuiCore
    big = rand(1000)
    l = C.Lazy(() -> sum(big))
    @test l.f !== nothing
    C.force(l)
    @test l.f === nothing
    e = C.Lazy{Int}(() -> error("boom"))
    @test_throws ErrorException C.force(e)
    @test e.f === nothing
end

@testitem "lazy: a throwing body runs once; the exception is cached and rethrown" tags = [:unit] begin
    using Test
    C = ChuiCore
    n = Ref(0)
    l = C.Lazy{Int}(() -> (n[] += 1; throw(DomainError(n[], "bad"))))
    err1 = try
        C.force(l)
    catch e
        e
    end
    err2 = try
        C.force(l)
    catch e
        e
    end
    @test err1 isa DomainError
    @test err2 === err1
    @test n[] == 1
    @test C.isforced(l)
    # A body whose inferred type is Union{} (always throws) still constructs and rethrows.
    u = C.Lazy(() -> error("always"))
    @test_throws ErrorException C.force(u)
    @test_throws ErrorException C.force(u)
end

@testitem "lazy: a body that forces its own Lazy throws an ArgumentError" tags = [:unit] begin
    using Test
    C = ChuiCore
    r = Ref{Any}(nothing)
    l = C.Lazy{Int}(() -> C.force(r[]) + 1)
    r[] = l
    @test_throws ArgumentError C.force(l)
    # The cycle error is the body's exception: cached, rethrown, no recursion.
    @test_throws ArgumentError C.force(l)
    @test C.isforced(l)
end

@testitem "lazy: concurrent force in one process runs the body once" tags = [:unit] begin
    using Test
    C = ChuiCore
    for _ in 1:50
        n = Threads.Atomic{Int}(0)
        l = C.Lazy{Int}(() -> (Threads.atomic_add!(n, 1); sleep(0.001); 42))
        ts = [Threads.@spawn C.force(l) for _ in 1:4]
        @test all(==(42), fetch.(ts))
        @test n[] == 1
    end
end

@testitem "lazy: R5 two tasks, julia -t 4 subprocess, 500 trials" tags = [:unit] begin
    using Test
    # A child `julia -t 4` with the parent's resolved load path (so it loads this ChuiCore).
    sep = Sys.iswindows() ? ";" : ":"
    julia = addenv(Base.julia_cmd(), "JULIA_LOAD_PATH" => join(Base.load_path(), sep), "JULIA_PROJECT" => nothing)
    script = """
    using ChuiCore
    Threads.nthreads() >= 2 || (println("threads=", Threads.nthreads()); exit(2))
    multi = 0; threw = 0; wrong = 0
    for _ in 1:500
        n = Threads.Atomic{Int}(0)
        l = ChuiCore.Lazy{Int}(() -> (Threads.atomic_add!(n, 1); 42))
        ts = [Threads.@spawn try
                ChuiCore.force(l)
            catch
                nothing
            end for _ in 1:4]
        rs = fetch.(ts)
        global multi += n[] != 1
        global threw += count(isnothing, rs)
        global wrong += count(r -> r !== nothing && r != 42, rs)
    end
    println("multi_init=", multi, " threw=", threw, " wrong=", wrong)
    exit(multi == 0 && threw == 0 && wrong == 0 ? 0 : 1)
    """
    out = IOBuffer()
    proc = run(pipeline(ignorestatus(`$julia --startup-file=no -t 4 -e $script`); stdout = out, stderr = out))
    report = String(take!(out))
    println(report)
    @test proc.exitcode == 0
    @test occursin("multi_init=0 threw=0 wrong=0", report)
end

@testitem "lazy: fmap, ap, chain are deferred" tags = [:unit] begin
    using Test
    C = ChuiCore
    n = Ref(0)
    l = C.Lazy(() -> (n[] += 1; 3))
    m = C.fmap(x -> x + 1, l)
    @test m isa C.Lazy
    @test n[] == 0
    @test !C.isforced(l)
    @test C.force(m) == 4
    @test n[] == 1
    p = C.pure(C.LazyTag(), 9)
    @test p isa C.Lazy{Int}
    @test C.isforced(p)
    @test C.force(p) == 9
    k = Ref(0)
    ff = C.Lazy(() -> (k[] += 1; x -> 2x))
    a = C.ap(ff, C.Lazy(() -> (k[] += 1; 5)))
    @test k[] == 0
    @test C.force(a) == 10
    @test k[] == 2
    c = chain(x -> C.Lazy(() -> (k[] += 1; x * 3)), C.Lazy(() -> 2))
    @test k[] == 2
    @test C.force(c) == 6
    @test k[] == 3
    @test C.constructorclass(typeof(l)) === C.LazyTag()
end

@testitem "laws: Lazy Functor, Applicative, Monad" tags = [:laws] begin
    using Test
    C = ChuiCore
    L = C.LazyTag()
    eq = (a, b) -> isequal(C.force(a), C.force(b))
    # Fresh lazies per law check (a memo cell is mutable): generators build them on demand.
    las = [C.Lazy(() -> 1), C.Lazy(() -> -2), C.pure(L, 0), C.@lazy(40 + 2)]
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(L, las, fs; eq)
    test_applicative_laws(L, las, fs, [0, 5]; eq)
    ks = [x -> C.Lazy(() -> x + 1), x -> C.pure(L, 2x)]
    test_monad_laws(L, las, ks, [0, 5]; eq)
end

@testitem "laws: Lazy through Supposition" tags = [:laws, :property] begin
    using Test, Supposition
    using Supposition: Data
    C = ChuiCore
    L = C.LazyTag()
    eq = (a, b) -> isequal(C.force(a), C.force(b))
    ints = Data.Integers(-100, 100)
    gen = Data.OneOf(map(x -> C.Lazy(() -> x), ints), map(x -> C.pure(L, x), ints))
    fs = [x -> x + 1, abs, x -> 2x]
    ks = [x -> C.Lazy(() -> x + 1), x -> C.pure(L, 2x)]
    test_functor_laws(L, gen, fs; eq, max_examples = 50)
    test_applicative_laws(L, gen, fs, ints; eq, max_examples = 50)
    test_monad_laws(L, gen, ks, ints; eq, max_examples = 50)
end
