# WendaoAnalyzer

WendaoAnalyzer is the first standalone Julia analyzer package that sits on top of the WendaoArrow `v1` contract.

## What This Package Owns

WendaoAnalyzer does not own HTTP routing, Arrow IPC encode/decode, or transport-level validation.

- `WendaoArrow` owns the Julia-side Arrow IPC transport and HTTP handler composition.
- `WendaoAnalyzer` owns deterministic scoring over WendaoArrow `v1` request tables or streams.
- Rust continues to own request shaping, timeout policy, fallback, and response validation.

## Current Strategy

The first analyzer is a deterministic linear blend:

- `analyzer_score = cosine_similarity(embedding, query_embedding)`
- `final_score = 0.35 * vector_score + 0.65 * analyzer_score`

This keeps the analyzer explainable and stable while still demonstrating a real Julia-side rerank strategy.

The default response shape is:

- `doc_id`
- `analyzer_score`
- `final_score`
- `ranking_reason`

The first three columns match WendaoArrow `v1`. `ranking_reason` is additive.

The package now also exposes a small typed strategy surface:

- `AnalyzerConfig(strategy = :linear_blend, vector_weight = 0.35, similarity_weight = 0.65)`
- `AnalyzerConfig(strategy = :similarity_only)`
- `AnalyzerConfig(strategy = :vector_only)`

Use `build_analyzer(config)` when you want a stable typed analyzer instance
before wiring it into `analyze_table(...)`, `analyze_stream(...)`, or the
processor builders.

The example servers also support runtime selection:

- `--service-mode stream|table`
- `--analyzer-strategy linear_blend|similarity_only|vector_only`
- `--vector-weight <float>`
- `--similarity-weight <float>`
- `--analyzer-config .data/WendaoAnalyzer/config/analyzer.example.toml`

## Service Contract

`WendaoAnalyzer` treats service launch as a two-part contract:

- analyzer-owned flags are parsed by `WendaoAnalyzer`
- all remaining flags are passed through to `WendaoArrow`

The public Julia entrypoint for that contract is:

- `analyzer_service_contract_from_args(args::Vector{String})`
- `analyzer_service_descriptor_from_args(args::Vector{String})`

It resolves:

- `runtime::AnalyzerRuntimeConfig`
- `wendaoarrow_args::Vector{String}`
- `service_mode::Symbol`

The analyzer-owned flags are:

- `--service-mode stream|table`
- `--analyzer-config <path>`
- `--analyzer-strategy linear_blend|similarity_only|vector_only`
- `--vector-weight <float>`
- `--similarity-weight <float>`

The passthrough flags continue to belong to `WendaoArrow`, including:

- `--config`
- `--host`
- `--port`
- `--route`
- `--health-route`
- `--content-type`

## Public API

- `analyze_table(table; analyzer = LinearBlendAnalyzer())`
- `analyze_stream(stream; analyzer = LinearBlendAnalyzer())`
- `build_analyzer(config::AnalyzerConfig)`
- `analyzer_service_contract_from_args(args)`
- `analyzer_service_descriptor_from_args(args)`
- `build_table_processor(; analyzer = LinearBlendAnalyzer())`
- `build_stream_processor(; analyzer = LinearBlendAnalyzer())`

The builder helpers are intended to plug directly into `WendaoArrow.build_handler(...)` and `WendaoArrow.build_stream_handler(...)`.

## Examples

Start the generic analyzer service:

```bash
.data/WendaoAnalyzer/scripts/run_analyzer_service.sh --service-mode stream
```

Start the table-first analyzer server:

```bash
.data/WendaoAnalyzer/scripts/run_table_linear_blend_server.sh
```

Start the stream-first analyzer server:

```bash
.data/WendaoAnalyzer/scripts/run_stream_linear_blend_server.sh
```

Start the stream-first analyzer server with a runtime-selected strategy:

```bash
.data/WendaoAnalyzer/scripts/run_stream_linear_blend_server.sh --analyzer-strategy similarity_only --port 18080
```

Or load analyzer runtime settings from TOML:

```bash
.data/WendaoAnalyzer/scripts/run_stream_linear_blend_server.sh --analyzer-config .data/WendaoAnalyzer/config/analyzer.example.toml --port 18080
```

Pass analyzer and transport config together through the same service contract:

```bash
.data/WendaoAnalyzer/scripts/run_stream_linear_blend_server.sh \
  --analyzer-config .data/WendaoAnalyzer/config/analyzer.example.toml \
  --config .data/WendaoArrow/config/wendao_arrow.example.toml \
  --port 18080
```

The named stream/table scripts remain compatibility wrappers around the generic
`run_analyzer_service.sh` launcher. All of them load the local
`.data/WendaoArrow` package through `LOAD_PATH` before launch, so they can run
against the package in this repository without runtime package-manager mutation.

## Validation

```bash
direnv exec . julia --project=.data/WendaoAnalyzer -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Live e2e coverage also exists on the Rust side in
`xiuxian-wendao-julia` transport tests. Those tests boot
`.data/WendaoAnalyzer/scripts/run_stream_linear_blend_server.sh` and verify a
real HTTP Arrow IPC roundtrip against the analyzer-owned server.

There is now also a main-crate planned-search integration in `xiuxian-wendao`
that points the Julia rerank runtime at the same analyzer-owned stream server,
so the package is covered at both the transport layer and the higher-level
search-runtime layer.

`xiuxian-wendao` can now also express analyzer strategy preferences in its
`link_graph.retrieval.julia_rerank` runtime config through additive fields such
as `analyzer_strategy`, `vector_weight`, and `similarity_weight`. The current
main integration coverage proves those settings can drive a non-default
`similarity_only` analyzer selection against the analyzer-owned test server.
