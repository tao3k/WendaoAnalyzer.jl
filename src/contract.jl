abstract type AbstractAnalyzer end

struct AnalyzerConfig
    strategy::Symbol
    vector_weight::Float64
    similarity_weight::Float64
end

function AnalyzerConfig(;
    strategy::Symbol = :linear_blend,
    vector_weight::Real = 0.35,
    similarity_weight::Real = 0.65,
)
    strategy in (:linear_blend, :similarity_only, :vector_only) ||
        throw(ArgumentError("unsupported strategy: $(strategy)"))

    return AnalyzerConfig(
        strategy,
        Float64(vector_weight),
        Float64(similarity_weight),
    )
end

struct LinearBlendAnalyzer <: AbstractAnalyzer
    vector_weight::Float64
    similarity_weight::Float64
    ranking_reason::String
end

function LinearBlendAnalyzer(;
    vector_weight::Real = 0.35,
    similarity_weight::Real = 0.65,
)
    vector_weight >= 0 || throw(ArgumentError("vector_weight must be non-negative"))
    similarity_weight >= 0 || throw(ArgumentError("similarity_weight must be non-negative"))
    total_weight = Float64(vector_weight + similarity_weight)
    total_weight > 0 || throw(ArgumentError("at least one weight must be positive"))

    normalized_vector_weight = Float64(vector_weight) / total_weight
    normalized_similarity_weight = Float64(similarity_weight) / total_weight
    ranking_reason = "final_score=$(normalized_vector_weight)*vector_score+$(normalized_similarity_weight)*cosine_similarity"

    return LinearBlendAnalyzer(
        normalized_vector_weight,
        normalized_similarity_weight,
        ranking_reason,
    )
end

struct SimilarityOnlyAnalyzer <: AbstractAnalyzer
    ranking_reason::String
end

SimilarityOnlyAnalyzer() = SimilarityOnlyAnalyzer("final_score=cosine_similarity")

struct VectorScoreAnalyzer <: AbstractAnalyzer
    ranking_reason::String
end

VectorScoreAnalyzer() = VectorScoreAnalyzer("final_score=vector_score")

function build_analyzer(config::AnalyzerConfig)::AbstractAnalyzer
    if config.strategy == :linear_blend
        return LinearBlendAnalyzer(
            vector_weight = config.vector_weight,
            similarity_weight = config.similarity_weight,
        )
    elseif config.strategy == :similarity_only
        return SimilarityOnlyAnalyzer()
    else
        return VectorScoreAnalyzer()
    end
end
