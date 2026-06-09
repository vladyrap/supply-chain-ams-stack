# Política de Privacidad — AMS Platform

**Última actualización**: 2026-06-09
**Versión**: 1.0
**Aplicable a**: AMS Platform (servicio SaaS) operado por [TU EMPRESA SpA], RUT [XXXX], Chile.

Cumple con:
- Ley N° 19.628 sobre Protección de la Vida Privada (Chile)
- Ley N° 21.719 (modernización protección de datos, vigencia 2026)
- GDPR (Reglamento UE 2016/679) — para clientes con presencia EU
- LGPD (Brasil) — para clientes con datos brasileños

---

## 1. Datos que recolectamos

### 1.1 Datos del usuario (administrador del cliente)
- Email corporativo
- Nombre y apellido
- Rol asignado (viewer / consultor / aprobador / admin)
- Logs de acceso (IP, timestamp, user-agent)

### 1.2 Datos operacionales del cliente
- Tickets de soporte SAP creados (descripción, módulo, prioridad)
- Mensajes intercambiados con el agente IA
- Documentos cargados al knowledge base
- Adjuntos (capturas, logs SAP) — se procesan y luego se ofuscan PII

### 1.3 Datos generados por el sistema
- Análisis de IA sobre tus tickets (categorización, ETA, recomendaciones)
- Auditoría completa de eventos
- Métricas agregadas de uso

### 1.4 Lo que **NO** recolectamos
- Datos de tu sistema SAP productivo (no nos conectamos directo)
- Información financiera detallada
- Datos personales de tus empleados que no sean usuarios de AMS

---

## 2. Cómo usamos los datos

| Finalidad | Base legal | Retención |
|---|---|---|
| Prestación del servicio AMS | Contrato | Mientras dure la suscripción + 12 meses |
| Mejora del producto (analytics agregada) | Interés legítimo | Indefinido (datos anonimizados) |
| Soporte técnico | Contrato | 90 días post-cierre del ticket |
| Auditoría de seguridad | Obligación legal | 6 años |
| Facturación | Obligación legal | 6 años (Servicio de Impuestos Internos) |

**NO usamos tus datos para:**
- Entrenar nuestros modelos de IA con tu información sin consentimiento explícito
- Venta o cesión a terceros
- Publicidad dirigida

---

## 3. Procesadores externos

Compartimos data limitada con:

| Proveedor | Datos | Propósito | Localización |
|---|---|---|---|
| **Google Cloud (Gemini API)** | Texto del ticket + contexto SAP | Análisis IA | EU/US |
| **Hetzner Cloud** | Toda la operación | Hosting servidor | Alemania |
| **Backblaze B2** | Backups encriptados | Storage backups | US |
| **Sentry** | Logs de error (sin payload) | Monitoreo crashes | EU |

Todos firmaron DPA (Data Processing Agreement) con cláusulas modelo UE.

---

## 4. Tus derechos (ARCO + RGPD)

Como titular de datos tenés derecho a:

| Derecho | Cómo ejercerlo | Plazo respuesta |
|---|---|---|
| **A — Acceso** | Email a privacy@tuempresa.cl | 30 días |
| **R — Rectificación** | Vos mismo desde /admin/profile o ticket de soporte | Inmediato |
| **C — Cancelación** | Email a privacy@tuempresa.cl | 30 días |
| **O — Oposición** | Email a privacy@tuempresa.cl | 30 días |
| **P — Portabilidad** (GDPR) | Email — entregamos export JSON | 30 días |
| **L — Limitación** (GDPR) | Email a privacy@tuempresa.cl | 30 días |

Si no quedás satisfecho, podés reclamar ante:
- **Chile**: Consejo para la Transparencia (https://www.consejotransparencia.cl)
- **EU**: Autoridad nacional de protección de datos (AEPD si España)
- **Brasil**: ANPD (https://www.gov.br/anpd)

---

## 5. Seguridad de los datos

Medidas técnicas implementadas:

- **Encriptación en reposo**: PostgreSQL + backups con AES-256
- **Encriptación en tránsito**: TLS 1.3 (HTTPS obligatorio)
- **Control de acceso**: RBAC + 5 roles + audit log
- **Backups**: diarios + retención 30 días + restore test semanal
- **Headers de seguridad**: Helmet (XSS, clickjacking, MIME sniff)
- **Rate limiting**: 200 req/min por IP
- **CSRF protection**: validación de Origin en mutations
- **Secretos**: gestionados con Doppler/Vault (no en código)
- **Rotación de claves**: cada 90 días o ante sospecha de leak

**Notificación de breach**: si ocurriera, notificamos a:
- Titulares afectados: en máximo 72h
- Autoridad (Consejo Transparencia / AEPD): en 72h
- Por: email + status page público

---

## 6. Cookies

Usamos cookies estrictamente necesarias:

| Cookie | Propósito | Duración |
|---|---|---|
| `ams_session` | Mantener sesión iniciada | 8 horas |
| `ams_csrf` | Protección CSRF | sesión |
| `ams_pref_theme` | Preferencia dark/light | 1 año |

**No usamos**: cookies de tracking, analytics third-party (Google Analytics, Facebook Pixel, etc.)

---

## 7. Menores de edad

AMS Platform es un servicio B2B. NO recolectamos datos de menores de 18 años a sabiendas. Si detectamos cuenta de menor, la suspendemos y eliminamos los datos en 30 días.

---

## 8. Cambios a esta política

Te notificaremos por email + banner en la app al menos 30 días antes de cualquier cambio material. Cambios menores (typos, clarificaciones) se publican sin aviso pero con nota de versión.

---

## 9. Contacto

**Encargado de Datos (DPO)**:
- Email: privacy@tuempresa.cl
- Teléfono: +56 9 XXXX XXXX
- Dirección postal: [TU DIRECCIÓN], Chile

**Para temas de seguridad**:
- security@tuempresa.cl (PGP key disponible)
- Vulnerability disclosure: security.txt en /.well-known/security.txt
