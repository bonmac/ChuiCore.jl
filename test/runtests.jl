# Seeded by the ecosystem factory. Test items (TestItemRunner, ADR-0007) are selected by tag:
#   julia scripts/ci.jl test                 -> everything except the tags in EXCLUDE
#   julia scripts/ci.jl test -- laws unit    -> only items tagged :laws or :unit
#   julia scripts/ci.jl test -- all          -> every item except :contract
# :contract items run in their own environment (test/contracts/), via `julia scripts/ci.jl contracts`.
using TestItemRunner

# :doctest and :snapshot output depends on the Julia version, so they run on stable Julia only
# (ecosystem ADR-0008 §3). STABLE_MIN is the oldest Julia whose printed output they expect.
# CI_STABLE overrides it either way ("true" runs them, "false" skips them): CI.yml sets it on
# every job (true on '1', false on lts and pre). Unset, a plain `]test` decides by VERSION, so a
# fresh clone passes on the LTS too. JET is not here: see test/jet/.
const STABLE_MIN = v"1.13"
const STABLE = let v = get(ENV, "CI_STABLE", "")
    v == "true" ? true : v == "false" ? false : isempty(v) ? VERSION >= STABLE_MIN :
        throw(ArgumentError("CI_STABLE must be \"true\", \"false\" or unset, got $(repr(v))"))
end
const EXCLUDE = !STABLE ?
    (:slow, :quality, :contract, :differential, :doctest, :snapshot) :
    (:slow, :quality, :contract, :differential)
const SELECT = Symbol.(ARGS)
const ROOT = dirname(@__DIR__)
:contract in SELECT && @info "contract items run in test/contracts/'s own environment: julia scripts/ci.jl contracts"

@run_package_tests filter = ti -> begin
    # TestItemRunner scans the whole package directory: never pick up test items from lane
    # scratch copies or nested worktrees (both gitignored).
    first(splitpath(relpath(ti.filename, ROOT))) in (".lanes", ".worktrees") && return false
    :contract in ti.tags && return false
    :all in SELECT && return true
    isempty(SELECT) && return !any(in(EXCLUDE), ti.tags)
    return any(in(SELECT), ti.tags)
end
