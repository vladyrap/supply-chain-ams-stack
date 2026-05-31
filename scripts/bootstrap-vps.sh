#!/usr/bin/env bash
# =============================================================
# bootstrap-vps.sh — preparar un VPS Debian/Ubuntu desde cero
# =============================================================
# Pegá esto en el VPS UNA VEZ. Después usá deploy.sh para actualizaciones.
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/vladyrap/supply-chain-ams-stack/main/scripts/bootstrap-vps.sh | bash
#
# O subilo manualmente y:
#   bash bootstrap-vps.sh
# =============================================================
set -euo pipefail

log() { echo -e "\033[36m[bootstrap]\033[0m $*"; }

# Requiere root o sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "Ejecutar como root o con sudo" 1>&2
  exit 1
fi

log "Actualizando paquetes…"
apt-get update -qq
apt-get upgrade -y -qq

log "Instalando dependencias del sistema…"
apt-get install -y -qq \
  curl ca-certificates gnupg lsb-release \
  git ufw fail2ban \
  htop ncdu jq

# Docker
if ! command -v docker >/dev/null; then
  log "Instalando Docker…"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  ARCH=$(dpkg --print-architecture)
  CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

log "Versión docker:"
docker --version
docker compose version

# Firewall
log "Configurando UFW (firewall)…"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# fail2ban con defaults
log "fail2ban activo (defaults)"
systemctl enable --now fail2ban

# Estructura de directorios
log "Creando /opt/ams …"
mkdir -p /opt/ams
cd /opt/ams

# Clonar repos si no existen
for repo in supply-chain-ams-agent supply-chain-ams-platform supply-chain-ams-stack; do
  if [ ! -d "/opt/ams/$repo" ]; then
    log "git clone $repo…"
    git clone "https://github.com/vladyrap/$repo.git"
  else
    log "$repo ya existe, salto clone"
  fi
done

# Backup dir
mkdir -p /var/backups/ams
chmod 700 /var/backups/ams

log ""
log "✓ Bootstrap listo."
log ""
log "Próximo paso:"
log "  cd /opt/ams/supply-chain-ams-stack"
log "  cp .env.production.example .env"
log "  nano .env       # completar valores reales"
log "  bash scripts/deploy.sh"
log ""
log "Cuando ya esté corriendo, agendá backup diario en cron:"
log "  echo '0 3 * * * /opt/ams/supply-chain-ams-stack/scripts/backup-db.sh >> /var/log/ams-backup.log 2>&1' | crontab -"
