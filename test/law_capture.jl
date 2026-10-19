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

    "Descriptions of the test sets that directly hold a `Fail` or an `Error`."
    function failing(ts::Capture, acc = Set{String}())
        for r in ts.results
            if r isa Capture
                failing(r, acc)
            elseif r isa Union{Test.Fail, Test.Error}
                push!(acc, ts.description)
            end
        end
        return acc
    end

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
    failure or error, and the set of leaf test sets that ran.
    """
    function captured(f)
        ts = Test.@testset Capture "captured" begin
            f()
        end
        return failing(ts), leaves(ts)
    end
end
