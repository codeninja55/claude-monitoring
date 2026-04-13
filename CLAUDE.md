# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Docker Compose stack that collects Claude Code OpenTelemetry data (metrics, events, traces) from multiple machines on a LAN and visualizes it in Grafana. There is no application code — only configuration files for infrastructure services.

## Architecture

```
Claude Code (OTLP) → OTel Collector → Mimir (metrics)
                                     → Loki  (events/logs)
                                     → Tempo (traces)
                                            ↓
                                       Grafana (dashboards)
```

Five Docker Compose services on a single bridge network (`monitoring`). The OTel Collector is the only ingress point — it receives OTLP on ports 4317 (gRPC) and 4318 (HTTP), then routes each signal to its backend. Mimir, Loki, and Tempo are not exposed to the host; only the collector and Grafana have published ports.

## Key files

| File | What it configures |
|------|-------------------|
| `docker-compose.yml` | Service definitions, volume mounts, port bindings |
| `otel-collector/config.yaml` | OTLP receivers → batch/memory_limiter processors → exporters to Mimir/Loki/Tempo |
| `mimir/config.yaml` | Monolithic-mode Mimir with filesystem TSDB storage and 1-year retention |
| `loki/config.yaml` | Monolithic-mode Loki with OTLP ingest, TSDB index, filesystem chunks, 1-year retention |
| `tempo/config.yaml` | Monolithic-mode Tempo with local trace storage, 1-year retention, metrics generator pushing to Mimir |
| `grafana/provisioning/datasources/datasources.yaml` | Auto-provisioned Mimir, Loki, Tempo datasources with cross-links |
| `grafana/provisioning/dashboards/dashboards.yaml` | Dashboard file provider config |
| `grafana/dashboards/claude-code-usage.json` | Pre-built dashboard — stat panels, time series, pie charts, tables, Loki-based event panels |

## Common commands

```bash
# Start everything
docker compose up -d

# Check status
docker compose ps

# View logs for a specific service
docker compose logs -f otel-collector

# Restart after config change
docker compose restart <service-name>

# Tear down (data persists in volumes)
docker compose down

# Full recreate (e.g. after image version bump)
docker compose pull && docker compose up -d --force-recreate
```

## How signals flow

- **Metrics**: Claude Code sends delta-temporality counters via OTLP. The OTel Collector forwards them to Mimir's `/otlp` endpoint (HTTP). Mimir converts delta→cumulative at ingest. Grafana queries Mimir using PromQL.
- **Events/logs**: Claude Code sends structured log events (tool_result, api_request, api_error, user_prompt, tool_decision) via OTLP. The collector forwards to Loki's `/otlp` endpoint. Grafana queries Loki using LogQL.
- **Traces**: Claude Code sends spans linking prompts→API calls→tool executions via OTLP. The collector forwards to Tempo via gRPC. Tempo's metrics generator derives RED metrics and pushes them to Mimir.

## OTLP metric naming

Claude Code metric names use dots (e.g. `claude_code.token.usage`). After OTLP→Prometheus conversion in Mimir, dots become underscores: `claude_code_token_usage`. With cumulative temporality via OTLP ingest, Mimir does NOT append a `_total` suffix. Dashboard queries use the converted form without `_total`.

## Dashboard editing workflow

The dashboard JSON at `grafana/dashboards/claude-code-usage.json` is provisioned read-only into Grafana. To edit:

1. Make changes in the Grafana UI
2. Export via Dashboard settings → JSON model → Copy
3. Replace the JSON file
4. `docker compose restart grafana`

## Container UIDs

Containers run as non-root users. Data directories must be writable by these UIDs:

| Service | UID | Note |
|---------|-----|------|
| Mimir | root | Runs as root by default |
| Loki | 10001 | |
| Tempo | 10001 | |
| Grafana | 472 | |

If data volumes get permission errors after recreation, fix with `chmod 777` on the data directories or set ownership per UID.

## Things to watch for

- **Metric name mismatches**: If a dashboard panel shows "No data", check the actual metric name in Grafana Explore (Mimir datasource) — the OTLP→Prometheus naming convention may differ from what's in the query.
- **Loki label cardinality**: Only `service.name` and `event.name` are indexed as labels. High-cardinality attributes like `session.id` and `tool_name` are in structured metadata — query them with `| json` pipeline, not as label matchers.
- **Tempo gRPC port conflict**: Tempo listens on port 4317 internally for OTLP traces. This is distinct from the OTel Collector's external 4317 — they're on different containers. Don't expose Tempo's 4317 to the host.
- **Delta temporality rejection**: Mimir rejects delta-temporality counters with HTTP 400 ("invalid temporality and type combination"). Claude Code's `settings.json` must set `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`. The OTel Collector also has a `deltatocumulative` processor as a safety net for clients that send delta anyway.
- **Protocol and port pairing**: With `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, the endpoint must use port 4318 (HTTP). With `grpc`, use port 4317. Mismatching protocol and port results in silent connection failures.
