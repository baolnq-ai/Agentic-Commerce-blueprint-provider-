#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

info()  { printf "[INFO]  %s\n" "$1"; }
ok()    { printf "[OK]    %s\n" "$1"; }
err()   { printf "[ERROR] %s\n" "$1"; }

if ! command -v docker >/dev/null 2>&1; then
  err "docker is required"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  err "docker daemon is not running"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/env.example" "$ENV_FILE"
  info "Created .env from env.example"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

NIM_RUN_MODE="${NIM_RUN_MODE:-api}"
if [[ "$NIM_RUN_MODE" != "api" && "$NIM_RUN_MODE" != "local_nim" ]]; then
  err "NIM_RUN_MODE must be one of: api, local_nim"
  exit 1
fi

if [[ "$NIM_RUN_MODE" == "api" ]]; then
  if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
    err "NVIDIA_API_KEY missing in .env"
    exit 1
  fi

  if [[ "${NVIDIA_API_KEY}" == "nvapi-xxx" ]]; then
    err "NVIDIA_API_KEY is still placeholder (nvapi-xxx)"
    exit 1
  fi
else
  NVIDIA_API_KEY="${NVIDIA_API_KEY:-local-nim}"
  NIM_LLM_BASE_URL="${NIM_LLM_BASE_URL:-http://ollama:11434/v1}"
  NIM_EMBED_BASE_URL="${NIM_EMBED_BASE_URL:-http://ollama:11434/v1}"
  if [[ -z "${NIM_LLM_MODEL_NAME:-}" || "${NIM_LLM_MODEL_NAME}" == "nvidia/llama-3.1-nemotron-nano-8b-v1" ]]; then
    NIM_LLM_MODEL_NAME="${OLLAMA_LLM_MODEL:-llama3.2:1b}"
  fi
  if [[ -z "${NIM_EMBED_MODEL_NAME:-}" || "${NIM_EMBED_MODEL_NAME}" == "nvidia/nv-embedqa-e5-v5" ]]; then
    NIM_EMBED_MODEL_NAME="${OLLAMA_EMBED_MODEL:-nomic-embed-text:latest}"
  fi
fi

export NVIDIA_API_KEY NIM_RUN_MODE NIM_LLM_BASE_URL NIM_EMBED_BASE_URL NIM_LLM_MODEL_NAME NIM_EMBED_MODEL_NAME
export OLLAMA_LLM_MODEL="${OLLAMA_LLM_MODEL:-llama3.2:1b}"
export OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text:latest}"

COMPOSE_FILES=(-f "$ROOT_DIR/docker-compose.infra.yml" -f "$ROOT_DIR/docker-compose.yml")
COMPOSE_CMD=(docker compose "${COMPOSE_FILES[@]}")

if ! docker network inspect acp-infra-network >/dev/null 2>&1; then
  docker network create acp-infra-network >/dev/null
  ok "Created network acp-infra-network"
fi

if [[ "$NIM_RUN_MODE" == "local_nim" && ( "$NIM_LLM_BASE_URL" == *"://ollama:"* || "$NIM_EMBED_BASE_URL" == *"://ollama:"* ) ]]; then
  export COMPOSE_PROFILES="${COMPOSE_PROFILES:-local-model}"
  info "Preparing bundled local model runtime"
  "${COMPOSE_CMD[@]}" up -d ollama
  "${COMPOSE_CMD[@]}" run --rm ollama-init
fi

info "Starting provider stack"
"${COMPOSE_CMD[@]}" up -d --build

info "Waiting for core services"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:${HTTP_HOST_PORT:-80}/api/health" >/dev/null 2>&1 \
    && curl -sf "http://localhost:${HTTP_HOST_PORT:-80}/psp/health" >/dev/null 2>&1 \
    && curl -sf "http://localhost:${HTTP_HOST_PORT:-80}/apps-sdk/health" >/dev/null 2>&1; then
    ok "Core services are healthy"
    break
  fi
  if [[ "$i" -eq 60 ]]; then
    err "Core health checks did not pass in time"
    exit 1
  fi
  sleep 3
done

info "Waiting for agent services"
for i in $(seq 1 300); do
  if "${COMPOSE_CMD[@]}" exec -T search-agent curl -sf "http://localhost:8005/health" >/dev/null 2>&1 \
    && "${COMPOSE_CMD[@]}" exec -T recommendation-agent curl -sf "http://localhost:8004/health" >/dev/null 2>&1; then
    ok "Search and recommendation agents are healthy"
    break
  fi
  if [[ "$i" -eq 300 ]]; then
    err "Agent health checks did not pass in time"
    exit 1
  fi
  sleep 3
done

cat <<EOF

Provider is ready.
- UI:             http://localhost:${HTTP_HOST_PORT:-80}
- Merchant:       http://localhost:${HTTP_HOST_PORT:-80}/api/health
- PSP:            http://localhost:${HTTP_HOST_PORT:-80}/psp/health
- Apps SDK:       http://localhost:${HTTP_HOST_PORT:-80}/apps-sdk/health

EOF
