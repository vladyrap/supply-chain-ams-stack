#!/usr/bin/env bash
# =============================================================================
# setup-secrets.sh — Genera todos los secrets criptográficos para .env productivo
# =============================================================================
# Uso:
#   bash scripts/setup-secrets.sh             # imprime a stdout (copy-paste)
#   bash scripts/setup-secrets.sh --to-env    # appendea a ./.env (BACKUP previo)
#   bash scripts/setup-secrets.sh --vault     # guarda a archivo cifrado (gpg)
#
# Outputs SIEMPRE en password manager. Estos valores son IRRECUPERABLES si los
# perdés (rotarlos implica relogin de todos los users + nuevo deploy).
# =============================================================================
set -euo pipefail

MODE="${1:---print}"

# Verificar openssl disponible
if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl no encontrado. Instalar con: apt install openssl"
  exit 1
fi

# Generar valores
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)
AMS_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | head -c 16)
CSRF_BYPASS_TOKEN=$(openssl rand -hex 32)
WORKER_CSRF_BYPASS_TOKEN=$(openssl rand -hex 32)

SECRETS_BLOCK=$(cat <<EOF
# =============================================================
# Secrets generados $(date -u +%Y-%m-%dT%H:%M:%SZ) — GUARDAR EN PASSWORD MANAGER
# =============================================================
JWT_SECRET=$JWT_SECRET
COOKIE_SECRET=$COOKIE_SECRET
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
AMS_BOOTSTRAP_ADMIN_PASSWORD=$AMS_BOOTSTRAP_ADMIN_PASSWORD
CSRF_BYPASS_TOKENS=$CSRF_BYPASS_TOKEN
WORKER_CSRF_BYPASS_TOKEN=$WORKER_CSRF_BYPASS_TOKEN
EOF
)

case "$MODE" in
  --print|-p)
    echo "$SECRETS_BLOCK"
    echo ""
    echo "⚠  IMPORTANTE:"
    echo "  1. Copiar TODOS estos valores a tu password manager (Bitwarden, 1Password, etc)"
    echo "  2. NO commitearlos a git"
    echo "  3. Pegarlos en .env del VPS — ese archivo nunca debe pushearse"
    ;;

  --to-env|-e)
    ENV_FILE="${ENV_FILE:-.env}"
    if [ -f "$ENV_FILE" ]; then
      BACKUP="${ENV_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
      cp "$ENV_FILE" "$BACKUP"
      echo "✓ Backup de .env previo en: $BACKUP"
    fi
    echo "" >> "$ENV_FILE"
    echo "$SECRETS_BLOCK" >> "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "✓ Secrets appended a $ENV_FILE (chmod 600)"
    echo ""
    echo "Verificar con:"
    echo "  grep -E '^(JWT|COOKIE|POSTGRES|GRAFANA|CSRF|WORKER)' $ENV_FILE"
    ;;

  --vault|-v)
    if ! command -v gpg >/dev/null 2>&1; then
      echo "ERROR: gpg no encontrado. Instalar con: apt install gnupg"
      exit 1
    fi
    VAULT_FILE="ams-secrets-$(date +%Y%m%d).asc"
    echo "$SECRETS_BLOCK" | gpg --armor --symmetric --output "$VAULT_FILE"
    chmod 600 "$VAULT_FILE"
    echo "✓ Secrets cifrados en: $VAULT_FILE"
    echo "Para leer: gpg --decrypt $VAULT_FILE"
    ;;

  --help|-h)
    echo "Uso: bash setup-secrets.sh [--print|--to-env|--vault]"
    echo ""
    echo "  --print   (default) Imprime los secrets en stdout para copy-paste"
    echo "  --to-env  Appendea al archivo .env (con backup previo)"
    echo "  --vault   Encripta los secrets con gpg (passphrase interactiva)"
    ;;

  *)
    echo "Modo desconocido: $MODE"
    echo "Usar --help para ver opciones"
    exit 1
    ;;
esac
