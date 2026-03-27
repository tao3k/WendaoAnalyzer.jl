# WendaoAnalyzer Specification

## Intent

WendaoAnalyzer provides domain logic on top of the WendaoArrow transport boundary.

## Ownership Boundary

- WendaoArrow owns HTTP transport, Arrow IPC decode/encode, route handling, and schema-version headers.
- WendaoAnalyzer owns score computation and contract-shaped output generation.

## First Analyzer Contract

Input requirements follow WendaoArrow `v1` required request columns:

- `doc_id`
- `vector_score`
- `embedding`
- `query_embedding`

Output guarantees:

- `doc_id`
- `analyzer_score`
- `final_score`
- optional additive `ranking_reason`

## First Strategy

The initial strategy is a normalized linear blend between Rust coarse retrieval score and Julia cosine similarity.

This is intentionally:

- deterministic
- explainable
- cheap to compute
- easy to replace in a future package revision

## Strategy Surface

The package now exposes a typed strategy surface through `AnalyzerConfig` and
`build_analyzer(...)`.

Built-in strategies:

- `:linear_blend`
- `:similarity_only`
- `:vector_only`

The default remains `:linear_blend`, so existing transport and Rust integration
surfaces keep the same behavior.

## Runtime Selection

The example-server layer can choose analyzer strategy at runtime without
changing the transport contract.

Supported analyzer-only inputs:

- `--analyzer-strategy`
- `--vector-weight`
- `--similarity-weight`
- `--analyzer-config <path>`

Analyzer-only arguments are separated locally inside `WendaoAnalyzer`, while the
remaining arguments still flow through `WendaoArrow.config_from_args(...)`.
