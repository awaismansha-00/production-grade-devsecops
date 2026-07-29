'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const tracesEndpoint = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
const tracingDisabled = process.env.OTEL_TRACES_EXPORTER === 'none';

if (!tracingDisabled && tracesEndpoint) {
  const sdk = new NodeSDK({
    traceExporter: new OTLPTraceExporter({
      url: tracesEndpoint,
    }),
    instrumentations: [getNodeAutoInstrumentations()],
  });

  sdk.start();

  const shutdown = () => {
    sdk.shutdown()
      .catch((err) => console.error('OpenTelemetry shutdown failed:', err))
      .finally(() => process.exit(0));
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}
