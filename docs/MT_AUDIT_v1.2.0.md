# Audit Multi-Tenant v1.2.0 · Gaps detectados

**Fecha:** 2026-06-10
**Versión auditada:** v1.2.0-multi-tenant
**Método:** 4 agents en paralelo (backend services, frontend, RAG/embeddings/cron, data integrity)

## 🚨 Resumen — 8 gaps reales (5 CRÍTICOS, 3 ALTOS)

| # | Gap | Archivo | Severidad |
|---|-----|---------|-----------|
| **G1** | `audit.service.ts` INSERT audit_logs SIN tenant_id → **NOT NULL violation al primer audit post-deploy** | `services/audit.service.ts` | 🔴 CRÍTICO BLOQUEANTE |
| **G2** | `stats.service.ts` recentAudit SIN filtro tenant → dashboard muestra audit cross-tenant | `services/stats.service.ts:88-96` | 🔴 CRÍTICO |
| **G3** | `rbac.service.ts` platform_users SIN tenant_id en queries → leak/INSERT roto | `services/rbac.service.ts` | 🔴 CRÍTICO |
| **G4** | **Worker `ingest.ts` NO escribe tenant_id en knowledge_items** → RAG cross-tenant + KB de acme termina como 'default' | `worker/src/jobs/ingest.ts` | 🔴 CRÍTICO BLOQUEANTE |
| **G5** | **Worker `autonomous.ts` cron jobs SIN tenant scoping** → alertas SLA cross-tenant | `worker/src/jobs/autonomous.ts` | 🔴 CRÍTICO |
| **G6** | `scope-items.service.ts:188,198` JOIN sin filtro tenant → readiness cross-tenant | `services/scope-items.service.ts` | 🟠 ALTO |
| **G7** | `escalation_records.escalation_number` UNIQUE global → 2 tenants colisionan en ESC-0001 | schema escalation | 🟠 ALTO |
| **G8** | Frontend: localStorage keys no scoped por tenant → super_admin alternando = data leak | múltiples hooks | 🟠 ALTO |

## ✅ Lo que está OK (verificado)

- RAG / pgvector: `rag.service` + `training-embeddings` + `search.service` filtran tenant_id ANTES del `ORDER BY <=>` ✅
- `audit-events.service.ts` (la versión rica) — perfecto, scoped, super_admin con "*"
- `admin-usage.service.ts` cache per-tenant
- 51 services backend con scoping correcto (auth, ticket, support/*, knowledge, training, meeting, incident, customer-response, call-log, provenance, sap-inbound, documents, playbooks, escalation, testing, eval, qa-eval, feedback, integrations, etc.)
- `self-training-cron.service.ts` worker itera tenants activos
- TenantContext bien wireado en frontend
- `/admin/tenants` UI funcional con 403 handling
- Sidebar branding dinámico
- `apiFetch` central con 24 services migrados
- Migrations 005+006 idempotentes y aplicables sin romper datos
- FK ON DELETE RESTRICT en todas las 40 tablas data → tenants

## 🔧 Fixes requeridos antes de deploy

### G1+G2 (audit_logs legacy)
`audit.service.ts` + `stats.service.ts:88-96` → agregar tenant_id en INSERT + WHERE de SELECT.

### G3 (rbac.service platform_users)
Decidir: ¿platform_users es global o per-tenant?
- Si **global** (un solo conjunto de users del producto): DROP COLUMN tenant_id en migration 007
- Si **per-tenant** (cada cliente tiene sus users): agregar tenantId a todas las queries (getSnapshot, upsertUser, deleteUser, resetDemo)

**Decisión recomendada:** mantener per-tenant porque cada cliente debe gestionar SUS usuarios sin ver los de otros.

### G4 (worker ingest)
`worker/src/jobs/ingest.ts` línea 51-69 → agregar `tenant_id` al INSERT de knowledge_items usando `data.tenantId` del job payload.

### G5 (worker autonomous)
`worker/src/jobs/autonomous.ts` → iterar tenants activos (mismo patrón que self-training-cron) y pasar tenantId a cada query + emitEvent.

### G6 (scope-items JOIN)
`services/scope-items.service.ts:188,198` → agregar `AND ak.tenant_id = $X` al JOIN con agent_knowledge / agent_qa.

### G7 (escalation_number UNIQUE)
Migration 007 → DROP UNIQUE global, ADD UNIQUE (tenant_id, escalation_number).

### G8 (localStorage scoping)
Helper `tenantStorage(tenantId, key)` que prefije `tnt:${id}:${key}`. Migrar los 10+ hooks legacy que usan localStorage directo.

## 📋 Otros pendientes (no bloqueantes)

- AuthUser type sin `tenant_id` (deuda técnica)
- Header.tsx / HeroCard.tsx con "AMS Platform" hardcoded
- Customer response signature solo en localStorage (no se persiste a tenant.settings)
- /admin/tenants modal no expone tenant.settings.signature en el form
- Fail-fast check de tabla tenants en index.ts boot
- dashboard JOIN: reforzar `u.tenant_id = t.tenant_id` defense-in-depth
