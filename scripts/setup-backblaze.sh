#!/bin/bash
# =============================================================================
# setup-backblaze.sh — Configurar offsite backup con Backblaze B2 (free 10GB)
# =============================================================================
# v1.2.8-prod · One-shot setup. Te pide las credenciales (NO las pegues en chat
# de claude — pegalas en la terminal del VPS cuando corra este script).
#
# Antes de correr:
#   1. Crear cuenta gratuita en https://www.backblaze.com/b2/cloud-storage.html
#   2. Crear un Application Key con permisos "Read + Write" en B2
#      → Menú "Account" → "Application Keys" → "Add a New Application Key"
#      → "Allow access to Bucket(s)": dejar "All" o crear bucket "ams-prod-backups"
#      → guardá keyID y applicationKey (la app key SOLO se muestra una vez)
#   3. Crear bucket "ams-prod-backups" (privado) en https://secure.backblaze.com/b2_buckets.htm
#
# Después correr:
#   sudo bash /opt/ams/supply-chain-ams-stack/scripts/setup-backblaze.sh
# =============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi

if ! command -v rclone >/dev/null 2>&1; then
  echo "Instalando rclone…"
  curl https://rclone.org/install.sh | bash
fi

echo ""
echo "Vamos a configurar rclone con Backblaze B2."
echo "Pegá las credenciales cuando rclone te las pida — quedan SOLO en /root/.config/rclone/rclone.conf."
echo ""
read -p "Bucket name [ams-prod-backups]: " BUCKET
BUCKET=${BUCKET:-ams-prod-backups}

rclone config create b2 b2 \
  account "${B2_ACCOUNT_ID:-}" \
  key "${B2_APP_KEY:-}" \
  --non-interactive 2>/dev/null || true

if ! rclone listremotes | grep -q "^b2:"; then
  echo ""
  echo "→ Configurá b2 manualmente con: rclone config"
  echo "  Type: b2"
  echo "  Account ID: tu keyID"
  echo "  Application Key: tu applicationKey"
  echo "  Hard delete: false"
  rclone config
fi

# Test
echo ""
echo "Test acceso…"
rclone lsd "b2:$BUCKET" >/dev/null || {
  echo "ERROR: no puedo listar el bucket. Verificá keyID/key o que el bucket exista."
  exit 1
}
echo "OK acceso al bucket b2:$BUCKET"

# Actualizar /etc/cron.d (o crontab) con RCLONE_REMOTE
crontab -l 2>/dev/null | grep -v backup-ams-prod > /tmp/crontab_new
echo "30 3 * * * RCLONE_REMOTE=b2:$BUCKET /usr/local/bin/backup-ams-prod.sh >> /var/log/ams-backup.log 2>&1" >> /tmp/crontab_new
crontab /tmp/crontab_new
rm -f /tmp/crontab_new

echo ""
echo "OK — cron actualizado. Backup nightly subirá a b2:$BUCKET"
echo "Test inmediato:"
echo "  RCLONE_REMOTE=b2:$BUCKET /usr/local/bin/backup-ams-prod.sh"
