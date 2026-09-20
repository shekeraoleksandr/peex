# Observability data types (Trainee item: "Identify observability data types")

Observability rests on three primary signal types — **metrics, logs, and traces**
— often complemented by **events**. Each answers a different question, and this
stack collects them with dedicated tools.

## 1. Metrics
Numeric measurements sampled over time (time series). Cheap to store, ideal for
dashboards, trend analysis and alerting thresholds.
- Examples: CPU load, memory %, request rate, error rate, queue depth.
- Sub-types: counters (monotonic, e.g. `http_requests_total`), gauges
  (up/down, e.g. `node_load1`), histograms/summaries (latency distributions).
- In this stack: **Prometheus** scrapes **node-exporter** for infrastructure
  metrics; alert **rules** evaluate metrics; **Grafana** visualizes them.

## 2. Logs
Timestamped, discrete text records of events. High cardinality and detail;
best for root-cause investigation of a specific incident.
- Examples: application logs, access logs, audit logs, system logs.
- Formats: plaintext, structured (JSON), or key=value (as in `logs/sample.log`).
- In this stack: **Promtail** tails host and container logs and ships them to
  **Loki**; queried in **Grafana**. `scripts/log-summary.sh` shows offline
  extraction and summarization of log entries.

## 3. Traces
Records of a single request as it flows across services (spans with parent/child
relationships and timing). Best for latency analysis in distributed systems.
- Examples: a checkout request traversing api → payments → db, each span timed.
- Tools: OpenTelemetry, Jaeger, Grafana Tempo (distributed tracing is a
  Senior-level item and is out of scope for this Junior task, noted for completeness).

## 4. Events (supporting)
Discrete state-change notifications: deploys, config changes, scaling actions,
**alerts firing**. They provide context ("what changed?") alongside the signals.
- In this stack: **Alertmanager** turns a firing alert into an event delivered
  to an automated process (the webhook receiver).

## Quick reference

| Type    | Question answered            | Cost      | Tool here            |
|---------|------------------------------|-----------|----------------------|
| Metrics | "Is it healthy? trending?"   | Low       | Prometheus + node-exporter |
| Logs    | "What exactly happened?"     | Medium    | Loki + Promtail      |
| Traces  | "Where is the latency?"      | High      | (Tempo/Jaeger — out of scope) |
| Events  | "What changed / fired?"      | Low       | Alertmanager         |
