#!/usr/bin/env bash
# =============================================================================
# restore-test.sh — Valida un backup SIN tocar la DB de producción
# =============================================================================
# Crea un Postgres efímero, restaura el dump ahí y verifica:
#   - Se puede cargar sin errores
#   - Tiene tablas core (users, audit_events, agent_usage, etc.)
#   - El conteo de filas es razonable
#
# Uso:
#   bash scripts/restore-test.sh /var/backups/ams/prod/ams_prod_20260609.sql.gz
#
# Salida: exit 0 = backup OK · exit 1 = backup roto
# Pensado para correr en cron semanal post-backup como smoke test:
#   0 5 * * 0 /opt/ams/supply-chain-ams-stack/scripts/restore-test.sh \
#     $(ls -t /var/backups/ams/prod/*.sql.gz | head -1) >> /var/log/ams-restore-test.log 2>&1
# =============================================================================
set -euo pipefail

DUMP="${1:-}"
[ -n "$DUMP" ] || { echo "Uso: $0 <archivo.sql.gz>" 1>&2; exit 1; }
[ -f "$DUMP" ] || { echo "[restore-test] no existe: $DUMP" 1>&2; exit 1; }

CONTAINER="ams-restore-test-$(date +%s)"
PG_PASS="restore_test_$(date +%s)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[restore-test] Levantando Postgres efímero ($CONTAINER)..."
docker run --rm -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PG_PASS" \
  -e POSTGRES_USER=ams_user \
  -e POSTGRES_DB=ams_restore_test \
  pgvector/pgvector:pg16 >/dev/null

echo "[restore-test] Esperando que Postgres esté ready..."
for i in $(seq 1 30); do
  if docker exec "$CONTAINER" pg_isready -U ams_user >/dev/null 2>&1; then
    echo "  ✓ ready en ${i}s"
    break
  fi
  sleep 1
done

echo "[restore-test] Restaurando $DUMP..."
if ! gunzip -c "$DUMP" | docker exec -i "$CONTAINER" psql -U ams_user -d ams_restore_test -v ON_ERROR_STOP=1 >/dev/null 2>&1; then
  echo "[restore-test] ❌ FAILED: error al restaurar el dump" 1>&2
  exit 1
fi
echo "  ✓ restore OK"

echo "[restore-test] Verificando tablas core..."
EXPECTED_TABLES=("users" "audit_events" "agent_usage" "incidents")
MISSING=0
for table in "${EXPECTED_TABLES[@]}"; do
  if ! docker exec "$CONTAINER" psql -U ams_user -d ams_restore_test -tAc \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='$table')" \
    | grep -q "^t$"; then
    echo "  ❌ tabla faltante: $table"
    MISSING=$((MISSING + 1))
  else
    COUNT=$(docker exec "$CONTAINER" psql -U ams_user -d ams_restore_test -tAc "SELECT COUNT(*) FROM $table")
    echo "  ✓ $table: $COUNT filas"
  fi
done

if [ "$MISSING" -gt 0 ]; then
  echo "[restore-test] ❌ FAILED: $MISSING tabla(s) crítica(s) faltante(s)" 1>&2
  exit 1
fi

# Validación adicional: el dump debe tener al menos 1 usuario (sino backup roto)
USERS=$(docker exec "$CONTAINER" psql -U ams_user -d ams_restore_test -tAc "SELECT COUNT(*) FROM users")
if [ "$USERS" -lt 1 ]; then
  echo "[restore-test] ❌ FAILED: 0 usuarios en backup (DB vacía?)" 1>&2
  exit 1
fi

echo "[restore-test] ✅ ALL OK · backup $DUMP es válido y restaurable"
exit 0
