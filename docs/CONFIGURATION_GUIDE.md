# Guía de Configuración AMS Platform v1.2.2

**Para qué sirve:** llevar el sistema de "código en GitHub" a "funcionando en producción con clientes reales".
**Tiempo total:** 3-5 horas (la mayoría es esperar — DNS propagación, Let's Encrypt, etc.).
**Cuándo usar:** primera vez deployando. Para updates futuros, GitHub Actions deploy-on-tag se encarga.

> 📘 Esta guía es complementaria a `DEPLOY_TO_PRODUCTION_GUIDE.md` (10 fases). Acá nos centramos en **CONFIGURACIÓN** (qué setear y dónde).

---

## 📦 Inventario de servicios externos

| Servicio | Para qué | Costo |
|----------|----------|-------|
| **Nic Chile** (o similar) | Dominio `.cl` | ~CLP 9.000/año |
| **Hetzner Cloud CX32** | VPS productivo | €7/mes (~CLP 7.500) |
| **Google Cloud** | Gemini API + OAuth | $1-5 USD/mes |
| **Backblaze B2** | Backup remoto DB | ~$0.05 USD/mes (10GB) |
| **Resend** (opcional) | Email transaccional | Free hasta 3K/mes |
| **Sentry** (opcional) | Error tracking | Free hasta 5K errores/mes |
| **Slack** (opcional) | Alertas Alertmanager | Gratis |

**Total mínimo: ~CLP 9K/mes operativo.**

---

## 🎯 PASO 1 — Crear cuentas externas (45 min)

### 1.1 Dominio
- https://www.nic.cl → registrar `tudominio.cl`
- Anotar credenciales del panel DNS (las vas a usar en Paso 4)

### 1.2 VPS Hetzner Cloud
- https://console.hetzner.cloud → **New Project**: AMS
- **Add Server:**
  - Location: **Falkenstein** (mejor latencia LATAM)
  - Image: **Ubuntu 24.04 LTS**
  - Type: **CX32** (4 vCPU, 8 GB RAM, 80 GB)
  - SSH Key: subí tu clave pública del compu
  - Name: `ams-prod`
- **Anotar IP pública** ←→ vas a usarla muchas veces

### 1.3 Google Cloud (Gemini + OAuth)
- https://console.cloud.google.com → New Project: **AMS Platform**
- **APIs & Services → Library:**
  - Habilitar **Generative Language API**
- **APIs & Services → Credentials:**
  - **+ CREATE CREDENTIALS → API key** → copiar `GEMINI_API_KEY`
  - **+ CREATE CREDENTIALS → OAuth 2.0 Client ID → Web application:**
    - Authorized redirect URI: `https://ams.tudominio.cl/api/auth/callback/google`
    - Copiar `GOOGLE_OAUTH_CLIENT_ID` + `GOOGLE_OAUTH_CLIENT_SECRET`
- **Billing → Budgets & alerts:**
  - **CREATE BUDGET** → monto **$5 USD/mes** → thresholds 50%, 90%, 100%

### 1.4 Backblaze B2 (backups)
- https://www.backblaze.com/cloud-storage → registrar
- **Buckets → Create Bucket:**
  - Name: `ams-prod-backups`
  - Private
- **App Keys → Add a New Application Key:**
  - Name: `ams-prod-backup-key`
  - Allow access to: solo `ams-prod-backups`
  - Capabilities: Read + Write
  - Anotar `keyID` + `applicationKey`

### 1.5 Resend (opcional pero recomendado)
- https://resend.com → registrar
- **Domains → Add Domain:** `tudominio.cl`
- Agregar los TXT/MX records que te muestra (te los pongo en el paso DNS)
- **API Keys → Create API Key** → copiar `RESEND_API_KEY`

### 1.6 Sentry (opcional pero recomendado)
- https://sentry.io → New Project → React/Next.js
- Copiar el `DSN` que muestra el setup

### 1.7 Slack webhook (opcional)
- En tu workspace Slack → **Apps → Incoming Webhooks → Add to Slack**
- Elegir canal `#ams-alerts`
- Copiar el `Webhook URL`

---

## 🔐 PASO 2 — Generar secrets criptográficos (5 min)

En tu compu local (o en el VPS directamente):

```bash
# Si usás bash, copiá este bloque entero y ejecutalo:
cat <<EOF
JWT_SECRET=$(openssl rand -hex 32)
COOKIE_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)
AMS_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=' | head -c 16)
CSRF_BYPASS_TOKEN=$(openssl rand -hex 32)
WORKER_CSRF_BYPASS_TOKEN=$(openssl rand -hex 32)
EOF
```

⚠️ **Guardar TODOS estos valores en un password manager** (Bitwarden, 1Password, KeepassXC). Si los perdés, restaurar el sistema implica reset completo.

---

## 🌐 PASO 3 — DNS records (15 min + propagación)

En el panel de tu registrar (Nic Chile, etc.), agregar:

| Tipo | Nombre | Valor | TTL |
|------|--------|-------|-----|
| A | `ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `api.ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `status.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `*.ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| MX | `tudominio.cl` | 10 feedback-smtp.us-east-1.amazonses.com (de Resend) | 3600 |
| TXT | `tudominio.cl` | `v=spf1 include:amazonses.com ~all` | 3600 |
| TXT | `resend._domainkey.tudominio.cl` | (DKIM key de Resend) | 3600 |

**Verificar propagación:**
```bash
dig +short ams.tudominio.cl
dig +short api.ams.tudominio.cl
# ambos deben devolver tu IP del VPS
```

⏱ Esperar 5-30 min antes de seguir.

---

## 🖥 PASO 4 — Setup VPS (30 min)

### 4.1 SSH inicial + crear usuario non-root
```bash
ssh root@<IP_VPS>

adduser ams                      # password fuerte
usermod -aG sudo ams
mkdir -p /home/ams/.ssh
cp ~/.ssh/authorized_keys /home/ams/.ssh/
chown -R ams:ams /home/ams/.ssh
chmod 700 /home/ams/.ssh && chmod 600 /home/ams/.ssh/authorized_keys

# Endurecer SSH
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Firewall
apt update && apt install -y ufw
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp
ufw --force enable

exit
```

### 4.2 Re-loguearse como `ams` + instalar Docker
```bash
ssh ams@<IP_VPS>

# Docker
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release git rclone
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ams
exit

# Re-loguear
ssh ams@<IP_VPS>
docker --version && docker compose version
```

### 4.3 Setup directorio + clone repos
```bash
sudo mkdir -p /opt/ams && sudo chown ams:ams /opt/ams
cd /opt/ams

git clone https://github.com/vladyrap/supply-chain-ams-agent.git
git clone https://github.com/vladyrap/supply-chain-ams-platform.git
git clone https://github.com/vladyrap/supply-chain-ams-stack.git

# Checkout v1.2.2 (última stable)
for repo in supply-chain-ams-agent supply-chain-ams-platform supply-chain-ams-stack; do
  cd /opt/ams/$repo
  git checkout tags/v1.2.2-mt-complete
done
cd /opt/ams/supply-chain-ams-stack
```

---

## ⚙ PASO 5 — Configurar `.env` productivo (20 min)

### 5.1 Copiar template
```bash
cd /opt/ams/supply-chain-ams-stack
cp .env.production.example .env
chmod 600 .env
nano .env
```

### 5.2 Plantilla rellenable (copiar al .env)

```bash
# ===== DOMINIOS =====
AMS_DOMAIN=ams.tudominio.cl
AMS_API_DOMAIN=api.ams.tudominio.cl
PUBLIC_BASE_DOMAIN=tudominio.cl

# ===== LLM =====
GEMINI_API_KEY=AIzaSy...                          # Paso 1.3
GEMINI_MODEL=gemini-2.5-flash
GEMINI_CAP_PER_MINUTE=20
GEMINI_CAP_PER_HOUR=80
GEMINI_CAP_PER_DAY=200

# ===== POSTGRES =====
POSTGRES_USER=ams_user
POSTGRES_PASSWORD=<paste-del-paso-2>
POSTGRES_DB=ams_agent
PG_POOL_MAX=25
PG_STATEMENT_TIMEOUT_MS=15000

# ===== AUTH SECRETS (FAIL-FAST si vacíos en prod) =====
JWT_SECRET=<paste-del-paso-2>
COOKIE_SECRET=<paste-del-paso-2>
JWT_TTL_HOURS=8
AUTH_BCRYPT_ROUNDS=12

# Signup desactivado en prod (evita race admin)
ENABLE_PUBLIC_SIGNUP=false

# Bootstrap admin (solo al primer boot con DB vacía)
AMS_BOOTSTRAP_ADMIN_EMAIL=vladimir@tudominio.cl
AMS_BOOTSTRAP_ADMIN_PASSWORD=<paste-del-paso-2>

# ===== MULTI-TENANCY =====
MULTI_TENANCY_MODE=hybrid
DEFAULT_TENANT_ID=default

# ===== RATE LIMIT + CSRF =====
RATE_LIMIT_MAX_PER_MIN=200
RATE_LIMIT_ALLOWLIST=
AUTH_RATE_LIMIT_MAX=8
ENFORCE_ORIGIN_CSRF=true
CSRF_BYPASS_TOKENS=<paste-del-paso-2>
WORKER_CSRF_BYPASS_TOKEN=<paste-del-paso-2>

# ===== CORS =====
CORS_ORIGINS=https://ams.tudominio.cl

# ===== SSO GOOGLE (opcional) =====
GOOGLE_OAUTH_CLIENT_ID=...apps.googleusercontent.com   # Paso 1.3
GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-...                  # Paso 1.3
GOOGLE_OAUTH_ALLOWED_DOMAINS=tudominio.cl
PUBLIC_BASE_URL=https://ams.tudominio.cl

# ===== EMAIL RESEND (opcional) =====
RESEND_API_KEY=re_...                                  # Paso 1.5
EMAIL_FROM=AMS Platform <noreply@tudominio.cl>

# ===== FRONTEND BRANDING =====
NEXT_PUBLIC_AGENT_API_URL=https://api.ams.tudominio.cl
NEXT_PUBLIC_SALES_EMAIL=ventas@tudominio.cl
NEXT_PUBLIC_SUPPORT_EMAIL=soporte@tudominio.cl
NEXT_PUBLIC_COMPANY_NAME=Tu Empresa SpA

# ===== SENTRY (opcional) =====
SENTRY_DSN=https://...@sentry.io/...                   # Paso 1.6
NEXT_PUBLIC_SENTRY_DSN=https://...@sentry.io/...
NEXT_PUBLIC_SENTRY_ENV=production
NEXT_PUBLIC_SENTRY_TRACES_RATE=0.1

# ===== GRAFANA (si activás observability) =====
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<paste-del-paso-2>

# ===== ALERTMANAGER (si activás observability + Slack) =====
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... # Paso 1.7
ALERTMANAGER_TO=alerts@tudominio.cl

# ===== BACKUP =====
BACKUP_RCLONE_REMOTE=b2:ams-prod-backups
BACKUP_RETAIN_DAYS=30

# ===== TUNING =====
LOG_LEVEL=info
NODE_ENV=production
USD_TO_CLP_RATE=950
```

### 5.3 Setup rclone para B2
```bash
rclone config
# n) New remote
# name> b2
# Storage> 5 (Backblaze B2)
# account> <keyID del paso 1.4>
# key> <applicationKey del paso 1.4>
# resto: default (enter enter enter)
# y) Yes this is OK
# q) Quit

# Verificar
rclone ls b2:ams-prod-backups
# debe responder sin error (vacío al principio)
```

---

## 🚀 PASO 6 — Primer deploy + migrations (30 min)

```bash
cd /opt/ams/supply-chain-ams-stack

# Levantar stack (build inicial 5-10 min)
docker compose -f docker-compose.prod.yml up -d --build

# Esperar healthchecks
sleep 30
docker compose -f docker-compose.prod.yml ps
# Todos deben estar "Up" o "Up (healthy)"

# Aplicar migrations EN ORDEN (crítico)
for migration in 003 004 005 006 007; do
  echo "Aplicando migration $migration..."
  docker exec -i ams-prod-db psql -U ams_user -d ams_agent < \
    ../supply-chain-ams-agent/database/migrations/${migration}-*.sql
done

# Verificar foundation multi-tenant
docker exec ams-prod-db psql -U ams_user -d ams_agent -c \
  "SELECT id, name, status FROM tenants;"
# Debe mostrar: default | Default Tenant | active
```

---

## ✅ PASO 7 — Smoke tests (10 min)

```bash
# Backend health
curl -sk https://api.ams.tudominio.cl/health
# {"status":"ok",...}

# Status detallado
curl -sk https://api.ams.tudominio.cl/api/status | head -c 500

# Frontend
curl -sIk https://ams.tudominio.cl/
# HTTP/2 200

# Tenants endpoint
curl -sk https://api.ams.tudominio.cl/api/tenants/me \
  --cookie-jar /tmp/c.txt
# 401 (no autenticado, esperado)
```

### Login UI
- Browser → `https://ams.tudominio.cl/login`
- Email: `vladimir@tudominio.cl` (del `AMS_BOOTSTRAP_ADMIN_EMAIL`)
- Password: la del Paso 2

### Verificar aislamiento multi-tenant
- /admin/costs → debe mostrar panel (con $0)
- /admin/tenants → debe mostrar tenant "default" + opción de crear
- Crear ticket de prueba → AIE enrich exitoso

---

## 🔄 PASO 8 — Backup automático (10 min)

```bash
# Primer backup manual de prueba
bash /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod
# Debe terminar: "subido a b2:ams-prod-backups/ams/prod/"

# Verificar en B2
rclone ls b2:ams-prod-backups/ams/prod/

# Cron diario 3 AM (mantener 30 días)
sudo crontab -e
# Pegar al final:
0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1
```

---

## 📊 PASO 9 — Observabilidad (opcional, 15 min)

```bash
docker compose -f docker-compose.prod.yml --profile observability up -d
# Levanta Prometheus + Grafana + Alertmanager

# Grafana: http://<IP_VPS>:3000 (si lo abrís en firewall, sino solo interno)
# Login: admin / <GRAFANA_ADMIN_PASSWORD>

# Verificar Alertmanager
docker logs ams-prod-alertmanager 2>&1 | tail -10
# Debe decir "==> alertmanager.yml generado"

# Test alerta a Slack
curl -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"test","severity":"warning"},"annotations":{"summary":"Test deploy v1.2.2"}}]'
```

---

## 🔁 PASO 10 — CI/CD GitHub Actions (15 min, opcional pero recomendado)

Permite hacer `git tag vX.Y.Z && git push --tags` desde tu compu y deploy automático.

### 10.1 SSH key dedicada
```bash
# En tu compu local
ssh-keygen -t ed25519 -C "github-deploy@ams" -f ~/.ssh/ams_deploy_key
# Sin passphrase (enter enter)

# Subir al VPS
cat ~/.ssh/ams_deploy_key.pub | ssh ams@<IP_VPS> "cat >> ~/.ssh/authorized_keys"

# Obtener fingerprint
ssh-keyscan -t ed25519 <IP_VPS>
# Copiar la línea completa
```

### 10.2 GitHub Secrets
- https://github.com/vladyrap/supply-chain-ams-agent/settings/secrets/actions
- **New repository secret** para cada uno:

| Name | Value |
|------|-------|
| `VPS_HOST` | `<IP_VPS>` |
| `VPS_USER` | `ams` |
| `VPS_SSH_KEY` | (contenido completo de `~/.ssh/ams_deploy_key`) |
| `VPS_DEPLOY_PATH` | `/opt/ams/supply-chain-ams-stack` |
| `VPS_HOST_FINGERPRINT` | (la línea del `ssh-keyscan`) |
| `AMS_DOMAIN` | `ams.tudominio.cl` |

### 10.3 Test
```bash
# En tu compu
cd ~/Desktop/supply-chain-ams-agent
git tag v1.2.3-test
git push --tags
# GitHub Actions debe correr el workflow deploy-on-tag y deployar al VPS
```

---

## 👤 PASO 11 — Crear primer cliente real (10 min)

### 11.1 Desde la UI (recomendado)
- Login como super_admin → `/admin/tenants` → "+ Crear tenant"
- Llenar form:
  - ID: `acme` (slug)
  - Nombre: `ACME Cliente`
  - Subdominio: `acme`
  - Plan: `standard`
  - Brand: nombre + accent + logo URL
  - Settings: signature default
- Click "Crear"

### 11.2 Crear admin del tenant
```bash
docker exec -it ams-prod-backend node -e "
  const {createUser} = require('./dist/services/auth.service');
  createUser('acme', {
    email: 'admin@acme.com',
    password: 'CambiameEnPrimerLogin123!',
    name: 'Admin ACME',
    role: 'admin'
  }).then(console.log);
"
```

### 11.3 DNS subdominio
- Si usás subdomain routing: ya está cubierto por el wildcard `*.ams.tudominio.cl` del Paso 3 ✅
- El cliente entra a `https://acme.ams.tudominio.cl/login`

### 11.4 Onboarding del cliente
1. Enviá credenciales (email + password temporal) por canal seguro
2. Pedile que cambie password en primer login
3. Lo guiás a `/knowledge` para cargar PDFs/DOCX iniciales
4. Lo guiás a `/settings → Customer Response` para setear su firma
5. Le mostrás `/tickets` para que cree primero de prueba

---

## 🆘 Troubleshooting

| Síntoma | Causa probable | Fix |
|---------|----------------|-----|
| Backend "FATAL: tabla 'tenants' no existe" | Migration 005 no aplicada | Aplicar migration 005 (Paso 6) |
| "JWT_SECRET required in production" | Var vacía o < 32 chars | Generar con `openssl rand -hex 32` |
| Caddy no obtiene cert SSL | DNS no propagado, puertos 80/443 cerrados, rate limit Let's Encrypt | `dig +short`, `ufw status`, esperar 1h si excediste rate limit |
| 502 Bad Gateway | Container backend/platform down | `docker compose logs backend / platform` |
| Gemini 429 quota | Cap diario excedido | Aumentar `GEMINI_CAP_PER_DAY` o esperar al rollover 00:00 UTC |
| Backup no sube a B2 | rclone mal configurado | `rclone config show b2` + `rclone ls b2:ams-prod-backups` |
| Alertas no llegan a Slack | `SLACK_WEBHOOK_URL` vacío | Setear var + restart alertmanager |

---

## ✅ Checklist final pre-cliente

- [ ] Dominio comprado + DNS propagado (`dig +short`)
- [ ] VPS Hetzner accesible vía SSH como `ams`
- [ ] Docker + compose funcionando
- [ ] `.env` con TODOS los secrets generados y guardados en password manager
- [ ] Migrations 003→007 aplicadas (verificar `SELECT * FROM tenants`)
- [ ] HTTPS funciona en frontend + API (cert Let's Encrypt OK)
- [ ] Login con bootstrap admin funciona
- [ ] `/admin/tenants` muestra tenant "default"
- [ ] `/admin/costs` muestra panel
- [ ] `/status` muestra "Operacional"
- [ ] Crear ticket → AIE enrichment exitoso
- [ ] Primer backup manual subido a B2
- [ ] Cron backup diario en `crontab -l`
- [ ] (opcional) SSO Google funciona
- [ ] (opcional) Email Resend llega
- [ ] (opcional) Alertmanager → Slack test exitoso
- [ ] GitHub Actions deploy-on-tag verde
- [ ] Google Cloud Budget configurado a $5
- [ ] Solo 1 tarjeta activa en Google Billing

---

## 📚 Referencias rápidas

| Archivo | Contenido |
|---------|-----------|
| `.env.production.example` | Plantilla con todas las vars |
| `docker-compose.prod.yml` | Stack productivo |
| `Caddyfile.prod` | Reverse proxy + HTTPS auto |
| `scripts/backup-db-env.sh` | Backup PG + rclone B2 |
| `scripts/restore-db.sh` | Restore desde dump |
| `scripts/setup-secrets.sh` | (nuevo) genera todos los secrets |
| `scripts/verify-config.sh` | (nuevo) valida `.env` antes de deploy |
| `migrations/00[3-7]*.sql` | Multi-tenant foundation |

---

**v1.2.2-mt-complete** · Multi-tenant real con aislamiento verificable 🚀
