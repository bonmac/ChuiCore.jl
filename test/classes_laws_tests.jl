# Constructor classes: every instance passes its law kits (ADR-0007), with sample collections and,
# for Functor/Applicative/Monad on Maybe, through the Supposition driver.

@testitem "laws: Maybe" tags = [:laws] begin
    using Test
    C = ChuiCore
    M = C.MaybeTag()
    fa = [Some(1), nothing, Some(-3)]
    fs = [x -> x + 1, abs, x -> 2x]
    xs = [0, 1, -2]
    ks = [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing, x -> nothing]
    test_functor_laws(M, fa, fs)
    test_applicative_laws(M, fa, fs, xs)
    test_monad_laws(M, fa, ks, xs)
    test_alternative_laws(M, [Some(1), nothing, Some(2)])
    test_traversable_laws(M, [Some(1), nothing, Some(-2)], [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing])
end

@testitem "laws: Maybe through Supposition" tags = [:laws, :property] begin
    using Test, Supposition
    using Supposition: Data
    C = ChuiCore
    M = C.MaybeTag()
    gen = Data.OneOf(map(Some, Data.Integers(-100, 100)), Data.Just(nothing))
    fs = [x -> x + 1, abs, x -> 2x]
    ks = [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing, x -> nothing]
    test_functor_laws(M, gen, fs; max_examples = 50)
    test_applicative_laws(M, gen, fs, Data.Integers(-100, 100); max_examples = 50)
    test_monad_laws(M, gen, ks, Data.Integers(-100, 100); max_examples = 50)
end

@testitem "laws: Array" tags = [:laws] begin
    using Test
    A = ChuiCore.ArrayTag()
    fa = [[1, 2], Int[], [3]]
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(A, [fa; [[1 2; 3 4]]], fs)
    test_applicative_laws(A, fa, fs, [0, -1])
    test_monad_laws(A, fa, [x -> [x, x + 1], x -> Int[], x -> [2x]], [0, 3])
    test_alternative_laws(A, [[1], Int[], [2, 3]])
    test_foldable_laws(A, [[1, 2, 3], Int[], [4], [1 2; 3 4]])
    test_traversable_laws(A, [[1, 2], Int[], [-1, 3], [1 2; 3 4]], [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing])
end

@testitem "laws: Tuple, Dict, Pair" tags = [:laws] begin
    using Test
    C = ChuiCore
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(C.TupleTag(), [(1, 2), (), (3,)], fs)
    test_foldable_laws(C.TupleTag(), [(1, 2, 3), (), (4,)])
    test_traversable_laws(C.TupleTag(), [(1, -2), (), (3,)], [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing])
    test_bifunctor_laws(C.TupleTag(), [(1, 2), (3, -4)], fs)
    test_functor_laws(C.DictTag(), [Dict(1 => 2, 3 => 4), Dict{Int, Int}()], fs)
    test_bifunctor_laws(C.PairTag(), [1 => 2, -3 => 4], fs)
end

@testitem "laws: Function" tags = [:laws] begin
    using Test
    F = ChuiCore.FunctionTag()
    fs = [x -> x + 1, abs, x -> 2x]
    xs = [-2, 0, 3]
    test_profunctor_laws(F, [x -> x + 1, abs, x -> x^2], fs, xs)
    test_category_laws(F, fs, xs)
    test_arrow_laws(F, fs, [x -> x - 1, x -> 3x], xs)
end

@testitem "laws: Identity, ZipVector, Predicate" tags = [:laws] begin
    using Test
    C = ChuiCore
    I = C.Identity
    fs = [x -> x + 1, abs, x -> 2x]
    test_functor_laws(C.IdentityTag(), [I(1), I(-2)], fs)
    test_applicative_laws(C.IdentityTag(), [I(1), I(-2)], fs, [0, 5])
    test_monad_laws(C.IdentityTag(), [I(1), I(-2)], [x -> I(x + 1), x -> I(2x)], [0, 5])
    test_foldable_laws(C.IdentityTag(), [I(1), I("a")])
    test_traversable_laws(C.IdentityTag(), [I(1), I(-2)], [x -> Some(x + 1), x -> x > 0 ? Some(x) : nothing])
    Z = C.ZipVectorTag()
    zs = [C.ZipVector([1, 2]), C.ZipVector(Int[]), C.ZipVector([3, 4, 5]), C.pure(Z, 7)]
    test_functor_laws(Z, zs, fs)
    test_applicative_laws(Z, zs, fs, [0, 5])
    ps = [C.Predicate(iseven), C.Predicate(x -> x > 0)]
    test_contravariant_laws(C.PredicateTag(), ps, fs, [-2, -1, 0, 3])
end
