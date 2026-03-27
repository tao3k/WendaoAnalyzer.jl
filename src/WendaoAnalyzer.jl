module WendaoAnalyzer

using LinearAlgebra
using TOML

const REQUEST_DOC_ID_COLUMN = :doc_id
const REQUEST_VECTOR_SCORE_COLUMN = :vector_score
const REQUEST_EMBEDDING_COLUMN = :embedding
const REQUEST_QUERY_EMBEDDING_COLUMN = :query_embedding

const RESPONSE_DOC_ID_COLUMN = :doc_id
const RESPONSE_ANALYZER_SCORE_COLUMN = :analyzer_score
const RESPONSE_FINAL_SCORE_COLUMN = :final_score
const RESPONSE_RANKING_REASON_COLUMN = :ranking_reason

include("contract.jl")
include("runtime_config.jl")
include("scoring.jl")
include("processors.jl")

export AbstractAnalyzer
export AnalyzerConfig
export AnalyzerRuntimeConfig
export AnalyzerServiceContract
export AnalyzerServiceDescriptor
export LinearBlendAnalyzer
export SimilarityOnlyAnalyzer
export VectorScoreAnalyzer
export analyze_table
export analyze_stream
export analyzer_service_contract_from_args
export analyzer_service_descriptor_from_args
export analyzer_runtime_from_args
export build_analyzer
export build_table_processor
export build_stream_processor
export cosine_similarity
export columnar_input
export load_analyzer_runtime_config
export split_runtime_args

end
