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
- For `NIM_RUN_MODE=api`: NVIDIA API key in `.env`
- For `NIM_RUN_MODE=local_nim`: NVIDIA Container Toolkit + GPU runtime (`nvidia`), and optional NVIDIA API key for model/bootstrap access

Create .env from template if missing:

```bash
cp env.example .env
```

Set for API mode:

```env
NVIDIA_API_KEY=nvapi-...
```

Set for local mode:

```env
NIM_RUN_MODE=local_nim
NIM_LLM_BASE_URL=http://host.docker.internal:8010/v1
NIM_EMBED_BASE_URL=http://host.docker.internal:8011/v1
```

When `NIM_RUN_MODE=local_nim`, `runall.sh` brings up local NIM services from `docker-compose-nim.yml`, waits for `/v1/models` on both LLM and embedding endpoints, then starts the provider stack.

## Notes

- This provider keeps only files required for runtime packaging and provider integration.
- Development docs/tests/playbooks are intentionally removed to keep footprint small.
