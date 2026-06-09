# Onboarding de Cliente — AMS Platform

> Pasos para dar de alta un cliente nuevo en la plataforma.
> Asume que el sistema ya está desplegado en producción.

## ⏱️ Tiempo estimado

- Setup técnico: **30 min**
- Sesión de onboarding con cliente: **1 h**
- Total: **~1.5 h por cliente**

---

## 📋 Pre-requisitos

- [ ] Sistema en prod con HTTPS funcionando
- [ ] Backup remoto activo (rclone configurado)
- [ ] Budget HARD CAP Google Cloud activo
- [ ] Sentry recibiendo errors
- [ ] Tu rol = `admin` en la plataforma

---

## 🎯 Flujo de onboarding

### Paso 1 — Crear cuenta del cliente (5 min)

```sql
-- Conectarse a DB prod
ssh ams-prod
docker exec -it ams-db-prod psql -U ams_user -d ams_agent_prod

-- Crear cliente
INSERT INTO users (email, password_hash, role, tenant_id, is_active, name)
VALUES (
  'admin@cliente.com',
  crypt('PASSWORD_TEMPORAL', gen_salt('bf')),
  'admin',
  'cliente_slug',  -- ej: 'acme_corp'
  true,
  'Admin Cliente'
);
```

**O por UI** (cuando esté SSO activo):
1. Login con tu admin
2. `/admin` → tab Usuarios → "+ Nuevo usuario"
3. Asignar rol `admin` + tenant_id

### Paso 2 — Configurar tenant del cliente (5 min)

```bash
# Crear directorio de uploads del tenant
ssh ams-prod
mkdir -p /var/ams/uploads/cliente_slug

# Setear branding (opcional)
docker exec -i ams-db-prod psql -U ams_user -d ams_agent_prod <<SQL
INSERT INTO tenant_settings (tenant_id, brand_color, brand_logo_url, business_hours)
VALUES ('cliente_slug', '#0891b2', 'https://cdn.../logo.png', '09:00-18:00 CLT');
SQL
```

### Paso 3 — Cargar Knowledge Base inicial (15 min)

El cliente típicamente tiene docs de su operación SAP. Cargar:

1. Login en la plataforma como admin
2. Ir a **Conocimiento** → "Subir documento"
3. Cargar PDFs/Word/MD:
   - Manual de proceso SAP del cliente
   - Lista de transacciones críticas
   - Glosario de términos del cliente
   - Procedimientos operativos estándar (POEs)
4. El sistema procesa y crea embeddings automáticos

### Paso 4 — Configurar integraciones (opcional, 10 min)

Si el cliente usa Jira/ServiceNow/Slack:

```bash
# Ir a /admin → Integraciones
# Cargar credenciales API en .env del cliente:
JIRA_BASE_URL=https://cliente.atlassian.net
JIRA_API_TOKEN=...
JIRA_USER_EMAIL=...
SLACK_WEBHOOK_URL=...
```

### Paso 5 — Sesión de onboarding live (60 min)

**Agenda:**

| Tiempo | Tema |
|---|---|
| 0-10 min | Login + tour del sidebar + roles |
| 10-25 min | Crear primer ticket guiado + ver enrichment AI |
| 25-35 min | Mostrar Audit Trail + Customer Response generation |
| 35-45 min | Dashboard Mission Control + Topology |
| 45-55 min | Documents Factory + Reuniones |
| 55-60 min | Q&A + handover |

**Material a tener listo:**
- Manual PDF de cliente (`PDFs/manual-cliente.pdf`)
- Demo flow guiado (`/demo` page)
- Credenciales temporales escritas

### Paso 6 — Post-onboarding (mismo día)

```bash
# 1. Enviar al cliente:
- Login URL (https://ams.tuempresa.cl)
- Credenciales (password temporal con OBLIGACIÓN de cambiar al primer login)
- Manual PDF
- WhatsApp del soporte

# 2. Marcar en CRM interno:
- Fecha onboarding
- Plan contratado
- Próximo check-in (7 días)

# 3. Setear monitoreo cliente-específico:
docker exec -i ams-db-prod psql -U ams_user -d ams_agent_prod <<SQL
INSERT INTO client_health_check (tenant_id, last_check, status)
VALUES ('cliente_slug', NOW(), 'onboarding');
SQL
```

---

## 📊 Métricas a vigilar primera semana

```bash
# Diariamente en la consola:
ssh ams-prod
docker exec ams-db-prod psql -U ams_user -d ams_agent_prod -c "
SELECT
  tenant_id,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day') as tickets_24h,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as tickets_7d
FROM incidents
WHERE tenant_id = 'cliente_slug'
GROUP BY tenant_id;
"
```

**Señales de éxito:**
- ≥3 tickets creados en primera semana
- ≥1 enrichment AI completado
- Login del admin cliente ≥2 veces por semana

**Señales de alerta:**
- 0 tickets en 7 días → llamar al cliente
- 0 logins en 5 días → llamar al cliente
- Tickets atascados en `enrichment_failed` → debugear

---

## 🚨 Si algo sale mal en onboarding

| Problema | Fix rápido |
|---|---|
| Login no funciona | Verificar `is_active=true` en users + password_hash correcto |
| Enrichment AI falla | Verificar `GEMINI_API_KEY` válida + budget no excedido |
| Documentos no se procesan | Verificar worker corriendo: `docker ps \| grep worker` |
| UI lenta | Verificar `/api/status` healthy + memoria backend < 500MB |

---

## 📞 Soporte post-onboarding

**Plan estándar** (incluido):
- Email support 24h response
- Bug fixes incluidos
- 1 sesión Q&A mensual

**Plan premium** (extra):
- WhatsApp directo
- 4h SLA bug crítico
- Sesiones de mejora mensuales
- Roadmap input

---

## 🎁 Welcome kit a enviar

- [ ] Email de bienvenida con credenciales
- [ ] Link al manual PDF (auto-generado en `/admin/manual`)
- [ ] Video walkthrough 10 min
- [ ] Agenda de check-in a 7 días
