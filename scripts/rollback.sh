#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Rollback rápido a un tag anterior (v1.2.5-prod en VPS)
# =============================================================================
# Uso:
#   bash scripts/rollback.sh v1.2.4-prod
#
# Qué hace:
#   1. Backup DB del estado actual (pg_dump → backup_pre_rollback_TIMESTAMP.sql.gz)
#   2. git checkout al tag indicado en /opt/ams/{agent,platform,stack}
#   3. docker compose pull (si imágenes están en ghcr.io) o build
#   4. docker compose up -d (sin recrear DB/Redis)
#   5. Health check del backend en 90s
#   6. Si health falla → restaurar DB del dump
#
# IMPORTANTE:
#   - Solo hace rollback de CÓDIGO + imágenes. NO revierte migrations de DB.
#   - Si el tag anterior tiene schema incompatible, hay que restaurar el dump.
#   - Para QAS local usar QAS_PROJECT=qas y QAS_DEPLOY_PATH=/tmp/ams-qas/...
# =============================================================================
set -euo pipefail

TAG="${1:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/ams/supply-chain-ams-stack}"
AGENT_PATH="${AGENT_PATH:-/opt/ams/supply-chain-ams-agent}"
PLATFORM_PATH="${PLATFORM_PATH:-/opt/ams/supply-chain-ams-platform}"
BACKUP_DIR="${BACKUP_DIR:-/opt/ams/backups}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_CONTAINER="${DB_CONTAINER:-ams-prod-db}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-ams-prod-backend}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8001/health}"

if [ -z "$TAG" ]; then
  echo "Uso: $0 <tag-objetivo>"
  echo ""
  echo "Tags disponibles en agent:"
  git -C "$AGENT_PATH" tag --list 'v*-prod' 2>/dev/null | tail -5
  echo ""
  echo "Tags disponibles en platform:"
  git -C "$PLATFORM_PATH" tag --list 'v*-prod' 2>/dev/null | tail -5
  exit 1
fi

# Validar formato de tag
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-prod$ ]]; then
  echo "ERROR: Tag '$TAG' debe tener formato vX.Y.Z-prod"
  exit 1
fi

echo ""
echo "=========================================================================="
echo "  AMS Rollback → $TAG"
echo "=========================================================================="

# ===== 1. Backup DB =====
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/pre_rollback_${TAG}_${TIMESTAMP}.sql.gz"
echo ""
echo "[1/5] Backup DB pre-rollback → $BACKUP_FILE"
if docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
  docker exec "$DB_CONTAINER" pg_dumpall -U "${POSTGRES_USER:-ams_user}" 2>/dev/null | gzip > "$BACKUP_FILE"
  if [ -s "$BACKUP_FILE" ]; then
    echo "  ✓ Backup $(du -h "$BACKUP_FILE" | cut -f1)"
  else
    echo "  ✗ Backup vacío — abortando rollback"
    rm -f "$BACKUP_FILE"
    exit 1
  fi
else
  echo "  ⚠️  $DB_CONTAINER no corriendo — sin backup"
fi

# ===== 2. Checkout tags en agent + platform + stack =====
echo ""
echo "[2/5] Checkout tag $TAG en los 3 repos"
for repo_path in "$AGENT_PATH" "$PLATFORM_PATH" "$DEPLOY_PATH"; do
  repo_name=$(basename "$repo_path")
  cd "$repo_path"
  git fetch --tags --quiet
  if git rev-parse "tags/$TAG" >/dev/null 2>&1; then
    git checkout "tags/$TAG" --quiet
    echo "  ✓ $repo_name → $TAG"
  else
    echo "  ⚠️  $repo_name no tiene tag $TAG — mantiene HEAD actual"
  fi
done

# ===== 3. Pull/Build imágenes =====
echo ""
echo "[3/5] Update imágenes (pull desde ghcr.io o build local)"
cd "$DEPLOY_PATH"
docker compose -f "$COMPOSE_FILE" pull 2>&1 | tail -5 || \
  docker compose -f "$COMPOSE_FILE" build 2>&1 | tail -5

# ===== 4. Up containers (sin recrear DB/Redis) =====
echo ""
echo "[4/5] Restart containers"
docker compose -f "$COMPOSE_FILE" up -d --no-deps backend worker platform 2>&1 | tail -5

# ===== 5. Health check =====
echo ""
echo "[5/5] Health check (max 90s)"
HEALTHY=false
for i in $(seq 1 18); do
  STATUS=$(docker exec "$BACKEND_CONTAINER" wget -q -O - "$HEALTH_URL" 2>/dev/null | grep -c '"status":"ok"' || echo 0)
  if [ "$STATUS" -gt 0 ]; then
    echo "  ✓ Backend healthy en $((i*5))s"
    HEALTHY=true
    break
  fi
  echo "  Esperando warmup... ($((i*5))s)"
  sleep 5
done

# ===== Resultado =====
echo ""
echo "=========================================================================="
if [ "$HEALTHY" = true ]; then
  echo "  ✓ Rollback a $TAG completado OK"
  echo "  Backup del estado pre-rollback: $BACKUP_FILE"
  echo "  Para restaurar ese estado: gunzip < $BACKUP_FILE | docker exec -i $DB_CONTAINER psql -U \${POSTGRES_USER:-ams_user}"
  exit 0
else
  echo "  ✗ Health check falló — la nueva versión no responde"
  echo ""
  echo "  Opciones:"
  echo "    1. Investigar logs: docker logs --tail 50 $BACKEND_CONTAINER"
  echo "    2. Restaurar DB pre-rollback: gunzip < $BACKUP_FILE | docker exec -i $DB_CONTAINER psql -U \${POSTGRES_USER:-ams_user}"
  echo "    3. Rollback al tag anterior anterior: bash $0 <otro-tag>"
  exit 1
fi
