using Pkg
using TOML

const SCRIPT_ROOT = @__DIR__
const ANALYZER_ROOT = normpath(joinpath(SCRIPT_ROOT, ".."))

function maybe_git_root(path::AbstractString)
    try
        return readchomp(pipeline(`git -C $path rev-parse --show-toplevel`; stderr = devnull))
    catch
        return nothing
    end
end

function flight_roots(path::AbstractString)
    roots = String[]
    current = abspath(path)
    while true
        root = maybe_git_root(current)
        if !isnothing(root) && root ∉ roots
            push!(roots, root)
        end
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return roots
end

function flight_env_path()
    if haskey(ENV, "WENDAO_ANALYZER_FLIGHT_ENV")
        path = abspath(ENV["WENDAO_ANALYZER_FLIGHT_ENV"])
        mkpath(path)
        return path
    end
    for root in flight_roots(SCRIPT_ROOT)
        parent = joinpath(root, ".cache", "julia")
        mkpath(parent)
        path = joinpath(parent, "wendaoanalyzer-flight-env-$(getpid())-$(Base.time_ns())")
        mkpath(path)
        return path
    end
    return mktempdir()
end

function maybe_override_wendaoarrow()
    haskey(ENV, "WENDAO_ANALYZER_WENDAOARROW_PATH") || return nothing
    candidate = abspath(ENV["WENDAO_ANALYZER_WENDAOARROW_PATH"])
    isdir(candidate) || error("WENDAO_ANALYZER_WENDAOARROW_PATH does not exist: $candidate")
    return candidate
end

function maybe_local_wendaoarrow()
    for root in flight_roots(SCRIPT_ROOT)
        candidate = joinpath(root, ".data", "WendaoArrow.jl")
        isdir(candidate) && return candidate
    end
    return nothing
end

function maybe_local_arrow_checkout()
    candidates = String[]
    if haskey(ENV, "PRJ_ROOT")
        push!(candidates, ENV["PRJ_ROOT"])
    end
    for root in flight_roots(SCRIPT_ROOT)
        push!(candidates, root)
    end
    for candidate_root in unique(normpath.(abspath.(candidates)))
        candidate = joinpath(candidate_root, ".data", "arrow-julia")
        isdir(candidate) || continue
        isfile(joinpath(candidate, "Project.toml")) || continue
        isfile(joinpath(candidate, "src", "ArrowTypes", "Project.toml")) || continue
        return candidate
    end
    return nothing
end

function declared_wendaoarrow_source()
    project = TOML.parsefile(joinpath(ANALYZER_ROOT, "Project.toml"))
    sources = get(project, "sources", Dict{String, Any}())
    source = get(sources, "WendaoArrow", nothing)
    source === nothing && error("WendaoAnalyzer Project.toml does not declare a WendaoArrow source")
    return source
end

function activate_flight_env()
    env_path = flight_env_path()
    if haskey(ENV, "WENDAO_ANALYZER_FLIGHT_ENV")
        for stale_file in ("Project.toml", "Manifest.toml")
            candidate = joinpath(env_path, stale_file)
            isfile(candidate) && rm(candidate; force = true)
        end
    end
    Pkg.activate(env_path)
    local_arrow = maybe_local_arrow_checkout()
    if !isnothing(local_arrow)
        Pkg.develop(
            [
                PackageSpec(path = local_arrow),
                PackageSpec(path = joinpath(local_arrow, "src", "ArrowTypes")),
            ],
        )
    end
    override = something(maybe_override_wendaoarrow(), maybe_local_wendaoarrow())
    if !isnothing(override)
        Pkg.develop(PackageSpec(path = override))
    else
        source = declared_wendaoarrow_source()
        Pkg.add(PackageSpec(url = source["url"], rev = source["rev"]))
    end
    Pkg.develop(PackageSpec(path = ANALYZER_ROOT))
    Pkg.add("Tables")
    Pkg.instantiate()
    return env_path
end

function main(args::Vector{String})
    activate_flight_env()
    empty!(ARGS)
    append!(ARGS, args)
    return include(joinpath(ANALYZER_ROOT, "examples", "analyzer_service.jl"))
end

main(copy(ARGS))
