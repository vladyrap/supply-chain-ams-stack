#!/bin/bash
# =============================================================================
# import-historical-tickets.sh — Importar tickets reales resueltos a la KB
# =============================================================================
# v1.2.8-prod
# Recibe un CSV con casos resueltos y los inserta como rows en support_tickets
# + genera un knowledge_document por cada caso para que el RAG lo consulte.
#
# CSV esperado (separador ; o ,):
#   sintoma;modulo_sap;proceso;cliente;causa_raiz;resolucion;horas_reales;prioridad
#
# Uso:
#   sudo bash import-historical-tickets.sh /tmp/casos_historicos.csv [tenant_id]
# =============================================================================
set -euo pipefail

CSV="${1:-}"
TENANT="${2:-default}"
if [ -z "$CSV" ] || [ ! -f "$CSV" ]; then
  echo "Uso: $0 <ruta_csv> [tenant_id]"
  echo "El CSV debe tener encabezado: sintoma;modulo_sap;proceso;cliente;causa_raiz;resolucion;horas_reales;prioridad"
  exit 1
fi

# Detectar separador (; o ,)
HEADER=$(head -1 "$CSV")
if echo "$HEADER" | grep -q ';'; then SEP=';'; else SEP=','; fi
echo "Detected separator: $SEP"

CONTAINER="ams-prod-db"
TMP_SQL=$(mktemp /tmp/import_kb.XXXXXX.sql)

cat > "$TMP_SQL" <<EOF
-- Auto-generated import of historical tickets to KB
BEGIN;
EOF

ROW_COUNT=0
tail -n +2 "$CSV" | while IFS="$SEP" read -r sintoma modulo proceso cliente causa resolucion horas prioridad; do
  # Escape single quotes (SQL standard)
  esc_sintoma=$(echo "$sintoma" | sed "s/'/''/g")
  esc_causa=$(echo "$causa" | sed "s/'/''/g")
  esc_res=$(echo "$resolucion" | sed "s/'/''/g")
  esc_cli=$(echo "$cliente" | sed "s/'/''/g")
  esc_mod=$(echo "$modulo" | sed "s/'/''/g")
  esc_proc=$(echo "$proceso" | sed "s/'/''/g")
  uuid=$(uuidgen | tr 'A-Z' 'a-z')

  cat >> "$TMP_SQL" <<EOF

-- Caso $((++ROW_COUNT))
INSERT INTO knowledge_documents (id, title, source_type, module, process, client, status, chunk_count, tenant_id, indexed_at)
VALUES ('$uuid', 'Caso histórico · ${esc_sintoma:0:60}', 'caso_historico', '$esc_mod', '$esc_proc', '$esc_cli', 'indexed', 1, '$TENANT', NOW());

INSERT INTO knowledge_items (document_id, title, source_type, module, process, client, chunk_index, content, tokens, tenant_id)
VALUES ('$uuid', '${esc_sintoma:0:60}', 'caso_historico', '$esc_mod', '$esc_proc', '$esc_cli', 0,
  'SÍNTOMA: $esc_sintoma' || E'\n' ||
  'MÓDULO: $esc_mod ($esc_proc)' || E'\n' ||
  'CLIENTE: $esc_cli' || E'\n' ||
  'CAUSA RAÍZ: $esc_causa' || E'\n' ||
  'RESOLUCIÓN: $esc_res' || E'\n' ||
  'HORAS REALES: $horas' || E'\n' ||
  'PRIORIDAD: $prioridad',
  120, '$TENANT');
EOF
done

cat >> "$TMP_SQL" <<EOF
COMMIT;
SELECT COUNT(*) AS casos_importados FROM knowledge_documents WHERE source_type='caso_historico' AND tenant_id='$TENANT';
EOF

echo "Ejecutando import…"
docker cp "$TMP_SQL" "$CONTAINER":/tmp/import.sql
docker exec "$CONTAINER" psql -U ams_user -d ams_prod -f /tmp/import.sql

rm -f "$TMP_SQL"
echo "✓ Import completo."
