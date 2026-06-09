#!/usr/bin/env bash
# =============================================================================
# verify-config.sh — Valida configuración productiva antes del deploy
# =============================================================================
# Verifica:
#   - .env existe + chmod 600
#   - Secrets críticos presentes y de longitud correcta
#   - Defaults inseguros NO presentes
#   - DNS resolvable
#   - Docker daemon up
#   - rclone B2 configurado
#   - Tabla tenants accesible (si DB ya levantada)
#
# Uso:
#   bash scripts/verify-config.sh             # checks pre-deploy
#   bash scripts/verify-config.sh --post      # checks post-deploy
# =============================================================================
set -uo pipefail

MODE="${1:---pre}"
PASS=0
WARN=0
FAIL=0

ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠  $1"; WARN=$((WARN+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo ""
echo "=========================================================================="
echo "  AMS Platform · Verificación de configuración ($MODE)"
echo "=========================================================================="

# ===== 1. Archivo .env =====
echo ""
echo "[1/7] Archivo .env"
if [ ! -f .env ]; then
  fail ".env no existe — copiar de .env.production.example y completar"
  exit 1
fi
ok ".env existe"

PERM=$(stat -c "%a" .env 2>/dev/null || stat -f "%Lp" .env 2>/dev/null)
if [ "$PERM" = "600" ] || [ "$PERM" = "400" ]; then
  ok ".env tiene permisos seguros ($PERM)"
else
  warn ".env tiene permisos $PERM — recomendado 600. Fix: chmod 600 .env"
fi

# Cargar .env de forma defensiva
set -a
# shellcheck disable=SC1091
source .env 2>/dev/null || true
set +a

# ===== 2. Secrets críticos (FAIL-FAST en prod) =====
echo ""
echo "[2/7] Secrets críticos"
check_secret() {
  local name=$1 minlen=$2
  local val="${!name:-}"
  if [ -z "$val" ]; then
    fail "$name vacío — backend NO bootea en prod"
  elif [ ${#val} -lt "$minlen" ]; then
    fail "$name muy corto (${#val} chars, min $minlen)"
  else
    ok "$name OK (${#val} chars)"
  fi
}
check_secret JWT_SECRET 32
check_secret COOKIE_SECRET 32
check_secret POSTGRES_PASSWORD 16

# Defaults inseguros detectables
if [ "${GRAFANA_ADMIN_PASSWORD:-}" = "cambiame" ] || [ "${GRAFANA_ADMIN_PASSWORD:-}" = "cambiame-grafana" ]; then
  fail "GRAFANA_ADMIN_PASSWORD es valor por defecto inseguro"
fi
if [ "${POSTGRES_PASSWORD:-}" = "cambiame-pega-output-de-openssl-rand" ]; then
  fail "POSTGRES_PASSWORD es valor del template (sin reemplazar)"
fi
if [ "${AMS_BOOTSTRAP_ADMIN_PASSWORD:-}" = "cambiame-password-fuerte-de-12chars-min" ]; then
  fail "AMS_BOOTSTRAP_ADMIN_PASSWORD es valor del template"
fi

# ===== 3. Dominios + DNS =====
echo ""
echo "[3/7] Dominios"
check_dns() {
  local domain=$1
  if [ -z "$domain" ]; then return; fi
  if command -v dig >/dev/null 2>&1; then
    local ip
    ip=$(dig +short "$domain" A 2>/dev/null | head -1)
    if [ -n "$ip" ]; then
      ok "$domain → $ip"
    else
      warn "$domain no resuelve (DNS aún no propagado?)"
    fi
  else
    warn "dig no instalado, skip DNS check"
  fi
}
check_dns "${AMS_DOMAIN:-}"
check_dns "${AMS_API_DOMAIN:-}"

if [ -n "${PUBLIC_BASE_URL:-}" ]; then
  if [[ "$PUBLIC_BASE_URL" =~ ^https:// ]]; then
    ok "PUBLIC_BASE_URL es https://"
  else
    fail "PUBLIC_BASE_URL debe ser https:// en prod (es: $PUBLIC_BASE_URL)"
  fi
fi

# ===== 4. Multi-tenancy + safety =====
echo ""
echo "[4/7] Multi-tenancy + safety"
if [ "${ENABLE_PUBLIC_SIGNUP:-}" = "true" ]; then
  warn "ENABLE_PUBLIC_SIGNUP=true en prod — race condition admin posible"
else
  ok "ENABLE_PUBLIC_SIGNUP=false (correcto en prod)"
fi
if [ "${ENFORCE_ORIGIN_CSRF:-true}" = "false" ]; then
  fail "ENFORCE_ORIGIN_CSRF=false en prod — CSRF abierto"
else
  ok "CSRF protection activo"
fi
if [ "${MULTI_TENANCY_MODE:-}" = "" ]; then
  warn "MULTI_TENANCY_MODE no seteado (default 'hybrid')"
else
  ok "MULTI_TENANCY_MODE=$MULTI_TENANCY_MODE"
fi

# ===== 5. Docker =====
echo ""
echo "[5/7] Docker"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon corriendo"
    DC_VERSION=$(docker compose version --short 2>/dev/null || echo "?")
    ok "docker compose: $DC_VERSION"
  else
    fail "Docker daemon no responde"
  fi
else
  fail "docker no instalado"
fi

# ===== 6. rclone (backup) =====
echo ""
echo "[6/7] Backup (rclone)"
if command -v rclone >/dev/null 2>&1; then
  if rclone listremotes 2>/dev/null | grep -q "^b2:"; then
    ok "rclone remote 'b2:' configurado"
    if rclone ls b2:ams-prod-backups 2>/dev/null >/dev/null; then
      ok "B2 bucket ams-prod-backups accesible"
    else
      warn "B2 bucket inaccesible (verificar keyID/applicationKey)"
    fi
  else
    warn "rclone remote 'b2:' no configurado (correr: rclone config)"
  fi
else
  warn "rclone no instalado (apt install rclone)"
fi

# ===== 7. Migrations + tenants (solo modo post-deploy) =====
if [ "$MODE" = "--post" ]; then
  echo ""
  echo "[7/7] Foundation post-deploy"
  if docker ps --format '{{.Names}}' | grep -q ams-prod-db; then
    if docker exec ams-prod-db psql -U "${POSTGRES_USER:-ams_user}" -d "${POSTGRES_DB:-ams_agent}" -tAc \
      "SELECT EXISTS (SELECT FROM tenants WHERE id='default')" 2>/dev/null | grep -q "^t"; then
      ok "Tabla tenants existe con 'default' seedeado"
    else
      fail "Tabla tenants vacía o no existe — aplicar migration 005"
    fi
    if docker exec ams-prod-db psql -U "${POSTGRES_USER:-ams_user}" -d "${POSTGRES_DB:-ams_agent}" -tAc \
      "SELECT COUNT(*) FROM users WHERE tenant_id='default'" 2>/dev/null | grep -q "^[1-9]"; then
      ok "Bootstrap admin existe en tenant 'default'"
    else
      warn "No hay users en tenant 'default' — el primer signup creará el admin"
    fi
  else
    fail "Container ams-prod-db no está corriendo"
  fi
fi

# ===== Resumen =====
echo ""
echo "=========================================================================="
echo "  Resumen: $PASS OK · $WARN warnings · $FAIL fallos"
echo "=========================================================================="

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "✗ $FAIL CHECK(S) FALLARON — NO HACER DEPLOY hasta resolverlos"
  exit 1
elif [ $WARN -gt 0 ]; then
  echo ""
  echo "⚠  $WARN advertencias — revisar antes de deploy productivo"
  exit 0
else
  echo ""
  echo "✓ Configuración OK — listo para deploy"
  exit 0
fi
