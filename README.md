# Agentic Commerce Provider

Provider repository for Hub-managed deployment of the Agentic Commerce stack.

This repo is optimized for:
- one-command startup
- Docker-based runtime only
- provider metadata for Hub discovery/installation

## Quick Start (One Command)

From repo root:

```bash
bash runall.sh
```

This command will:
1. Ensure required Docker network exists.
2. Start infrastructure and app services with Docker Compose.
3. Wait for core health checks.
4. Print ready endpoints.

## Stop

```bash
bash stop.sh
```

## Exposed Endpoints

- UI Gateway: http://localhost
- Merchant Health: http://localhost/api/health
- PSP Health: http://localhost/psp/health
- Apps SDK Health: http://localhost/apps-sdk/health

## Provider Metadata

Hub-facing provider metadata is in:

- provider.metadata.json

Suggested Hub contract fields are included:
- id, name, version, description
- install/start/stop commands
- health checks
- dependency requirements
- runtime ports

## Requirements

- Docker Engine 24+
- Docker Compose v2
- NVIDIA API key in .env

Create .env from template if missing:

```bash
cp env.example .env
```

Set:

```env
NVIDIA_API_KEY=nvapi-...
```

## Notes

- This provider keeps only files required for runtime packaging and provider integration.
- Development docs/tests/playbooks are intentionally removed to keep footprint small.
