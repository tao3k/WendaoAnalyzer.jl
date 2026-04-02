# WendaoAnalyzer

WendaoAnalyzer is the first standalone Julia analyzer package that sits on top of the WendaoArrow `v1` contract.

The current package boundary is intentionally lockable as `0.2.0`.

## What This Package Owns

WendaoAnalyzer does not own browser HTTP routing or Arrow Flight transport-level validation.

- `WendaoArrow` is now a formal package dependency of `WendaoAnalyzer`, and its default source is a pinned GitHub revision instead of an implicit sibling-checkout assumption.
- `WendaoArrow` owns the Julia-side Arrow Flight service composition and request/response contract validation.
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
- `--analyzer-config config/analyzer.example.toml`

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

## Public API

- `analyze_table(table; analyzer = LinearBlendAnalyzer())`
- `analyze_stream(stream; analyzer = LinearBlendAnalyzer())`
- `build_analyzer(config::AnalyzerConfig)`
- `analyzer_service_contract_from_args(args)`
- `analyzer_service_descriptor_from_args(args)`
- `build_table_processor(; analyzer = LinearBlendAnalyzer())`
- `build_stream_processor(; analyzer = LinearBlendAnalyzer())`

The builder helpers are intended to plug directly into
`WendaoArrow.build_flight_service(...)` and
`WendaoArrow.build_stream_flight_service(...)`.

## Examples

Start the generic analyzer service:

```bash
scripts/run_analyzer_service.sh --service-mode stream
```

Start the table-first analyzer server:

```bash
scripts/run_table_linear_blend_server.sh
```

Start the stream-first analyzer server:

```bash
scripts/run_stream_linear_blend_server.sh
```

Start the stream-first analyzer server with a runtime-selected strategy:

```bash
scripts/run_stream_linear_blend_server.sh --analyzer-strategy similarity_only --port 18080
```

Or load analyzer runtime settings from TOML:

```bash
scripts/run_stream_linear_blend_server.sh --analyzer-config config/analyzer.example.toml --port 18080
```

Pass analyzer and transport config together through the same service contract:

```bash
scripts/run_stream_linear_blend_server.sh \
  --analyzer-config config/analyzer.example.toml \
  --config ../WendaoArrow/config/wendao_arrow.example.toml \
  --port 18080
```

The named stream/table scripts remain compatibility wrappers around the generic
`run_analyzer_service.sh` launcher. The launcher bootstraps a cached Flight
environment under `.cache/julia/wendaoanalyzer-flight-env`, develops the local
`WendaoAnalyzer`, resolves the pinned `WendaoArrow` GitHub source declared by
this package, develops vendored `gRPCServer.jl`, then includes the example
entrypoint. Set `WENDAO_ANALYZER_WENDAOARROW_PATH` if you explicitly want to
override that default with a local `WendaoArrow` checkout.

## Validation

```bash
direnv exec . julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Live e2e coverage also exists on the Rust side in
`xiuxian-wendao-julia` transport tests. Those tests boot
`scripts/run_stream_linear_blend_server.sh` and verify a real Arrow Flight
roundtrip against the analyzer-owned server.

There is now also a main-crate planned-search integration in `xiuxian-wendao`
that points the Julia rerank runtime at the same analyzer-owned stream server,
so the package is covered at both the transport layer and the higher-level
search-runtime layer. The current gate slice verifies:

- the Flight-only custom WendaoArrow rerank service path
- the official WendaoArrow stream scoring and stream metadata examples
- the WendaoAnalyzer `linear_blend` and `similarity_only` launcher paths

`xiuxian-wendao` can now also express analyzer strategy preferences in its
`link_graph.retrieval.julia_rerank` runtime config through additive fields such
as `service_mode`, `analyzer_config_path`, `analyzer_strategy`,
`vector_weight`, and `similarity_weight`. A concrete Rust-side sample now lives
at `config/link_graph_julia_rerank.example.toml`. The
current main integration coverage proves those settings can drive a non-default
`similarity_only` analyzer selection against the analyzer-owned test server.
Rust now also derives a crate-owned launch manifest from that runtime config,
so the analyzer-owned launcher path and ordered Julia args can be assembled
without re-encoding the same mapping inside test support.
This `0.2.0` lock point means the current analyzer-owned service/runtime
surface, config examples, and shipped launcher scripts move together as one
beta package boundary.
It also means the package declares `WendaoArrow` directly in `Project.toml`
with a pinned GitHub source, so Flight-backed analyzer service flows are part
of the formal package seam.
That same runtime surface is now also exported as a serializable deployment
artifact, with a concrete example at
`config/julia_deployment_artifact.example.toml`.
`xiuxian-wendao` now also exposes crate-owned export helpers on that artifact,
so deployment assembly can render or write the final TOML artifact directly
instead of rebuilding serialization outside the runtime-config surface.
The same runtime-config layer now also exposes a top-level consumer path:
Rust can resolve the current Julia deployment artifact and emit its TOML
without manually calling the lower-level retrieval-policy resolver.
That consumer path is now also visible at the Wendao inspection boundary
through the `wendao.julia_deployment_artifact` native/RPC tool, with both TOML
and structured JSON output modes.
The same resolved artifact is also available through the Studio gateway debug
surface at `/api/ui/julia-deployment-artifact`, with JSON default output and
`format=toml` parity for inspection workflows.
That endpoint is now also represented as a first-class Studio/OpenAPI contract
on the Rust side, so analyzer deployment inspection can rely on a stable
gateway-visible JSON surface instead of an internal runtime struct.
That visible contract now also includes artifact-level metadata fields
(`artifact_schema_version` and `generated_at`) so deployment inspection can
track artifact-contract evolution independently from the Arrow transport
`schema_version`.
On the Rust inspection side, `wendao.julia_deployment_artifact` can now also
persist the resolved artifact with `output_path`, which makes the analyzer
deployment contract directly writable as either TOML or JSON from the existing
tool boundary.
On the frontend side, Qianji Studio now also has a typed consumer for the same
Studio debug endpoint, so analyzer deployment inspection is available through
the shared API client surface instead of ad hoc fetch calls.
That same consumer is now surfaced in the live workspace `StatusBar`, so the
resolved analyzer launcher, service mode, strategy, and Arrow transport
coordinates are visible in the running Studio shell.
The same shell surface now also supports copying the resolved TOML artifact
and downloading the structured JSON artifact directly from the `StatusBar`
popover.
The frontend inspection/export behavior for that shell surface is now also
consolidated into a dedicated frontend feature folder, so the analyzer deployment UI
path has one formatting/export owner on the frontend side.
That frontend feature folder now also owns the artifact popover subview, so
the running Studio shell keeps the same analyzer deployment behavior while
moving rendering responsibility below the StatusBar surface.
The adjacent repo-index diagnostics popover is now also rendered through its
own subview, keeping the whole StatusBar composition model consistent across
deployment inspection and repository diagnostics.
The same StatusBar path now also centralizes its derived labels and tones in a
dedicated model helper, so the frontend shell keeps one orchestration layer
above both the analyzer deployment popover and the repo diagnostics popover.
The analyzer deployment popover path now also owns its local action-state
controller, so export feedback is managed inside the inspection feature folder
instead of the top-level status shell.
