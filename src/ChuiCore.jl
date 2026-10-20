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
using ConstructionBase: setproperties     # optics rebuild structs through it (ADR-0008)
using PrecompileTools: @compile_workload, @setup_workload   # the workload (ADR-0010)

include("compose.jl")
include("laws.jl")
include("algebra/algebra.jl")
include("classes/classes.jl")
include("transducers/transducers.jl")
include("transducers/folds.jl")
include("schemes/schemes.jl")
include("schemes/free.jl")
include("optics/optics.jl")
include("lazy.jl")
include("banner.jl")
include("names.jl")
include("precompile.jl")                  # last: the workload calls the code above

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
export test_lens_laws, test_prism_laws

# The name-conflict banner (docs/agent/BRIEF.md): interactive sessions only, silenced by
# CHUI_QUIET_CONFLICTS, never throws (src/banner.jl). Non-interactive loads pay one global read.
# `invokelatest` is a deliberate inference barrier: a direct call lets the precompiled `__init__`
# pull the whole banner into the package image (~0.3 MB of native code, about +3-5 ms on every
# `using ChuiCore` on Julia 1.10). The price is compiling the banner in interactive sessions
# (about 0.25-0.3 s; docs/src/tutorials/conflict-banner.md cites the measurements).
function __init__()
    isinteractive() && Base.invokelatest(_init_banner, stderr, @__MODULE__)
    return nothing
end

end # module ChuiCore
