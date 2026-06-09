# Deploy AMS Platform a Producción · Guía paso a paso (v1.1.3)

**Tiempo total estimado:** 4-6 horas (primera vez).
**Pre-requisitos:** tarjeta de crédito, acceso SSH, dominio comprable, cuenta GitHub.

---

## 📋 Resumen de fases

| Fase | Qué | Tiempo |
|------|-----|--------|
| **0** | Pre-compras (dominio, VPS, cuentas SaaS) | 30 min |
| **1** | Setup VPS Hetzner (firewall + Docker) | 30 min |
| **2** | DNS A records (dominio → VPS) | 15 min + propagación |
| **3** | Generar secrets + clone repos en VPS | 20 min |
| **4** | Configurar `.env` production | 30 min |
| **5** | Primer `docker compose up` + migrations | 30 min |
| **6** | Bootstrap admin + smoke test | 15 min |
| **7** | Setup backups (rclone + cron) | 20 min |
| **8** | (Opcional) Activar observability + Alertmanager | 30 min |
| **9** | Configurar GitHub Actions deploy-on-tag | 20 min |
| **10** | Primer cliente / onboarding | 30 min |

---

## FASE 0 — Pre-compras (hacelo en tu compu)

### 0.1 Comprar dominio (CLP ~9.000/año)
- **Nic Chile:** https://www.nic.cl → registrar `tudominio.cl`
- Sugerencia: dominio corto, fácil de pronunciar
- Verificar disponibilidad antes de avanzar

### 0.2 Crear VPS Hetzner Cloud
- https://console.hetzner.cloud → **New Project** → **AMS**
- **Add Server:**
  - Location: **Falkenstein** (mejor latencia desde LATAM)
  - Image: **Ubuntu 24.04 LTS**
  - Type: **CX32** (4 vCPU, 8 GB RAM, 80 GB disk) — €7/mes
  - SSH key: subí tu clave pública (`~/.ssh/id_ed25519.pub` o `id_rsa.pub`)
  - Name: `ams-prod-1`
- Anotá la **IP pública** que te da Hetzner
- (Opcional) **Volume 40GB** para `/var/lib/docker` si esperás >100GB de uploads

### 0.3 Google Cloud — Gemini API + OAuth
- https://console.cloud.google.com → crear proyecto **AMS Platform**
- **APIs & Services → Library:**
  - Activar **Generative Language API** (Gemini)
- **APIs & Services → Credentials:**
  - Click **+ CREATE CREDENTIALS** → **API key** → copiar `GEMINI_API_KEY`
  - Click **+ CREATE CREDENTIALS** → **OAuth 2.0 Client ID** → **Web application**:
    - Authorized redirect URI: `https://ams.tudominio.cl/api/auth/callback/google`
    - Copiar `Client ID` + `Client Secret`
- **Billing → Budgets & alerts:**
  - **+ CREATE BUDGET** → monto **$5 USD/mes** → **Threshold 50%, 90%, 100%** → notificaciones por email
  - ⚠ Esto NO es HARD CAP — Gemini paid no tiene auto-shutdown nativo. Vivir con el rate-limiter local + budget alert.
- **Billing → Payment methods:** mantener UNA sola tarjeta activa (eliminar las extra).

### 0.4 Resend (email transaccional — opcional)
- https://resend.com → crear cuenta
- **Domains:** agregar `tudominio.cl` + verificar (TXT/MX records)
- **API Keys:** crear key → copiar `RESEND_API_KEY`

### 0.5 Sentry (errores frontend — opcional pero recomendado)
- https://sentry.io → New Project → React/Next.js
- Copiar el `DSN` que aparece en setup

### 0.6 Slack webhook (alertas — opcional)
- En tu workspace Slack → **Apps** → **Incoming Webhooks** → **Add to Slack**
- Elegir canal `#ams-alerts` → copiar `Webhook URL`

### 0.7 Cuenta GitHub
- Los 3 repos ya están en `github.com/vladyrap/supply-chain-ams-{agent,platform,stack}`
- Verificar que tenés acceso

---

## FASE 1 — Setup VPS Hetzner (desde tu compu)

### 1.1 SSH inicial como root
```bash
ssh root@<IP_VPS>
```

### 1.2 Setup usuario non-root
```bash
adduser ams                          # crear usuario "ams" con password
usermod -aG sudo ams                 # darle sudo
mkdir -p /home/ams/.ssh
cp ~/.ssh/authorized_keys /home/ams/.ssh/
chown -R ams:ams /home/ams/.ssh
chmod 700 /home/ams/.ssh
chmod 600 /home/ams/.ssh/authorized_keys
```

### 1.3 Endurecer SSH (cerrar root login + password)
```bash
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
```

### 1.4 Firewall (ufw)
```bash
apt update && apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp                     # SSH
ufw allow 80/tcp                     # HTTP (Caddy → redirect a HTTPS)
ufw allow 443/tcp                    # HTTPS
ufw allow 443/udp                    # HTTP/3
ufw --force enable
ufw status verbose
```

### 1.5 Salir de root, re-loguear como `ams`
```bash
exit
ssh ams@<IP_VPS>                     # debe entrar con la SSH key
```

### 1.6 Instalar Docker + docker compose
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release git
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ams
exit                                 # re-loguear para que aplique el group
```

```bash
ssh ams@<IP_VPS>
docker --version                     # debe responder con version
docker compose version
```

### 1.7 Setup directorio de deploy
```bash
sudo mkdir -p /opt/ams
sudo chown ams:ams /opt/ams
cd /opt/ams
```

---

## FASE 2 — DNS A records

En el panel de Nic Chile (o tu registrar), agregar:

| Tipo | Nombre | Valor | TTL |
|------|--------|-------|-----|
| A | `ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `api.ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `status.tudominio.cl` | `<IP_VPS>` | 3600 |
| A | `*.ams.tudominio.cl` | `<IP_VPS>` | 3600 |
| MX | `tudominio.cl` | (Resend o tu MX) | 3600 |
| TXT | `tudominio.cl` | (SPF/DKIM de Resend) | 3600 |

⏱ Esperar 5-30 minutos para propagación. Verificar:
```bash
dig +short ams.tudominio.cl
# debe devolver tu IP del VPS
```

---

## FASE 3 — Clone repos + generar secrets (en VPS)

```bash
cd /opt/ams
git clone https://github.com/vladyrap/supply-chain-ams-agent.git
git clone https://github.com/vladyrap/supply-chain-ams-platform.git
git clone https://github.com/vladyrap/supply-chain-ams-stack.git

# Checkout tag de producción
cd supply-chain-ams-agent && git checkout tags/v1.1.3-all-bugs-fixed && cd ..
cd supply-chain-ams-platform && git checkout tags/v1.1.3-all-bugs-fixed && cd ..
cd supply-chain-ams-stack && git checkout tags/v1.1.3-all-bugs-fixed && cd ..

cd supply-chain-ams-stack
```

### Generar secrets criptográficos
```bash
echo "JWT_SECRET=$(openssl rand -hex 32)"
echo "COOKIE_SECRET=$(openssl rand -hex 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)"
echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24)"
echo "AMS_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -base64 18)"
echo "CSRF_BYPASS_TOKEN=$(openssl rand -hex 32)   # opcional, solo si tenés cron/webhook server-to-server"
```

📝 Copiar estos valores a un **password manager seguro** (Bitwarden / 1Password). Los vas a necesitar en el siguiente paso.

---

## FASE 4 — Configurar `.env` production

```bash
cd /opt/ams/supply-chain-ams-stack
cp .env.production.example .env
nano .env
```

**Mínimo absolutamente necesario para arrancar (sin SSO ni email):**

```bash
# Dominios
AMS_DOMAIN=ams.tudominio.cl
AMS_API_DOMAIN=api.ams.tudominio.cl
PUBLIC_BASE_DOMAIN=tudominio.cl

# Gemini
GEMINI_API_KEY=AIza...                          # de Fase 0.3

# Postgres
POSTGRES_PASSWORD=<pegar del generador>

# Auth secrets (FAIL-FAST si vacíos)
JWT_SECRET=<pegar del generador>
COOKIE_SECRET=<pegar del generador>

# Signup desactivado (anti race condition admin)
ENABLE_PUBLIC_SIGNUP=false
AMS_BOOTSTRAP_ADMIN_EMAIL=vladimir@tudominio.cl
AMS_BOOTSTRAP_ADMIN_PASSWORD=<pegar del generador>

# Multi-tenancy
MULTI_TENANCY_MODE=hybrid
DEFAULT_TENANT_ID=default

# Rate limit + CSRF (defaults seguros)
RATE_LIMIT_MAX_PER_MIN=200
RATE_LIMIT_ALLOWLIST=
AUTH_RATE_LIMIT_MAX=8
ENFORCE_ORIGIN_CSRF=true
CSRF_BYPASS_TOKENS=

# CORS
CORS_ORIGINS=https://ams.tudominio.cl

# Frontend → API
NEXT_PUBLIC_AGENT_API_URL=https://api.ams.tudominio.cl

# Frontend branding
NEXT_PUBLIC_SALES_EMAIL=ventas@tudominio.cl
NEXT_PUBLIC_SUPPORT_EMAIL=soporte@tudominio.cl
NEXT_PUBLIC_COMPANY_NAME=Tu Empresa SpA

# Runtime
NODE_ENV=production
LOG_LEVEL=info
```

**Si querés activar SSO Google (recomendado):**
```bash
GOOGLE_OAUTH_CLIENT_ID=...apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-...
GOOGLE_OAUTH_ALLOWED_DOMAINS=tudominio.cl
PUBLIC_BASE_URL=https://ams.tudominio.cl
```

**Si querés activar email Resend:**
```bash
RESEND_API_KEY=re_...
EMAIL_FROM=AMS Platform <noreply@tudominio.cl>
```

**Si querés Sentry frontend:**
```bash
NEXT_PUBLIC_SENTRY_DSN=https://....@sentry.io/...
NEXT_PUBLIC_SENTRY_ENV=production
NEXT_PUBLIC_SENTRY_TRACES_RATE=0.1
```

**Permisos del archivo:**
```bash
chmod 600 .env                       # solo el owner puede leer secrets
```

---

## FASE 5 — Primer deploy + migrations

### 5.1 Levantar el stack base
```bash
cd /opt/ams/supply-chain-ams-stack
docker compose -f docker-compose.prod.yml up -d --build
```

Esto va a:
- Buildear imágenes backend + platform (5-10 min primera vez)
- Levantar Postgres (que aplica `init.sql` automáticamente)
- Levantar Redis + worker BullMQ
- Levantar Caddy con HTTPS automático Let's Encrypt

### 5.2 Verificar containers
```bash
docker compose -f docker-compose.prod.yml ps
# todos deben estar "Up" o "Up (healthy)"
```

### 5.3 Aplicar migrations en orden
```bash
# Migration 003: indexes + tenant hardening
docker exec -i ams-prod-db psql -U ams_user -d ams_agent \
  < ../supply-chain-ams-agent/database/migrations/003-indexes-and-tenant-hardening.sql

# Migration 004: FK hardening + DDL audit_events centralizado
docker exec -i ams-prod-db psql -U ams_user -d ams_agent \
  < ../supply-chain-ams-agent/database/migrations/004-fk-hardening-and-uuid.sql
```

Verificar que aplicaron:
```bash
docker exec ams-prod-db psql -U ams_user -d ams_agent -c \
  "SELECT indexname FROM pg_indexes WHERE tablename IN ('audit_events','agent_usage','tickets_demo','users') ORDER BY indexname"
# debe mostrar idx_audit_events_*, idx_agent_usage_*, idx_tickets_demo_intelligence_gin, uq_users_email_lower, etc.
```

### 5.4 Smoke test endpoints
```bash
curl -sk https://api.ams.tudominio.cl/health
# {"status":"ok","time":"..."}

curl -sk https://api.ams.tudominio.cl/api/status | head -c 500
# JSON con backend/database/geminiRateLimiter

curl -sIk https://ams.tudominio.cl/
# HTTP/2 200 (frontend Next.js)
```

---

## FASE 6 — Bootstrap admin + smoke test funcional

### 6.1 Login con el admin bootstrapeado
- Browser → `https://ams.tudominio.cl/login`
- Email: `vladimir@tudominio.cl` (lo que pusiste en `AMS_BOOTSTRAP_ADMIN_EMAIL`)
- Password: la generaste en Fase 3

Si el admin **NO** entra:
```bash
# Verificar que existe en DB
docker exec ams-prod-db psql -U ams_user -d ams_agent -c \
  "SELECT id, email, role, is_active FROM users WHERE email='vladimir@tudominio.cl'"

# Si no existe, crearlo manualmente:
docker exec -it ams-prod-backend node -e "
  const {createUser} = require('./dist/services/auth.service');
  createUser({email:'vladimir@tudominio.cl', password:'<password>', name:'Vladimir', role:'admin'}).then(console.log);
"
```

### 6.2 Smoke test UI
- ✅ Login exitoso → redirige a /dashboard
- ✅ Sidebar muestra menú completo (admin ve todo)
- ✅ /admin/costs muestra panel con $0 (sin uso aún)
- ✅ /status muestra "Operacional" en verde
- ✅ /tickets carga lista (vacía o demo)
- ✅ Crear un ticket de prueba → enriquecimiento AIE corre → status="enriched"

### 6.3 Verificar SSO Google (si activaste)
- Logout
- /login → click "Sign in with Google"
- Debe redirigir a Google, autenticar, volver a /dashboard como user nuevo

---

## FASE 7 — Setup backups automáticos

### 7.1 Cloudflare R2 / Backblaze B2 (almacenamiento externo barato)
- **B2 (recomendado):** https://www.backblaze.com/cloud-storage
  - $0.005/GB/mes
  - Crear bucket `ams-prod-backups`
  - Crear application key → guardar `keyID` + `applicationKey`

### 7.2 Setup rclone en VPS
```bash
sudo apt install -y rclone
rclone config
# n) New remote
# name> b2
# Storage> Backblaze B2
# account> <keyID>
# key> <applicationKey>
# resto: default
```

Test:
```bash
rclone ls b2:ams-prod-backups
# (vacío al principio, pero no debe dar error)
```

### 7.3 Variable de entorno + primer backup manual
```bash
echo "BACKUP_RCLONE_REMOTE=b2:ams-prod-backups" >> /opt/ams/supply-chain-ams-stack/.env
bash /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod
# debe terminar OK con "subido a b2:ams-prod-backups/ams/prod/"
```

### 7.4 Cron automático (diario 3 AM, retener 30 días)
```bash
sudo crontab -e
# pegar:
0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1
```

### 7.5 Test restore (en QAS o staging idealmente)
```bash
bash /opt/ams/supply-chain-ams-stack/scripts/restore-test.sh
# levanta un postgres efímero, restaura el último backup, verifica conteos
```

---

## FASE 8 — Observabilidad (opcional pero recomendado)

### 8.1 Activar perfil observability
```bash
cd /opt/ams/supply-chain-ams-stack
docker compose -f docker-compose.prod.yml --profile observability up -d
```

Esto levanta: Prometheus + Grafana + Alertmanager.

### 8.2 Grafana
- Browser → `https://ams.tudominio.cl/grafana` (si lo agregaste al Caddyfile) o `http://<IP_VPS>:3000` (interno)
- Login: `admin` / `<GRAFANA_ADMIN_PASSWORD>` (lo generaste en Fase 3)
- Importar dashboard AMS (provisioning ya lo hace automático)

### 8.3 Alertmanager → Slack
- Editar `.env`:
  ```bash
  SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
  ```
- Restart alertmanager:
  ```bash
  docker compose -f docker-compose.prod.yml --profile observability restart alertmanager
  ```
- Verificar logs:
  ```bash
  docker logs ams-prod-alertmanager 2>&1 | tail -20
  # debe decir "==> alertmanager.yml generado en /tmp/alertmanager.yml"
  ```
- Test alerta:
  ```bash
  curl -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"test","severity":"warning"},"annotations":{"summary":"Test desde curl"}}]'
  # debe llegar a Slack en segundos
  ```

---

## FASE 9 — GitHub Actions deploy-on-tag

Esto te permite hacer `git tag v1.1.4-feature-x && git push --tags` desde tu compu y el deploy ocurre solo.

### 9.1 Generar SSH key dedicada para deploy
En tu compu local:
```bash
ssh-keygen -t ed25519 -C "github-deploy@ams" -f ~/.ssh/ams_deploy_key
# enter dos veces (sin passphrase)
```

### 9.2 Agregar la pública al VPS como `ams` user
```bash
cat ~/.ssh/ams_deploy_key.pub | ssh ams@<IP_VPS> "cat >> ~/.ssh/authorized_keys"
```

### 9.3 Obtener fingerprint del VPS
```bash
ssh-keyscan -t ed25519 <IP_VPS>
# copiar la línea completa, ej: "49.13.x.x ssh-ed25519 AAAAC3NzaC1lZDI1..."
```

### 9.4 Configurar GitHub Secrets
- https://github.com/vladyrap/supply-chain-ams-agent/settings/secrets/actions
- Click **New repository secret** para cada uno:

| Name | Value |
|------|-------|
| `VPS_HOST` | `<IP_VPS>` |
| `VPS_USER` | `ams` |
| `VPS_SSH_KEY` | (pegar el contenido completo de `~/.ssh/ams_deploy_key`) |
| `VPS_DEPLOY_PATH` | `/opt/ams/supply-chain-ams-stack` |
| `VPS_HOST_FINGERPRINT` | (la línea completa del `ssh-keyscan`) |
| `AMS_DOMAIN` | `ams.tudominio.cl` |

### 9.5 Test del workflow
- Re-correr el workflow fallido (Actions → "Deploy on tag" → click el run rojo → "Re-run all jobs")
- Debe pasar todos los steps:
  1. ✅ Resolve and validate tag
  2. ✅ Verify required secrets
  3. ✅ Setup SSH key
  4. ✅ Pin VPS host fingerprint
  5. ✅ Pull + redeploy stack
  6. ✅ Smoke test post-deploy

### 9.6 Próximos deploys (workflow normal)
```bash
# En tu compu, después de mergear features:
git tag v1.1.4-feature-x
git push --tags
# GitHub Actions deploya automáticamente al VPS
```

---

## FASE 10 — Onboarding primer cliente

### 10.1 DNS subdominio del cliente
- Agregar `acme.ams.tudominio.cl` apuntando al VPS (o usar wildcard `*.ams.tudominio.cl` ya configurado en Fase 2)

### 10.2 Crear tenant en DB
```bash
docker exec ams-prod-db psql -U ams_user -d ams_agent <<EOF
INSERT INTO tenants (id, name, subdomain, created_at)
VALUES ('acme', 'ACME Cliente', 'acme', NOW());
EOF
```

### 10.3 Crear admin del tenant
```bash
docker exec -it ams-prod-backend node -e "
  const {createUser} = require('./dist/services/auth.service');
  createUser({
    email:'admin@acme.com',
    password:'<password-temporal>',
    name:'Admin ACME',
    role:'admin',
    tenantId:'acme'
  }).then(console.log);
"
```

### 10.4 Cargar KB inicial
- Browser → `https://acme.ams.tudominio.cl/login` con `admin@acme.com`
- /knowledge → "Importar documentos" → arrastrar PDFs / DOCX del cliente
- Esperar ingest + embeddings (1-5 min según volumen)

### 10.5 Enviar credenciales al cliente
Usar el email transaccional Resend (si configurado) o manual con plantilla:

> Bienvenido a AMS Platform · ACME
>
> Tu cuenta admin: admin@acme.com
> URL: https://acme.ams.tudominio.cl
> Password temporal: <password>
>
> Cambiala en tu primer login (Settings → Cambiar contraseña).

---

## 🚨 Troubleshooting común

### "JWT_SECRET required in production"
- Backend boot falla con esto si la var no está seteada o tiene < 32 chars.
- Fix: `openssl rand -hex 32` → pegar en `.env` → `docker compose restart backend`

### Caddy no obtiene certificado SSL
- Verificar DNS: `dig +short ams.tudominio.cl` debe devolver tu IP del VPS
- Verificar puertos 80 + 443 abiertos: `sudo ufw status`
- Ver logs Caddy: `docker logs ams-prod-caddy 2>&1 | tail -50`
- Let's Encrypt tiene rate limit (5 fails/hr/domain). Si excediste, esperar 1 hora.

### "POSTGRES_PASSWORD required" en compose
- El compose tiene `${POSTGRES_PASSWORD:?required}` → falla si vacío
- Fix: agregar a `.env` y `docker compose up -d`

### Gemini "429 quota exceeded"
- Excediste el cap diario local (200 calls/día default)
- Aumentar: `echo "GEMINI_CAP_PER_DAY=500" >> .env && docker compose restart backend`
- O esperar al rollover (00:00 UTC)

### Frontend 502 Bad Gateway
- Container platform no está up: `docker compose ps`
- Build falló: `docker compose logs platform 2>&1 | tail -50`
- Caddy no ve healthy: `docker exec ams-prod-caddy wget -O- http://platform:3000/` debe responder

### Backend 500 en mutations
- Probablemente falla por algo del audit fix. Ver logs:
  ```bash
  docker logs ams-prod-backend 2>&1 | tail -100
  ```
- Comunes:
  - "tenant_id violates not-null" → un audit event se está insertando sin tenantId. Verificar que `tenantPlugin` está antes de routes en server.ts (ya lo está en v1.1.3).
  - "PUT intelligence 403 origin not allowed" → CORS_ORIGINS no incluye el dominio del frontend.

---

## ✅ Checklist final pre-cliente

- [ ] DNS A records propagados (`dig +short` responde con IP del VPS)
- [ ] HTTPS funcional en `https://ams.tudominio.cl` + `https://api.ams.tudominio.cl`
- [ ] Login con admin bootstrap funciona
- [ ] /admin/costs muestra panel (con $0 inicial)
- [ ] /status muestra "Operacional"
- [ ] Crear ticket → AIE enrich exitoso
- [ ] Backup nocturno corre (verificar log al día siguiente)
- [ ] Backup subido a B2/R2 (`rclone ls b2:ams-prod-backups`)
- [ ] SSO Google funciona (si activado)
- [ ] Welcome email llega (si Resend activado)
- [ ] Alertmanager → Slack funciona (si activado)
- [ ] GitHub deploy-on-tag verde
- [ ] Budget alert Google Cloud configurado a $5
- [ ] Solo 1 tarjeta activa en Google Billing

---

## 📚 Referencias

- **Migrations:** `agent/database/migrations/001..004*.sql`
- **Audit completo:** `stack/docs/BUGS_AUDIT_v1.1.0.md` (64 bugs, 100% cerrados)
- **Reporte SLA:** `stack/docs/v1.1.0-SLA-READY-REPORT.md`
- **Manual cliente:** `stack/docs/MANUAL_FUNCIONAL.md`
- **Documentación técnica:** `stack/docs/DOCUMENTACION_TECNICA.md`
- **Doc ejecutivo:** `stack/docs/DOCUMENTO_EJECUTIVO.md`

---

**v1.1.3-all-bugs-fixed** · 64/64 bugs auditados cerrados · Listo para producción 🚀
