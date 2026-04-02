using WendaoAnalyzer
using WendaoArrow
using gRPCServer

service = WendaoAnalyzer.analyzer_service_descriptor_from_args(ARGS)
config = WendaoArrow.config_from_args(service.contract.wendaoarrow_args)
descriptor = WendaoArrow.flight_descriptor(("rerank",))

if service.service_mode == :stream
    processor = WendaoAnalyzer.build_stream_processor(analyzer = service.contract.runtime.analyzer)
    WendaoArrow.serve_stream_flight(
        processor;
        descriptor = descriptor,
        host = config.host,
        port = config.port,
    )
else
    processor = WendaoAnalyzer.build_table_processor(analyzer = service.contract.runtime.analyzer)
    WendaoArrow.serve_flight(
        processor;
        descriptor = descriptor,
        host = config.host,
        port = config.port,
    )
end
