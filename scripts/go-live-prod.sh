#!/usr/bin/env bash
# =============================================================================
# go-live-prod.sh — Primer deploy a PROD en un comando
# =============================================================================
# Ejecutar DESPUÉS de bootstrap-go-live.sh + completar /opt/ams/bootstrap-config.env
#
# Hace todo:
#   1. Lee bootstrap-config.env
#   2. Valida que DNS apunte al VPS
#   3. Genera /etc/caddy/Caddyfile con tus dominios reales
#   4. Genera .env.prod en agent y platform
#   5. Build + up de containers PROD
#   6. Smoke test final
#
# Uso:
#   bash /opt/ams/supply-chain-ams-stack/scripts/go-live-prod.sh
# =============================================================================
set -euo pipefail

CFG="/opt/ams/bootstrap-config.env"
AGENT_DIR="/opt/ams/supply-chain-ams-agent"
PLATFORM_DIR="/opt/ams/supply-chain-ams-platform"
STACK_DIR="/opt/ams/supply-chain-ams-stack"

log()  { echo -e "\033[36m[go-live]\033[0m $*"; }
warn() { echo -e "\033[33m[go-live]\033[0m $*"; }
err()  { echo -e "\033[31m[go-live]\033[0m $*" 1>&2; }
ok()   { echo -e "\033[32m[go-live]\033[0m $*"; }

if [ "$(id -u)" -ne 0 ]; then
  err "Ejecutar como root"
  exit 1
fi

# ============================================================
# 1. Validar config
# ============================================================
log "[1/6] Validando $CFG..."
[ -f "$CFG" ] || { err "No existe $CFG — ejecutá bootstrap-go-live.sh primero"; exit 1; }

# shellcheck disable=SC1090
set -a; source "$CFG"; set +a

required=(AMS_DOMAIN LETSENCRYPT_EMAIL GEMINI_API_KEY_PROD POSTGRES_PASSWORD_PROD AMS_ADMIN_EMAIL AMS_ADMIN_PASSWORD)
missing=()
for v in "${required[@]}"; do
  if [ -z "${!v:-}" ]; then missing+=("$v"); fi
done
if [ ${#missing[@]} -gt 0 ]; then
  err "Variables faltantes en $CFG: ${missing[*]}"
  err "Editá ese archivo, completalas y volvé a correr este script."
  exit 1
fi

API_DOMAIN="api.${AMS_DOMAIN}"
ok "  Dominio frontend: $AMS_DOMAIN"
ok "  Dominio API:      $API_DOMAIN"

# ============================================================
# 2. Validar DNS
# ============================================================
log "[2/6] Validando DNS..."
PUBLIC_IP=$(curl -s https://ifconfig.io || curl -s https://ipinfo.io/ip)
[ -n "$PUBLIC_IP" ] || { err "No pude obtener IP pública del VPS"; exit 1; }
log "  IP pública VPS: $PUBLIC_IP"

for dom in "$AMS_DOMAIN" "$API_DOMAIN"; do
  RESOLVED=$(dig +short "$dom" @1.1.1.1 | head -1)
  if [ -z "$RESOLVED" ]; then
    err "  $dom NO resuelve a ninguna IP. Apuntá DNS antes de seguir."
    exit 1
  fi
  if [ "$RESOLVED" != "$PUBLIC_IP" ]; then
    warn "  $dom resuelve a $RESOLVED (esperado $PUBLIC_IP)"
    warn "  Si recién apuntaste DNS, esperá 5-15 min y reintentá."
    read -p "  ¿Seguir igual? (yes/N): " ans
    [ "$ans" = "yes" ] || exit 0
  else
    ok "  $dom → $PUBLIC_IP ✓"
  fi
done

# ============================================================
# 3. Generar Caddyfile
# ============================================================
log "[3/6] Generando /etc/caddy/Caddyfile..."
cat > /etc/caddy/Caddyfile <<EOF
# Generado por go-live-prod.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  email $LETSENCRYPT_EMAIL
}

$AMS_DOMAIN {
  encode gzip zstd
  reverse_proxy localhost:6900
  log {
    output file /var/log/caddy/prod-platform.log {
      roll_size 100mb
      roll_keep 10
    }
  }
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
  }
}

$API_DOMAIN {
  encode gzip zstd
  reverse_proxy localhost:6901
  log {
    output file /var/log/caddy/prod-api.log {
      roll_size 100mb
      roll_keep 10
    }
  }
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
  }
}
EOF

caddy validate --config /etc/caddy/Caddyfile || { err "Caddyfile inválido"; exit 1; }
systemctl restart caddy
sleep 3
systemctl is-active --quiet caddy || { err "Caddy no arrancó"; systemctl status caddy --no-pager | tail; exit 1; }
ok "  Caddy corriendo. Let's Encrypt está pidiendo certificados (~30s)..."

# ============================================================
# 4. Generar .env.prod en agent y platform
# ============================================================
log "[4/6] Generando .env.prod..."

cat > "$AGENT_DIR/.env.prod" <<EOF
# Generado por go-live-prod.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ)
NODE_ENV=production
LOG_LEVEL=warn
BACKEND_PORT=8000
FRONTEND_PORT=3000

GEMINI_API_KEY=$GEMINI_API_KEY_PROD
GEMINI_MODEL=gemini-2.5-flash

POSTGRES_USER=ams_user
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_PROD
POSTGRES_DB=ams_agent_prod
DATABASE_URL=postgresql://ams_user:$POSTGRES_PASSWORD_PROD@db-prod:5432/ams_agent_prod

REDIS_URL=redis://redis-prod:6379/0

RAG_ENABLED=true
RAG_TOP_K=6
RAG_MIN_SCORE=0.55
GEMINI_EMBEDDING_MODEL=gemini-embedding-001
GEMINI_EMBEDDING_DIM=768
RAG_CHUNK_CHARS=3500
RAG_CHUNK_OVERLAP=400

AMS_BOOTSTRAP_ADMIN_EMAIL=$AMS_ADMIN_EMAIL
AMS_BOOTSTRAP_ADMIN_PASSWORD=$AMS_ADMIN_PASSWORD

SENTRY_DSN=$SENTRY_DSN
EOF
chmod 600 "$AGENT_DIR/.env.prod"

cat > "$PLATFORM_DIR/.env.prod" <<EOF
# Generado por go-live-prod.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ)
NODE_ENV=production
PORT=3000
NEXT_PUBLIC_AGENT_API_URL=https://$API_DOMAIN
NEXT_PUBLIC_SENTRY_DSN=$SENTRY_DSN
EOF
chmod 600 "$PLATFORM_DIR/.env.prod"

ok "  .env.prod generados (permisos 600)"

# ============================================================
# 5. Checkout branch prod + build + up
# ============================================================
log "[5/6] Build + up containers PROD..."

# Si las branches prod no existen aún (caso de bootstrap inicial), usar main
for repo_dir in "$AGENT_DIR" "$PLATFORM_DIR"; do
  cd "$repo_dir"
  git fetch --all --tags --prune
  if git show-ref --verify --quiet refs/remotes/origin/prod; then
    git checkout prod
    git pull origin prod
  else
    warn "  $(basename $repo_dir): branch 'prod' no existe en origin, uso 'main'"
    git checkout main
    git pull origin main
  fi
done

cd "$AGENT_DIR"
log "  Building backend..."
docker compose -f docker-compose.prod.yml --env-file .env.prod -p ams-prod build 2>&1 | tail -5
log "  Up backend + db + redis..."
docker compose -f docker-compose.prod.yml --env-file .env.prod -p ams-prod up -d

cd "$PLATFORM_DIR"
log "  Building platform..."
docker compose -f docker-compose.prod.yml --env-file .env.prod -p ams-platform-prod build 2>&1 | tail -5
log "  Up platform..."
docker compose -f docker-compose.prod.yml --env-file .env.prod -p ams-platform-prod up -d

# ============================================================
# 6. Smoke test
# ============================================================
log "[6/6] Smoke test..."
sleep 10

# Esperar backend healthy
for i in $(seq 1 30); do
  status=$(docker inspect --format '{{.State.Health.Status}}' ams-backend-prod 2>/dev/null || echo "starting")
  [ "$status" = "healthy" ] && { ok "  backend healthy"; break; }
  printf "."
  sleep 4
  if [ $i -eq 30 ]; then
    err "Backend no llegó a healthy en 2 min. Logs:"
    docker logs ams-backend-prod --tail 20
    exit 1
  fi
done
echo

# Test HTTPS frontend
log "  Testing https://$AMS_DOMAIN ..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$AMS_DOMAIN" || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "307" ] || [ "$HTTP_CODE" = "302" ]; then
  ok "  Frontend HTTPS OK ($HTTP_CODE)"
else
  warn "  Frontend devolvió $HTTP_CODE — esperar 1-2 min más a que Let's Encrypt termine"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$API_DOMAIN/api/tickets/provider" || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
  ok "  API HTTPS OK ($HTTP_CODE — 401 es esperado por RBAC)"
else
  warn "  API devolvió $HTTP_CODE"
fi

echo ""
ok "========================================="
ok "  GO-LIVE PROD COMPLETADO"
ok "========================================="
ok "  Frontend: https://$AMS_DOMAIN"
ok "  API:      https://$API_DOMAIN"
ok "  Admin:    $AMS_ADMIN_EMAIL"
ok "========================================="
echo ""
log "Próximos pasos:"
log "  - Loguearte con $AMS_ADMIN_EMAIL y la password que pusiste"
log "  - Activar cron de backups: crontab -e"
log "    0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1"
log "  - (Opcional) sumar DEV y QAS con deploy-env.sh dev / qas"
echo ""
