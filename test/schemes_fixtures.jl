# Base functors used by the recursion-scheme tests: an expression functor, a list functor, a
# natural-number functor (all wrapped in `Fix`), and a downstream-style query-plan node type that
# is its own base functor (R6: traversed through `project(x) = x`, never rewrapped).

@testmodule SchemeFx begin
    using ChuiCore
    const C = ChuiCore

    # ---------------------------------------------------------------------------------------
    # Expression functor: LitF | AddF | MulF | DivF. Functor and Traversable.
    struct LitF
        v::Int
    end
    struct AddF{L, R}
        l::L
        r::R
    end
    struct MulF{L, R}
        l::L
        r::R
    end
    struct DivF{L, R}
        l::L
        r::R
    end
    struct ExprTag end
    C.constructorclass(::Type{<:Union{LitF, AddF, MulF, DivF}}) = ExprTag()
    C.FunctorStyle(::ExprTag) = C.IsFunctor()
    C.TraversableStyle(::ExprTag) = C.IsTraversable()
    C.fmap(::C.IsFunctor, f, x::LitF) = x
    C.traverse(::C.IsTraversable, tag, f, x::LitF) = C.pure(tag, x)
    for T in (:AddF, :MulF, :DivF)
        @eval C.fmap(::C.IsFunctor, f, x::$T) = $T(f(x.l), f(x.r))
        @eval C.traverse(::C.IsTraversable, tag, f, x::$T) =
            C.ap(C.fmap(l -> (r -> $T(l, r)), f(x.l)), f(x.r))
    end

    lit(v) = C.Fix(LitF(v))
    add(a, b) = C.Fix(AddF(a, b))
    mul(a, b) = C.Fix(MulF(a, b))
    divide(a, b) = C.Fix(DivF(a, b))

    evalalg(x::LitF) = x.v
    evalalg(x::AddF) = x.l + x.r
    evalalg(x::MulF) = x.l * x.r

    # A fixed pseudo-random tree of the given depth (no Random dependency: a linear congruence).
    function sampletree(seed::Int, depth::Int)
        depth == 0 && return lit(mod(seed, 7) - 3)
        s1 = mod(1103515245 * seed + 12345, 2^31)
        s2 = mod(1103515245 * s1 + 12345, 2^31)
        mod(seed, 5) == 0 && return lit(mod(seed, 11) - 5)
        node = isodd(seed) ? add : mul
        return node(sampletree(s1, depth - 1), sampletree(s2, depth - 1))
    end
    const TREES = [sampletree(s, d) for s in (1, 2, 3, 17, 42) for d in (0, 1, 3, 5)]

    # ---------------------------------------------------------------------------------------
    # List functor: NilF | ConsF(h, t). Functor (on the tail) and Traversable.
    struct NilF end
    struct ConsF{T}
        h::Int
        t::T
    end
    struct ListTag end
    C.constructorclass(::Type{<:Union{NilF, ConsF}}) = ListTag()
    C.FunctorStyle(::ListTag) = C.IsFunctor()
    C.TraversableStyle(::ListTag) = C.IsTraversable()
    C.fmap(::C.IsFunctor, f, x::NilF) = x
    C.fmap(::C.IsFunctor, f, x::ConsF) = ConsF(x.h, f(x.t))
    C.traverse(::C.IsTraversable, tag, f, x::NilF) = C.pure(tag, x)
    C.traverse(::C.IsTraversable, tag, f, x::ConsF) = C.fmap(t -> ConsF(x.h, t), f(x.t))

    fromlist(v) = foldr((h, t) -> C.Fix(ConsF(h, t)), v; init = C.Fix(NilF()))
    listalg(::NilF) = Int[]
    listalg(x::ConsF) = pushfirst!(copy(x.t), x.h)
    tolist(l) = C.cata(listalg, l)

    # ---------------------------------------------------------------------------------------
    # Natural numbers: ZeroF | SuccF(p).
    struct ZeroF end
    struct SuccF{T}
        p::T
    end
    struct NatTag end
    C.constructorclass(::Type{<:Union{ZeroF, SuccF}}) = NatTag()
    C.FunctorStyle(::NatTag) = C.IsFunctor()
    C.fmap(::C.IsFunctor, f, x::ZeroF) = x
    C.fmap(::C.IsFunctor, f, x::SuccF) = SuccF(f(x.p))
    nat(n) = C.ana(k -> k == 0 ? ZeroF() : SuccF(k - 1), n)

    # ---------------------------------------------------------------------------------------
    # R6: a downstream-style plan node type, a closed Union of plain structs, its own base
    # functor (children fields are parametric so a layer can hold results).
    struct Source
        name::Symbol
    end
    struct Where{P, Ch}
        pred::P
        child::Ch
    end
    struct Select{Ch}
        cols::Tuple{Vararg{Symbol}}
        child::Ch
    end
    const PlanNode = Union{Source, Where, Select}
    struct PlanTag end
    C.constructorclass(::Type{<:PlanNode}) = PlanTag()
    C.FunctorStyle(::PlanTag) = C.IsFunctor()
    C.fmap(::C.IsFunctor, f, x::Source) = x
    C.fmap(::C.IsFunctor, f, x::Where) = Where(x.pred, f(x.child))
    C.fmap(::C.IsFunctor, f, x::Select) = Select(x.cols, f(x.child))

    const TABLES = Dict(:t => [(a = 1, b = 2), (a = 3, b = 4), (a = 5, b = 0)])
    evalplan(x::Source) = TABLES[x.name]
    evalplan(x::Where) = filter(x.pred, x.child)
    evalplan(x::Select) = [NamedTuple{x.cols}(r) for r in x.child]

    # Predicate pushdown with `para`: a `Where` whose ORIGINAL child is a `Select` moves below
    # it. Deciding on the original (not on the rewritten child) makes this one bottom-up step.
    pushdown(x::Source) = x
    pushdown(x::Select) = Select(x.cols, x.child[2])
    function pushdown(x::Where)
        orig, res = x.child
        return orig isa Select ? Select(res.cols, Where(x.pred, res.child)) : Where(x.pred, res)
    end
end
