#!/usr/bin/env bash
# =============================================================================
# backup-db-env.sh — pg_dump por ambiente (dev/qas/prod)
# =============================================================================
# Uso:
#   bash scripts/backup-db-env.sh prod                # backup a /var/backups/ams/prod/
#   bash scripts/backup-db-env.sh qas
#   bash scripts/backup-db-env.sh dev
#
# Cron sugerido en el VPS:
#   # PROD diario a las 3 AM (mantener 30 días)
#   0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1
#   # QAS cada 3 días (mantener 14 días)
#   0 4 */3 * * BACKUP_RETAIN_DAYS=14 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh qas >> /var/log/ams-backup-qas.log 2>&1
#   # DEV semanal (mantener 7 días)
#   0 4 * * 0 BACKUP_RETAIN_DAYS=7 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh dev >> /var/log/ams-backup-dev.log 2>&1
# =============================================================================
set -euo pipefail

ENV="${1:-}"
[[ -z "$ENV" ]] && { echo "Uso: $0 <dev|qas|prod>"; exit 1; }

case "$ENV" in
  dev|qas|prod) ;;
  *) echo "Ambiente desconocido: $ENV"; exit 1 ;;
esac

CONTAINER="ams-db-$ENV"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/ams}"
BACKUP_DIR="$BACKUP_ROOT/$ENV"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-30}"

# Cargar .env.{env} del agent para obtener credenciales
AGENT_DIR="${AGENT_DIR:-/opt/ams/supply-chain-ams-agent}"
ENV_FILE="$AGENT_DIR/.env.$ENV"
[ -f "$ENV_FILE" ] || { echo "[backup] No encuentro $ENV_FILE" 1>&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

POSTGRES_USER="${POSTGRES_USER:-ams_user}"
POSTGRES_DB="${POSTGRES_DB:-ams_agent_$ENV}"

mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$BACKUP_DIR/ams_${ENV}_${TS}.sql.gz"

echo "[backup-$ENV] dump $CONTAINER → $OUT"
docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges \
  | gzip > "$OUT"

# Validar
SIZE=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")
if [ "$SIZE" -lt 1024 ]; then
  echo "[backup-$ENV] ERROR: archivo demasiado chico ($SIZE bytes). pg_dump falló." 1>&2
  rm -f "$OUT"
  exit 1
fi
echo "[backup-$ENV] OK ($((SIZE / 1024)) KB)"

# Retención
find "$BACKUP_DIR" -name "ams_${ENV}_*.sql.gz" -mtime "+$RETAIN_DAYS" -delete
echo "[backup-$ENV] limpiados >$RETAIN_DAYS días"

# Sync a remoto opcional (B2 / S3 via rclone)
if command -v rclone >/dev/null && [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
  rclone copy "$OUT" "$BACKUP_RCLONE_REMOTE/ams/$ENV/" --quiet
  echo "[backup-$ENV] subido a $BACKUP_RCLONE_REMOTE/ams/$ENV/"
fi
