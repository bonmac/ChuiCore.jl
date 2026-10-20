# The transducer substrate (ADR-0003): types, protocol, composition, folds, aggregate.

@testitem "transducers: Map, Filter, MapCat" tags = [:unit] begin
    const CC = ChuiCore
    collectxf(xf, itr) = CC.foldxl(push!, xf, itr; init = Any[])
    @test collectxf(CC.Map(x -> 2x), 1:4) == [2, 4, 6, 8]
    @test collectxf(CC.Filter(iseven), 1:6) == [2, 4, 6]
    @test collectxf(CC.MapCat(x -> 1:x), 1:3) == [1, 1, 2, 1, 2, 3]
    @test collectxf(CC.MapCat(x -> ()), 1:3) == []
    @test CC.foldxl(+, CC.Map(abs), [-1, 2, -3]; init = 0) == 6
    @test CC.foldxl(+, CC.Filter(iseven), Int[]; init = 0) == 0
    # MapCat conveys a downstream Reduced out of its inner loop.
    @test collectxf(CC.MapCat(x -> 1:x) ⨟ CC.Take(4), 1:10) == [1, 1, 2, 1]
end

@testitem "transducers: composition order and flattening" tags = [:unit] begin
    const CC = ChuiCore
    f(x) = x + 1
    p(x) = iseven(x)
    xf = CC.Map(f) ⨟ CC.Filter(p)
    @test xf isa CC.Composed
    @test xf == CC.Filter(p) ∘ CC.Map(f)
    @test CC.foldxl(+, xf, 1:6; init = 0) == 2 + 4 + 6
    # Filter then Map is a different pipeline.
    @test CC.foldxl(+, CC.Filter(p) ⨟ CC.Map(f), 1:6; init = 0) == 3 + 5 + 7
    # Flattening: one Composed whose tuple holds the leaves in data order.
    xf3 = CC.Map(f) ⨟ CC.Filter(p) ⨟ CC.Take(2)
    @test xf3 isa CC.Composed
    @test length(xf3.xfs) == 3
    @test xf3.xfs[3] == CC.Take(2)
    @test (CC.Map(f) ⨟ (CC.Filter(p) ⨟ CC.Take(2))) == xf3
    # A plain function in a composition gives Base's ComposedFunction (unsupported).
    @test (CC.Map(f) ⨟ identity) isa ComposedFunction
    # asrf returns structs, never closures.
    rf = CC.asrf(xf, +)
    @test rf isa CC.R
    @test rf.inner isa CC.R
    @test rf.inner.inner isa CC.Bottom
    @test !(rf isa Function)
    @test CC.asrf(CC.Map(f), +) isa CC.R{CC.Map{typeof(f)}, CC.Bottom{typeof(+)}}
    # An empty Composed is the identity pipeline.
    @test CC.foldxl(+, CC.Composed(()), 1:3; init = 0) == 6
end

@testitem "transducers: no call method on any v1 transducer (CC-001 not applicable)" tags = [:unit] begin
    const CC = ChuiCore
    xfs = (
        CC.Map(abs), CC.Filter(iseven), CC.MapCat(x -> (x,)), CC.Take(1), CC.TakeWhile(<(3)),
        CC.Scan(+, 0), CC.Partition(2), CC.Partition{Int}(2), CC.Map(abs) ⨟ CC.Take(1),
    )
    for xf in xfs
        @test !hasmethod(xf, Tuple{Any})
        @test !(xf isa Function)
    end
    @test any(x -> x isa CC.Composed, xfs)
end

@testitem "transducers: Reduced helpers" tags = [:unit] begin
    const CC = ChuiCore
    r = CC.reduced(3)
    @test r isa CC.Reduced{Int}
    @test CC.isreduced(r) && !CC.isreduced(3)
    @test CC.unreduced(r) === 3 && CC.unreduced(3) === 3
    @test CC.reduced(r) === r
    # Early termination from the bottom op.
    @test CC.foldxl((a, x) -> x > 3 ? CC.reduced(a) : a + x, CC.Map(identity), 1:10; init = 0) == 6
end

@testitem "transducers: Take" tags = [:unit] begin
    const CC = ChuiCore
    collectxf(xf, itr) = CC.foldxl(push!, xf, itr; init = Any[])
    @test collectxf(CC.Take(3), 1:10) == [1, 2, 3]
    @test collectxf(CC.Take(3), 1:2) == [1, 2]
    @test collectxf(CC.Take(0), 1:5) == []
    @test_throws ArgumentError CC.Take(-1)
    # Unbounded input terminates.
    @test CC.foldxl(+, CC.Take(4), Iterators.countfrom(1); init = 0) == 10
    # Both orders with another stateful transducer.
    @test collectxf(CC.Take(2) ⨟ CC.Scan(+, 0), 1:10) == [1, 3]
    @test collectxf(CC.Scan(+, 0) ⨟ CC.Take(2), 1:10) == [1, 3]
    @test CC.isstateless(CC.Take(1)) == false
end

@testitem "transducers: TakeWhile" tags = [:unit] begin
    const CC = ChuiCore
    collectxf(xf, itr) = CC.foldxl(push!, xf, itr; init = Any[])
    @test collectxf(CC.TakeWhile(<(4)), 1:10) == [1, 2, 3]
    @test collectxf(CC.TakeWhile(<(4)), [5, 1]) == []
    # Both orders with Partition and Take.
    @test collectxf(CC.TakeWhile(<(5)) ⨟ CC.Partition(3), 1:10) == [[1, 2, 3], [4]]
    @test collectxf(CC.Partition(3) ⨟ CC.TakeWhile(x -> sum(x) < 10), 1:10) == [[1, 2, 3]]
    @test collectxf(CC.TakeWhile(<(5)) ⨟ CC.Take(2), 1:10) == [1, 2]
    @test collectxf(CC.Take(2) ⨟ CC.TakeWhile(<(5)), 1:10) == [1, 2]
    @test CC.isstateless(CC.TakeWhile(<(4))) == false
end

@testitem "transducers: Scan" tags = [:unit] begin
    const CC = ChuiCore
    collectxf(xf, itr) = CC.foldxl(push!, xf, itr; init = Any[])
    @test collectxf(CC.Scan(+, 0), 1:5) == [1, 3, 6, 10, 15]
    @test collectxf(CC.Scan(*, 1), Int[]) == []
    @test CC.foldxl(+, CC.Scan(+, 0), 1:100; init = 0) == 171700
    # Both orders with Partition.
    @test collectxf(CC.Scan(+, 0) ⨟ CC.Partition(2), 1:5) == [[1, 3], [6, 10], [15]]
    @test collectxf(CC.Partition(2) ⨟ CC.Scan((s, c) -> s + sum(c), 0), 1:5) == [3, 10, 15]
    # Reuse: state comes from start, so a second fold starts from init again.
    xf = CC.Scan(+, 0)
    @test collectxf(xf, 1:3) == collectxf(xf, 1:3) == [1, 3, 6]
    @test CC.isstateless(xf) == false
end

@testitem "transducers: Partition" tags = [:unit] begin
    const CC = ChuiCore
    collectxf(xf, itr) = CC.foldxl(push!, xf, itr; init = Any[])
    @test CC.Partition(3) === CC.Partition{Any}(3)
    @test_throws ArgumentError CC.Partition(0)
    # Flush on complete.
    @test collectxf(CC.Partition(3), 1:8) == [[1, 2, 3], [4, 5, 6], [7, 8]]
    @test collectxf(CC.Partition(3), 1:6) == [[1, 2, 3], [4, 5, 6]]
    @test collectxf(CC.Partition(3), Int[]) == []
    # Element type of the emitted chunks; chunks are copies.
    out = collectxf(CC.Partition{Int}(2), 1:5)
    @test out == [[1, 2], [3, 4], [5]]
    @test all(c -> c isa Vector{Int}, out)
    @test collectxf(CC.Partition(2), 1:2)[1] isa Vector{Any}
    @test out[1] !== out[2]
    # Both orders with Take: no flush into a reduced downstream; flush after an upstream reduce.
    @test collectxf(CC.Partition(3) ⨟ CC.Take(1), 1:8) == [[1, 2, 3]]
    @test collectxf(CC.Take(2) ⨟ CC.Partition(3), 1:8) == [[1, 2]]
    @test collectxf(CC.Take(4) ⨟ CC.Partition(3), 1:8) == [[1, 2, 3], [4]]
    # A downstream that reduces mid-stream never receives the remainder.
    seen = Any[]
    stopop(acc, c) = (push!(seen, copy(c)); CC.reduced(acc + 1))
    @test CC.foldxl(stopop, CC.Partition(2), 1:5; init = 0) == 1
    @test seen == [[1, 2]]
    # Reuse of one Partition value.
    xf = CC.Partition(2)
    @test collectxf(xf, 1:3) == collectxf(xf, 1:3) == [[1, 2], [3]]
    @test CC.isstateless(xf) == false
end

@testitem "transducers: isstateless is fail-closed (ADR-0012 P2)" tags = [:unit] begin
    const CC = ChuiCore
    struct LocalXf <: CC.Transducer end
    @test CC.isstateless(CC.Map(abs))
    @test CC.isstateless(CC.Filter(iseven))
    @test CC.isstateless(CC.MapCat(x -> (x,)))
    @test CC.isstateless(CC.Map(abs) ⨟ CC.Filter(iseven))
    @test CC.isstateless(CC.Map(abs) ⨟ CC.MapCat(x -> (x,)) ⨟ CC.Filter(iseven))
    @test !CC.isstateless(CC.Take(1))
    @test !CC.isstateless(CC.TakeWhile(<(3)))
    @test !CC.isstateless(CC.Scan(+, 0))
    @test !CC.isstateless(CC.Partition(2))
    @test !CC.isstateless(CC.Map(abs) ⨟ CC.Take(1))
    @test !CC.isstateless(LocalXf())
    @test !CC.isstateless(42)
    @test !CC.isstateless(nothing)
end

@testitem "transducers: complete runs exactly once, also after Reduced" tags = [:unit] begin
    const CC = ChuiCore
    # A test transducer that counts its completions in a field the test owns.
    struct CountComplete <: CC.Transducer
        n::Base.RefValue{Int}
    end
    CC.next(rf::CC.R{CountComplete}, acc, x) = CC.next(rf.inner, acc, x)
    function CC.complete(rf::CC.R{CountComplete}, acc)
        rf.xf.n[] += 1
        return CC.complete(rf.inner, acc)
    end
    CC.isstateless(::CountComplete) = true
    c = CountComplete(Ref(0))
    @test CC.foldxl(+, c, 1:10; init = 0) == 55
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldxl(+, c ⨟ CC.Take(2), 1:10; init = 0) == 3
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldxl(+, CC.Take(2) ⨟ c, 1:10; init = 0) == 3
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldxl(+, CC.Partition(3) ⨟ CC.Map(sum) ⨟ c ⨟ CC.Take(1), 1:10; init = 0) == 6
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldxl((a, x) -> CC.reduced(a + x), c, 1:10; init = 0) == 1
    @test c.n[] == 1
    # foldparts: one complete on the merged accumulator, not one per partition.
    c.n[] = 0
    @test CC.foldparts(+, c, [1:3, 4:6, 7:10]; init = () -> 0, merge = +) == 55
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldparts((a, x) -> x == 5 ? CC.reduced(a + x) : a + x, c, [1:3, 4:6, 7:10]; init = () -> 0, merge = +) == 15
    @test c.n[] == 1
    c.n[] = 0
    @test CC.foldxt(+, c, collect(1:10); init = () -> 0, merge = +, ntasks = 4) == 55
    @test c.n[] == 1
end

@testitem "transducers: foldparts" tags = [:unit] begin
    const CC = ChuiCore
    parts = [[1, 2], [3], Int[], [4, 5, 6]]
    @test CC.foldparts(+, CC.Map(identity), parts; init = () -> 0, merge = +) == 21
    @test CC.foldparts(+, CC.Map(identity), Vector{Int}[]; init = () -> 0, merge = +) == 0
    # Merged strictly in partition order (a non-commutative merge).
    cat_ = CC.foldparts(push!, CC.Map(identity), parts; init = () -> Int[], merge = append!)
    @test cat_ == 1:6
    # Stateful: one sequential foldxl over the flattened parts.
    @test CC.foldparts(push!, CC.Scan(+, 0), parts; init = () -> Int[], merge = append!) == cumsum(1:6)
    @test CC.foldparts(push!, CC.Partition(4), parts; init = () -> Any[], merge = append!) == [[1, 2, 3, 4], [5, 6]]
    # A Reduced in a partition stops later partitions from being merged.
    stop5(a, x) = x == 5 ? CC.reduced(a + x) : a + x
    @test CC.foldparts(stop5, CC.Map(identity), [1:3, 4:6, 7:10]; init = () -> 0, merge = +) == (1 + 2 + 3) + (4 + 5)
    # init must be a factory; merge is required.
    @test_throws ArgumentError CC.foldparts(+, CC.Map(identity), parts; init = 0, merge = +)
    @test_throws ArgumentError CC.foldparts(+, CC.Take(1), parts; init = 0, merge = +)
    @test_throws UndefKeywordError CC.foldparts(+, CC.Map(identity), parts; init = () -> 0)
end

@testitem "transducers: foldparts waits for every task; errors after a stop propagate" tags = [:unit] begin
    const CC = ChuiCore
    parts = [1:3, 4:6, 7:9]
    # Partition 2 reduces at 5, but only after partition 3 has started (the Event), so partition
    # 3 cannot be skipped: deterministic on any thread count.
    started = Base.Event()
    function boom(a, x)
        x == 7 && (notify(started); error("boom in partition 3"))
        x == 5 && (wait(started); return CC.reduced(a + x))
        return a + x
    end
    err = try
        CC.foldparts(boom, CC.Map(identity), parts; init = () -> 0, merge = +)
        nothing
    catch e
        e
    end
    @test err isa TaskFailedException
    @test err.task.exception isa ErrorException
    @test err.task.exception.msg == "boom in partition 3"
    # The same through foldxt and aggregate (three views of 1:9 with ntasks = 3).
    started2 = Base.Event()
    function boom2(a, x)
        x == 7 && (notify(started2); error("boom"))
        x == 5 && (wait(started2); return CC.reduced(a + x))
        return a + x
    end
    @test_throws TaskFailedException CC.foldxt(boom2, CC.Map(identity), collect(1:9); init = () -> 0, merge = +, ntasks = 3)
    started3 = Base.Event()
    f3(x) = x == 7 ? (notify(started3); error("boom")) : x == 5 ? (wait(started3); x) : x
    @test_throws TaskFailedException CC.aggregate(CC.First(), CC.Map(f3), parts)
    # No task outlives the call: partition 3 finishes before foldparts returns, and its result
    # is discarded after partition 2's Reduced.
    started4 = Base.Event()
    done = Threads.Atomic{Bool}(false)
    function slow(a, x)
        x == 7 && notify(started4)
        x == 9 && (sleep(0.2); done[] = true)
        x == 5 && (wait(started4); return CC.reduced(a + x))
        return a + x
    end
    @test CC.foldparts(slow, CC.Map(identity), parts; init = () -> 0, merge = +) == (1 + 2 + 3) + (4 + 5)
    @test done[]
    # The sequential path (not stateless) throws the original exception.
    @test_throws ErrorException CC.foldparts((a, x) -> error("seq"), CC.Take(5), parts; init = () -> 0, merge = +)
end

@testitem "transducers: foldxt over views" tags = [:unit] begin
    const CC = ChuiCore
    v = collect(1:100)
    for n in (1, 2, 3, 4, 7, 100, 1000)
        @test CC.foldxt(+, CC.Map(x -> 2x) ⨟ CC.Filter(>(10)), v; init = () -> 0, merge = +, ntasks = n) ==
            CC.foldxl(+, CC.Map(x -> 2x) ⨟ CC.Filter(>(10)), v; init = 0)
        @test CC.foldxt(push!, CC.Map(identity), v; init = () -> Int[], merge = append!, ntasks = n) == v
    end
    @test CC.foldxt(+, CC.Map(identity), Int[]; init = () -> 0, merge = +) == 0
    @test CC.foldxt(+, CC.Take(3), v; init = () -> 0, merge = +, ntasks = 4) == 6
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), v; init = () -> 0, merge = +, ntasks = 0)
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), (x for x in 1:10); init = () -> 0, merge = +)
    @test CC.foldxt(+, CC.Map(identity), 1:10; init = () -> 0, merge = +, ntasks = 4) == 55
    @test_throws ArgumentError CC.foldxt(+, CC.Map(identity), Set([1, 2]); init = () -> 0, merge = +)
    # Partitions are views: no copy of the input (10^5 Int = 800 kB would show up here).
    big = collect(1:(10^5))
    g(xs) = CC.foldxt(+, CC.Map(identity), xs; init = () -> 0, merge = +, ntasks = 4)
    allocs(xs) = (g(xs); @allocated g(xs))
    @test g(big) == sum(big)
    @test allocs(big) < 50_000
end

@testitem "transducers: aggregate (CC-004 unchanged)" tags = [:unit] begin
    const CC = ChuiCore
    parts = [[1, 2], [3], Int[]]
    @test CC.aggregate(CC.Sum(), CC.Map(identity), parts) == 6
    @test CC.aggregate(CC.Sum(), CC.Map(x -> 2x) ⨟ CC.Filter(>(2)), parts) == 10
    @test CC.aggregate(CC.First(), CC.Filter(>(1)), parts) == 2
    @test CC.aggregate(CC.Last(), CC.Map(identity), parts) == 3
    @test CC.aggregate(CC.Count(), CC.MapCat(x -> (x, x)), parts) == 6
    # Stateful pipelines run sequentially over the flattened parts.
    @test CC.aggregate(CC.Sum(), CC.Take(2), parts) == 3
    @test CC.aggregate(CC.Sum(), CC.Scan(+, 0), parts) == 1 + 3 + 6
    @test CC.aggregate(CC.Mean(), CC.Map(float), [[1, 2], [3, 4]]) ≈ 2.5
    # The empty-input result of an aggregator without identity (CC-006).
    @test_throws ArgumentError CC.aggregate(CC.Max(), CC.Map(identity), [Int[]])
    @test_throws ArgumentError CC.aggregate(CC.Max(), CC.Take(1), [Int[]])
end
