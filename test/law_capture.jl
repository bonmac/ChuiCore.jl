# A capturing test set for the planted-violation tests (ADR-0007 §5): a law kit runs inside it,
# its failures are collected instead of failing the enclosing test item, and the test asserts
# which law test sets failed.

@testmodule LawCapture begin
    using Test

    mutable struct Capture <: Test.AbstractTestSet
        description::String
        results::Vector{Any}
    end
    Capture(description; kwargs...) = Capture(description, Any[])

    Test.record(ts::Capture, r) = (push!(ts.results, r); r)
    function Test.finish(ts::Capture)
        # Nested captures report to their parent capture; the outermost one reports to nobody, so
        # the planted failures never reach the test item's own test set.
        if Test.get_testset_depth() > 0
            parent = Test.get_testset()
            parent isa Capture && Test.record(parent, ts)
        end
        return ts
    end

    "Descriptions of the test sets that directly hold a result of type `T`."
    function holding(T, ts::Capture, acc = Set{String}())
        for r in ts.results
            if r isa Capture
                holding(T, r, acc)
            elseif r isa T
                push!(acc, ts.description)
            end
        end
        return acc
    end
    # A planted law must FAIL, not crash: an `Error` is never counted as a caught violation.
    failing(ts::Capture) = holding(Test.Fail, ts)

    "Descriptions of the test sets that hold at least one result and no nested test set."
    function leaves(ts::Capture, acc = Set{String}())
        any(r -> r isa Capture, ts.results) || isempty(ts.results) || push!(acc, ts.description)
        for r in ts.results
            r isa Capture && leaves(r, acc)
        end
        return acc
    end

    """
        captured(f) -> (failing, ran)

    Run `f()` inside a capturing test set. Returns the set of test-set descriptions holding a
    `Fail`, and the set of leaf test sets that ran. Any `Error` inside (a crashing law, or a kit
    that throws) is reported as a failing `@test` in the CALLER's test set, so it cannot hide.
    """
    function captured(f)
        ts = Test.@testset Capture "captured" begin
            f()
        end
        errored = holding(Test.Error, ts)
        Test.@test isempty(errored)
        return failing(ts), leaves(ts)
    end
end
