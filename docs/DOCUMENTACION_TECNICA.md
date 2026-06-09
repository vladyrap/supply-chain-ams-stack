# 🔧 Documentación Técnica — AMS Platform

> **Para**: developers, DevOps, arquitectos, integradores
> **Versión**: v1.0.0
> **Última actualización**: 2026-06-09

---

## 📑 Índice

1. [Arquitectura general](#1-arquitectura-general)
2. [Stack tecnológico](#2-stack-tecnológico)
3. [Estructura de repos](#3-estructura-de-repos)
4. [Setup local de desarrollo](#4-setup-local-de-desarrollo)
5. [Ambientes (dev / qas / prod)](#5-ambientes-dev--qas--prod)
6. [Schema de base de datos](#6-schema-de-base-de-datos)
7. [API Reference](#7-api-reference)
8. [Pipeline AIE (Auto-Intelligence Enrichment)](#8-pipeline-aie-auto-intelligence-enrichment)
9. [Seguridad](#9-seguridad)
10. [Observabilidad](#10-observabilidad)
11. [Multi-tenancy](#11-multi-tenancy)
12. [CI/CD](#12-cicd)
13. [Deploy](#13-deploy)
14. [Performance](#14-performance)
15. [Convenciones de código](#15-convenciones-de-código)

---

## 1. Arquitectura general

```
┌──────────────────────────────────────────────────────────┐
│              Cliente (Browser, móvil)                    │
└─────────────────┬────────────────────────────────────────┘
                  │ HTTPS (443)
                  ▼
┌──────────────────────────────────────────────────────────┐
│  Caddy 2 — Reverse proxy + auto-SSL Let's Encrypt        │
│  app.X.cl → :6700  ·  api.X.cl → :6601  ·  status →:6700│
└──────────┬──────────────────────┬────────────────────────┘
           │                      │
           ▼                      ▼
┌─────────────────────┐  ┌─────────────────────────┐
│  Platform           │  │  Backend Agent          │
│  Next.js 14 SSR     │  │  Fastify 4 TS           │
│  :3000 (host 6700)  │  │  :8000 (host 6601)      │
│                     │  │                         │
│  RBAC + cookies     │  │  helmet + rate-limit    │
│  ErrorBoundary      │  │  CSRF + tenant resolve  │
└──────────┬──────────┘  └────────┬────────────────┘
           │ HTTP/JSON              │
           └──────────┬─────────────┘
                      │
        ┌─────────────┼─────────────┬──────────────┐
        ▼             ▼             ▼              ▼
   ┌────────┐   ┌────────┐   ┌─────────┐   ┌──────────┐
   │ PostgreSQL │ │ Redis  │   │ Whisper │   │ Worker   │
   │ pgvector  │  │ cache  │   │ ASR     │   │ (jobs)   │
   │ :6602     │  │ :6603  │   │ :6611   │   │          │
   └─────┬─────┘  └────────┘   └─────────┘   └──────────┘
         │
         ▼
   ┌──────────────────────────────────────┐
   │  Gemini API (Google Cloud)           │
   │  gemini-2.5-flash · embeddings       │
   └──────────────────────────────────────┘

   Observability stack (separado):
   ┌─────────────┐ ┌──────────┐ ┌────────────┐ ┌──────────┐
   │ Prometheus  │ │ Grafana  │ │ Alertmanager│ │ ELK     │
   │ :6609       │ │ :6605    │ │             │ │ :6604   │
   └─────────────┘ └──────────┘ └────────────┘ └──────────┘
```

### Flujo de un request típico

1. Browser → `https://app.x.cl/tickets`
2. Caddy termina TLS → forward a platform:3000
3. Next.js SSR renderea HTML
4. Browser carga JS, hace `fetch /api/tickets` → Caddy → backend:8000
5. Backend: helmet headers → rate limit check → CSRF check → tenant resolve → handler
6. Handler: DB query (Postgres) o LLM call (Gemini con rate limit defensive)
7. Response JSON → browser
8. React actualiza UI

---

## 2. Stack tecnológico

### Frontend (platform)
| Componente | Versión | Por qué |
|---|---|---|
| **Next.js** | 14.2.x | App Router + SSR + buen DX |
| **React** | 18.x | Standard |
| **TypeScript** | 5.x | Type safety |
| **@sentry/nextjs** | 9.x | Error tracking productivo |
| **@playwright/test** | 1.x | Tests E2E |

### Backend (agent)
| Componente | Versión | Por qué |
|---|---|---|
| **Node.js** | 20 LTS | Estabilidad |
| **Fastify** | 4.28.x | 10x más rápido que Express |
| **TypeScript** | 5.x | Type safety + DX |
| **@fastify/helmet** | 11.x | Security headers |
| **@fastify/rate-limit** | 9.x | Anti-abuse |
| **@fastify/cors** | 8.x | CORS productivo |
| **@google/genai** | latest | Cliente Gemini |
| **@sentry/node** | 8.x | Error tracking |
| **pg** | 8.x | Postgres driver |
| **pino** | 9.x | Logger estructurado |
| **bcrypt** | 5.x | Hash passwords |

### Database
| Componente | Versión | Por qué |
|---|---|---|
| **PostgreSQL** | 16 | Robusto + JSONB rico |
| **pgvector** | latest | Embeddings de RAG nativo |
| **Redis** | 7-alpine | Cache + jobs queue |

### Infra
| Componente | Versión | Por qué |
|---|---|---|
| **Docker Compose** | 2.20+ | Orquestación local + VPS |
| **Caddy** | 2.x | Reverse proxy + SSL auto |
| **Hetzner Cloud CX32** | - | VPS productivo barato |

### Observabilidad
| Componente | Versión | Por qué |
|---|---|---|
| **Prometheus** | latest | Métricas |
| **Grafana** | latest | Dashboards |
| **Alertmanager** | latest | Routing alertas |
| **Elasticsearch** | 8.13 | Logs |
| **Kibana** | 8.13 | Log search |
| **Logstash** | 8.13 | Log pipeline |
| **Sentry SaaS** | - | Error tracking |
| **k6** | latest | Load testing |

### LLM
| Componente | Versión | Por qué |
|---|---|---|
| **Gemini 2.5 Flash** | - | Balance precio/calidad |
| **Gemini 2.5 Flash-Lite** | - | Tareas simples |
| **gemini-embedding-001** | 768 dim | RAG embeddings |
| **Whisper ASR** | base | Transcripción local (no envía audio a cloud) |

---

## 3. Estructura de repos

3 repos independientes en GitHub `vladyrap/`:

### `supply-chain-ams-agent`
**Backend Fastify + Worker + DB schema**

```
backend/
├── src/
│   ├── server.ts              # Bootstrap Fastify
│   ├── routes/                # 24+ archivos de rutas
│   ├── services/              # Lógica de negocio (audit, gemini, etc.)
│   ├── middleware/            # tenant.ts, auth, rbac
│   ├── intelligence/          # task-router, prompt-packs, schemas
│   ├── schemas/               # JSON schemas para structured output
│   ├── database/              # db connection + migrations
│   ├── utils/                 # logger, retry, metrics, rate-limiter
│   └── types/                 # Tipos compartidos
├── prompts/                   # Prompt templates por tipo de tarea
├── Dockerfile
└── package.json

database/
├── init.sql                   # Schema base
└── migrations/                # SQL migrations idempotentes

worker/                        # Jobs en background (RAG indexing, etc.)
observability/                 # Prometheus rules, Alertmanager config
```

### `supply-chain-ams-platform`
**Frontend Next.js 14**

```
src/
├── app/                       # App Router
│   ├── (public)/              # /login, /signup (sin auth)
│   ├── (platform)/            # /dashboard, /tickets, /admin/* (con auth)
│   └── status/                # Status page pública
├── components/
│   ├── admin/                 # AdminCostsPanel, AdminRoiPanel, etc.
│   ├── tickets/               # TicketCommandCenter, N1PackageSection, etc.
│   ├── common/                # ErrorBoundary, Modal, etc.
│   └── dashboard/             # Mission Control, etc.
├── hooks/                     # useTicketAudit, useAutoEnrichment, etc.
├── services/                  # API clients (tickets.api, admin-usage.api)
├── intelligence/              # Engines client-side (N1 normalizer, etc.)
├── lib/
│   ├── modules.ts             # MODULES = sidebar definition + RBAC
│   └── demo/                  # Datos demo
├── utils/                     # rbac, business-value-engine, etc.
└── types/                     # Tipos compartidos

tests/e2e/                     # Playwright tests
```

### `supply-chain-ams-stack`
**Orquestador + scripts + docs + legal + observability**

```
.
├── docker-compose.yml         # Stack completo dev (include agent + platform)
├── docker-compose.prod.yml    # Prod con Caddy + secrets via env
├── Caddyfile.prod             # Caddy reverse proxy + auto SSL
├── Caddyfile.multi-env        # Caddy con 3 subdominios (dev/qas/prod)
├── scripts/                   # backup, restore, deploy, healthcheck, cleanup
├── observability/             # alertmanager.yml, prometheus rules
├── loadtest/                  # k6 scripts
├── docs/                      # Toda la docs operacional
│   ├── DEPLOY_MULTI_ENV.md
│   ├── SSO_GOOGLE_GUIDE.md
│   └── ...
├── legal/                     # POLITICA_PRIVACIDAD.md, TERMINOS_USO.md
├── RUNBOOK.md                 # Incident response
├── CHECKLIST_PROD.md          # 35 items prod-readiness
├── ONBOARDING_CLIENTE.md      # Cómo alta cliente nuevo
├── MANUAL_FUNCIONAL.md        # Manual para usuarios
├── DOCUMENTACION_TECNICA.md   # ESTE archivo
└── DOCUMENTO_EJECUTIVO.md     # Visión C-level
```

---

## 4. Setup local de desarrollo

### Pre-requisitos
- Node.js 20 LTS
- Docker Desktop (con WSL2 si Windows)
- Git Bash
- 8 GB RAM disponibles (containers usan ~3 GB)

### Pasos

```bash
# 1. Clonar los 3 repos como hermanos
cd ~/Desktop
git clone https://github.com/vladyrap/supply-chain-ams-agent.git
git clone https://github.com/vladyrap/supply-chain-ams-platform.git
git clone https://github.com/vladyrap/supply-chain-ams-stack.git

# 2. Configurar .env de agent
cd supply-chain-ams-agent
cp .env.example .env
# Editar con GEMINI_API_KEY válida + COOKIE_SECRET

# 3. Configurar .env de platform
cd ../supply-chain-ams-platform
cp .env.example .env
# Default: NEXT_PUBLIC_AGENT_API_URL=http://localhost:6601

# 4. Levantar stack completo
cd ../supply-chain-ams-stack
docker compose up -d

# 5. Esperar 60-90s a que todo esté healthy
docker ps --filter "name=supply-chain-ams"

# 6. Verificar
curl http://localhost:6601/health
curl http://localhost:6700/

# 7. Browser
# http://localhost:6700  → login
```

### Desarrollo con hot-reload (backend)

```bash
cd supply-chain-ams-agent/backend
npm install
npm run dev   # tsx watch + auto-restart
```

### Desarrollo con hot-reload (platform)

```bash
cd supply-chain-ams-platform
npm install
npm run dev   # Next.js dev server
```

⚠️ Si usás hot-reload local, apagá los containers de agent/platform para no chocar de puertos.

---

## 5. Ambientes (dev / qas / prod)

### Estructura por ambiente

| Ambiente | Branch | Compose file | Subdomain prod |
|---|---|---|---|
| **dev** | `main` | `docker-compose.yml` | dev.tuempresa.cl |
| **qas** | `qas` | `docker-compose.qas.yml` | qas.tuempresa.cl |
| **prod** | `main` (tags) | `docker-compose.prod.yml` | app.tuempresa.cl |

### Variables por ambiente

```
agent/
├── .env.example     # Plantilla
├── .env.dev         # dev (gitignored)
├── .env.qas         # qas
└── .env.prod        # prod (en Doppler/Vault)
```

### Deploy a un ambiente específico

```bash
# En el VPS:
cd /opt/ams/supply-chain-ams-stack
bash scripts/deploy-env.sh prod   # o qas, dev
```

---

## 6. Schema de base de datos

### Tablas core

```sql
-- Auth y users
users                    (id UUID PK, email, password_hash, role, tenant_id, is_active, last_login_at, ...)
refresh_tokens           (id UUID PK, user_id FK, token_hash, expires_at)
auth_events              (id, user_id, event_type, ip, ua, created_at)

-- Tickets y operación
tickets_demo             (key PK, title, description, intelligence JSONB, intelligence_status, sap_module, environment, priority, ...)
ticket_intelligence_history (id UUID PK, ticket_key FK, version, intelligence JSONB, ...)
incidents                (id UUID PK, user_name, client_name, sap_module, message, response, model, ...)
scope_items              (id UUID PK, code, module, process, transaction, description, is_active)

-- RBAC
roles                    (id, code, name, permissions JSONB)

-- Audit
audit_events             (id UUID PK, tenant_id, ticket_id, actor_user_id FK, actor_name, event_type, category, severity, payload JSONB, source, created_at, created_minute)
  UNIQUE INDEX uq_audit_events_dedup_minute ON (event_type, ticket_id, audit_events_minute_bucket(created_at)) WHERE ticket_id IS NOT NULL
audit_logs               (legacy, antes de v0.9)

-- Knowledge Base
kb_articles              (id UUID PK, title, content, module, embedding vector(768), created_at)
kb_training_gaps         (id, query, response_quality, action_required)
kb_self_training_config  (...)
kb_self_training_runs    (...)

-- Customer responses
customer_responses       (id UUID PK, ticket_id, type, audience, body, quality_score, version, ...)

-- Escalation
escalation_records       (id, ticket_id, criterion, reason, payload JSONB, status, created_at)
escalation_rules         (...)
escalation_settings      (...)

-- LLM usage tracking
agent_usage              (id UUID PK, source, model, prompt_tokens, completion_tokens, total_tokens, cost_usd, incident_id FK, conversation_id, metadata JSONB, created_at)
agent_evaluations        (...)
agent_feedback           (...)
agent_hallucinations     (...)
agent_response_provenance (...)
agent_prompt_versions    (...)

-- Voice
call_logs                (...)
call_turns               (...)

-- Documents
generated_documents      (...)

-- Integrations
itsm_connectors          (...)
integration_deliveries   (...)
integration_destinations (...)

-- Quality + Testing
eval_runs                (...)
eval_results             (...)

-- Self-training
ai_response_feedback     (...)
```

### Migrations

```
database/
└── migrations/
    ├── 001-audit-events.sql          # Tabla audit_events rica
    └── 002-audit-events-dedup.sql    # UNIQUE constraint anti-duplicación
```

**Aplicar migrations**:
```bash
docker exec -i ams-db-prod psql -U ams_user -d ams_agent_prod < database/migrations/001-audit-events.sql
```

Idempotentes — usan `IF NOT EXISTS` siempre.

---

## 7. API Reference

### Health
```
GET  /health                      → 200 {status: "ok"}
GET  /health/deep                 → 200 con check DB
GET  /api/status                  → 200 con checks detallados
GET  /metrics                     → Prometheus scrape
```

### Auth
```
POST /api/auth/login              → cookies + JWT
POST /api/auth/logout             → clear cookies
GET  /api/auth/me                 → user actual
POST /api/auth/refresh            → refresh token
```

### Tickets (demo)
```
GET    /api/tickets               → list (filtros: status, module, source)
POST   /api/tickets               → crear
GET    /api/tickets/:key          → detalle
PATCH  /api/tickets/:key          → editar
PUT    /api/tickets/:key/intelligence → persistir resultado AIE
DELETE /api/tickets/:key          → soft delete
```

### Audit
```
GET  /api/audit/events            → list (filtros: ticket_id, event_type, since, until)
POST /api/audit/events            → record evento
GET  /api/audit/events/summary    → stats agregadas
GET  /api/audit/events/by-ticket/:key
```

### Admin
```
GET  /api/admin/usage/summary     → costos Gemini ULTIMATE (health, recommendations, forecast, etc.)
GET  /api/rbac/roles              → list roles
POST /api/rbac/users              → crear user
```

### AMS Agent
```
POST /api/ams/classify            → clasificar ticket sin guardar
POST /api/ams/enrich              → enrichment AIE
POST /api/ams/customer-response   → generar respuesta
POST /api/ams/escalation-payload  → armar paquete N2
```

### Knowledge
```
POST   /api/knowledge/upload       → procesar documento (con multipart)
GET    /api/knowledge/search       → semantic search (RAG)
DELETE /api/knowledge/:id          → eliminar
```

### Otros (resumido)
```
/api/meetings/*       → transcripción + minuta
/api/voice/*          → llamadas + ASR
/api/document-factory/* → generar PDFs/Word
/api/scope-items/*    → CRUD scope items SAP
/api/search/*         → global search
/api/eval/*           → quality eval del agente
/api/agent-lab/*      → prompt playground
/api/dashboard/*      → métricas KPIs
/api/integration/*    → mirrors a Jira/SN
/api/sap-inbound/*    → ingest desde SAP webhooks
```

### Endpoints públicos (sin auth)
```
/health · /health/deep · /api/status · /metrics
```

Todos los demás requieren autenticación.

---

## 8. Pipeline AIE (Auto-Intelligence Enrichment)

### Flujo completo

```
Ticket creado/editado
       ▼
useAutoEnrichment hook detecta cambio
       ▼
runAutoEnrichmentPipeline()
       ▼
┌──────────────────────────────────────────────────────┐
│ 1. SAP Context Detector                              │
│    Detecta: module, process, transaction (regex)     │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 2. Contextual Estimation Engine                      │
│    Busca 30 casos similares en DB                    │
│    Calcula ETA min-max + confidence                  │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 3. RAG Retrieval                                     │
│    Embedding del ticket → similar chunks en KB       │
│    Top K=6 con score > 0.55                          │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 4. AMS Specialists Orchestrator                      │
│    8 agentes especializados por módulo:              │
│      MM, SD, FI, CO, PP, WM, PM, BASIS               │
│    Router → primary + secondaries                    │
│    Cada uno emite análisis estructurado              │
│    Consolidator merge + confidence global            │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 5. Gemini Structured Call                            │
│    task-router elige model + temperature             │
│    prompt-loader carga template del taskType         │
│    parseOrRepair valida JSON schema (1 retry)        │
│    Recolecta usage tokens + costo                    │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 6. N1 Package Builder                                │
│    Construye checklist resoluble en N1               │
│    Detecta criterios de escalación N2                │
│    Calcula readiness score 0-100                     │
└──────────────────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────┐
│ 7. Persist + Audit                                   │
│    PUT /api/tickets/:key/intelligence                │
│    Audit events: AUTO_ENRICHMENT_COMPLETED, etc.     │
└──────────────────────────────────────────────────────┘
       ▼
UI actualiza con setIntelligence()
```

### Locks anti-loop (capa 1)
```ts
const inFlightLocks = new Map<string, Promise<TicketIntelligence>>();
// 6 guards en useAutoEnrichment.ts evitan re-disparos
```

### Anti-cost capa 2 (Gemini Rate Limiter)
```ts
assertCanCallGemini("label")  // throws si excede 20/min, 80/hora o 200/día
```

### Anti-cost capa 3 (Backend UNIQUE constraint)
```sql
UNIQUE (event_type, ticket_id, audit_events_minute_bucket(created_at))
```

---

## 9. Seguridad

### Headers de seguridad (helmet)
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: cross-origin
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
```

### Rate limiting global
- Default: 200 req/min por IP
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- Configurable: `RATE_LIMIT_MAX_PER_MIN` env var
- Allowlist: localhost (dev)
- Key generator: `X-Forwarded-For` first IP o `req.ip`

### CORS productivo
```ts
origin: (origin, cb) => ALLOWED_ORIGINS.includes(origin)
// env: CORS_ORIGINS=https://app.tuempresa.cl,https://admin.tuempresa.cl
```

### CSRF Origin-based
- Mutations (POST/PUT/PATCH/DELETE) validan `Origin` o `Referer` header
- Si no está en ALLOWED_ORIGINS → 403
- GET/HEAD/OPTIONS libres (safe per spec)
- Toggle: `ENFORCE_ORIGIN_CSRF=false`

### Body parser robusto
- JSON vacío → `{}` (no 400 unhandled)
- JSON inválido → 400 con error claro

### RBAC en 5 niveles
- viewer / consultor / aprobador / admin / super_admin
- `permissionKey` en MODULES → check `usePermissions()` hook
- `RequirePermission` wrapper en cada page
- Audit `UNAUTHORIZED_ROUTE_ACCESS_ATTEMPT`

### Passwords
- bcrypt cost 12
- Histórico de cambios
- Política de complejidad (próxima feature)

### Secretos
- `.env` gitignored (siempre)
- En prod: Doppler / HashiCorp Vault
- Rotación cada 90 días recomendada
- `COOKIE_SECRET`, `JWT_SECRET`, `GEMINI_API_KEY`, `POSTGRES_PASSWORD`

---

## 10. Observabilidad

### Logs
- Pino structured JSON en stdout
- Docker compose recolecta → Logstash → Elasticsearch
- Kibana en `:6604` para search

### Métricas Prometheus
```
http_requests_total{method, route, status_code}
http_request_duration_seconds{method, route}
gemini_calls_total{model, status}
gemini_call_duration_seconds
gemini_json_invalid_total
gemini_repair_attempts_total
gemini_fallback_used_total
gemini_confidence_level{level}
audit_events_insert_total
```

### Alertas (Alertmanager → Slack)
- 11 alert rules en `observability/prometheus/rules/ams-alerts.yml`
- Severities: critical/warning/info
- Cada alerta tiene `runbook_url` al RUNBOOK.md

### Tracing (Sentry)
- Backend: `@sentry/node` con `initSentry()` (activa solo si SENTRY_DSN)
- Platform: `@sentry/nextjs` (wizard interactivo para setup)
- Captures unhandled errors + custom captureException()

### Health checks
- `/health` (200 sin DB check, para liveness rápido)
- `/health/deep` (200 con DB ping)
- `/api/status` (público, con todos los checks + uptime)

---

## 11. Multi-tenancy

### Resolución de tenant_id (en orden)
1. Header `X-Tenant-Id`
2. Subdomain (`acme.tuempresa.cl` → `acme`)
3. JWT claim `tenantId`
4. Fallback: `default`

### Helper para queries
```ts
import { scopedWhere } from "./middleware/tenant";

// Compatible single-tenant (cuando tenant=default no agrega WHERE)
const { rows } = await query(
  `SELECT * FROM tickets ${scopedWhere(req.tenantId)} ORDER BY created_at DESC`
);
```

### Status actual
- Middleware: ✅ implementado
- Tabla `tenant_id` columns: existen en audit_events, tickets_demo (pero NULL en data demo)
- Queries con scopedWhere: ⚠️ requiere refactor en services (próximo sprint)

---

## 12. CI/CD

### Workflows existentes

**agent/.github/workflows/ci.yml**
- backend typecheck
- worker typecheck
- docker compose config validation
- SQL init.sql dry-run

**platform/.github/workflows/ci.yml**
- platform typecheck
- next build dry-run

**stack/.github/workflows/ci.yml**
- compose validate
- shellcheck scripts
- docs structure check
- Caddyfile validate

### Pipeline ideal (futuro)
```yaml
on: push
  → typecheck
  → lint
  → test (Playwright + unit)
  → build Docker image
  → push to registry
  → deploy a staging (auto)
on: tag v*.*.*-prod
  → deploy a prod (manual approval)
```

---

## 13. Deploy

### Pre-requisitos VPS
- Ubuntu 22.04 LTS
- 8 GB RAM mínimo (recomendado 16)
- 80 GB SSD
- Docker + Docker Compose 2.20+
- Caddy con dominio + Let's Encrypt

### Bootstrap VPS desde cero
```bash
ssh root@VPS_IP
git clone https://github.com/vladyrap/supply-chain-ams-stack.git /opt/ams/supply-chain-ams-stack
cd /opt/ams/supply-chain-ams-stack
bash scripts/bootstrap-vps.sh    # instala Docker, Caddy, crea dirs
```

### Deploy regular
```bash
ssh ams-prod
cd /opt/ams/supply-chain-ams-stack
bash scripts/backup-db-env.sh prod   # snapshot pre-deploy
git fetch --tags
git checkout v1.0.0-prod-ready
bash scripts/deploy-env.sh prod
bash scripts/healthcheck.sh prod
```

### Rollback
```bash
git checkout v0.13.0-observability-multitenancy   # tag anterior
bash scripts/deploy-env.sh prod
```

### Backups
- `scripts/backup-db-env.sh prod` (cron 3 AM diario)
- Retención: 30 días local + remoto rclone (B2/S3)
- `scripts/restore-test.sh` (cron domingo) valida que el backup sirve

---

## 14. Performance

### Targets actuales
- Backend response p95 < 1s (non-LLM)
- Backend response p95 < 10s (LLM)
- Frontend FCP < 2s
- Frontend TTI < 4s

### Load testing
```bash
k6 run -e BASE_URL=http://localhost:6700 -e API_URL=http://localhost:6601 loadtest/k6-smoke.js
```
Verifica 100 users concurrentes 5 min.

### Caches
- Backend admin/usage: 60s TTL in-memory
- Frontend SWR: ningún cache por default (cada nav = fetch)
- Gemini structured: prompt cache (Google side)

### DB tuning
- pg_settings recomendados para prod:
  - shared_buffers = 25% RAM
  - effective_cache_size = 75% RAM
  - work_mem = 64MB
  - max_connections = 200
- Indexes existentes cubren queries comunes

---

## 15. Convenciones de código

### TypeScript
- `strict: true` en tsconfig
- No `any` (preferir `unknown` + type guards)
- Tipos compartidos en `types/`

### Estructura archivos
```
service.ts        → lógica de negocio (puro)
controller.ts     → handlers HTTP (delegan a services)
routes.ts         → registración Fastify
types.ts          → tipos del módulo
```

### Naming
- camelCase para variables/funciones
- PascalCase para tipos/components React
- SCREAMING_SNAKE para constants
- kebab-case para archivos

### Imports
- Path alias `@/` para src/
- Order: node-builtin → npm-deps → @/ → relative

### Commits (convencional)
```
feat(v0.X.Y): descripción
fix(v0.X.Y): descripción
docs(...): solo docs
refactor(...): sin cambio funcional
test(...): solo tests
chore(...): build, deps, infra
```

### Tags
- `v0.X.Y-feature-name`: releases incremental
- `v1.0.0-prod-ready`: tag de mojón
- `checkpoint-YYYY-MM-DD-verified`: snapshot estable

---

## 🧪 Tests

### Backend
- Tests unitarios: pendiente (Jest config existe)
- Tests integración smoke: en CI workflow

### Platform
- Playwright E2E: `tests/e2e/smoke.spec.ts` (10 tests, 100% passing)
- Tests unitarios componentes: pendiente

### E2E desde CI
```bash
npx playwright install --with-deps chromium
npx playwright test
```

---

## 📞 Soporte técnico interno

| Área | Owner |
|---|---|
| Backend | Vladimir |
| Platform | Vladimir |
| Infra/DevOps | Vladimir |
| DB | Vladimir |
| Tests | A definir |

Para issues: usar GitHub Issues en cada repo.
