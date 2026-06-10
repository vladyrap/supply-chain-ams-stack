#!/bin/bash
# =============================================================================
# backup-ams-prod.sh — Backup nightly de DB AMS prod
# =============================================================================
# v1.2.7-prod
# - pg_dump custom format (comprimido + restaurable parcial)
# - Retención: 7 dailies + 4 weeklies + 6 monthlies
# - Log a /var/log/ams-backup.log
# - Opcional: si rclone está configurado, sube a remoto (Backblaze B2)
# =============================================================================
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/opt/ams/backups}"
DB_CONTAINER="${DB_CONTAINER:-ams-prod-db}"
DB_USER="${DB_USER:-ams_user}"
DB_NAME="${DB_NAME:-ams_prod}"
LOG_FILE="${LOG_FILE:-/var/log/ams-backup.log}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"  # ej: "b2:ams-prod-backups"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$BACKUP_ROOT"/{daily,weekly,monthly}

STAMP=$(date -u +%Y-%m-%d_%H%M%S)
DOW=$(date -u +%u)   # 1..7 (lunes..domingo)
DOM=$(date -u +%d)   # día del mes

DAILY_FILE="$BACKUP_ROOT/daily/ams_prod_${STAMP}.dump"

log "Backup DB AMS prod → $DAILY_FILE"

if ! docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -Fc -Z 9 "$DB_NAME" > "$DAILY_FILE.tmp"; then
  log "ERROR: pg_dump falló"
  rm -f "$DAILY_FILE.tmp"
  exit 1
fi
mv "$DAILY_FILE.tmp" "$DAILY_FILE"
SIZE=$(du -h "$DAILY_FILE" | cut -f1)
log "OK daily $SIZE"

# Domingo → weekly
if [ "$DOW" = "7" ]; then
  cp "$DAILY_FILE" "$BACKUP_ROOT/weekly/ams_prod_${STAMP}_wk.dump"
  log "OK weekly snapshot"
fi
# Día 1 → monthly
if [ "$DOM" = "01" ]; then
  cp "$DAILY_FILE" "$BACKUP_ROOT/monthly/ams_prod_${STAMP}_mo.dump"
  log "OK monthly snapshot"
fi

# Retención
find "$BACKUP_ROOT/daily"   -name "*.dump" -mtime +7  -delete
find "$BACKUP_ROOT/weekly"  -name "*.dump" -mtime +30 -delete
find "$BACKUP_ROOT/monthly" -name "*.dump" -mtime +180 -delete
log "Retención aplicada (7d/30d/180d)"

# Offsite con rclone (opcional)
if [ -n "$RCLONE_REMOTE" ] && command -v rclone >/dev/null 2>&1; then
  log "Sync offsite → $RCLONE_REMOTE"
  if rclone sync "$BACKUP_ROOT/daily" "$RCLONE_REMOTE/daily" --transfers 2 --quiet; then
    log "OK offsite daily"
  else
    log "WARN: rclone falló — backup local OK, remoto NO"
  fi
fi

log "Backup completo."
