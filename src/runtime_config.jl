Base.@kwdef struct AnalyzerRuntimeConfig
    analyzer::AbstractAnalyzer = build_analyzer(AnalyzerConfig())
end

Base.@kwdef struct AnalyzerServiceContract
    runtime::AnalyzerRuntimeConfig = AnalyzerRuntimeConfig()
    wendaoarrow_args::Vector{String} = String[]
end

Base.@kwdef struct AnalyzerServiceDescriptor
    service_mode::Symbol = :stream
    contract::AnalyzerServiceContract = AnalyzerServiceContract()
end

function load_analyzer_runtime_config(path::AbstractString)::AnalyzerRuntimeConfig
    parsed = TOML.parsefile(path)
    section = get(parsed, "analyzer", Dict{String, Any}())

    config = AnalyzerConfig(
        strategy = Symbol(get(section, "strategy", "linear_blend")),
        vector_weight = Float64(get(section, "vector_weight", 0.35)),
        similarity_weight = Float64(get(section, "similarity_weight", 0.65)),
    )

    return AnalyzerRuntimeConfig(analyzer = build_analyzer(config))
end

function split_runtime_args(args::Vector{String})
    analyzer_args = String[]
    wendaoarrow_args = String[]

    index = 1
    while index <= length(args)
        argument = args[index]
        if startswith(argument, "--analyzer-config=") ||
           startswith(argument, "--analyzer-strategy=") ||
           startswith(argument, "--service-mode=") ||
           startswith(argument, "--vector-weight=") ||
           startswith(argument, "--similarity-weight=")
            push!(analyzer_args, argument)
        elseif argument in (
            "--analyzer-config",
            "--analyzer-strategy",
            "--service-mode",
            "--vector-weight",
            "--similarity-weight",
        )
            push!(analyzer_args, argument)
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for $argument"))
            push!(analyzer_args, args[index])
        else
            push!(wendaoarrow_args, argument)
            if argument in ("--config", "--host", "--port", "--route", "--health-route", "--content-type")
                index += 1
                index <= length(args) || throw(ArgumentError("missing value for $argument"))
                push!(wendaoarrow_args, args[index])
            end
        end
        index += 1
    end

    return analyzer_args, wendaoarrow_args
end

function analyzer_runtime_from_args(args::Vector{String})::AnalyzerRuntimeConfig
    config_path = nothing
    strategy = nothing
    vector_weight = nothing
    similarity_weight = nothing

    index = 1
    while index <= length(args)
        argument = args[index]
        if startswith(argument, "--analyzer-config=")
            config_path = split(argument, "=", limit = 2)[2]
        elseif argument == "--analyzer-config"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --analyzer-config"))
            config_path = args[index]
        elseif startswith(argument, "--analyzer-strategy=")
            strategy = split(argument, "=", limit = 2)[2]
        elseif argument == "--analyzer-strategy"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --analyzer-strategy"))
            strategy = args[index]
        elseif startswith(argument, "--service-mode=")
            nothing
        elseif argument == "--service-mode"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --service-mode"))
        elseif startswith(argument, "--vector-weight=")
            vector_weight = parse(Float64, split(argument, "=", limit = 2)[2])
        elseif argument == "--vector-weight"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --vector-weight"))
            vector_weight = parse(Float64, args[index])
        elseif startswith(argument, "--similarity-weight=")
            similarity_weight = parse(Float64, split(argument, "=", limit = 2)[2])
        elseif argument == "--similarity-weight"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --similarity-weight"))
            similarity_weight = parse(Float64, args[index])
        else
            throw(ArgumentError("unsupported analyzer argument: $argument"))
        end
        index += 1
    end

    base = isnothing(config_path) ? AnalyzerRuntimeConfig() : load_analyzer_runtime_config(config_path)
    base_config = if base.analyzer isa LinearBlendAnalyzer
        AnalyzerConfig(
            strategy = :linear_blend,
            vector_weight = base.analyzer.vector_weight,
            similarity_weight = base.analyzer.similarity_weight,
        )
    elseif base.analyzer isa SimilarityOnlyAnalyzer
        AnalyzerConfig(strategy = :similarity_only)
    else
        AnalyzerConfig(strategy = :vector_only)
    end

    resolved = AnalyzerConfig(
        strategy = isnothing(strategy) ? base_config.strategy : Symbol(strategy),
        vector_weight = isnothing(vector_weight) ? base_config.vector_weight : vector_weight,
        similarity_weight = isnothing(similarity_weight) ? base_config.similarity_weight : similarity_weight,
    )

    return AnalyzerRuntimeConfig(analyzer = build_analyzer(resolved))
end

function analyzer_service_contract_from_args(args::Vector{String})::AnalyzerServiceContract
    analyzer_args, wendaoarrow_args = split_runtime_args(args)
    return AnalyzerServiceContract(
        runtime = analyzer_runtime_from_args(analyzer_args),
        wendaoarrow_args = wendaoarrow_args,
    )
end

function analyzer_service_descriptor_from_args(args::Vector{String})::AnalyzerServiceDescriptor
    service_mode = :stream
    index = 1
    while index <= length(args)
        argument = args[index]
        if startswith(argument, "--service-mode=")
            service_mode = Symbol(split(argument, "=", limit = 2)[2])
        elseif argument == "--service-mode"
            index += 1
            index <= length(args) || throw(ArgumentError("missing value for --service-mode"))
            service_mode = Symbol(args[index])
        end
        index += 1
    end

    service_mode in (:stream, :table) ||
        throw(ArgumentError("unsupported service mode: $service_mode"))

    return AnalyzerServiceDescriptor(
        service_mode = service_mode,
        contract = analyzer_service_contract_from_args(args),
    )
end
