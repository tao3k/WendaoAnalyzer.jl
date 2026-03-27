using Pkg

ROOT = joinpath(@__DIR__, "..")
ARROW_ROOT = joinpath(ROOT, "..", "WendaoArrow")

Pkg.activate(ROOT)
pushfirst!(LOAD_PATH, ARROW_ROOT)

using WendaoAnalyzer
using WendaoArrow

service = WendaoAnalyzer.analyzer_service_descriptor_from_args(ARGS)
config = WendaoArrow.config_from_args(service.contract.wendaoarrow_args)

if service.service_mode == :stream
    processor = WendaoAnalyzer.build_stream_processor(analyzer = service.contract.runtime.analyzer)
    WendaoArrow.serve_stream(processor; config = config)
else
    processor = WendaoAnalyzer.build_table_processor(analyzer = service.contract.runtime.analyzer)
    WendaoArrow.serve(processor; config = config)
end
