# Deploy AMS Platform — DEV / QAS / PROD en un VPS

Guía paso-a-paso para levantar los 3 ambientes en un VPS (recomendado: Hetzner CX32, Ubuntu 24.04 LTS).

## Arquitectura

```
┌─ Internet ─────────────────────────────────────────────────┐
│                                                             │
│  dev.amsplatform.tudominio.com    →  Caddy → :6700 (DEV)    │
│  dev-api.amsplatform.tudominio.com →  Caddy → :6601 (DEV)   │
│                                                             │
│  qas.amsplatform.tudominio.com    →  Caddy → :6800 (QAS)    │
│  qas-api.amsplatform.tudominio.com →  Caddy → :6801 (QAS)   │
│                                                             │
│  amsplatform.tudominio.com        →  Caddy → :6900 (PROD)   │
│  api.amsplatform.tudominio.com    →  Caddy → :6901 (PROD)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                          │
                  ┌───────┴───────┐
                  │  VPS Ubuntu   │
                  │  Caddy (host) │
                  │               │
                  │  Docker:      │
                  │   ams-network │
                  │     ├ DEV: backend-dev + db-dev + redis-dev + platform-dev
                  │     ├ QAS: backend-qas + db-qas + redis-qas + platform-qas
                  │     └ PROD: backend-prod + db-prod + redis-prod + platform-prod
                  └───────────────┘
```

## Branches en GitHub

| Branch | Ambiente | Auto-deploy |
|---|---|---|
| `main` | DEV | manual con `deploy-env.sh dev` |
| `qas` | QAS | manual tras merge `main → qas` |
| `prod` | PROD | manual con confirmación tras merge `qas → prod` |
| `backup/pre-vXX` | — | ramas snapshot, no se tocan |

## Promoción de cambios

```bash
# Desarrollo activo en main
git checkout main
git pull
# ...trabajo...
git push origin main
ssh vps "cd /opt/ams/supply-chain-ams-stack && bash scripts/deploy-env.sh dev"

# Cuando DEV está estable → promover a QAS
git checkout qas
git merge main
git push origin qas
ssh vps "cd /opt/ams/supply-chain-ams-stack && bash scripts/deploy-env.sh qas"
# Smoke tests + UAT del cliente

# Cuando QAS está aprobado → promover a PROD
git checkout prod
git merge qas
git push origin prod
ssh vps "cd /opt/ams/supply-chain-ams-stack && bash scripts/deploy-env.sh prod"
# (pide confirmación "yes")
```

## Setup inicial (una sola vez)

### 1. Contratar VPS

- Provider: **Hetzner Cloud CX32** (recomendado)
- OS: **Ubuntu 24.04 LTS**
- Region: **Ashburn (US East)** o la más cercana a tu cliente
- SSH key cargada antes de crear

### 2. DNS

En tu registrador de dominio, crear estos 6 registros A apuntando a la IP del VPS:

```
dev.amsplatform.tudominio.com           A   <ip-vps>
dev-api.amsplatform.tudominio.com       A   <ip-vps>
qas.amsplatform.tudominio.com           A   <ip-vps>
qas-api.amsplatform.tudominio.com       A   <ip-vps>
amsplatform.tudominio.com               A   <ip-vps>
api.amsplatform.tudominio.com           A   <ip-vps>
```

Esperá 5-15 minutos a que propaguen antes de seguir.

### 3. Bootstrap del VPS

```bash
ssh root@<ip-vps>

# Instalar Docker + Compose
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg git ufw fail2ban
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Instalar Caddy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Firewall mínimo
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# fail2ban con defaults
systemctl enable --now fail2ban

# Estructura de directorios
mkdir -p /opt/ams /var/backups/ams /var/log/caddy
```

### 4. Clonar los 3 repos

```bash
cd /opt/ams
git clone https://github.com/vladyrap/supply-chain-ams-stack.git
git clone https://github.com/vladyrap/supply-chain-ams-agent.git
git clone https://github.com/vladyrap/supply-chain-ams-platform.git

# Crear red Docker compartida
docker network create ams-network
```

### 5. Configurar Caddy

```bash
# Copiar Caddyfile multi-env (cambiar el dominio antes!)
cp /opt/ams/supply-chain-ams-stack/Caddyfile.multi-env /etc/caddy/Caddyfile
sed -i 's/tudominio.com/TUDOMINIO_REAL.com/g' /etc/caddy/Caddyfile

# Validar y reiniciar Caddy (genera certificados Let's Encrypt automáticamente)
caddy validate --config /etc/caddy/Caddyfile
systemctl restart caddy
systemctl status caddy
# Esperar ~30s para que Let's Encrypt emita los 6 certificados
```

### 6. Crear .env por ambiente

```bash
cd /opt/ams/supply-chain-ams-agent
cp .env.dev.example .env.dev
cp .env.qas.example .env.qas
cp .env.prod.example .env.prod
# Editar cada uno y reemplazar:
#   - GEMINI_API_KEY con keys reales (3 keys distintas, una por ambiente)
#   - POSTGRES_PASSWORD con passwords fuertes distintos
#   - AMS_BOOTSTRAP_ADMIN_PASSWORD distinto por ambiente

cd /opt/ams/supply-chain-ams-platform
cp .env.dev.example .env.dev
cp .env.qas.example .env.qas
cp .env.prod.example .env.prod
# Editar URLs en NEXT_PUBLIC_AGENT_API_URL para apuntar al dominio real
```

### 7. Primer deploy DEV

```bash
cd /opt/ams/supply-chain-ams-stack
bash scripts/deploy-env.sh dev
```

Esperá ~2-3 minutos al primer build. Cuando termine, abrí `https://dev.amsplatform.tudominio.com` en el browser y verificá login.

### 8. Smoke test DEV

- Login con admin bootstrap → debe redirigir a dashboard
- `/tickets` → crear ticket rápido → ver spinner "Analizando…"
- Ticket aparece enriquecido con AmsSpecialistsSection
- `/audit-trail` → ver eventos `GEMINI_CALL_*` o `AMS_ORCHESTRATOR_*`

Si todo OK → repetir paso 7 con `qas` después promover a `prod`.

### 9. Activar backups cron

```bash
# Editar crontab del root
crontab -e

# Pegar (ajustar BACKUP_RETAIN_DAYS si querés):
0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1
0 4 */3 * * BACKUP_RETAIN_DAYS=14 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh qas >> /var/log/ams-backup-qas.log 2>&1
0 4 * * 0 BACKUP_RETAIN_DAYS=7 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh dev >> /var/log/ams-backup-dev.log 2>&1
```

## Rollback rápido

Si un deploy a PROD sale mal:

```bash
# Volver al tag anterior conocido
cd /opt/ams/supply-chain-ams-agent
git checkout v0.11.0   # o cualquier tag previo
docker compose -f docker-compose.prod.yml --env-file .env.prod build
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d

# Idem en platform
cd /opt/ams/supply-chain-ams-platform
git checkout v0.13.0
docker compose -f docker-compose.prod.yml --env-file .env.prod build
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
```

Si la DB se corrompió:

```bash
# Restore del último backup
bash /opt/ams/supply-chain-ams-stack/scripts/restore-db.sh /var/backups/ams/prod/ams_prod_<timestamp>.sql.gz
```

## Checklist pre-deploy PROD

- [ ] Tests pasaron en DEV
- [ ] UAT del cliente aprobado en QAS
- [ ] Branch `prod` está al día con `qas`
- [ ] Tag de versión creado en GitHub (ej. v1.0.0)
- [ ] Backup DB PROD reciente (< 24h)
- [ ] `.env.prod` no tiene placeholders sin reemplazar
- [ ] `GEMINI_API_KEY` PROD tiene quota suficiente
- [ ] Caddy logs sin errores recientes
- [ ] Disco VPS tiene > 5GB libres
- [ ] Plan de comunicación al cliente si hay downtime esperado

## Troubleshooting

### "ams-network not found"

```bash
docker network create ams-network
```

### Caddy no genera certificado

DNS no propagó. Verificá con:
```bash
dig dev.amsplatform.tudominio.com +short
```

### Backend health failing

```bash
docker logs ams-backend-dev --tail 50
# Buscar errores Postgres / Gemini / RAG
```

### Disco lleno

```bash
docker system prune -af --volumes
# CUIDADO: borra volúmenes no usados. NO borra DBs en uso.
```
