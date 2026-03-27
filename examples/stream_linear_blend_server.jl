using Pkg

ROOT = joinpath(@__DIR__, "..")
ARROW_ROOT = joinpath(ROOT, "..", "WendaoArrow")

Pkg.activate(ROOT)
pushfirst!(LOAD_PATH, ARROW_ROOT)

using WendaoAnalyzer
include(joinpath(@__DIR__, "analyzer_service.jl"))
