# Instruction sets and handlers for the free-monad tests: a key-value store and a log (combined as
# a Coproduct signature), and two pure instructions for the monad laws.

@testmodule FreeFx begin
    using ChuiCore
    const C = ChuiCore

    # Key-value instructions.
    abstract type KV end
    struct Get <: KV
        key::Symbol
    end
    struct Put <: KV
        key::Symbol
        val::Int
    end
    # Log instructions.
    abstract type Log end
    struct Tell <: Log
        msg::String
    end
    # A third component for nested coproducts.
    abstract type Err end
    struct Throw <: Err
        msg::String
    end

    const Sig = C.Coproduct{KV, Log}

    struct KVHandler
        store::Dict{Symbol, Int}
    end
    (h::KVHandler)(op::Get) = get(h.store, op.key, 0)
    (h::KVHandler)(op::Put) = (h.store[op.key] = op.val; nothing)
    struct LogHandler
        lines::Vector{String}
    end
    (h::LogHandler)(op::Tell) = (push!(h.lines, op.msg); nothing)

    # Pure instructions for the law tests: Ask() answers 7, Twice(x) answers 2x.
    struct Ask end
    struct Twice
        x::Int
    end
    answer(::Ask) = 7
    answer(op::Twice) = 2op.x

    # Equality of programs: the same final value AND the same instruction trace.
    function traced(m)
        trace = Any[]
        v = C.interpret(op -> (push!(trace, op); answer(op)), m)
        return (v, trace)
    end
    progeq(a, b) = isequal(traced(a), traced(b))

    ask() = C.liftF(Ask())
    twice(x) = C.liftF(Twice(x))
    # A program of n instructions: ask, then double n - 1 times (n = 0 is `Pure(1)`).
    function program(n::Int)
        n == 0 && return C.Pure(1)
        m = ask()
        for _ in 2:n
            m = chain(twice, m)
        end
        return m
    end
    const PROGRAMS = [C.Pure(1), C.Pure(-4), ask(), twice(3), program(3), C.fmap(x -> x + 1, ask())]
    const KS = [x -> C.Pure(x + 1), twice, x -> chain(y -> C.Pure(x + y), ask())]

    # Counting instruction for the scaling tests.
    struct Incr
        x::Int
    end
    incr(op::Incr) = op.x + 1
    function leftprog(n)
        m = C.Pure(0)
        for _ in 1:n
            m = chain(x -> C.liftF(Incr(x)), m)
        end
        return m
    end
    struct Tick end
    countdown(n) = n == 0 ? C.Pure(:done) : chain(_ -> countdown(n - 1), C.liftF(Tick()))
end
