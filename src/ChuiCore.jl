"""
    ChuiCore

The functional-programming core of the Chui ecosystem: composition, algebraic structures with
law-test kits, and the monoids and aggregators that ChuiFrames' engine reuses.

Names come in three tiers (ADR-0005): a short exported vocabulary (`⨟`, `papply`, `chain`, the
`test_*_laws` kits, …); public names used qualified (`ChuiCore.combine`, `ChuiCore.Sum`,
`ChuiCore.fmap`, …); and internal names with no stability promise. See `docs/agent/BRIEF.md`.
"""
module ChuiCore

using Compat: @compat
using CompositionsBase: ⨟, opcompose

include("compose.jl")
include("laws.jl")
include("algebra/algebra.jl")
include("classes/classes.jl")
include("transducers/transducers.jl")
include("transducers/folds.jl")
include("names.jl")

# Exported tier (ADR-0005 §3). Each name passes the clash list (test/exports/).
export ⨟, opcompose                       # CompositionsBase's binding (ADR-0006, CC-001)
export papply, pipe, flip                 # composition helpers
export chain, alt, zeroalt                # Monad, Alternative
export contramap, bimap, dimap, lmap, rmap
export idarrow, arr, arrfirst, arrsecond, arrsplit, fanout
export test_semigroup_laws, test_monoid_laws, test_aggregator_laws
export test_functor_laws, test_applicative_laws, test_monad_laws, test_alternative_laws
export test_foldable_laws, test_traversable_laws
export test_contravariant_laws, test_bifunctor_laws, test_profunctor_laws
export test_category_laws, test_arrow_laws

end # module ChuiCore
