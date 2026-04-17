using Test
using TOML
using WendaoAnalyzer

@testset "package version stays on the locked beta boundary" begin
    @test pkgversion(WendaoAnalyzer) == v"0.2.0"
end

@testset "package declares WendaoArrow as a formal Flight dependency" begin
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    @test haskey(project["deps"], "WendaoArrow")
    @test project["deps"]["WendaoArrow"] == "561c8d8d-4bcf-4807-873b-a6b7d1e55843"
    source = get(project, "sources", Dict{String, Any}())["WendaoArrow"]
    @test source["url"] == "https://github.com/tao3k/WendaoArrow.jl.git"
    @test source["rev"] == "1631e7a7ed864d94f90f11c3cf732f83b9a39d87"
end

@testset "load_analyzer_runtime_config reads TOML strategy" begin
    temp_dir = mktempdir()
    config_path = joinpath(temp_dir, "analyzer.toml")
    write(
        config_path,
        """
        [analyzer]
        strategy = "linear_blend"
        vector_weight = 2
        similarity_weight = 6
        """,
    )

    runtime = load_analyzer_runtime_config(config_path)
    @test runtime.analyzer isa LinearBlendAnalyzer
    @test runtime.analyzer.vector_weight == 0.25
    @test runtime.analyzer.similarity_weight == 0.75
end

@testset "split_runtime_args separates analyzer flags" begin
    analyzer_args, wendaoarrow_args = split_runtime_args([
        "--analyzer-strategy",
        "similarity_only",
        "--vector-weight=0.2",
        "--port",
        "18080",
    ])

    @test analyzer_args == ["--analyzer-strategy", "similarity_only", "--vector-weight=0.2"]
    @test wendaoarrow_args == ["--port", "18080"]
end

@testset "analyzer_runtime_from_args resolves flags" begin
    runtime = analyzer_runtime_from_args([
        "--analyzer-strategy",
        "vector_only",
    ])
    @test runtime.analyzer isa VectorScoreAnalyzer

    weighted = analyzer_runtime_from_args([
        "--analyzer-strategy=linear_blend",
        "--vector-weight=2",
        "--similarity-weight=6",
    ])
    @test weighted.analyzer isa LinearBlendAnalyzer
    @test weighted.analyzer.vector_weight == 0.25
    @test weighted.analyzer.similarity_weight == 0.75
end

@testset "analyzer_service_contract_from_args preserves analyzer and passthrough args" begin
    temp_dir = mktempdir()
    config_path = joinpath(temp_dir, "analyzer.toml")
    write(
        config_path,
        """
        [analyzer]
        strategy = "vector_only"
        vector_weight = 1
        similarity_weight = 0
        """,
    )

    contract = analyzer_service_contract_from_args([
        "--analyzer-strategy",
        "similarity_only",
        "--analyzer-config",
        config_path,
        "--port",
        "18080",
    ])

    @test contract.runtime.analyzer isa SimilarityOnlyAnalyzer
    @test contract.wendaoarrow_args == ["--port", "18080"]
end

@testset "analyzer_service_descriptor_from_args resolves service mode" begin
    stream_descriptor = analyzer_service_descriptor_from_args([
        "--service-mode",
        "stream",
        "--port",
        "18080",
    ])
    @test stream_descriptor.service_mode == :stream
    @test stream_descriptor.contract.wendaoarrow_args == ["--port", "18080"]

    table_descriptor = analyzer_service_descriptor_from_args([
        "--service-mode=table",
        "--analyzer-strategy=vector_only",
    ])
    @test table_descriptor.service_mode == :table
    @test table_descriptor.contract.runtime.analyzer isa VectorScoreAnalyzer
end

@testset "AnalyzerConfig builds typed strategies" begin
    @test build_analyzer(AnalyzerConfig()) isa LinearBlendAnalyzer
    @test build_analyzer(AnalyzerConfig(strategy = :similarity_only)) isa SimilarityOnlyAnalyzer
    @test build_analyzer(AnalyzerConfig(strategy = :vector_only)) isa VectorScoreAnalyzer
end

@testset "LinearBlendAnalyzer normalizes weights" begin
    analyzer = LinearBlendAnalyzer(vector_weight = 2, similarity_weight = 6)
    @test analyzer.vector_weight == 0.25
    @test analyzer.similarity_weight == 0.75
end

@testset "cosine_similarity handles zero norm" begin
    @test cosine_similarity(Float32[0, 0], Float32[1, 0]) == 0.0
end

@testset "analyze_table emits WendaoArrow contract columns" begin
    table = (
        doc_id = ["alpha", "beta"],
        vector_score = Float64[0.2, 0.8],
        embedding = [Float32[1, 0], Float32[0, 1]],
        query_embedding = [Float32[1, 0], Float32[1, 0]],
    )

    result = analyze_table(table)

    @test result.doc_id == ["alpha", "beta"]
    @test result.analyzer_score[1] ≈ 1.0
    @test result.analyzer_score[2] ≈ 0.0
    @test result.final_score[1] ≈ (0.35 * 0.2 + 0.65 * 1.0)
    @test result.final_score[2] ≈ (0.35 * 0.8 + 0.65 * 0.0)
    @test all(reason == first(result.ranking_reason) for reason in result.ranking_reason)
end

@testset "alternate strategies keep contract shape" begin
    table = (
        doc_id = ["alpha", "beta"],
        vector_score = Float64[0.2, 0.8],
        embedding = [Float32[1, 0], Float32[0, 1]],
        query_embedding = [Float32[1, 0], Float32[1, 0]],
    )

    similarity_only = analyze_table(
        table;
        analyzer = build_analyzer(AnalyzerConfig(strategy = :similarity_only)),
    )
    vector_only = analyze_table(
        table;
        analyzer = build_analyzer(AnalyzerConfig(strategy = :vector_only)),
    )

    @test similarity_only.doc_id == ["alpha", "beta"]
    @test similarity_only.final_score[1] ≈ 1.0
    @test similarity_only.final_score[2] ≈ 0.0
    @test similarity_only.ranking_reason[1] == "final_score=cosine_similarity"

    @test vector_only.doc_id == ["alpha", "beta"]
    @test vector_only.final_score == [0.2, 0.8]
    @test vector_only.ranking_reason[1] == "final_score=vector_score"
end

@testset "analyze_stream folds batches into one contract-shaped response" begin
    stream = [
        (
            doc_id = ["alpha"],
            vector_score = Float64[0.2],
            embedding = [Float32[1, 0]],
            query_embedding = [Float32[1, 0]],
        ),
        (
            doc_id = ["beta"],
            vector_score = Float64[0.8],
            embedding = [Float32[0, 1]],
            query_embedding = [Float32[1, 0]],
        ),
    ]

    result = analyze_stream(stream)

    @test result.doc_id == ["alpha", "beta"]
    @test length(result.analyzer_score) == 2
    @test length(result.final_score) == 2
    @test length(result.ranking_reason) == 2
end

@testset "processor builders stay callable" begin
    table_processor = build_table_processor()
    stream_processor = build_stream_processor()
    vector_only_processor =
        build_table_processor(analyzer = build_analyzer(AnalyzerConfig(strategy = :vector_only)))
    table = (
        doc_id = ["alpha"],
        vector_score = Float64[0.4],
        embedding = [Float32[1, 0]],
        query_embedding = [Float32[1, 0]],
    )

    @test table_processor(table).doc_id == ["alpha"]
    @test stream_processor([table]).doc_id == ["alpha"]
    @test vector_only_processor(table).final_score == [0.4]
end
