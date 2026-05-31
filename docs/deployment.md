# 🚀 Deploy a producción · supply-chain-ams-stack

Guía paso a paso para poner el stack online en un VPS (Arsys, Hetzner,
DigitalOcean, lo que tengas). El sistema queda accesible vía HTTPS
con dominio propio.

## 0. Antes de empezar

Necesitás tener listo:

| Item | Cómo | Costo |
|---|---|---|
| **VPS** Debian 12 / Ubuntu 22.04+ | 2 vCPU, 4 GB RAM, 50 GB SSD mínimo | $10–20/mes |
| **Dominio o subdominio** | Cualquier registrador | $10/año o $0 si reusás uno |
| **2 registros DNS A** | `ams.tudominio.cl` y `api.ams.tudominio.cl` → IP del VPS | gratis |
| **Gemini API key** | https://aistudio.google.com/app/apikey | gratis |
| **Acceso SSH al VPS** con usuario root o sudo | proveedor te da las credenciales | — |

Si vas a usar tu VPS Arsys donde corre `miespejo.cl`, tenés que **decidir el dominio del AMS**.
Opciones:
- `ams.miespejo.cl` (subdominio del existente) — más simple, no pagás dominio nuevo.
- `tu-marca-ams.cl` (dominio nuevo) — más profesional para vender a clientes.

Esta guía asume `ams.miespejo.cl` y `api.ams.miespejo.cl`. Cambiá esos
valores donde aparezcan si usás otros.

---

## 1. Configurar DNS

En el panel de tu registrador (donde compraste el dominio):

```
Tipo  Nombre         Valor (IP del VPS)
A     ams            82.223.196.65
A     api.ams        82.223.196.65
```

Verificá la propagación:

```bash
dig +short ams.miespejo.cl
dig +short api.ams.miespejo.cl
# ambos deben devolver tu IP
```

La propagación puede tardar entre 5 minutos y 24 horas. Caddy va a fallar
en obtener el certificado SSL si los DNS no resuelven todavía.

## 2. Bootstrap del VPS

Conectate al VPS:

```bash
ssh root@82.223.196.65
```

Si **es la primera vez** que usás este VPS para AMS, corré el bootstrap.
Esto instala Docker, configura firewall y clona los 3 repos en `/opt/ams/`:

```bash
curl -sSL https://raw.githubusercontent.com/vladyrap/supply-chain-ams-stack/main/scripts/bootstrap-vps.sh | bash
```

Si ya tenés Docker en el VPS (porque ya corre miespejo.cl), igual podés
correrlo: detecta lo que ya está y no rompe nada.

**Coexistencia con miespejo.cl:** el stack AMS usa la red Docker
`ams-prod-net` (aislada) y nombres `ams-prod-*` para los contenedores.
No interfiere con el stack de miespejo.cl. **PERO** el puerto 80/443
sólo puede ser usado por **un único reverse proxy**.

### Si miespejo.cl ya tiene su propio Caddy/Nginx en 80/443

Tenés dos opciones:

**Opción A (más fácil):** sumar el AMS al Caddyfile/Nginx existente y
no levantar el Caddy del compose del AMS. Ver sección 7 más abajo.

**Opción B:** mover miespejo.cl al mismo Caddyfile del AMS para que un
único Caddy maneje los dos sitios.

## 3. Configurar `.env`

En el VPS:

```bash
cd /opt/ams/supply-chain-ams-stack
cp .env.production.example .env
nano .env
```

Valores mínimos que **DEBES** completar:

```bash
AMS_DOMAIN=ams.miespejo.cl
AMS_API_DOMAIN=api.ams.miespejo.cl

GEMINI_API_KEY=AIzaSy...               # tu key real

POSTGRES_PASSWORD=$(openssl rand -base64 32)   # generá una fuerte
COOKIE_SECRET=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

CORS_ORIGINS=https://ams.miespejo.cl
NEXT_PUBLIC_AGENT_API_URL=https://api.ams.miespejo.cl

AMS_BOOTSTRAP_ADMIN_EMAIL=tu@email.com
AMS_BOOTSTRAP_ADMIN_PASSWORD=password-fuerte-de-al-menos-12-chars
```

**Tip:** generar los secrets directamente en línea:

```bash
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)"
echo "COOKIE_SECRET=$(openssl rand -hex 32)"
echo "JWT_SECRET=$(openssl rand -hex 32)"
```

Copiá las 3 líneas que salgan y pegalas en el `.env`.

## 4. Primer deploy

```bash
cd /opt/ams/supply-chain-ams-stack
bash scripts/deploy.sh
```

El script hace:
1. Pull de los 3 repos desde GitHub.
2. Backup de la DB (si ya existe).
3. Build de las imágenes Docker.
4. `docker compose up -d`.
5. Espera healthchecks.
6. Smoke tests.

Después de ~3-5 minutos deberías ver:

```
✓ Healthy: backend + platform
ams-prod-caddy     Up 5 minutes
ams-prod-backend   Up 5 minutes (healthy)
ams-prod-platform  Up 5 minutes (healthy)
ams-prod-db        Up 5 minutes (healthy)
ams-prod-redis     Up 5 minutes
ams-prod-worker    Up 5 minutes
```

## 5. Primer login

Abrí `https://ams.miespejo.cl` en el navegador.

Caddy va a obtener un certificado SSL de Let's Encrypt automáticamente
(puede tardar 30s la primera vez). Si ves un error de SSL, esperá un
minuto y refrescá.

Login con las credenciales bootstrap del `.env`:
- Email: el valor de `AMS_BOOTSTRAP_ADMIN_EMAIL`
- Password: el valor de `AMS_BOOTSTRAP_ADMIN_PASSWORD`

El primer usuario queda como `admin`. Después podés crear más usuarios
desde `/admin`.

## 6. Verificación post-deploy

```bash
cd /opt/ams/supply-chain-ams-stack
bash scripts/healthcheck.sh
```

Salida esperada:

```
▸ Containers
  ✓ ams-prod-caddy · running
  ✓ ams-prod-backend · running
  ✓ ams-prod-platform · running
  ✓ ams-prod-db · running
  ✓ ams-prod-redis · running
  ✓ ams-prod-worker · running

▸ Endpoints públicos (vía Caddy + HTTPS)
  ✓ https://ams.miespejo.cl/ · 307
  ✓ https://api.ams.miespejo.cl/health · 200

▸ Postgres
  ✓ pg_isready · accepting connections

✓ Todos los checks pasaron.
```

## 7. Activar perfiles opcionales

### Voice (Whisper + Twilio)

Si querés el módulo de voz funcionando:

```bash
# 1. Editar .env y poner credenciales Twilio
nano .env
# TWILIO_ACCOUNT_SID=...
# TWILIO_AUTH_TOKEN=...
# TWILIO_PHONE_NUMBER=...

# 2. Levantar con perfil voice
docker compose -f docker-compose.prod.yml --profile voice up -d whisper
```

Esto suma ~1 GB de RAM mientras esté idle, ~2 GB durante transcripción.

### Observability (Prometheus + Grafana)

```bash
docker compose -f docker-compose.prod.yml --profile observability up -d prometheus grafana
```

Por seguridad, Grafana no expone puerto al exterior. Para acceder desde
afuera, agregá al Caddyfile un subdominio extra como `grafana.ams.miespejo.cl`
con basic auth y reverse_proxy a `grafana:3000`.

## 8. Backups automáticos

```bash
# Agregar a crontab del root (3am UTC todos los días)
(crontab -l 2>/dev/null; echo '0 3 * * * /opt/ams/supply-chain-ams-stack/scripts/backup-db.sh >> /var/log/ams-backup.log 2>&1') | crontab -

# Verificar
crontab -l
```

Los dumps quedan en `/var/backups/ams/` con retención de 14 días.

Restaurar un backup:

```bash
bash scripts/restore-db.sh /var/backups/ams/ams_db_20260530T030000Z.sql.gz
```

**Recomendado:** copiar el directorio `/var/backups/ams/` a un bucket
externo (S3, B2, Drive) por si el VPS se pierde:

```bash
# Con rclone (instalación: apt install rclone && rclone config)
rclone copy /var/backups/ams/ b2:tu-bucket/ams-backups/
# Agregar al cron
```

## 9. Updates / nuevos deploys

Cuando hagas cambios al código:

```bash
ssh root@82.223.196.65
cd /opt/ams/supply-chain-ams-stack
bash scripts/deploy.sh
```

El script hace `git pull` de los 3 repos y rebuild de las imágenes
que cambiaron. Downtime típico: 30-60 segundos.

Si necesitás rebuild sin caché (raro):

```bash
bash scripts/deploy.sh --no-cache
```

## 10. Coexistencia con miespejo.cl (opción A)

Si miespejo.cl ya ocupa el puerto 80/443 con su propio Caddy/Nginx,
NO levantes el Caddy del compose del AMS. En vez de eso:

### 10.1 Editar `docker-compose.prod.yml` del AMS

Comentá el bloque `caddy:` completo. Después agregá ports al `platform`
y `backend` (sólo localhost):

```yaml
  backend:
    # ... lo demás igual ...
    ports:
      - "127.0.0.1:6601:8000"  # sólo localhost

  platform:
    # ... lo demás igual ...
    ports:
      - "127.0.0.1:6700:3000"
```

### 10.2 Agregar al Caddyfile existente de miespejo.cl

```
ams.miespejo.cl {
    encode zstd gzip
    reverse_proxy 127.0.0.1:6700
}

api.ams.miespejo.cl {
    encode zstd gzip
    request_body { max_size 110MB }
    reverse_proxy 127.0.0.1:6601 {
        transport http {
            read_timeout 5m
            write_timeout 5m
        }
    }
}
```

Después `systemctl reload caddy` (o restart del contenedor de Caddy).

## 11. Troubleshooting

### Caddy no obtiene certificado SSL

- Verificá DNS: `dig +short ams.miespejo.cl` debe devolver tu IP.
- Puertos 80 y 443 deben estar abiertos. `sudo ufw status`.
- Logs: `docker logs ams-prod-caddy --tail 50`.
- Si pegaste credenciales de staging de Let's Encrypt, te frenan; esperá 1h.

### `/api/auth/login` devuelve 401 con credenciales correctas

- Verificá que `COOKIE_SECRET` y `JWT_SECRET` no estén vacíos.
- Verificá `CORS_ORIGINS` incluya tu dominio real con `https://`.
- Borrá cookies del navegador y reintentá.

### Frontend carga pero `/api/*` devuelve CORS errors

- `CORS_ORIGINS` debe coincidir EXACTAMENTE con el origen del navegador.
- Incluir `https://` y sin trailing slash.

### Backend cae cada pocos minutos (OOM)

- Subí el VPS a 8 GB. O bajá `ASR_MODEL=tiny` si activaste Whisper.
- Desactivá observability profile si está activo.
- Monitor: `docker stats`.

### Las imágenes Docker no se rebuildean tras `git pull`

- Compose cachea agresivamente. Forzá: `bash scripts/deploy.sh --no-cache`.

### El video subido no se ve después de un rebuild

- Los videos viven en el volumen `ams-prod-uploads`, que es persistente
  entre rebuilds. Si NO se ven, verificá: `docker volume inspect ams-prod-uploads`.

### Postgres pierde datos tras rebuild

- El volumen `ams-prod-postgres` es persistente. Si lo borraste accidentalmente
  con `docker volume rm`, restaurá desde el último backup en `/var/backups/ams/`.

### Quiero ver qué está pasando ahora mismo

```bash
docker stats                              # CPU/RAM por contenedor
docker logs ams-prod-backend -f --tail 50 # logs backend en vivo
docker logs ams-prod-platform -f --tail 50
docker logs ams-prod-caddy -f --tail 50
```

## 12. Seguridad mínima en producción

- ✅ Firewall UFW abierto sólo a 22, 80, 443 (lo hace bootstrap-vps.sh).
- ✅ fail2ban activo contra bruteforce SSH.
- ✅ HTTPS forzado con Caddy + HSTS.
- ✅ Bcrypt 12 rounds para passwords.
- ✅ JWT_SECRET y COOKIE_SECRET aleatorios (no defaults).
- ✅ Sin exponer 6601/6700/5432 al exterior.
- ✅ Postgres con password fuerte (`openssl rand -base64 32`).
- ⚠ Activar **basic auth** de Caddy para gate adicional si el sitio es
  para uso interno (no demo público): seteá `AMS_BASIC_AUTH` en el `.env`
  y descomentá la sección `basic_auth` en `Caddyfile.prod`.
- ⚠ **NO subas el `.env` a git nunca.** Está en `.gitignore`.
- ⚠ Rotar `JIRA_API_TOKEN` y otros tokens cada 90 días.
- ⚠ Habilitá Sentry (`SENTRY_DSN`) para visibilidad de errores 5xx.

## 13. Comandos útiles del día a día

```bash
# Status general
docker compose -f docker-compose.prod.yml ps

# Reiniciar sólo el backend (sin tocar la DB)
docker compose -f docker-compose.prod.yml up -d --no-deps backend

# Entrar al Postgres
docker exec -it ams-prod-db psql -U ams_user -d ams_agent

# Ver upload de videos
docker exec ams-prod-backend ls -la /app/uploads/testing/

# Limpieza de espacio (eliminar imágenes viejas)
docker system prune -af --volumes=false

# Detener TODO (cuidado, los datos sobreviven en volúmenes)
docker compose -f docker-compose.prod.yml down

# Wipeo total (PIERDE LOS DATOS, requiere backup previo)
docker compose -f docker-compose.prod.yml down -v
```

## 14. Costos estimados mensuales

| Item | Cost |
|---|---|
| VPS Arsys 4 vCPU / 8 GB / 80 GB | ~€18 |
| Dominio `.cl` | $5/año (~$0.5/mes) |
| Gemini API | $0 free tier (suficiente para piloto) |
| Backups B2/S3 | $1-5 |
| **Total** | **~$20-25/mes** |

Si activás Twilio: + $1/mes por número + ~$0.013/min por llamada.

## 15. Si querés volver atrás

Wipeo completo del stack AMS sin tocar miespejo.cl:

```bash
cd /opt/ams/supply-chain-ams-stack
docker compose -f docker-compose.prod.yml down -v
docker volume ls | grep ams-prod- | awk '{print $2}' | xargs -r docker volume rm
# Si querés también borrar el código:
rm -rf /opt/ams/
```

---

## Siguientes pasos (post-deploy)

- [ ] Verificar que `/admin` lista los 5 usuarios demo iniciales.
- [ ] Crear un usuario propio con tu email real y rol ADMIN.
- [ ] Deshabilitar el usuario `admin@demo.cl` (cambiarle a INACTIVE).
- [ ] Cambiar `AMS_BOOTSTRAP_ADMIN_PASSWORD` por algo definitivo.
- [ ] Configurar backup externo (rclone a B2/Drive).
- [ ] Configurar Sentry (`SENTRY_DSN` + `NEXT_PUBLIC_SENTRY_DSN`).
- [ ] Activar integraciones reales que necesites (Jira/ServiceNow/Cloud ALM)
      con `*_ENABLED=true` + credenciales.
- [ ] Documentar el handover al equipo / cliente.
- [ ] Verificar que el dashboard se carga rápido (~1s primer paint).
