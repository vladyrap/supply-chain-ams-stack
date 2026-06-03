#!/usr/bin/env bash
# =============================================================================
# bootstrap-go-live.sh — Setup VPS de cero a AMS Platform en internet
# =============================================================================
# Ejecutar UNA VEZ en un VPS Ubuntu 22.04+/Debian 12+ fresco, como root.
#
# Modo "todo o nada":
#   - Instala Docker + Caddy + fail2ban + ufw
#   - Clona los 3 repos en /opt/ams/
#   - Crea red Docker ams-network
#   - Crea estructura /var/backups/ams/{dev,qas,prod}
#   - Genera /opt/ams/bootstrap-config.env (vacío) para que completés
#   - Configura Caddy con placeholders (NO arranca PROD hasta que completes config)
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/vladyrap/supply-chain-ams-stack/main/scripts/bootstrap-go-live.sh | bash
#
# Después de correr esto, editá /opt/ams/bootstrap-config.env con tus valores
# y ejecutá `bash /opt/ams/supply-chain-ams-stack/scripts/go-live-prod.sh`
# =============================================================================
set -euo pipefail

log()  { echo -e "\033[36m[bootstrap]\033[0m $*"; }
warn() { echo -e "\033[33m[bootstrap]\033[0m $*"; }
err()  { echo -e "\033[31m[bootstrap]\033[0m $*" 1>&2; }
ok()   { echo -e "\033[32m[bootstrap]\033[0m $*"; }

# Root check
if [ "$(id -u)" -ne 0 ]; then
  err "Ejecutar como root: sudo bash $0"
  exit 1
fi

# OS check
if [ ! -f /etc/os-release ]; then
  err "No es un sistema Linux con /etc/os-release"
  exit 1
fi
. /etc/os-release
case "$ID" in
  ubuntu|debian) ;;
  *) err "OS no soportado: $ID (esperado ubuntu/debian)"; exit 1 ;;
esac
log "OS: $PRETTY_NAME"

# === 1. Update + paquetes base ===
log "[1/7] Actualizando paquetes del sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl ca-certificates gnupg lsb-release \
  git ufw fail2ban \
  debian-keyring debian-archive-keyring apt-transport-https \
  htop ncdu jq wget

# === 2. Docker ===
if ! command -v docker >/dev/null; then
  log "[2/7] Instalando Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker instalado: $(docker --version)"
else
  ok "[2/7] Docker ya instalado: $(docker --version)"
fi

# === 3. Caddy ===
if ! command -v caddy >/dev/null; then
  log "[3/7] Instalando Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y caddy
  ok "Caddy instalado: $(caddy version)"
else
  ok "[3/7] Caddy ya instalado: $(caddy version)"
fi

# === 4. Firewall + fail2ban ===
log "[4/7] Configurando firewall (ufw) + fail2ban..."
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
systemctl enable --now fail2ban
ok "Firewall: 22, 80, 443 abiertos. fail2ban activo."

# === 5. Estructura directorios + clonar repos ===
log "[5/7] Creando estructura /opt/ams + clonando repos..."
mkdir -p /opt/ams /var/backups/ams/{dev,qas,prod} /var/log/caddy
chmod 700 /var/backups/ams
cd /opt/ams

for repo in supply-chain-ams-stack supply-chain-ams-agent supply-chain-ams-platform; do
  if [ ! -d "/opt/ams/$repo" ]; then
    log "  clonando $repo..."
    git clone "https://github.com/vladyrap/$repo.git" 2>&1 | tail -3
  else
    log "  $repo ya existe, salto"
  fi
done

# === 6. Red Docker compartida ===
log "[6/7] Creando red Docker ams-network..."
docker network create ams-network 2>/dev/null || ok "  ams-network ya existe"

# === 7. Generar bootstrap-config.env si no existe ===
CFG="/opt/ams/bootstrap-config.env"
if [ ! -f "$CFG" ]; then
  log "[7/7] Generando $CFG (completar antes de go-live)..."
  cat > "$CFG" <<'EOF'
# =============================================================================
# bootstrap-config.env — COMPLETAR ANTES de ejecutar go-live-prod.sh
# =============================================================================

# --- Dominio root (sin https://, sin trailing slash) ---
# Ejemplos: amsplatform.io / sap-ams.tudominio.com
# Los subdominios se construyen así:
#   PROD frontend: amsplatform.tudominio.com
#   PROD API:      api.amsplatform.tudominio.com
#   (DEV/QAS opcionales — se activan después)
AMS_DOMAIN=amsplatform.tudominio.com

# --- Email para Let's Encrypt (notificaciones de renovación) ---
LETSENCRYPT_EMAIL=admin@tudominio.com

# --- Gemini API key PROD ---
# Generar en https://aistudio.google.com/app/apikey
GEMINI_API_KEY_PROD=

# --- Postgres password PROD (>=16 chars, sin espacios) ---
POSTGRES_PASSWORD_PROD=

# --- Bootstrap admin AMS ---
AMS_ADMIN_EMAIL=admin@tudominio.com
AMS_ADMIN_PASSWORD=

# --- Sentry DSN (opcional pero recomendado) ---
SENTRY_DSN=
EOF
  chmod 600 "$CFG"
  ok "  $CFG creado (permisos 600)"
else
  ok "[7/7] $CFG ya existe, salto creación"
fi

echo ""
ok "========================================="
ok "  Bootstrap completado en este VPS"
ok "========================================="
echo ""
log "Próximos pasos:"
log ""
log "1. Editar la config:"
log "   nano /opt/ams/bootstrap-config.env"
log ""
log "2. Apuntar DNS al IP de este VPS (registros A):"
log "   amsplatform.tudominio.com       → IP del VPS"
log "   api.amsplatform.tudominio.com   → IP del VPS"
log ""
log "3. Esperar ~5-15 minutos a que propague DNS"
log ""
log "4. Ejecutar el go-live de PROD:"
log "   bash /opt/ams/supply-chain-ams-stack/scripts/go-live-prod.sh"
log ""
log "El script de go-live se encarga de:"
log "  - Cargar tu bootstrap-config.env"
log "  - Generar Caddyfile con tus dominios"
log "  - Generar .env.prod en agent y platform"
log "  - Build + up de containers"
log "  - Validar HTTPS funcionando"
log ""
