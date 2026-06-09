# Audit de bugs · v1.1.0-sla-ready

**Fecha:** 2026-06-09
**Alcance:** 7 dominios revisados en paralelo (SSO/JWT, multi-tenancy, AppSec backend, frontend, DevOps, DB, pipeline AIE/Gemini)
**Total hallazgos:** 11 CRÍTICOS · 18 ALTOS · 21 MEDIOS · 10 BAJOS

---

## CRÍTICOS (fix obligatorio antes de producción)

| # | Área | Archivo:línea | Bug | Fix |
|---|------|---------------|-----|-----|
| **C1** | Multi-tenancy | `server.ts:203` | `tenantPlugin` registrado DESPUÉS de routes → `req.tenantId` siempre vacío en todas las rutas de negocio. Multi-tenancy "no se ejecuta" en producción. | Mover `app.register(tenantPlugin)` ANTES de la primera `app.register(*Routes)` |
| **C2** | Multi-tenancy | `tenant.ts:27-31` | Header `X-Tenant-Id` gana sobre JWT → user del tenant A manda header y lee tenant B | Invertir orden: JWT primero, header sólo si role=super_admin |
| **C3** | Multi-tenancy | `tenant.ts:78-85` | `scopedWhere` retorna `""` si tenantId=`"default"` → bypass total mandando `X-Tenant-Id: default` | Eliminar branch "default = sin filtro"; siempre filtrar |
| **C4** | Multi-tenancy | `tenant.ts:84` | SQL injection latente: interpolación con escape de comilla casero | Devolver `{clause, params}` parametrizado |
| **C5** | AppSec | `auth.controller.ts:69-80` | Signup público con "primer usuario = admin" → race condition deja escalada de privilegios | Desactivar signup público en prod (`ENABLE_PUBLIC_SIGNUP=false`); seed CLI |
| **C6** | AppSec | `jwt.service.ts:11` + `server.ts:143` | JWT_SECRET / COOKIE_SECRET arrancan con default 51-char (warning < 32 nunca dispara) | Fail-fast en NODE_ENV=production si secret no seteado o < 32 chars |
| **C7** | AppSec | `training.routes.ts`, `agent-lab.routes.ts`, `support.routes.ts` | Rutas POST/PATCH/DELETE sin `requirePermission` → anónimo borra KB, modifica training corpus | Agregar `preHandler: requirePermission(...)` a todas las rutas mutantes |
| **C8** | DevOps | `deploy-on-tag.yml:50-59` | Shell injection vía `$TAG` + HEREDOC roto (set -e no aplica) | Validar tag formato regex + pasar script vía stdin con `bash -s -- "$TAG"` |
| **C9** | DevOps | `compose.prod.yml:206` | `GRAFANA_ADMIN_PASSWORD:-cambiame` → panel admin con default `admin/cambiame` | `${GRAFANA_ADMIN_PASSWORD:?required}` |
| **C10** | DB | `db.ts:9-13` | Pool max=10, sin statement_timeout → pool exhaustion (admin-usage hace 9 queries Promise.all) | max=25, statement_timeout=15s, agregar `withTx` helper |
| **C11** | Email | `email.service.ts:87-89,126,161` | XSS / template injection en `${opts.name}` sin escape HTML; CRLF en subject | `escapeHtml()` en todos los `${...}` HTML + `.replace(/[\r\n]/g,"")` en subject |

---

## ALTOS (fix antes del primer cliente real)

### Multi-tenancy
- **A1** `audit-events.service.ts` — `tenant_id` nullable y callsites no lo setean → forensics rotos cross-tenant
- **A2** `audit-events.service.ts:162-252` — `listAuditEvents`/`getAuditByTicket`/`getAuditSummary` sin `WHERE tenant_id`
- **A3** `admin-usage.routes.ts:14` — sin RBAC ni filtro tenant; cache global cross-tenant
- **A4** `escalation.service.ts:575`, `documents.service.ts:84` — `SELECT *` sin tenant filter

### Auth/SSO
- **A5** `auth-google.routes.ts:74,131` — `PUBLIC_BASE_URL` sin validar HTTPS en prod → cookie sin `secure`
- **A6** `auth-google.routes.ts:94` — un email registrado por password puede ser hijacked vía SSO Google (no se verifica `auth_provider` previo)
- **A7** `auth-google.routes.ts:79` — `endsWith('@dominio')` case-sensitive; no usa `userInfo.hd` (Workspace verified)
- **A8** `server.ts:93-104` — `allowList: ["127.0.0.1"]` + `trustProxy: true` → spoof `X-Forwarded-For` bypassea rate limit
- **A9** `auth.routes.ts` — sin rate limit dedicado para login/signup/reset (200/min/IP es brute-forceable)
- **A10** `server.ts:119` — bypass CSRF si no hay `Origin/Referer` → botnet `curl` ataca rutas sin auth (combo con C7)
- **A11** `testing.controller.ts:74-118` — multipart upload sin allowlist de mime types → SVG con JS = XSS stored

### Frontend
- **A12** Landing + Status — placeholders `tuempresa.cl`/`tudominio.cl` rotos en 6+ CTAs prod
- **A13** `sentry.client.config.ts:31-35` — `beforeSend` solo borra cookies; deja headers (`authorization`), `event.user.email`, query tokens
- **A14** `sentry.client.config.ts:38` — `window.Sentry = Sentry` expone SDK a scripts third-party / XSS
- **A15** `status/page.tsx:131` — expone URL de backend interno (`http://10.0.x.x:6601`) al público

### Pipeline AIE
- **A16** `useAutoEnrichment.ts:25` — lock `Map` module-level del bundle = no comparte entre tabs → 2 tabs duplican enrichment + costo 2×
- **A17** `ticket.controller.ts:230` — PUT intelligence sin lock optimista → last-write-wins entre tabs
- **A18** `gemini-rate-limiter.ts:75` — assertCanCallGemini chequea per-call, NO per-ticket → cap se golpea en call #3 de 5, primeras 2 ya se cobraron, ticket queda parcial
- **A19** `parse-or-repair.ts:87` — retry NO chequea rate limit → 2× cost cuando Gemini devuelve JSON malo

### DevOps
- **A20** `backup-db-env.sh:50-58` — `pg_dump | gzip` puede pasar SIZE check con backup truncado
- **A21** `alertmanager.yml` — Alertmanager NO expande env vars → `${SLACK_WEBHOOK_URL}` se envía literal → monitoring silente en prod
- **A22** `Caddyfile.prod` — `reverse_proxy` sin `health_uri` → 502 al cliente durante deploys

---

## MEDIOS (fix oportunista)

### DB
- M1 `audit-events.service.ts:21-69` — DDL en cada cold start; race en cluster multi-worker
- M2 6+ `SELECT *` en services que serializan al cliente (`rbac.service.ts`, `escalation.service.ts`, `auth.service.ts`)
- M3 JSONB `tickets_demo.intelligence` sin GIN index → full-scan en future search
- M4 `agent_usage.created_at` sin BRIN → admin dashboard 10-100× más lento
- M5 `audit_events` sin composite index `(ticket_id, created_at)` / `(category, severity, created_at)`
- M6 `users.email UNIQUE` case-sensitive → `Foo@x`/`foo@x` duplican
- M7 FK `ON DELETE SET NULL` en `audit_events.actor_user_id` → audit pierde forensics
- M8 LIMIT 500-1000 sin paginación → responses 50MB+

### Frontend
- M9 `AdminCostsPanel`/`AdminRoiPanel` — `setInterval(refresh, 30s)` sin AbortController → fetches encolados si backend lento
- M10 `AdminRoiPanel.tsx:84` — div-by-zero mitigado con `?? 0.001` → ROI astronómico falso si costo=0
- M11 `status/page.tsx:53` — fetch sin timeout
- M12 `status/page.tsx:50-66` — race setState post-unmount

### Pipeline AIE
- M13 `gemini-structured.service.ts:138` — no chequea `finishReason === "SAFETY"` → ticket queda con análisis fantasma
- M14 PUT `/tickets/:key/intelligence` sin schema validation → DoS guardando 29MB JSON
- M15 SSE handlers sin `req.raw.on("close")` → memory leak si cliente cierra tab
- M16 Sin cache LRU por inputHash → reanalyze siempre gasta Gemini
- M17 Audit costo loggeado es ESTIMADO no real (no usa `resp.usageMetadata.totalTokenCount`)

### AppSec
- M18 Error handler devuelve `err.message` de 4xx sin sanitizar → enumeración de schema PG
- M19 `logger.error({err})` con stack/payload completo → Sentry recibe SQL queries con valores
- M20 OAuth: no chequea `userInfo.hd` para Workspace verified

### DevOps
- M21 `bootstrap-vps.sh` — `curl|bash` sin pin SHA → repo hackeado = VPS hackeado

---

## BAJOS (deuda técnica)

- B1 Landing `<div>©{new Date().getFullYear()}</div>` — hydration mismatch latente si se agrega `"use client"`
- B2 `(marketing)/layout.tsx` fragment vacío → depende de root layout
- B3 `sessions` sin index `(user_id, expires_at)` → purge lento
- B4 `ticket_intelligence_history.id BIGSERIAL` — secuencia adivinable
- B5 `call_turns` sin FK a `call_logs(call_sid)` → orphans
- B6 `deploy.sh` llama `backup-db.sh` sin arg de ambiente
- B7 `restore-db.sh:30` — `DROP DATABASE` sin terminar conexiones
- B8 `go-live-prod.sh` — HEREDOC no quoted en `cat > .env` → password con `$` corrompe archivo
- B9 `ci.yml:65` — `docker rm -f pg-ci` sin `trap EXIT` → leak contenedor en runner si psql falla
- B10 `audit-events` event con PII en payload (email completo en `actor_name`)

---

## Plan de remediación priorizado

### Fase 1 — Hot fixes (1-2 horas, BLOQUEANTE para clientes)
1. **C1**: mover `tenantPlugin` en `server.ts` antes de routes
2. **C2 + C3 + C4**: rewrite `tenant.ts` (JWT first, no default bypass, parametrizado)
3. **C6**: fail-fast secrets en prod
4. **C9**: quitar default `cambiame` de Grafana
5. **C11**: escapeHtml en email service
6. **A21**: alertmanager envsubst wrapper

### Fase 2 — Hardening (4-6 horas)
7. **C5 + A9**: `ENABLE_PUBLIC_SIGNUP=false` + rate limit login dedicado
8. **C7**: requirePermission en training/agent-lab/support routes
9. **C8**: deploy-on-tag con validation + stdin
10. **C10**: pool size + statement_timeout + withTx
11. **A1+A2+A3+A4**: aplicar scopedWhere en services críticos
12. **A16+A18**: lock server-side AIE + budget reservation per-ticket

### Fase 3 — Frontend + observability (2-3 horas)
13. **A12**: env vars para dominios/emails comerciales
14. **A13+A14**: Sentry beforeSend completo + sacar window.Sentry
15. **A15**: ocultar URL backend interno en /status
16. **A22**: Caddyfile `health_uri /health`

### Fase 4 — DB + perf (3-4 horas)
17. **M1**: extraer DDL a migrations/ formales
18. **M3+M4+M5**: agregar indices (GIN, BRIN, composite)
19. **M2**: enumerar columnas en SELECTs que cruzan HTTP boundary

---

**Total esfuerzo estimado:** ~12 horas de trabajo concentrado para cerrar todos los críticos + altos.
