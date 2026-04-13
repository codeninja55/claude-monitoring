# Claude Code monitoring stack

A Grafana LGTM observability stack for monitoring Claude Code usage via OpenTelemetry. Collects metrics, events, and traces from Claude Code instances across your LAN and visualizes them in a pre-built Grafana dashboard.

## Architecture

```
Claude Code instances ──▶ OTel Collector (:4317 gRPC, :4318 HTTP)
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              Mimir         Loki        Tempo
            (metrics)    (events/logs)  (traces)
                    └───────────┼───────────┘
                                │
                          Grafana (:3000)
```

| Component | Purpose | Image |
|-----------|---------|-------|
| OTel Collector | Receives OTLP data from Claude Code, routes to backends | `otel/opentelemetry-collector-contrib:0.120.0` |
| Mimir | Time-series metrics (tokens, costs, sessions, LOC) | `grafana/mimir:2.16.0` |
| Loki | Log-based events (tool results, API requests, errors) | `grafana/loki:3.5.0` |
| Tempo | Distributed traces (prompt → API call → tool execution) | `grafana/tempo:2.7.0` |
| Grafana | Dashboards and exploration UI | `grafana/grafana-oss:11.6.0` |

## Prerequisites

- Docker and Docker Compose (v2+)
- Claude Code installed on at least one machine
- Network access between Claude Code clients and this server (ports 4317, 4318, 3000)

## Quick start

### 1. Start the stack

```bash
cd claude-monitoring
docker compose up -d
```

Verify all containers are running:

```bash
docker compose ps
```

All 5 services should show status `Up`.

### 2. Configure Claude Code on this machine

Add these environment variables to `~/.claude/settings.json` under the `"env"` key:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta"
  }
}
```

### 3. Configure Claude Code on other LAN machines

Use the same settings but replace `localhost` with this server's LAN IP:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://<SERVER_LAN_IP>:4317",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta"
  }
}
```

### 4. Verify data flow

1. Start a Claude Code session (the new session picks up the env vars)
2. Open Grafana at `http://localhost:3000` (default: admin/admin)
3. Navigate to **Dashboards → Claude Code → Claude Code usage**
4. Set the time range to "Last 15 minutes" and wait for the first metric export (up to 60 seconds)

To verify each signal individually in Grafana Explore:

- **Metrics** (Mimir): query `claude_code_session_count_total`
- **Events** (Loki): query `{service_name="claude-code"}`
- **Traces** (Tempo): search for service `claude-code`

## Telemetry signals collected

### Metrics (via Mimir)

| Metric | Description |
|--------|-------------|
| `claude_code.session.count` | Sessions started |
| `claude_code.token.usage` | Tokens used (by type: input, output, cacheRead, cacheCreation) |
| `claude_code.cost.usage` | Estimated cost in USD (by model) |
| `claude_code.lines_of_code.count` | Lines added/removed |
| `claude_code.commit.count` | Git commits created |
| `claude_code.pull_request.count` | PRs created |
| `claude_code.active_time.total` | Active usage time in seconds |
| `claude_code.code_edit_tool.decision` | Edit tool accept/reject decisions |

### Events (via Loki)

| Event | Description |
|-------|-------------|
| `claude_code.user_prompt` | User prompt submissions (content redacted by default) |
| `claude_code.tool_result` | Tool execution results with success/failure, duration, parameters |
| `claude_code.api_request` | API calls with model, tokens, cost, latency |
| `claude_code.api_error` | API failures with error details and status codes |
| `claude_code.tool_decision` | Tool permission accept/reject decisions |

### Traces (via Tempo)

Distributed traces link each user prompt to the API requests and tool executions it triggers. Traces are a beta feature requiring `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`.

## Running the stack

### Start

```bash
docker compose up -d
```

### Stop

```bash
docker compose down
```

### View logs

```bash
# All services
docker compose logs -f

# Single service
docker compose logs -f otel-collector
```

### Restart a single service

```bash
docker compose restart grafana
```

### Check resource usage

```bash
docker stats
```

## Data retention and storage

By default, all persistent data is stored in `./data/` relative to the project root, with 1-year retention configured for each backend:

| Backend | Default path | Retention | Primary data |
|---------|-------------|-----------|--------------|
| Mimir | `./data/mimir/` | 365 days | TSDB blocks, compactor state |
| Loki | `./data/loki/` | 365 days | Log chunks, TSDB index |
| Tempo | `./data/tempo/` | 365 days | Trace blocks, WAL |
| Grafana | `./data/grafana/` | N/A | Dashboards DB, user prefs |

Check disk usage:

```bash
du -sh data/*/
```

### Storage size estimates

Data growth depends on the number of Claude Code users and session frequency. These estimates assume `OTEL_LOG_TOOL_DETAILS=1` is enabled:

| Scale | Daily ingest | Monthly | 1 year |
|-------|-------------|---------|--------|
| 1 developer, light use (5-10 sessions/day) | ~5-15 MB | ~200-450 MB | ~2-5 GB |
| 1 developer, heavy use (20-40 sessions/day) | ~20-60 MB | ~600 MB-1.8 GB | ~7-20 GB |
| Small team (5 developers) | ~100-300 MB | ~3-9 GB | ~35-100 GB |
| Medium team (20 developers) | ~400 MB-1.2 GB | ~12-36 GB | ~140-400 GB |

Breakdown by signal:
- **Metrics (Mimir)**: ~30% of total. Counter data is compact; the main driver is cardinality (number of unique label combinations).
- **Events/logs (Loki)**: ~50% of total. Each tool result, API request, and prompt event generates a log entry. `OTEL_LOG_TOOL_DETAILS=1` adds tool parameters which increases log size.
- **Traces (Tempo)**: ~20% of total. One trace per user prompt with spans for API calls and tool executions. Enabling `OTEL_LOG_TOOL_CONTENT=1` (not on by default) can significantly increase trace size.

Compaction runs automatically in all backends and reclaims space over time. Mimir compacts TSDB blocks, Loki compacts chunk indexes, and Tempo compacts trace blocks.

### Moving data to a separate volume

For production or heavier workloads, move data to a dedicated disk or RAID array to avoid filling your root filesystem.

1. Stop the stack:

   ```bash
   docker compose down
   ```

2. Create the target directory with open permissions (containers run as non-root UIDs):

   ```bash
   sudo mkdir -p /mnt/monitoring-data/{mimir,loki,tempo,grafana}
   sudo chmod -R 777 /mnt/monitoring-data
   ```

3. If migrating existing data, copy it:

   ```bash
   sudo cp -a ./data/mimir/* /mnt/monitoring-data/mimir/
   sudo cp -a ./data/loki/* /mnt/monitoring-data/loki/
   sudo cp -a ./data/tempo/* /mnt/monitoring-data/tempo/
   sudo cp -a ./data/grafana/* /mnt/monitoring-data/grafana/
   ```

4. Update `docker-compose.yml` — replace the relative `./data/` paths with absolute paths:

   ```yaml
   # Before
   - ./data/mimir:/data/mimir

   # After
   - /mnt/monitoring-data/mimir:/data/mimir
   ```

   Repeat for all four services (mimir, loki, tempo, grafana).

5. Start the stack:

   ```bash
   docker compose up -d
   ```

6. Verify data persists by checking Grafana at `http://localhost:3000` — historical dashboards should still show data.

**Permissions note**: Grafana runs as UID 472, Loki and Tempo run as UID 10001, and Mimir runs as root. The target directories need to be writable by these UIDs. Using `chmod 777` is the simplest approach for a private server. For stricter permissions, set ownership per directory:

```bash
sudo chown -R 10001:10001 /mnt/monitoring-data/{loki,tempo}
sudo chown -R 472:472 /mnt/monitoring-data/grafana
# Mimir runs as root — no ownership change needed
```

## Development

### Project structure

```
├── docker-compose.yml              # Service definitions
├── otel-collector/config.yaml      # Receiver → processor → exporter pipelines
├── mimir/config.yaml               # Metrics backend (monolithic mode)
├── loki/config.yaml                # Logs/events backend (monolithic mode)
├── tempo/config.yaml               # Traces backend (monolithic mode)
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/            # Auto-configured Mimir, Loki, Tempo
│   │   └── dashboards/             # Dashboard provider config
│   └── dashboards/
│       └── claude-code-usage.json  # Pre-built dashboard
└── data/                           # Persistent volumes (gitignored)
```

### Modifying the dashboard

The dashboard is provisioned from `grafana/dashboards/claude-code-usage.json`. To edit:

1. Make changes in the Grafana UI (http://localhost:3000)
2. Export the updated dashboard JSON (Dashboard settings → JSON model → Copy)
3. Save the JSON to `grafana/dashboards/claude-code-usage.json`
4. Restart Grafana: `docker compose restart grafana`

Provisioned dashboards are read-only in the UI by default. To enable editing, the dashboard has `"editable": true` set.

### Modifying configs

After changing any config file:

```bash
# Restart the affected service
docker compose restart <service-name>

# Or restart everything
docker compose up -d --force-recreate
```

### Updating component versions

Update the image tags in `docker-compose.yml` and pull:

```bash
docker compose pull
docker compose up -d
```

### Debugging telemetry

To verify the OTel Collector is receiving data, temporarily add a console exporter:

1. Edit `otel-collector/config.yaml` — add `debug` to the exporters and pipeline
2. `docker compose restart otel-collector`
3. `docker compose logs -f otel-collector` — watch for incoming data
4. Remove the debug exporter when done

### Testing with console exporter

For local debugging without the full stack, configure Claude Code with:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "console",
    "OTEL_LOGS_EXPORTER": "console",
    "OTEL_METRIC_EXPORT_INTERVAL": "5000"
  }
}
```

This prints telemetry to Claude Code's stderr.

## Firewall

If LAN devices cannot connect, ensure these ports are open:

| Port | Protocol | Purpose |
|------|----------|---------|
| 4317 | TCP | OTLP gRPC (Claude Code → OTel Collector) |
| 4318 | TCP | OTLP HTTP (Claude Code → OTel Collector) |
| 3000 | TCP | Grafana web UI |

Example with `ufw`:

```bash
sudo ufw allow 4317/tcp
sudo ufw allow 4318/tcp
sudo ufw allow 3000/tcp
```

## Privacy

| Setting | Status | Effect |
|---------|--------|--------|
| `OTEL_LOG_USER_PROMPTS` | Disabled | Prompt content is not collected (only length) |
| `OTEL_LOG_TOOL_DETAILS` | Enabled | Tool parameters (bash commands, file paths) are logged |
| `OTEL_LOG_TOOL_CONTENT` | Disabled | Tool input/output content is not logged in traces |

All data stays on your local network. No telemetry is sent to external services.
