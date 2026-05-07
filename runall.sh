#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

info()  { printf "[INFO]  %s\n" "$1"; }
ok()    { printf "[OK]    %s\n" "$1"; }
err()   { printf "[ERROR] %s\n" "$1"; }

port_is_free() {
  python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])

def can_bind(family, host):
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind((host, port))
    except OSError:
        return False
    finally:
        sock.close()
    return True

ok = can_bind(socket.AF_INET, "0.0.0.0")
if socket.has_ipv6:
    ok = ok and can_bind(socket.AF_INET6, "::")

sys.exit(0 if ok else 1)
PY
}

assign_port() {
  local var_name="$1"
  local default_port="$2"
  local label="$3"
  local current_port="${!var_name:-$default_port}"
  local candidate="$current_port"
  local shifted=0

  while ! port_is_free "$candidate"; do
    candidate=$((candidate + 1))
    shifted=1
  done

  export "$var_name=$candidate"

  if [[ "$shifted" -eq 1 ]]; then
    info "$label port $current_port is busy; using $candidate"
  else
    ok "$label port $candidate is available"
  fi
}

format_base_url() {
  local port="$1"
  if [[ "$port" == "80" ]]; then
    printf "http://localhost"
  else
    printf "http://localhost:%s" "$port"
  fi
}

ensure_min_float() {
  local var_name="$1"
  local minimum="$2"
  local label="$3"
  local current="${!var_name:-$minimum}"

  local normalized
  normalized="$(python3 - "$current" "$minimum" <<'PY'
import sys

current = float(sys.argv[1])
minimum = float(sys.argv[2])
print(max(current, minimum))
PY
)"

  export "$var_name=$normalized"

  if [[ "$normalized" != "$current" ]]; then
    info "$label timeout $current is too low for live LLM calls; using $normalized"
  fi
}

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

assign_port HTTP_HOST_PORT 80 "Gateway"
assign_port MINIO_CONSOLE_PORT 9001 "MinIO console"
assign_port MILVUS_PORT 19530 "Milvus"
assign_port MILVUS_METRICS_PORT 9091 "Milvus metrics"
assign_port PHOENIX_UI_PORT 6006 "Phoenix UI"
assign_port PHOENIX_GRPC_PORT 4317 "Phoenix gRPC"
assign_port NIM_LLM_HOST_PORT 8010 "Local NIM LLM"
assign_port NIM_EMBED_HOST_PORT 8011 "Local NIM embedding"

HOST_BASE_URL="$(format_base_url "$HTTP_HOST_PORT")"
export HOST_BASE_URL
export PHOENIX_ENDPOINT="http://localhost:${PHOENIX_UI_PORT}/v1/traces"
export MILVUS_URI="http://localhost:${MILVUS_PORT}"
ensure_min_float PROMOTION_AGENT_TIMEOUT 35.0 "Promotion agent"
ensure_min_float POST_PURCHASE_AGENT_TIMEOUT 70.0 "Post-purchase agent"

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
  NIM_LLM_BASE_URL="http://host.docker.internal:${NIM_LLM_HOST_PORT}/v1"
  NIM_EMBED_BASE_URL="http://host.docker.internal:${NIM_EMBED_HOST_PORT}/v1"
  NIM_LLM_MAX_MODEL_LEN="${NIM_LLM_MAX_MODEL_LEN:-4096}"
  NIM_LLM_KVCACHE_PERCENT="${NIM_LLM_KVCACHE_PERCENT:-0.55}"
  NIM_LLM_RELAX_MEM_CONSTRAINTS="${NIM_LLM_RELAX_MEM_CONSTRAINTS:-1}"
  NIM_LLM_NUM_KV_CACHE_SEQ_LENS="${NIM_LLM_NUM_KV_CACHE_SEQ_LENS:-1}"
  NIM_LLM_LOW_MEMORY_MODE="${NIM_LLM_LOW_MEMORY_MODE:-1}"
fi

export NVIDIA_API_KEY NIM_RUN_MODE NIM_LLM_BASE_URL NIM_EMBED_BASE_URL NIM_LLM_MODEL_NAME NIM_EMBED_MODEL_NAME
export NIM_LLM_MAX_MODEL_LEN NIM_LLM_KVCACHE_PERCENT NIM_LLM_RELAX_MEM_CONSTRAINTS NIM_LLM_NUM_KV_CACHE_SEQ_LENS NIM_LLM_LOW_MEMORY_MODE

COMPOSE_FILES=(-f "$ROOT_DIR/docker-compose.infra.yml" -f "$ROOT_DIR/docker-compose.yml")
COMPOSE_CMD=(docker compose "${COMPOSE_FILES[@]}")
NIM_COMPOSE=(-f "$ROOT_DIR/docker-compose-nim.yml")
NIM_CMD=(docker compose "${NIM_COMPOSE[@]}")

if ! docker network inspect acp-infra-network >/dev/null 2>&1; then
  docker network create acp-infra-network >/dev/null
  ok "Created network acp-infra-network"
fi

if [[ "$NIM_RUN_MODE" == "local_nim" ]]; then
  info "Starting local NVIDIA NIM runtime"
  "${NIM_CMD[@]}" up -d

  info "Waiting for local NVIDIA NIM endpoints"
  for i in $(seq 1 240); do
    if curl -sf --connect-timeout 3 --max-time 8 "${NIM_LLM_BASE_URL%/}/models" >/dev/null 2>&1 \
      && curl -sf --connect-timeout 3 --max-time 8 "${NIM_EMBED_BASE_URL%/}/models" >/dev/null 2>&1; then
      ok "Local NVIDIA NIM endpoints are ready"
      break
    fi
    if [[ "$i" -eq 240 ]]; then
      err "Local NVIDIA NIM endpoints did not become ready in time"
      exit 1
    fi
    sleep 5
  done

  info "Validating local NVIDIA NIM endpoints"
  if ! curl -sf --connect-timeout 3 --max-time 8 "${NIM_LLM_BASE_URL%/}/models" >/dev/null 2>&1; then
    err "Local NIM LLM endpoint is not reachable: ${NIM_LLM_BASE_URL%/}/models"
    exit 1
  fi
  if ! curl -sf --connect-timeout 3 --max-time 8 "${NIM_EMBED_BASE_URL%/}/models" >/dev/null 2>&1; then
    err "Local NIM embedding endpoint is not reachable: ${NIM_EMBED_BASE_URL%/}/models"
    exit 1
  fi
fi

info "Starting provider stack"
"${COMPOSE_CMD[@]}" up -d --build

info "Waiting for core services"
for i in $(seq 1 60); do
  if curl -sf --connect-timeout 3 --max-time 8 "${HOST_BASE_URL}/api/health" >/dev/null 2>&1 \
    && curl -sf --connect-timeout 3 --max-time 8 "${HOST_BASE_URL}/psp/health" >/dev/null 2>&1 \
    && curl -sf --connect-timeout 3 --max-time 8 "${HOST_BASE_URL}/apps-sdk/health" >/dev/null 2>&1; then
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
- UI:             ${HOST_BASE_URL}
- Merchant:       ${HOST_BASE_URL}/api/health
- PSP:            ${HOST_BASE_URL}/psp/health
- Apps SDK:       ${HOST_BASE_URL}/apps-sdk/health
- Phoenix:        http://localhost:${PHOENIX_UI_PORT}
- MinIO Console:  http://localhost:${MINIO_CONSOLE_PORT}

EOF
