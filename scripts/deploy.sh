#!/usr/bin/env bash
# =============================================================
# deploy.sh — deploy supply-chain-ams-stack en VPS
# =============================================================
# Uso (en el VPS):
#   cd /opt/ams/supply-chain-ams-stack
#   bash scripts/deploy.sh
#
# Asume estructura (la que crea bootstrap-vps.sh):
#   /opt/ams/supply-chain-ams-stack       (este repo)
#   /opt/ams/supply-chain-ams-agent       (clonado al lado, hermano)
#   /opt/ams/supply-chain-ams-platform    (clonado al lado, hermano)
# El script descubre los paths con dirname, así que también funciona si
# moviste todo a otro parent dir, siempre que los 3 repos sean hermanos.
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
STACK_DIR="$(pwd)"
PARENT="$(dirname "$STACK_DIR")"
AGENT_DIR="$PARENT/supply-chain-ams-agent"
PLATFORM_DIR="$PARENT/supply-chain-ams-platform"

log() { echo -e "\033[36m[deploy]\033[0m $*"; }
warn() { echo -e "\033[33m[deploy]\033[0m $*"; }
err() { echo -e "\033[31m[deploy]\033[0m $*" 1>&2; }

# 1. Sanity checks
[ -f "$STACK_DIR/.env" ] || { err "Falta .env en $STACK_DIR. cp .env.production.example .env y completar."; exit 1; }
[ -d "$AGENT_DIR" ] || { err "Falta $AGENT_DIR. git clone primero."; exit 1; }
[ -d "$PLATFORM_DIR" ] || { err "Falta $PLATFORM_DIR. git clone primero."; exit 1; }
command -v docker >/dev/null || { err "Docker no instalado"; exit 1; }
docker compose version >/dev/null || { err "Docker Compose v2 no disponible"; exit 1; }

# 2. Pull código
log "Pull supply-chain-ams-agent…"
git -C "$AGENT_DIR" pull --ff-only origin main

log "Pull supply-chain-ams-platform…"
git -C "$PLATFORM_DIR" pull --ff-only origin main

log "Pull supply-chain-ams-stack…"
git -C "$STACK_DIR" pull --ff-only origin main

# 3. Backup DB antes de cualquier cosa destructiva
if docker ps --filter "name=ams-prod-db" --format "{{.Names}}" | grep -q ams-prod-db; then
  log "Backup Postgres antes del deploy…"
  bash "$STACK_DIR/scripts/backup-db.sh" || warn "Backup falló pero continuamos."
else
  warn "DB aún no corre (primer deploy?). Salto backup."
fi

# 4. Build imágenes (no usar caché si hay flag --no-cache)
COMPOSE="docker compose -f docker-compose.prod.yml"
NO_CACHE=""
[ "${1:-}" = "--no-cache" ] && NO_CACHE="--no-cache"

log "Build imágenes…"
$COMPOSE build $NO_CACHE backend platform

# 5. Pull imágenes externas (caddy/postgres/redis)
log "Pull imágenes externas…"
$COMPOSE pull caddy db redis 2>&1 | grep -v "^Pulled\|up to date" || true

# 5b. Migraciones DB (tracked, idempotentes) contra la DB en caliente, ANTES de
#     levantar el backend nuevo → arranca con el esquema ya migrado. Sólo corre
#     las que faltan (según schema_migrations); una migración NUEVA que falle
#     ABORTA el deploy sin tocar los containers (el sistema actual sigue arriba).
#     Baseline: las 001..012 se marcaron aplicadas a mano en prod (ya estaban en
#     el esquema), así que este paso sólo aplica de la 013 en adelante.
MIG_DIR="$AGENT_DIR/database/migrations"
if docker ps --filter "name=ams-prod-db" --format '{{.Names}}' | grep -q '^ams-prod-db$'; then
  if [ -d "$MIG_DIR" ] && ls "$MIG_DIR"/*.sql >/dev/null 2>&1; then
    log "Aplicando migraciones DB pendientes…"
    DB_USER="$(docker exec ams-prod-db printenv POSTGRES_USER)"
    DB_NAME="$(docker exec ams-prod-db printenv POSTGRES_DB)"
    psql_db() { docker exec -i ams-prod-db psql -U "$DB_USER" -d "$DB_NAME" "$@"; }
    psql_db -v ON_ERROR_STOP=1 -q -c \
      "CREATE TABLE IF NOT EXISTS schema_migrations (filename TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"
    applied=0
    for f in $(ls -1 "$MIG_DIR"/*.sql | sort); do
      base="$(basename "$f")"
      done_row="$(psql_db -tAqc "SELECT 1 FROM schema_migrations WHERE filename = '$base';" | tr -d '[:space:]')"
      [ "$done_row" = "1" ] && continue
      log "  → aplicando $base"
      if psql_db -v ON_ERROR_STOP=1 -q -f - < "$f"; then
        psql_db -q -c "INSERT INTO schema_migrations (filename) VALUES ('$base') ON CONFLICT DO NOTHING;"
        applied=$((applied + 1))
      else
        err "Migración $base FALLÓ. Deploy abortado (containers sin tocar; el sistema actual sigue arriba). Revisar: docker exec -i ams-prod-db psql -U $DB_USER -d $DB_NAME -f - < $f"
        exit 1
      fi
    done
    log "Migraciones nuevas aplicadas: $applied"
  else
    warn "No hay migraciones en $MIG_DIR — salto."
  fi
else
  warn "DB no corre aún (primer deploy) — salto migraciones; se aplican en el próximo deploy."
fi

# 6. Up con downtime mínimo (re-crear sólo los containers cambiados)
log "docker compose up -d…"
$COMPOSE up -d --remove-orphans

# 7. Esperar healthcheck
log "Esperando que backend y platform estén healthy…"
for i in $(seq 1 30); do
  backend_ok=$(docker inspect --format '{{.State.Health.Status}}' ams-prod-backend 2>/dev/null || echo unknown)
  platform_ok=$(docker inspect --format '{{.State.Health.Status}}' ams-prod-platform 2>/dev/null || echo unknown)
  if [ "$backend_ok" = "healthy" ] && [ "$platform_ok" = "healthy" ]; then
    log "✓ Healthy: backend + platform"
    break
  fi
  printf "."
  sleep 5
  if [ $i -eq 30 ]; then
    err "Timeout esperando health. Estado: backend=$backend_ok platform=$platform_ok"
    err "Ver logs: docker logs ams-prod-backend  /  docker logs ams-prod-platform"
    exit 1
  fi
done
echo

# 8. Smoke tests rápidos
log "Smoke tests internos…"
docker exec ams-prod-backend node -e "fetch('http://localhost:8000/health').then(r=>r.text()).then(console.log)" || warn "Backend health check falló"

# 9. Status final
log "Containers corriendo:"
docker ps --filter "name=ams-prod-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
log "Deploy completo."
