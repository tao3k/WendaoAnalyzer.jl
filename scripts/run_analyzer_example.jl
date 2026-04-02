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

function locate_grpcserver()
    if haskey(ENV, "WENDAO_FLIGHT_GRPCSERVER_PATH")
        candidate = abspath(ENV["WENDAO_FLIGHT_GRPCSERVER_PATH"])
        isdir(candidate) || error("WENDAO_FLIGHT_GRPCSERVER_PATH does not exist: $candidate")
        return candidate
    end
    for root in flight_roots(SCRIPT_ROOT)
        candidate = joinpath(root, ".cache", "vendor", "gRPCServer.jl")
        isdir(candidate) && return candidate
    end
    error(
        "Could not locate vendored gRPCServer.jl. " *
        "Set WENDAO_FLIGHT_GRPCSERVER_PATH to an explicit checkout path.",
    )
end

function flight_env_path()
    if haskey(ENV, "WENDAO_ANALYZER_FLIGHT_ENV")
        path = abspath(ENV["WENDAO_ANALYZER_FLIGHT_ENV"])
        mkpath(path)
        return path
    end
    for root in flight_roots(SCRIPT_ROOT)
        path = joinpath(root, ".cache", "julia", "wendaoanalyzer-flight-env")
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

function declared_wendaoarrow_source()
    project = TOML.parsefile(joinpath(ANALYZER_ROOT, "Project.toml"))
    sources = get(project, "sources", Dict{String, Any}())
    source = get(sources, "WendaoArrow", nothing)
    source === nothing && error("WendaoAnalyzer Project.toml does not declare a WendaoArrow source")
    return source
end

function activate_flight_env()
    env_path = flight_env_path()
    Pkg.activate(env_path)
    Pkg.develop(PackageSpec(path = ANALYZER_ROOT))
    if let override = maybe_override_wendaoarrow()
        Pkg.develop(PackageSpec(path = override))
    else
        source = declared_wendaoarrow_source()
        Pkg.add(PackageSpec(url = source["url"], rev = source["rev"]))
    end
    Pkg.develop(PackageSpec(path = locate_grpcserver()))
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
