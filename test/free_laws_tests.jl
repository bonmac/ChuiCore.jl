# Functor, Applicative and Monad laws of the freer monad (FreeTag), compared by interpreting both
# sides: equal final value and equal instruction trace.

@testitem "free laws: samples" tags = [:laws] setup = [FreeFx] begin
    using Test
    using .FreeFx: PROGRAMS, KS, progeq
    F = ChuiCore.FreeTag()
    fs = [x -> x + 1, abs, x -> 2x]
    xs = [0, 3, -2]
    test_functor_laws(F, PROGRAMS, fs; eq = progeq)
    test_applicative_laws(F, PROGRAMS, fs, xs; eq = progeq)
    test_monad_laws(F, PROGRAMS, KS, xs; eq = progeq)
end

@testitem "free laws: through Supposition" tags = [:laws, :property] setup = [FreeFx] begin
    using Test, Supposition
    using Supposition: Data
    using .FreeFx: KS, progeq, program
    F = ChuiCore.FreeTag()
    gen = map(program, Data.Integers(0, 6))
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(F, gen, fs; eq = progeq, max_examples = 50)
    test_applicative_laws(F, gen, fs, Data.Integers(-50, 50); eq = progeq, max_examples = 50)
    test_monad_laws(F, gen, KS, Data.Integers(-50, 50); eq = progeq, max_examples = 50)
end
