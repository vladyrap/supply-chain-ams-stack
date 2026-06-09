#!/usr/bin/env bash
# =============================================================
# restore-db.sh — restaura un dump al Postgres de producción
# =============================================================
# Uso:
#   bash scripts/restore-db.sh /var/backups/ams/ams_db_20260530T030000Z.sql.gz
#
# ATENCIÓN: esto BORRA y reemplaza el contenido actual de la DB.
#
# FIX B7 (audit v1.1.0):
#   - Validar integridad del .gz con gunzip -t ANTES de drop
#   - Terminar conexiones activas con pg_terminate_backend (drop falla con
#     "database is being accessed by other users" si no)
#   - Detener backend + worker antes para evitar re-conexión inmediata
# =============================================================
set -euo pipefail

DUMP="${1:-}"
[ -n "$DUMP" ] || { echo "Uso: $0 <archivo.sql.gz>" 1>&2; exit 1; }
[ -f "$DUMP" ] || { echo "[restore] no existe: $DUMP" 1>&2; exit 1; }

# FIX B7: validar integridad del .gz ANTES de tocar la DB
if ! gunzip -t "$DUMP" 2>/dev/null; then
  echo "[restore] ERROR: dump corrupto (gunzip -t falló): $DUMP" 1>&2
  exit 1
fi

ENV_FILE="$(dirname "$0")/../.env"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

POSTGRES_USER="${POSTGRES_USER:-ams_user}"
POSTGRES_DB="${POSTGRES_DB:-ams_agent}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

echo "[restore] ⚠ Esto BORRA todo en $POSTGRES_DB y restaura desde $DUMP"
read -r -p "Confirmar tipeando \"si reemplazar\": " CONFIRM
[ "$CONFIRM" = "si reemplazar" ] || { echo "[restore] cancelado"; exit 1; }

# FIX B7: parar backend + worker que mantienen conexiones abiertas
echo "[restore] deteniendo backend + worker para liberar conexiones…"
docker compose -f "$COMPOSE_FILE" stop backend worker 2>/dev/null || true

# FIX B7: terminar conexiones residuales (otros clientes, pg_admin, etc)
echo "[restore] terminando conexiones residuales a $POSTGRES_DB…"
docker exec ams-prod-db psql -U "$POSTGRES_USER" -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$POSTGRES_DB' AND pid<>pg_backend_pid()" \
  >/dev/null || true

echo "[restore] drop y crear base de datos…"
docker exec ams-prod-db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB"
docker exec ams-prod-db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB"

echo "[restore] cargando dump…"
gunzip -c "$DUMP" | docker exec -i ams-prod-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# Re-arrancar servicios detenidos
echo "[restore] re-arrancando backend + worker…"
docker compose -f "$COMPOSE_FILE" start backend worker 2>/dev/null || true

echo "[restore] OK"
