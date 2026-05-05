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

if ! grep -q '^NVIDIA_API_KEY=' "$ENV_FILE"; then
  err "NVIDIA_API_KEY missing in .env"
  exit 1
fi

if grep -q '^NVIDIA_API_KEY=nvapi-xxx' "$ENV_FILE"; then
  err "NVIDIA_API_KEY is still placeholder (nvapi-xxx)"
  exit 1
fi

if ! docker network inspect acp-infra-network >/dev/null 2>&1; then
  docker network create acp-infra-network >/dev/null
  ok "Created network acp-infra-network"
fi

info "Starting provider stack"
docker compose -f "$ROOT_DIR/docker-compose.infra.yml" -f "$ROOT_DIR/docker-compose.yml" up -d --build

info "Waiting for core services"
for i in $(seq 1 60); do
  if curl -sf "http://localhost/api/health" >/dev/null 2>&1 \
    && curl -sf "http://localhost/psp/health" >/dev/null 2>&1 \
    && curl -sf "http://localhost/apps-sdk/health" >/dev/null 2>&1; then
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
for i in $(seq 1 80); do
  if curl -sf "http://localhost:8005/health" >/dev/null 2>&1 \
    && curl -sf "http://localhost:8004/health" >/dev/null 2>&1; then
    ok "Search and recommendation agents are healthy"
    break
  fi
  if [[ "$i" -eq 80 ]]; then
    err "Agent health checks did not pass in time"
    exit 1
  fi
  sleep 3
done

cat <<'EOF'

Provider is ready.
- UI:             http://localhost
- Merchant:       http://localhost/api/health
- PSP:            http://localhost/psp/health
- Apps SDK:       http://localhost/apps-sdk/health

EOF
