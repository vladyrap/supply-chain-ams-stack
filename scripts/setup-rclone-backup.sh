#!/usr/bin/env bash
# =============================================================================
# setup-rclone-backup.sh — Configura backups remotos a B2 / S3 / Drive (v0.4.1)
# =============================================================================
# Wrapper interactivo sobre rclone config para que un sysadmin pueda
# armar el destino remoto sin recordar la sintaxis exacta.
#
# Uso (en el VPS, como root o user con sudo):
#   bash scripts/setup-rclone-backup.sh
#
# Después configura:
#   1. Setea BACKUP_RCLONE_REMOTE en .env del stack
#   2. Reinicia el cron de backup
# =============================================================================
set -euo pipefail

if ! command -v rclone >/dev/null 2>&1; then
  echo "[setup-rclone] rclone no instalado. Instalando..."
  curl https://rclone.org/install.sh | sudo bash
fi

echo "==========================================="
echo "  Configurador de Backups Remotos AMS"
echo "==========================================="
echo ""
echo "Proveedores soportados:"
echo "  1) Backblaze B2 (recomendado - barato, $0.005/GB/mes)"
echo "  2) AWS S3"
echo "  3) Google Drive"
echo "  4) Otro (manual)"
echo ""
read -r -p "Elegí (1-4): " CHOICE

case "$CHOICE" in
  1)
    REMOTE_NAME="b2"
    echo ""
    echo "Para Backblaze B2 necesitás:"
    echo "  - Cuenta en https://www.backblaze.com/b2/"
    echo "  - Application Key con permiso Write/Read en bucket 'ams-backups'"
    echo "  - Bucket creado: 'ams-backups' (region: cualquiera, todo encrypted)"
    echo ""
    rclone config create "$REMOTE_NAME" b2
    ;;
  2)
    REMOTE_NAME="s3"
    rclone config create "$REMOTE_NAME" s3 provider AWS
    ;;
  3)
    REMOTE_NAME="gdrive"
    rclone config create "$REMOTE_NAME" drive
    ;;
  4)
    echo "Corré: rclone config"
    rclone config
    exit 0
    ;;
  *)
    echo "Opción inválida"; exit 1 ;;
esac

echo ""
echo "==========================================="
echo "  Configurar AMS para usar este remoto"
echo "==========================================="
echo ""
echo "Agregá a tu .env.prod del stack:"
echo "  BACKUP_RCLONE_REMOTE=${REMOTE_NAME}:ams-backups"
echo ""
echo "Y verificá con:"
echo "  rclone lsd ${REMOTE_NAME}:"
echo "  rclone copy /tmp/test.txt ${REMOTE_NAME}:ams-backups/test/"
echo ""
echo "Después, el script scripts/backup-db-env.sh detecta automáticamente"
echo "BACKUP_RCLONE_REMOTE y sincroniza cada backup."
echo ""
echo "Listo. Próxima ejecución del cron va a subir el dump al remoto."
