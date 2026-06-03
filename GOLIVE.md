# Go-Live AMS Platform en internet

**Tiempo estimado:** 30-40 min (incluyendo propagación DNS).

Esta guía asume que arrancás con **solo PROD** (un ambiente). Para sumar DEV y QAS después, ver `docs/DEPLOY_MULTI_ENV.md`.

---

## Paso 1 — Contratar VPS (10 min)

Recomendado: **Hetzner Cloud CX32**.

1. Crear cuenta en https://hetzner.cloud (necesita tarjeta o PayPal)
2. Crear "Server":
   - **Location:** Ashburn (us-east) — mejor latencia LATAM, o Helsinki si querés UE
   - **Image:** Ubuntu 24.04
   - **Type:** CX32 (4 vCPU, 8 GB RAM, 80 GB SSD) — **~8 EUR/mes**
   - **SSH Key:** subí tu clave pública (`~/.ssh/id_ed25519.pub` o `~/.ssh/id_rsa.pub`)
   - **Name:** `ams-prod`
3. Click **Create & Buy now**
4. Esperá ~1 min. Recibís un mail con la IP pública.

**Alternativas:**
- DigitalOcean Droplet 4GB (~24 USD/mes) si preferís panel más cómodo
- Arsys Cloud VPS S (~10-15 EUR/mes) si querés soporte ES

---

## Paso 2 — Apuntar DNS (5 min + 5-15 min propagación)

En tu registrador de dominio (Cloudflare / Namecheap / Arsys / etc.), crear **dos registros A**:

| Nombre | Tipo | Valor | TTL |
|---|---|---|---|
| `amsplatform` (o el nombre que elijas) | A | `<IP de tu VPS>` | 300 |
| `api.amsplatform` | A | `<IP de tu VPS>` | 300 |

> Si tu dominio es `acme.com`, vas a tener:
> - `amsplatform.acme.com` → frontend
> - `api.amsplatform.acme.com` → backend
>
> Si querés usar el dominio root (sin subdominio), reemplazá `amsplatform.acme.com` por `acme.com` y `api.amsplatform.acme.com` por `api.acme.com`.

Verificá propagación en https://dnschecker.org/ — esperá hasta que la mayoría devuelva la IP correcta.

---

## Paso 3 — Generar Gemini API key (3 min)

1. Ir a https://aistudio.google.com/app/apikey
2. Login con cuenta Google
3. Click **Create API key**
4. Copiá la key (empieza con `AIza...`). La vas a necesitar en el paso siguiente.
5. (Recomendado) En "Quota" ponele un límite mensual para no sorprenderte.

---

## Paso 4 — Bootstrap VPS (5 min)

Conectate al VPS por SSH:

```bash
ssh root@<IP-de-tu-VPS>
```

Ejecutá el bootstrap:

```bash
curl -sSL https://raw.githubusercontent.com/vladyrap/supply-chain-ams-stack/main/scripts/bootstrap-go-live.sh | bash
```

Esto instala Docker + Caddy + fail2ban + ufw, clona los 3 repos en `/opt/ams/`, crea la red Docker y genera `/opt/ams/bootstrap-config.env` (vacío).

---

## Paso 5 — Completar config (3 min)

```bash
nano /opt/ams/bootstrap-config.env
```

Completá estos 6 valores:

```env
AMS_DOMAIN=amsplatform.acme.com
LETSENCRYPT_EMAIL=tu-email@acme.com
GEMINI_API_KEY_PROD=AIza...
POSTGRES_PASSWORD_PROD=<una password fuerte de 20+ chars>
AMS_ADMIN_EMAIL=admin@acme.com
AMS_ADMIN_PASSWORD=<una password fuerte de 16+ chars>
```

Guardar (Ctrl+O, Enter, Ctrl+X en nano).

> El archivo tiene permisos 600 — solo root puede leerlo.

---

## Paso 6 — Go-Live (10 min — el primer build tarda)

```bash
bash /opt/ams/supply-chain-ams-stack/scripts/go-live-prod.sh
```

El script:

1. Valida que el DNS apunte a este VPS
2. Genera `/etc/caddy/Caddyfile` con tus dominios reales
3. Reinicia Caddy (pide certificados Let's Encrypt automáticamente)
4. Genera `.env.prod` en agent y platform
5. Checkout branch `prod` (si no existe, usa `main`)
6. Build + up de los 5 containers (db-prod, redis-prod, backend-prod, platform-prod)
7. Smoke test: verifica que `https://amsplatform.acme.com` y `https://api.amsplatform.acme.com` respondan

Si todo OK, vas a ver:

```
=========================================
  GO-LIVE PROD COMPLETADO
=========================================
  Frontend: https://amsplatform.acme.com
  API:      https://api.amsplatform.acme.com
  Admin:    admin@acme.com
=========================================
```

---

## Paso 7 — Primera entrada (2 min)

1. Abrí `https://amsplatform.acme.com` en el browser
2. Login con `admin@acme.com` + la password que pusiste en `bootstrap-config.env`
3. Deberías ver el dashboard. Crear un ticket de prueba en `/tickets`.

Si el certificado HTTPS no funciona la primera vez: **esperá 1-2 minutos** y refrescá. Let's Encrypt a veces tarda en emitir.

---

## Paso 8 — Activar backups diarios (1 min)

```bash
crontab -e
```

Pegá:

```cron
0 3 * * * BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod >> /var/log/ams-backup-prod.log 2>&1
```

Guardar. Listo. Backup diario a las 3 AM, retiene 30 días.

---

## Si algo sale mal

### El DNS no propaga
- Verificá en https://dnschecker.org/
- Esperá hasta que > 50% de servidores devuelvan tu IP
- Algunos registradores tardan hasta 30 min (Arsys especialmente)

### Caddy no genera certificado HTTPS
```bash
journalctl -u caddy --no-pager | tail -50
```
Buscá líneas con `cannot get certificate` — generalmente DNS aún no propagó.

### Backend no llega a healthy
```bash
docker logs ams-backend-prod --tail 50
```
Causas comunes:
- `GEMINI_API_KEY` mal pegada (con espacios)
- `POSTGRES_PASSWORD` con caracteres especiales que rompen el connection string
- Tabla no existe — esperá al primer hit autenticado y se crea sola

### "ams-network not found"
```bash
docker network create ams-network
```

### Rollback rápido
```bash
cd /opt/ams/supply-chain-ams-agent && git checkout v0.11.0
cd /opt/ams/supply-chain-ams-platform && git checkout v0.13.0
bash /opt/ams/supply-chain-ams-stack/scripts/go-live-prod.sh
```

---

## Próximos pasos opcionales

- **Sumar DEV y QAS:** seguí `docs/DEPLOY_MULTI_ENV.md` desde el paso 7
- **Sentry para errors en PROD:** crear proyecto en https://sentry.io y pegar el DSN en `bootstrap-config.env`
- **Backup remoto a B2/S3:** instalar `rclone` y setear `BACKUP_RCLONE_REMOTE=b2:tu-bucket` en el cron
- **Monitoring:** Uptime Kuma docker container apuntando a `/api/tickets/provider`
