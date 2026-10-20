# ChuiCore benchmark suite (ADR-0009; ecosystem ADR-0011). AirspeedVelocity and
# `julia scripts/ci.jl bench` both load this file and run `SUITE`, a BenchmarkTools group.
# Only public API, so the same file runs against the merge base. Inputs are built once here, outside
# the timed expressions, and interpolated with `$`.
#
#   julia --project=benchmark -e 'using Pkg; Pkg.develop(path = "."); include("benchmark/benchmarks.jl"); run(SUITE; verbose = true)'
#   benchpkg ChuiCore --rev=main,dirty --path=.        # AirspeedVelocity CLI (ADR-0011)
using BenchmarkTools
using ChuiCore
const C = ChuiCore

const SUITE = BenchmarkGroup()

# ---------------------------------------------------------------------------------------------
# Inputs. 10^4 elements: large enough that per-call overhead does not dominate, small enough to
# stay in L1/L2.
const N = 10_000
const VF = collect(range(-1.0, 1.0; length = N))
const VI = collect(1:N)
const VIEW = view(VF, 1:(N ÷ 2))
const GEN = (x for x in VF)
const PARTS4 = [view(VF, (1 + (k - 1) * (N ÷ 4)):(k * (N ÷ 4))) for k in 1:4]

# Recursion-scheme fixtures: a downstream-style node type that is its own base functor (untyped
# children, research A1) and the same tree wrapped in `Fix`. Depth 9: 1023 nodes.
struct BLit
    v::Int
end
struct BAdd
    l::Any
    r::Any
end
struct BTag end
C.constructorclass(::Type{<:Union{BLit, BAdd}}) = BTag()
C.FunctorStyle(::BTag) = C.IsFunctor()
C.fmap(::C.IsFunctor, f, x::BLit) = x
C.fmap(::C.IsFunctor, f, x::BAdd) = BAdd(f(x.l), f(x.r))
beval(x::BLit) = x.v
beval(x::BAdd) = x.l + x.r
bown(d) = d == 0 ? BLit(1) : BAdd(bown(d - 1), bown(d - 1))
bfix(d) = d == 0 ? C.Fix(BLit(1)) : C.Fix(BAdd(bfix(d - 1), bfix(d - 1)))
const TREE_OWN = bown(9)
const TREE_FIX = bfix(9)
bpara(x::BLit) = 1
bpara(x::BAdd) = x.l[2] + x.r[2]

# ---------------------------------------------------------------------------------------------
# Aggregators: one `partial` over a chunk, then `combine` and `final` (CC-004).
const AGG = SUITE["aggregators"] = BenchmarkGroup(["aggregators"])
for (name, agg) in (
        ("Sum", C.Sum()), ("Count", C.Count()), ("Mean", C.Mean()), ("Max", C.Max()),
        ("Extrema", C.Extrema()), ("Last", C.Last()), ("Var", C.Moments(:var)),
    )
    AGG["partial", name, "Vector{Float64}"] = @benchmarkable C.partial($agg, C.init($agg), $VF)
    AGG["partial", name, "SubArray"] = @benchmarkable C.partial($agg, C.init($agg), $VIEW)
    AGG["partial", name, "generator"] = @benchmarkable C.partial($agg, C.init($agg), $GEN)
    acc = C.partial(agg, C.init(agg), VF)
    AGG["combine+final", name] = @benchmarkable C.final($agg, C.combine($agg, $acc, $acc))
end
AGG["partial", "Sum", "Vector{Int}"] = @benchmarkable C.partial(C.Sum(), 0, $VI)

# ---------------------------------------------------------------------------------------------
# Transducer folds over chunks (ADR-0003).
const XF = SUITE["transducers"] = BenchmarkGroup(["transducers"])
const MF = C.Map(abs) ⨟ C.Filter(>(0.5))
XF["foldxl", "Map⨟Filter", "Vector"] = @benchmarkable C.foldxl(+, $MF, $VF; init = 0.0)
XF["foldxl", "Map⨟Filter", "SubArray"] = @benchmarkable C.foldxl(+, $MF, $VIEW; init = 0.0)
XF["foldxl", "Take(N/2)"] = @benchmarkable C.foldxl(+, C.Take($(N ÷ 2)), $VF; init = 0.0)
XF["foldxl", "Scan"] = @benchmarkable C.foldxl(+, C.Scan(+, 0.0), $VF; init = 0.0)
XF["foldxl", "MapCat"] = @benchmarkable C.foldxl(+, C.MapCat(x -> (x, -x)), $VF; init = 0.0)
XF["foldxl", "Partition(100)"] =
    @benchmarkable C.foldxl((a, p) -> a + length(p), C.Partition{Float64}(100), $VF; init = 0)
XF["aggregate", "Sum", "4 parts"] = @benchmarkable C.aggregate(C.Sum(), C.Map(abs), $PARTS4)
XF["aggregate", "Mean", "4 parts"] = @benchmarkable C.aggregate(C.Mean(), $MF, $PARTS4)

# ---------------------------------------------------------------------------------------------
# Recursion schemes over a 1023-node tree.
const RS = SUITE["schemes"] = BenchmarkGroup(["schemes"])
RS["cata", "own node type"] = @benchmarkable C.cata(beval, $TREE_OWN)
RS["cata", "Fix"] = @benchmarkable C.cata(beval, $TREE_FIX)
RS["para", "own node type"] = @benchmarkable C.para(bpara, $TREE_OWN)

# ---------------------------------------------------------------------------------------------
# Composition (the call cost of the composed value, not its construction).
const CO = SUITE["compose"] = BenchmarkGroup(["compose"])
const H3 = sin ⨟ cos ⨟ abs
const PA = papply(+, 1.0)
const FL = flip(-)
CO["⨟ (3 functions)"] = @benchmarkable $H3(x) setup = (x = 0.5)
CO["pipe (3 functions)"] = @benchmarkable pipe(x, sin, cos, abs) setup = (x = 0.5)
CO["papply"] = @benchmarkable $PA(x) setup = (x = 0.5)
CO["flip"] = @benchmarkable $FL(x, 2.0) setup = (x = 0.5)
