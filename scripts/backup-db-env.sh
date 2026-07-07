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

# v1.3.0 FIX: el container real es ams-<env>-db (ej. ams-prod-db), NO ams-db-<env>
# (nombre invertido → nunca existió → backup/cron fallaban en silencio).
CONTAINER="ams-$ENV-db"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/ams}"
BACKUP_DIR="$BACKUP_ROOT/$ENV"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-30}"

# v1.3.0 FIX: las credenciales se leen del PROPIO container (su env POSTGRES_*),
# no de un $AGENT_DIR/.env.<env> del host (que no existe en el VPS → fallaba).
docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' | grep -qx "$CONTAINER" \
  || { echo "[backup-$ENV] container '$CONTAINER' no está corriendo" 1>&2; exit 1; }

mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$BACKUP_DIR/ams_${ENV}_${TS}.sql.gz"

echo "[backup-$ENV] dump $CONTAINER → $OUT"

# FIX A20 (audit v1.1.0): pg_dump a archivo intermedio + gzip por separado.
# Antes: pg_dump | gzip ocultaba fallos de pg_dump (gzip producía .gz "exitoso"
# de 200 bytes con header válido). SIZE>1024 no detectaba dumps truncados.
# Ahora: si pg_dump falla → exit code != 0 → set -e aborta → nunca se comprime.
# Y gunzip -t valida integridad del .gz al final.
TMP_SQL="$BACKUP_DIR/ams_${ENV}_${TS}.sql.tmp"
# Credenciales tomadas del env del container (POSTGRES_USER/PASSWORD/DB).
docker exec "$CONTAINER" sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' > "$TMP_SQL"
gzip -f "$TMP_SQL"
GZIP_FILE="${TMP_SQL}.gz"
mv "$GZIP_FILE" "$OUT"

# Validar tamaño + integridad gzip
SIZE=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")
if [ "$SIZE" -lt 1024 ]; then
  echo "[backup-$ENV] ERROR: archivo demasiado chico ($SIZE bytes). pg_dump falló." 1>&2
  rm -f "$OUT"
  exit 1
fi
if ! gunzip -t "$OUT" 2>/dev/null; then
  echo "[backup-$ENV] ERROR: archivo corrupto (gunzip -t falló)." 1>&2
  rm -f "$OUT"
  exit 1
fi
echo "[backup-$ENV] OK ($((SIZE / 1024)) KB, integridad gzip verificada)"

# Retención
find "$BACKUP_DIR" -name "ams_${ENV}_*.sql.gz" -mtime "+$RETAIN_DAYS" -delete
echo "[backup-$ENV] limpiados >$RETAIN_DAYS días"

# Sync a remoto opcional (B2 / S3 via rclone)
if command -v rclone >/dev/null && [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
  rclone copy "$OUT" "$BACKUP_RCLONE_REMOTE/ams/$ENV/" --quiet
  echo "[backup-$ENV] subido a $BACKUP_RCLONE_REMOTE/ams/$ENV/"
fi
