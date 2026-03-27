function build_table_processor(;
    analyzer::AbstractAnalyzer = build_analyzer(AnalyzerConfig()),
)
    return table -> analyze_table(table; analyzer = analyzer)
end

function build_stream_processor(;
    analyzer::AbstractAnalyzer = build_analyzer(AnalyzerConfig()),
)
    return stream -> analyze_stream(stream; analyzer = analyzer)
end
