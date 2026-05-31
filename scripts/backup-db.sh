#!/usr/bin/env bash
# =============================================================
# backup-db.sh — pg_dump del Postgres de producción
# =============================================================
# Uso:
#   bash scripts/backup-db.sh              # backup a /var/backups/ams/
#   bash scripts/backup-db.sh /tmp         # backup a /tmp
#
# Cron sugerido (en el VPS, asumiendo el layout que crea bootstrap-vps.sh):
#   0 3 * * * /opt/ams/supply-chain-ams-stack/scripts/backup-db.sh >> /var/log/ams-backup.log 2>&1
# =============================================================
set -euo pipefail

BACKUP_DIR="${1:-/var/backups/ams}"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-14}"

# Cargar .env para obtener POSTGRES_USER/PASSWORD/DB
ENV_FILE="$(dirname "$0")/../.env"
[ -f "$ENV_FILE" ] || { echo "[backup] No encuentro $ENV_FILE" 1>&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

POSTGRES_USER="${POSTGRES_USER:-ams_user}"
POSTGRES_DB="${POSTGRES_DB:-ams_agent}"

mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$BACKUP_DIR/ams_db_${TS}.sql.gz"

echo "[backup] dump → $OUT"
docker exec ams-prod-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges \
  | gzip > "$OUT"

# Verificar tamaño mínimo (1KB)
SIZE=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")
if [ "$SIZE" -lt 1024 ]; then
  echo "[backup] ERROR: archivo demasiado chico ($SIZE bytes). pg_dump falló." 1>&2
  rm -f "$OUT"
  exit 1
fi

echo "[backup] OK ($((SIZE / 1024)) KB)"

# Retención: borrar backups con más de N días
find "$BACKUP_DIR" -name "ams_db_*.sql.gz" -mtime "+$RETAIN_DAYS" -delete
echo "[backup] limpiados backups con más de $RETAIN_DAYS días"

# Si tenés rclone configurado, subir a S3/Drive (opcional, comentado)
# if command -v rclone >/dev/null && [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
#   rclone copy "$OUT" "$BACKUP_RCLONE_REMOTE/ams/" --quiet
#   echo "[backup] subido a $BACKUP_RCLONE_REMOTE/ams/"
# fi
