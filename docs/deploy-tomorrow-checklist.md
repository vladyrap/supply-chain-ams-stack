# 📋 Checklist deploy — VPS productivo

Pre-deploy listo. Esta es la lista 1-a-1 para deployar al VPS nuevo.

> **Última actualización**: 2026-06-01. Incluye smoke tests del Ticket Command
> Center orquestador (NBA, Readiness, ETA Explainability), Visual Evidence
> Analyzer en CreateTicketModal y Demo guiada end-to-end.

---

## ANTES (hoy / mañana en la mañana)

- [ ] **Comprar VPS** 4 vCPU / 8 GB RAM / 80 GB SSD en Arsys o Hetzner
- [ ] Anotar **IP pública** del VPS:  `_____._____._____._____`
- [ ] Anotar **root password** o tener llave SSH lista
- [ ] **Decidir dominio:**
  - Opción A: `ams.miespejo.cl` (reusar dominio existente)
  - Opción B: dominio nuevo
- [ ] **Configurar DNS** en el panel del registrador:
  ```
  A    ams         IP_DEL_VPS
  A    api.ams     IP_DEL_VPS
  ```
- [ ] Verificar propagación: `dig +short ams.tudominio.cl` debe devolver tu IP nueva
- [ ] Tener a mano:
  - Tu key de **Gemini API** (https://aistudio.google.com/app/apikey)
  - Email para usuario admin
  - Password admin (12+ chars)

---

## EN EL VPS (a las 16:00 sharp · ~30 min total)

### Paso 1 · Conectar (1 min)
```bash
ssh root@IP_DEL_VPS
```

### Paso 2 · Bootstrap (5-8 min)
Instala Docker, configura firewall, clona los 3 repos.
```bash
curl -sSL https://raw.githubusercontent.com/vladyrap/supply-chain-ams-stack/main/scripts/bootstrap-vps.sh | bash
```
Esperar a que termine. Debe decir `✓ Bootstrap listo.`

### Paso 3 · Generar secrets (30 seg)
```bash
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)"
echo "COOKIE_SECRET=$(openssl rand -hex 32)"
echo "JWT_SECRET=$(openssl rand -hex 32)"
```
**Copiar las 3 líneas que salen** — vas a pegarlas en el `.env`.

### Paso 4 · Configurar .env (3 min)
```bash
cd /opt/ams/supply-chain-ams-stack
cp .env.production.example .env
nano .env
```

Completar mínimo estos valores:
```bash
AMS_DOMAIN=ams.miespejo.cl
AMS_API_DOMAIN=api.ams.miespejo.cl

GEMINI_API_KEY=AIzaSy...                # tu key real
POSTGRES_PASSWORD=...                    # del openssl
COOKIE_SECRET=...                        # del openssl
JWT_SECRET=...                           # del openssl

CORS_ORIGINS=https://ams.miespejo.cl
NEXT_PUBLIC_AGENT_API_URL=https://api.ams.miespejo.cl

AMS_BOOTSTRAP_ADMIN_EMAIL=tu@email.com
AMS_BOOTSTRAP_ADMIN_PASSWORD=password-fuerte-12chars-minimo
```
Guardar con `Ctrl+O` → `Enter` → `Ctrl+X`.

### Paso 5 · Primer deploy (10-15 min, build incluido)
```bash
bash scripts/deploy.sh
```
El script:
1. Pull de los 3 repos.
2. Build de imágenes (la primera vez tarda ~8 min).
3. `docker compose up -d`.
4. Espera healthcheck.

Al final debe mostrar `✓ Healthy: backend + platform` y la tabla con containers en `Up`.

### Paso 6 · Verificar (1 min)
```bash
bash scripts/healthcheck.sh
```
Todos los items con `✓` verde.

### Paso 7 · Probar en navegador (2 min)
Abrir `https://ams.miespejo.cl`:
- Espera el certificado SSL automático (puede tardar 30s la primera vez).
- Login con tu email + password del `.env`.
- Verás la landing `/welcome` con el hero animado.

### Paso 8 · Configurar backup automático (1 min)
```bash
(crontab -l 2>/dev/null; echo '0 3 * * * /opt/ams/supply-chain-ams-stack/scripts/backup-db.sh >> /var/log/ams-backup.log 2>&1') | crontab -
crontab -l
```

### Paso 9 · Cambiar password bootstrap (2 min)
En la UI:
1. Ir a `/admin`.
2. Editar tu usuario → cambiar password.
3. Crear un usuario adicional con tu nombre real y rol ADMIN.
4. Eliminar o desactivar `admin@demo.cl`.

---

## SI ALGO FALLA

### Caddy no obtiene SSL
```bash
docker logs ams-prod-caddy --tail 30
```
Verificar DNS: `dig +short ams.miespejo.cl` debe devolver la IP del VPS.

### Backend no arranca (unhealthy)
```bash
docker logs ams-prod-backend --tail 50
```
Causas comunes:
- `DATABASE_URL` mal formada — revisar password.
- `GEMINI_API_KEY` vacía o inválida.

### Frontend carga pero `/api/*` da CORS error
- `CORS_ORIGINS` debe ser EXACTO `https://ams.miespejo.cl` sin trailing slash.
- Rebuild backend: `docker compose -f docker-compose.prod.yml up -d --no-deps backend`.

### Rollback rápido (si todo está roto)
```bash
cd /opt/ams/supply-chain-ams-stack
docker compose -f docker-compose.prod.yml down
git -C /opt/ams/supply-chain-ams-platform checkout COMMIT_ANTERIOR
git -C /opt/ams/supply-chain-ams-agent checkout COMMIT_ANTERIOR
bash scripts/deploy.sh
```

---

## DESPUÉS DEL DEPLOY (cuando ya esté online)

- [ ] Compartir URL al cliente / equipo
- [ ] Verificar Sentry funcionando si seteaste `SENTRY_DSN`
- [ ] Configurar `JIRA_*` / `SERVICENOW_*` si vas a usarlos
- [ ] Probar el flujo end-to-end:
  1. Login → /welcome → dashboard.
  2. /agent → mandar pregunta → ver respuesta.
  3. /history → click en incidente → escalar N2.
  4. /testing-intelligence → crear escenario → grabar pantalla.
  5. /escalation-n2 → ver el registro creado en paso 3.
  6. /time-estimator → crear una estimación de prueba (ej. INCIDENT_RESOLUTION · MM · MEDIUM) → verificar que devuelve banda horas + fases + respuesta al cliente.

- [ ] **Smoke tests del Ticket Command Center** (features nuevos):
  1. /tickets → click "+ Crear ticket" → modal abre en el centro del viewport (no clipped por la card padre — confirma que ModalPortal funciona).
  2. En el modal: drag & drop una imagen SAP → ver `VisualEvidenceUploader` analizar y detectar transacción/módulo. **Verificar que la imagen NO se persiste** (`/api/tickets` payload solo lleva `visualEvidenceNotes`).
  3. Crear el ticket → abrir en /tickets → ver **TicketNextBestAction** card grande al tope con CTA.
  4. Verificar **TicketReadinessScore** muestra 0-100 con breakdown.
  5. Sección Estimación → expandir → ver **ETA Explainability** con columnas ↑ y ↓.
  6. Probar **QuickActions** (Document Factory, Testing, Quality, Playbook) → confirmar que abren el modal del módulo correspondiente sin saltar de pantalla.
  7. /tickets → click "Ejecutar demo completa" → ver **GuidedAmsDemo** ejecutar 13 pasos reales con SSE stream.

- [ ] **Verificar audit trail** (`/audit`): los nuevos event types aparecen:
  - `VISUAL_EVIDENCE_ATTACHED`, `VISUAL_EVIDENCE_ANALYZED`, `TICKET_ESTIMATED_WITH_VISUAL_ANALYSIS`
  - `DEMO_STARTED`, `DEMO_STEP_COMPLETED`, `DEMO_COMPLETED`

- [ ] **Generar manual del cliente** (opcional, no bloqueante):
  ```bash
  cd /opt/ams/supply-chain-ams-platform/docs/manual/scripts
  npm install
  npx playwright install chromium
  MANUAL_BASE_URL=https://ams.tudominio.cl \
    MANUAL_USER_EMAIL=admin@tudominio.cl \
    MANUAL_USER_PASSWORD=tu-password \
    npm run build
  ```
  Genera `../pdf/manual-{cliente,dev,sales}.pdf` (~50 MB c/u) listos para mandar al sponsor.

---

## INVENTARIO DE COMMITS ACTUALES (rebuildeables desde GitHub)

| Repo | Branch | Último commit local | Cambios clave |
|---|---|---|---|
| `supply-chain-ams-agent` | main | `8c5db48` | RBAC + auth bcrypt 12 + Jira/SN/CloudALM + IA video + Sentry |
| `supply-chain-ams-platform` | main | ver `git log -1` | UX polish + Estimador de Tiempos (módulo `/time-estimator`) |
| `supply-chain-ams-stack` | main | ver `git log -1` | docker-compose.prod + Caddy + scripts ops |

El `deploy.sh` hace `git pull origin main` así que va a traer automáticamente
los commits que estén en el remoto. **Antes del deploy verificá** que pusheaste
todo lo local con `git -C /opt/ams/<repo> log origin/main..HEAD` — si devuelve
commits, faltan en el remoto.

---

## ESTIMACIÓN DE TIEMPO

| Paso | Tiempo |
|---|---|
| Bootstrap VPS | 8 min |
| Configurar .env | 3 min |
| Primer build + deploy | 15 min |
| Verificación y primer login | 4 min |
| Configurar backups + admin | 3 min |
| **TOTAL** | **~33 min** |

Con margen, ponete **45 minutos** desde el SSH hasta tener cliente conectándose.

---

## VPS SUGERIDOS

| Provider | Plan | Specs | Precio aprox |
|---|---|---|---|
| **Hetzner** | CX31 | 4 vCPU · 8 GB · 80 GB SSD | €11/mes |
| **Hetzner** | CCX13 (CPU dedicada) | 2 vCPU dedicado · 8 GB | €15/mes |
| **Arsys** | Cloud VPS S | 4 vCPU · 8 GB · 80 GB | €19/mes |
| **DigitalOcean** | Premium Intel | 4 vCPU · 8 GB · 160 GB | $48/mes |

Recomendación: **Hetzner CX31** mejor relación precio/rendimiento si no
necesitás soporte en castellano. Si querés soporte local en Chile, **Arsys**.
