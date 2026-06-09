# RUNBOOK Operacional — AMS Platform

> Cómo responder a incidentes, hacer deploys, rollbacks y troubleshooting.
> Mantener actualizado en cada release.

## 🚨 Incident Response

### Severidad

| Sev | Definición | SLA respuesta | SLA resolución |
|---|---|---|---|
| **S1 — Critical** | Sistema caído / clientes sin servicio | 15 min | 1 hora |
| **S2 — High** | Funcionalidad core degradada | 1 hora | 4 horas |
| **S3 — Medium** | Bug afectando pocos users | 4 horas | 24 horas |
| **S4 — Low** | Mejora / bug cosmético | 24 horas | sprint actual |

### Flujo S1 (Critical)

```
1. Detectar (alert PagerDuty / Slack / monitoreo / cliente)
2. Acknowledge en <15 min
3. Verificar status:
   bash scripts/healthcheck.sh prod
4. Si hay caída total → rollback inmediato (ver sección Rollback)
5. Si parcial → mitigar primero, RCA después
6. Comunicar status público (status page)
7. Crear ticket interno con timeline
8. Post-mortem en 48h
```

## 🔄 Rollback de emergencia

### Rollback completo a tag anterior

```bash
ssh ams-prod
cd /opt/ams/supply-chain-ams-stack

# 1. Identificar tag estable previo
git tag --sort=-creatordate | head -5

# 2. Checkout y deploy
PREVIOUS_TAG=v0.12.6-usage-ultimate  # ajustar
git checkout $PREVIOUS_TAG
bash scripts/deploy-env.sh prod

# 3. Verificar health
bash scripts/healthcheck.sh prod
```

### Rollback de DB (último backup)

```bash
# Listar backups disponibles
ls -lh /var/backups/ams/prod/

# Restaurar el más reciente (CON CONFIRMACIÓN — borra DB actual)
bash scripts/restore-db.sh /var/backups/ams/prod/$(ls -t /var/backups/ams/prod/ | head -1)
```

### Rollback de migration SQL

```bash
# Las migrations son idempotentes (IF NOT EXISTS).
# Para revertir cambios destructivos: restaurar backup PREVIO a la migration.
```

## 🚀 Deploy de nueva versión

### Deploy estándar

```bash
ssh ams-prod
cd /opt/ams/supply-chain-ams-stack

# 1. Snapshot pre-deploy
bash scripts/backup-db-env.sh prod

# 2. Pull código
git fetch --tags
git checkout main  # o tag específico

# 3. Build + deploy
bash scripts/deploy-env.sh prod

# 4. Smoke test
bash scripts/healthcheck.sh prod

# 5. Verificar logs primeros 5 min
docker logs --tail 100 -f supply-chain-ams-backend
```

### Deploy con downtime mínimo

El stack soporta rolling deploy del platform (frontend) sin downtime, pero el backend requiere ~10s de corte mientras recrea.

## 🔍 Troubleshooting frecuente

### "Container backend Restarting"

```bash
docker logs --tail 100 supply-chain-ams-backend 2>&1 | grep -iE "error|fatal"

# Causas comunes:
# 1. DB no responde → docker compose restart db
# 2. GEMINI_API_KEY inválida → verificar .env.prod
# 3. Migration falló → ver logs de startup
```

### "Frontend devuelve 502/504"

```bash
# Caddy proxy errors
docker logs --tail 50 supply-chain-ams-caddy

# Probable: backend caído
docker ps --filter "name=supply-chain-ams-backend" --format "{{.Status}}"
```

### "Gemini devuelve 429 / 503"

```bash
# 429: quota agotada → ver panel /admin/costs
# 503: alta demanda Google → temporal, esperar 5-10 min
# Si persiste >30 min: cambiar modelo en .env a flash-lite

sed -i 's|^GEMINI_MODEL=.*|GEMINI_MODEL=gemini-2.5-flash-lite|' /opt/ams/supply-chain-ams-agent/.env
docker compose -f /opt/ams/supply-chain-ams-stack/docker-compose.prod.yml up -d --force-recreate backend
```

### "Audit events duplicados / loop"

```sql
-- Verificar UNIQUE constraint activo
SELECT indexname FROM pg_indexes
WHERE tablename='audit_events' AND indexname LIKE '%dedup%';

-- Si falta, ejecutar migration:
\i /opt/ams/supply-chain-ams-agent/database/migrations/002-audit-events-dedup.sql
```

### "Backend FastifyError unhandled"

Desde v0.12.7 se acepta body vacío en JSON requests. Si vuelven errores `FST_ERR_CTP_*`, verificar que el server.ts tenga el `addContentTypeParser` custom.

## 📊 Monitoreo

### Endpoints clave

| Endpoint | Descripción | Esperado |
|---|---|---|
| `GET /health` | Liveness backend | 200 con `{status: "ok"}` |
| `GET /metrics` | Prometheus metrics | 200 con scrape |
| `GET /api/admin/usage/summary` | Costos Gemini | 200 con JSON |
| `GET /admin/costs` (platform) | Panel admin costos | 200 |

### Métricas Prometheus a vigilar

```
gemini_calls_total                  → tasa de llamadas
gemini_call_duration_seconds         → p95 < 5s
audit_events_insert_total            → debería crecer
http_request_duration_seconds        → p95 < 1s para endpoints sin LLM
```

## 💾 Backups

### Estado backup actual

```bash
ls -lh /var/backups/ams/prod/ | tail -5
# Debe haber 1 archivo diario por los últimos 30 días
```

### Restore test (semanal)

```bash
# Validar último backup sin tocar prod
bash scripts/restore-test.sh $(ls -t /var/backups/ams/prod/*.sql.gz | head -1)
```

## 🔐 Rotación de secretos

Rotar cada 90 días o ante sospecha de leak:
- `GEMINI_API_KEY` → https://aistudio.google.com/apikey
- `COOKIE_SECRET` → generar con `openssl rand -hex 32`
- `POSTGRES_PASSWORD` → ALTER USER + actualizar .env + restart

## 📞 Escalación

| Rol | Cuándo | Contacto |
|---|---|---|
| L1 — Yo (Vladimir) | Default | (este teléfono) |
| L2 — DBA externo | DB corrupta, migration falló | (a definir) |
| L3 — Google Cloud Support | Gemini API issues persistentes >2h | https://support.google.com/cloud |

## 📋 Checklist post-incidente

- [ ] Sistema restaurado a status normal
- [ ] Causa raíz identificada
- [ ] Fix aplicado y desplegado
- [ ] Ticket interno con timeline completo
- [ ] Comunicación a stakeholders enviada
- [ ] Post-mortem agendado (48h max)
- [ ] Acción preventiva definida
- [ ] RUNBOOK actualizado si hace falta
