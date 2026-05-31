#!/usr/bin/env bash
# =============================================================
# healthcheck.sh — verificación rápida del stack en prod
# =============================================================
# Uso:
#   bash scripts/healthcheck.sh
#
# Exit code 0 = todo OK, !=0 = algo falla.
# =============================================================
set -euo pipefail

ENV_FILE="$(dirname "$0")/../.env"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

DOMAIN="${AMS_DOMAIN:-ams.miespejo.cl}"
API_DOMAIN="${AMS_API_DOMAIN:-api.ams.miespejo.cl}"

ok() { echo -e "  \033[32m✓\033[0m $*"; }
fail() { echo -e "  \033[31m✗\033[0m $*"; FAILED=1; }
hdr() { echo -e "\n\033[36m▸ $*\033[0m"; }

FAILED=0

hdr "Containers"
for c in ams-prod-caddy ams-prod-backend ams-prod-platform ams-prod-db ams-prod-redis ams-prod-worker; do
  status=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  if [ "$status" = "running" ]; then ok "$c · running"; else fail "$c · $status"; fi
done

hdr "Health endpoints (internos)"
code=$(docker exec ams-prod-backend node -e "fetch('http://localhost:8000/health').then(r=>console.log(r.status))" 2>/dev/null || echo "ERR")
[ "$code" = "200" ] && ok "backend /health · 200" || fail "backend /health · $code"

hdr "Endpoints públicos (vía Caddy + HTTPS)"
for url in "https://$DOMAIN/" "https://$API_DOMAIN/health"; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" || echo "ERR")
  if [ "$code" = "200" ] || [ "$code" = "307" ]; then
    ok "$url · $code"
  else
    fail "$url · $code"
  fi
done

hdr "Postgres"
pgok=$(docker exec ams-prod-db pg_isready -U "${POSTGRES_USER:-ams_user}" -d "${POSTGRES_DB:-ams_agent}" 2>&1 | grep -c "accepting connections" || true)
[ "$pgok" -gt 0 ] && ok "pg_isready · accepting connections" || fail "pg_isready · no responde"

hdr "Disk space"
du_root=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
[ "$du_root" -lt 85 ] && ok "Disco / · ${du_root}% usado" || fail "Disco / · ${du_root}% usado (>85%)"

hdr "Uploads volume"
upload_size=$(docker exec ams-prod-backend du -sh /app/uploads 2>/dev/null | awk '{print $1}' || echo "?")
ok "/app/uploads · $upload_size"

hdr "Memoria"
mem=$(free -h | awk '/^Mem:/ {print $3 " / " $2 " (libre " $7 ")"}')
ok "RAM · $mem"

echo
if [ $FAILED -eq 0 ]; then
  echo -e "\033[32m✓ Todos los checks pasaron.\033[0m"
  exit 0
else
  echo -e "\033[31m✗ Hay checks que fallaron. Revisar arriba.\033[0m"
  exit 1
fi
