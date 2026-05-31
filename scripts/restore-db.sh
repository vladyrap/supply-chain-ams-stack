#!/usr/bin/env bash
# =============================================================
# restore-db.sh — restaura un dump al Postgres de producción
# =============================================================
# Uso:
#   bash scripts/restore-db.sh /var/backups/ams/ams_db_20260530T030000Z.sql.gz
#
# ATENCIÓN: esto BORRA y reemplaza el contenido actual de la DB.
# =============================================================
set -euo pipefail

DUMP="${1:-}"
[ -n "$DUMP" ] || { echo "Uso: $0 <archivo.sql.gz>" 1>&2; exit 1; }
[ -f "$DUMP" ] || { echo "[restore] no existe: $DUMP" 1>&2; exit 1; }

ENV_FILE="$(dirname "$0")/../.env"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

POSTGRES_USER="${POSTGRES_USER:-ams_user}"
POSTGRES_DB="${POSTGRES_DB:-ams_agent}"

echo "[restore] ⚠ Esto BORRA todo en $POSTGRES_DB y restaura desde $DUMP"
read -r -p "Confirmar tipeando \"si reemplazar\": " CONFIRM
[ "$CONFIRM" = "si reemplazar" ] || { echo "[restore] cancelado"; exit 1; }

echo "[restore] drop y crear base de datos…"
docker exec ams-prod-db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB"
docker exec ams-prod-db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB"

echo "[restore] cargando dump…"
gunzip -c "$DUMP" | docker exec -i ams-prod-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

echo "[restore] OK"
