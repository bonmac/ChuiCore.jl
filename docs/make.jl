# Build with `julia scripts/ci.jl docs` (develops this checkout into docs/, then runs this file).
# Layout: ecosystem ADR-0008 (tutorials / howto / explanation / reference / changelog).
using Documenter
using ChuiCore

DocMeta.setdocmeta!(ChuiCore, :DocTestSetup, :(using ChuiCore); recursive = true)

# The changelog page is generated from CHANGELOG.md on every build (gitignored in docs/.gitignore),
# so the site never shows a stale copy.
let src = joinpath(@__DIR__, "..", "CHANGELOG.md"), dst = joinpath(@__DIR__, "src", "changelog.md")
    write(dst, "```@meta\nEditURL = \"../../CHANGELOG.md\"\n```\n\n", read(src, String))
end

# No git remote exists until the user approves pushing (common.md §1.6, ADR-0008). Until then
# source links are off; set CHUI_DOCS_REPO (e.g. "github.com/<owner>/ChuiCore.jl") to turn on
# source links and deployment.
const REPO = get(ENV, "CHUI_DOCS_REPO", "")
const REMOTE_KW = isempty(REPO) ? (; remotes = nothing) : (;)

makedocs(;
    modules = [ChuiCore],
    sitename = "ChuiCore.jl",
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", "false") == "true"),
    pages = [
        "Home" => "index.md",
        "Tutorials" => [
            "Composition" => "tutorials/composition.md",
            "Monoids and aggregators" => "tutorials/monoids.md",
            "Typeclasses and your own instance" => "tutorials/typeclasses.md",
            "Law kits for downstream packages" => "tutorials/law-kits.md",
            "Transducers" => "tutorials/transducers.md",
            "Recursion schemes" => "tutorials/recursion-schemes.md",
            "Free monads and interpreters" => "tutorials/free-monads.md",
            "Optics" => "tutorials/optics.md",
            "Laziness" => "tutorials/laziness.md",
            "The conflict banner" => "tutorials/conflict-banner.md",
        ],
        "How-to recipes" => "howto/recipes.md",
        "Explanation" => [
            "Why ChuiCore" => "explanation/why.md",
            "Purity and effects" => "explanation/purity-effects.md",
            "Export tiers and the clash list" => "explanation/export-tiers.md",
            "Runtime cost model" => "explanation/cost-model.md",
            # Kept at its phase-4 path: ADR-0009/0010 and benchmark/allocs.jl cite it.
            "Performance measurements" => "performance.md",
        ],
        "Reference" => [
            "Composition and law kits" => "reference/core.md",
            "Monoids and aggregators" => "reference/algebra.md",
            "Typeclasses" => "reference/classes.md",
            "Transducers" => "reference/transducers.md",
            "Recursion schemes and free monads" => "reference/schemes.md",
            "Optics" => "reference/optics.md",
            "Laziness and the banner" => "reference/lazy.md",
            "Internals" => "reference/internals.md",
        ],
        "Changelog" => "changelog.md",
    ],
    REMOTE_KW...,
)

isempty(REPO) || deploydocs(; repo = REPO, devbranch = "main", push_preview = false)
