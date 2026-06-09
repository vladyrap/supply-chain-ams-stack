# 🎯 CHECKLIST Producción — AMS Platform

> Lista granular de items que requieren intervención manual del owner.
> Ir tachando con `[x]` a medida que se completan.

---

## 🔴 Bloqueantes (NO ir a prod sin esto)

### Seguridad financiera

- [ ] Activar **Budget HARD CAP** con auto-shutdown en Google Cloud
  - URL: https://console.cloud.google.com/billing/budgets?project=gen-lang-client-0094704667
  - Monto: CLP 6.000 (~$6 USD)
  - **CRÍTICO**: marcar checkbox "Inhabilitar facturación al exceder presupuesto"
- [ ] **Limpiar tarjetas almacenadas** en Google Cloud (de 9 a máximo 1)
  - URL: https://console.cloud.google.com/billing/payment
  - Click "Administrar formas de pago" → eliminar las que no uses
- [ ] **Rotar tarjeta de pago** (Mastercard 3252 fue rechazada — verificar con banco)
- [ ] **Pagar saldo pendiente** si Google muestra banner amarillo

### Secretos

- [ ] **Rotar TODAS las keys actuales** (algunas pueden estar en commits viejos):
  - `GEMINI_API_KEY` → crear nueva en https://aistudio.google.com/apikey
  - `COOKIE_SECRET` → `openssl rand -hex 32`
  - `POSTGRES_PASSWORD` → cambiar en DB + .env
  - `SENTRY_DSN` → si aplica
- [ ] **Mover secretos a Doppler / HashiCorp Vault / AWS Secrets** (no en `.env` plano)
  - Doppler quickstart: https://docs.doppler.com/docs/install-cli

### Infraestructura

- [ ] **Comprar dominio productivo** (ej. `ams.tuempresa.cl`)
- [ ] **Configurar DNS** (A record → IP del VPS Hetzner)
- [ ] **HTTPS real** con Let's Encrypt (Caddy ya configurado, solo agregar dominio en `Caddyfile.prod`)
- [ ] **Backups automáticos cron** en VPS:
  ```cron
  0 3 * * *   BACKUP_RETAIN_DAYS=30 /opt/ams/supply-chain-ams-stack/scripts/backup-db-env.sh prod
  0 5 * * 0   /opt/ams/supply-chain-ams-stack/scripts/restore-test.sh \
              $(ls -t /var/backups/ams/prod/*.sql.gz | head -1)
  ```
- [ ] **Backup remoto** (rclone a B2 / S3) configurado en `.env`:
  ```
  BACKUP_RCLONE_REMOTE=b2:ams-backups
  ```

---

## 🟡 Importantes (antes de onboarding de clientes pagando)

### Auth y multi-tenancy

- [ ] **Auth real**: SSO Google / Microsoft / Auth0 (hoy es bootstrap admin)
- [ ] **Multi-tenancy activado**: poblar `tenant_id` en todas las tablas + queries con filtro
- [ ] **Política de passwords** (longitud mín, complejidad, expiración)
- [ ] **2FA opcional** para roles admin

### Quality assurance

- [ ] **Tests E2E con Playwright** (setup ya existe en `tests/e2e/`)
- [ ] **Load test** con k6 / Artillery: 100 users concurrentes durante 10 min
- [ ] **Limpiar mock/demo data** de DB productiva
- [ ] **Verificar visualmente** todos los flujos críticos (login, create ticket, enrichment, escalate, close)

### CORS y headers

- [ ] **CORS productivo**: limitar a dominio real, no localhost
  ```
  CORS_ORIGINS=https://ams.tuempresa.cl
  ```
- [ ] **CSP estricta** (hoy desactivada en helmet)
- [ ] **CSRF token** para mutations

### Monitoreo

- [ ] **Alertas Prometheus → Slack / email** (Alertmanager configurado)
- [ ] **Sentry productivo** activado con DSN real (no demo)
- [ ] **Log aggregation** (ELK local existe, falta retention policy + alertas)
- [ ] **Status page pública** (status.tuempresa.cl) — opcional

---

## 🟢 Operativos (después de prod, semana 1)

### Documentación

- [ ] Manual de usuario actualizado a la versión deployada
- [ ] FAQ con los 10 problemas más comunes
- [ ] Video onboarding de 5 min para nuevos users

### Procesos

- [ ] **SLA documentado** con clientes (uptime %, response time)
- [ ] **Política de datos** (retention, GDPR/Ley Chile 19628)
- [ ] **Plan de incidentes** (severities, escalación, comunicación)
- [ ] **Calendario de mantenciones** (windows mensuales)

### Performance

- [ ] **CDN para assets estáticos** (Cloudflare R2 / Bunny)
- [ ] **DB connection pooling** afinado
- [ ] **Redis cache** para queries frecuentes

---

## 📊 Estado de verificación

```bash
# Correr antes de pasar a prod:
ssh ams-prod
cd /opt/ams/supply-chain-ams-stack
bash scripts/healthcheck.sh prod
bash scripts/restore-test.sh $(ls -t /var/backups/ams/prod/*.sql.gz | head -1)
docker logs --tail 100 supply-chain-ams-backend | grep -iE "error|fatal"
curl -sS https://ams.tuempresa.cl/health
```

Si TODO pasa → estás listo.
Si falla algo → fix antes de cutover.

---

## 🚦 Semáforo go/no-go

| Categoría | Listo | Pendiente | Total |
|---|---|---|---|
| Seguridad financiera | 0 | 4 | 4 |
| Secretos | 0 | 2 | 2 |
| Infraestructura | 0 | 5 | 5 |
| Auth + multi-tenancy | 0 | 4 | 4 |
| QA | 0 | 4 | 4 |
| CORS + headers | 0 | 3 | 3 |
| Monitoreo | 0 | 4 | 4 |
| Docs + procesos | 0 | 6 | 6 |
| Performance | 0 | 3 | 3 |
| **TOTAL** | **0** | **35** | **35** |

**Estado actual: 🔴 NO LISTO para prod-prod**

Recomendación: 1-2 sprints (2-4 semanas) para llegar a 🟢.

---

## 📞 Necesitás ayuda?

- Para temas Google Cloud: https://support.google.com/cloud
- Para problemas del stack AMS: revisar `RUNBOOK.md`
- Para deploy del VPS: `GOLIVE.md`
