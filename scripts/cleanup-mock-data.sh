#!/usr/bin/env bash
# =============================================================================
# cleanup-mock-data.sh — Limpia datos demo de DB productiva (v0.4.1)
# =============================================================================
# ANTES de pasar a prod, ejecutar esto para sacar:
#   - users con @demo.cl (4 cuentas: admin, viewer, consultor, aprobador)
#   - tickets_demo (16 tickets de prueba)
#   - incidents demo (los que tienen client_name = 'demo')
#   - audit_events generados por usuarios @demo.cl
#
# Mantiene:
#   - users reales (no @demo.cl)
#   - admin@TU_EMPRESA si lo creaste
#   - schema (tablas e índices)
#
# Uso:
#   bash scripts/cleanup-mock-data.sh prod    # solicita confirmación
#   FORCE=1 bash scripts/cleanup-mock-data.sh prod   # sin confirmación
# =============================================================================
set -euo pipefail

ENV="${1:-}"
[[ -z "$ENV" ]] && { echo "Uso: $0 <dev|qas|prod>"; exit 1; }

case "$ENV" in
  dev|qas|prod) ;;
  *) echo "Ambiente desconocido: $ENV"; exit 1 ;;
esac

CONTAINER="ams-db-$ENV"
DB_USER="${POSTGRES_USER:-ams_user}"
DB_NAME="ams_agent_$ENV"

[[ "$ENV" = "dev" ]] && CONTAINER="supply-chain-ams-db" && DB_NAME="ams_agent"

if [ "${FORCE:-0}" != "1" ]; then
  echo "==========================================="
  echo "  ⚠ CLEANUP DE MOCK DATA — ambiente: $ENV"
  echo "==========================================="
  echo ""
  echo "Esto BORRA permanentemente:"
  echo "  - users @demo.cl"
  echo "  - tickets_demo (todos)"
  echo "  - incidents demo"
  echo "  - audit_events de usuarios @demo.cl"
  echo ""
  echo "Container: $CONTAINER · DB: $DB_NAME"
  echo ""
  read -r -p "Confirmar tipeando \"si limpiar $ENV\": " CONFIRM
  [ "$CONFIRM" = "si limpiar $ENV" ] || { echo "[cleanup] cancelado"; exit 1; }
fi

echo "[cleanup-$ENV] Iniciando..."

# Backup pre-cleanup (siempre, por seguridad)
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="/tmp/ams_pre_cleanup_${ENV}_${TS}.sql.gz"
echo "[cleanup-$ENV] Backup pre-cleanup: $BACKUP"
docker exec "$CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" | gzip > "$BACKUP"
echo "  ✓ backup OK ($(stat -c%s "$BACKUP" 2>/dev/null || stat -f%z "$BACKUP") bytes)"

echo "[cleanup-$ENV] Limpieza..."
docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

-- Conteos iniciales (para reporte)
\echo 'CONTEOS PRE-CLEANUP:'
SELECT 'users_total' AS metric, COUNT(*) AS n FROM users
UNION ALL SELECT 'users_demo', COUNT(*) FROM users WHERE email LIKE '%@demo.cl'
UNION ALL SELECT 'tickets_demo', COUNT(*) FROM tickets_demo
UNION ALL SELECT 'incidents', COUNT(*) FROM incidents
UNION ALL SELECT 'audit_events', COUNT(*) FROM audit_events;

-- 1. audit_events de actores @demo.cl (por actor_user_id O actor_name email)
DELETE FROM audit_events
WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE '%@demo.cl')
   OR actor_name LIKE '%@demo.cl';

-- 2. tickets_demo — limpiar TODA la tabla (es demo)
TRUNCATE tickets_demo;

-- 3. incidents con client_name='demo' o sin user_name real
DELETE FROM incidents
WHERE client_name ILIKE 'demo' OR user_name ILIKE '%demo%';

-- 4. agent_usage de incidents borrados (cleanup cascade manual)
DELETE FROM agent_usage WHERE incident_id NOT IN (SELECT id FROM incidents);

-- 5. users demo (al final, después de FK cleanup)
DELETE FROM users WHERE email LIKE '%@demo.cl';

-- Conteos finales
\echo 'CONTEOS POST-CLEANUP:'
SELECT 'users_total' AS metric, COUNT(*) AS n FROM users
UNION ALL SELECT 'tickets_demo', COUNT(*) FROM tickets_demo
UNION ALL SELECT 'incidents', COUNT(*) FROM incidents
UNION ALL SELECT 'audit_events', COUNT(*) FROM audit_events
UNION ALL SELECT 'agent_usage', COUNT(*) FROM agent_usage;

COMMIT;

\echo 'OK: cleanup en transacción confirmado'
SQL

echo "[cleanup-$ENV] ✅ Hecho"
echo ""
echo "Si algo salió mal, restaurar con:"
echo "  gunzip -c $BACKUP | docker exec -i $CONTAINER psql -U $DB_USER -d $DB_NAME"
echo ""
echo "Si todo OK, podés borrar el backup:"
echo "  rm $BACKUP"
