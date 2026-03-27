function columnar_input(table)
    if table isa NamedTuple
        return table
    end

    names = Tuple(propertynames(table))
    values = map(name -> getproperty(table, name), names)
    return NamedTuple{names}(Tuple(values))
end

function cosine_similarity(embedding, query_embedding)::Float64
    embedding_norm = norm(embedding)
    query_norm = norm(query_embedding)

    if embedding_norm == 0 || query_norm == 0
        return 0.0
    end

    return Float64(dot(embedding, query_embedding) / (embedding_norm * query_norm))
end

analyzer_ranking_reason(analyzer::LinearBlendAnalyzer) = analyzer.ranking_reason
analyzer_ranking_reason(analyzer::SimilarityOnlyAnalyzer) = analyzer.ranking_reason
analyzer_ranking_reason(analyzer::VectorScoreAnalyzer) = analyzer.ranking_reason

final_score_for(
    analyzer::LinearBlendAnalyzer,
    vector_score::Float64,
    similarity::Float64,
) = analyzer.vector_weight * vector_score + analyzer.similarity_weight * similarity

final_score_for(
    ::SimilarityOnlyAnalyzer,
    ::Float64,
    similarity::Float64,
) = similarity

final_score_for(
    ::VectorScoreAnalyzer,
    vector_score::Float64,
    ::Float64,
) = vector_score

function analyze_table(
    table;
    analyzer::AbstractAnalyzer = build_analyzer(AnalyzerConfig()),
)
    columns = columnar_input(table)

    doc_ids = collect(getproperty(columns, REQUEST_DOC_ID_COLUMN))
    vector_scores = getproperty(columns, REQUEST_VECTOR_SCORE_COLUMN)
    embeddings = getproperty(columns, REQUEST_EMBEDDING_COLUMN)
    query_embeddings = getproperty(columns, REQUEST_QUERY_EMBEDDING_COLUMN)

    row_count = length(doc_ids)
    analyzer_scores = Vector{Float64}(undef, row_count)
    final_scores = Vector{Float64}(undef, row_count)
    ranking_reasons = fill(analyzer_ranking_reason(analyzer), row_count)

    for index in eachindex(doc_ids)
        similarity = cosine_similarity(embeddings[index], query_embeddings[index])
        vector_score = Float64(vector_scores[index])

        analyzer_scores[index] = similarity
        final_scores[index] = final_score_for(analyzer, vector_score, similarity)
    end

    return (
        doc_id = doc_ids,
        analyzer_score = analyzer_scores,
        final_score = final_scores,
        ranking_reason = ranking_reasons,
    )
end

function analyze_stream(
    stream;
    analyzer::AbstractAnalyzer = build_analyzer(AnalyzerConfig()),
)
    doc_ids = String[]
    analyzer_scores = Float64[]
    final_scores = Float64[]
    ranking_reasons = String[]

    for batch in stream
        result = analyze_table(batch; analyzer = analyzer)
        append!(doc_ids, result.doc_id)
        append!(analyzer_scores, result.analyzer_score)
        append!(final_scores, result.final_score)
        append!(ranking_reasons, result.ranking_reason)
    end

    return (
        doc_id = doc_ids,
        analyzer_score = analyzer_scores,
        final_score = final_scores,
        ranking_reason = ranking_reasons,
    )
end
