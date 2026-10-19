# Build with `julia scripts/ci.jl docs` (develops this checkout into docs/, then runs this file).
using Documenter
using ChuiCore

DocMeta.setdocmeta!(ChuiCore, :DocTestSetup, :(using ChuiCore); recursive = true)

# No git remote exists until the user approves pushing (common.md §1.6, ADR-0008). Until then
# source links are off; set CHUI_DOCS_REPO (e.g. "github.com/<owner>/ChuiCore.jl") to turn on
# source links and deployment.
const REPO = get(ENV, "CHUI_DOCS_REPO", "")
const REMOTE_KW = isempty(REPO) ? (; remotes = nothing) : (;)

makedocs(;
    modules = [ChuiCore],
    sitename = "ChuiCore.jl",
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", "false") == "true"),
    pages = ["Home" => "index.md"],
    REMOTE_KW...,
)

isempty(REPO) || deploydocs(; repo = REPO, devbranch = "main", push_preview = false)
