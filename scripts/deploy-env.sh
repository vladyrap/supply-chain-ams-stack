#!/usr/bin/env bash
# =============================================================================
# deploy-env.sh — Despliegue selectivo por ambiente AMS Platform
# =============================================================================
# Uso (en el VPS):
#   cd /opt/ams/supply-chain-ams-stack
#   bash scripts/deploy-env.sh dev
#   bash scripts/deploy-env.sh qas
#   bash scripts/deploy-env.sh prod        # pide confirmacion
#
# Asume estructura:
#   /opt/ams/supply-chain-ams-stack       (este repo)
#   /opt/ams/supply-chain-ams-agent       (hermano)
#   /opt/ams/supply-chain-ams-platform    (hermano)
#
# Cada repo debe tener .env.{dev,qas,prod} creados desde los .example.
# =============================================================================
set -euo pipefail

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Uso: $0 <dev|qas|prod>"
  exit 1
fi

case "$ENV" in
  dev)
    BRANCH="main"
    COMPOSE="docker-compose.dev.yml"
    ENV_FILE=".env.dev"
    URL_PLATFORM="https://dev.amsplatform.tudominio.com"
    URL_API="https://dev-api.amsplatform.tudominio.com"
    ;;
  qas)
    BRANCH="qas"
    COMPOSE="docker-compose.qas.yml"
    ENV_FILE=".env.qas"
    URL_PLATFORM="https://qas.amsplatform.tudominio.com"
    URL_API="https://qas-api.amsplatform.tudominio.com"
    ;;
  prod)
    BRANCH="prod"
    COMPOSE="docker-compose.prod.yml"
    ENV_FILE=".env.prod"
    URL_PLATFORM="https://amsplatform.tudominio.com"
    URL_API="https://api.amsplatform.tudominio.com"
    echo ""
    echo "==========================================="
    echo "  PROD DEPLOY — ¿estas seguro? (yes/N)"
    echo "==========================================="
    read -r confirm
    [[ "$confirm" != "yes" ]] && { echo "Cancelado."; exit 0; }
    ;;
  *)
    echo "Ambiente desconocido: $ENV"
    exit 1
    ;;
esac

cd "$(dirname "$0")/.."
STACK_DIR="$(pwd)"
PARENT="$(dirname "$STACK_DIR")"
AGENT_DIR="$PARENT/supply-chain-ams-agent"
PLATFORM_DIR="$PARENT/supply-chain-ams-platform"

log()  { echo -e "\033[36m[deploy-$ENV]\033[0m $*"; }
warn() { echo -e "\033[33m[deploy-$ENV]\033[0m $*"; }
err()  { echo -e "\033[31m[deploy-$ENV]\033[0m $*" 1>&2; }

# Sanity checks
[ -d "$AGENT_DIR" ] || { err "Falta $AGENT_DIR"; exit 1; }
[ -d "$PLATFORM_DIR" ] || { err "Falta $PLATFORM_DIR"; exit 1; }
[ -f "$AGENT_DIR/$ENV_FILE" ] || { err "Falta $AGENT_DIR/$ENV_FILE — copiar desde .example"; exit 1; }
[ -f "$PLATFORM_DIR/$ENV_FILE" ] || { err "Falta $PLATFORM_DIR/$ENV_FILE — copiar desde .example"; exit 1; }
command -v docker >/dev/null || { err "Docker no instalado"; exit 1; }

# Backup DB en PROD antes de tocar nada
if [[ "$ENV" == "prod" ]]; then
  log "Backup DB PROD pre-deploy"
  bash "$STACK_DIR/scripts/backup-db.sh" prod || warn "Backup falló — continuando"
fi

# Agent: pull + build + up
log "[1/4] AGENT — fetch + checkout $BRANCH"
git -C "$AGENT_DIR" fetch --all --tags --prune
git -C "$AGENT_DIR" checkout "$BRANCH"
git -C "$AGENT_DIR" pull --ff-only origin "$BRANCH"

log "[2/4] AGENT — build + up ($COMPOSE)"
docker compose -f "$AGENT_DIR/$COMPOSE" --env-file "$AGENT_DIR/$ENV_FILE" -p "ams-$ENV" build
docker compose -f "$AGENT_DIR/$COMPOSE" --env-file "$AGENT_DIR/$ENV_FILE" -p "ams-$ENV" up -d

# Platform: pull + build + up
log "[3/4] PLATFORM — fetch + checkout $BRANCH"
git -C "$PLATFORM_DIR" fetch --all --tags --prune
git -C "$PLATFORM_DIR" checkout "$BRANCH"
git -C "$PLATFORM_DIR" pull --ff-only origin "$BRANCH"

log "[4/4] PLATFORM — build + up ($COMPOSE)"
docker compose -f "$PLATFORM_DIR/$COMPOSE" --env-file "$PLATFORM_DIR/$ENV_FILE" -p "ams-platform-$ENV" build
docker compose -f "$PLATFORM_DIR/$COMPOSE" --env-file "$PLATFORM_DIR/$ENV_FILE" -p "ams-platform-$ENV" up -d

# Wait for health
log "Esperando healthy backend..."
for i in $(seq 1 30); do
  status=$(docker inspect --format '{{.State.Health.Status}}' "ams-backend-$ENV" 2>/dev/null || echo "starting")
  if [[ "$status" == "healthy" ]]; then log "✓ backend healthy"; break; fi
  printf "."
  sleep 4
done
echo

# Status final
log "Containers $ENV:"
docker ps --filter "name=ams-.*-$ENV" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "==========================================="
echo "  Deploy $ENV completado"
echo "  Frontend: $URL_PLATFORM"
echo "  API:      $URL_API"
echo "==========================================="
