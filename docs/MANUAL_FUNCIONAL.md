# 📖 Manual Funcional — AMS Platform

> **Para**: usuarios finales, consultores AMS, mesa de soporte
> **Versión**: v1.0.0
> **Última actualización**: 2026-06-09

Este documento describe **cómo usar cada flujo** del sistema desde la perspectiva del usuario. Sin código, sin arquitectura — solo "qué hago para X".

---

## 📑 Índice de flujos

1. [Login y roles](#1-login-y-roles)
2. [Dashboard inicial](#2-dashboard-inicial)
3. [Crear ticket guiado (con IA)](#3-crear-ticket-guiado-con-ia)
4. [Crear ticket rápido](#4-crear-ticket-rápido)
5. [Trabajar un ticket — TCC](#5-trabajar-un-ticket--tcc)
6. [Enrichment automático IA](#6-enrichment-automático-ia)
7. [Generar respuesta al cliente](#7-generar-respuesta-al-cliente)
8. [Escalar a N2](#8-escalar-a-n2)
9. [Cerrar ticket](#9-cerrar-ticket)
10. [Cargar documento al Knowledge Base](#10-cargar-documento-al-knowledge-base)
11. [Document Factory (generar reportes)](#11-document-factory-generar-reportes)
12. [Reuniones AMS (transcripción + minuta)](#12-reuniones-ams-transcripción--minuta)
13. [Canal Telefónico](#13-canal-telefónico)
14. [Mission Control (dashboard ejecutivo)](#14-mission-control-dashboard-ejecutivo)
15. [Panel de Costos Gemini (admin)](#15-panel-de-costos-gemini-admin)
16. [Panel de ROI (admin/aprobador)](#16-panel-de-roi-adminaprobador)
17. [Administración de Usuarios](#17-administración-de-usuarios)

---

## 1. Login y roles

### Pasos:
1. Abrí `https://app.tuempresa.cl`
2. Ingresá tu email y password
3. (Próximamente) o usá "Continuar con Google" SSO
4. Si tu rol tiene permisos limitados, vas a ver menos opciones en el sidebar

### Roles disponibles:

| Rol | Qué puede hacer |
|---|---|
| **viewer** | Solo lectura: ver tickets, dashboard, KB |
| **consultor** | viewer + crear tickets + escribir respuestas + cerrar tickets |
| **aprobador** | consultor + ver ROI + aprobar escalamientos N2 |
| **admin** | TODO + administrar usuarios + ver costos + configurar tenant |

---

## 2. Dashboard inicial

Al loguear, vas a **`/dashboard`** que muestra:

- 📊 **KPIs del día**: tickets nuevos, en curso, cerrados
- 📈 **Tendencias** de la semana
- 🔔 **Notificaciones** recientes
- ⚡ **Quick actions**: crear ticket, ver pendientes, ir a soporte

**Tip**: clickeá cualquier KPI para drill-down al detalle.

---

## 3. Crear ticket guiado (con IA)

**Cuándo usarlo**: cuando el reportante NO sabe describir bien su problema o necesitás ayuda para clasificar.

### Pasos:
1. Sidebar → **Tickets** → botón verde **"🎯 Crear ticket guiado"**
2. Se abre un wizard de **6 pasos**:

| Paso | Qué se pide |
|---|---|
| **1. Contexto SAP** | Ambiente (PROD/QAS/DEV), módulo (MM, SD, FI, CO, etc.), proceso, transacción |
| **2. Problema** | Qué intentaba hacer · Mensaje de error EXACTO (copy/paste) |
| **3. Datos SAP** | (opcional) Datos relevantes del documento que falló |
| **4. Evidencia** | (opcional) Screenshots, logs, archivos |
| **5. Prioridad** | High / Medium / Low (auto-calculada según severity del error) |
| **6. Revisión** | Resumen + readiness score (cuánto le falta al ticket para ser resoluble en N1) |

3. Click **"Crear ticket"**
4. **Automático**: el agente IA empieza a analizar el ticket en segundos

### Lo que pasa después:
- Aparece banner "🤖 Agente AMS está enriqueciendo el ticket..."
- En 5-15 segundos: clasificación, ETA, recomendaciones IA, paquete N1 generado
- El ticket queda con **Readiness Score** (0-100): qué tan completo está

---

## 4. Crear ticket rápido

**Cuándo usarlo**: usuario experto que ya sabe el problema y solo quiere registrarlo.

### Pasos:
1. Sidebar → **Tickets** → botón gris **"+ Crear rápido"**
2. Solo 3 campos: título, descripción, prioridad
3. Click **"Crear"**

⚠️ **Tradeoff**: no hay validación guiada, pero el agente IA igual lo enriquece después.

---

## 5. Trabajar un ticket — TCC (Ticket Command Center)

Cuando clickeás un ticket de la lista, se abre el **TCC** a la derecha con TODA la info y acciones en una pantalla:

### Secciones del TCC:

| Sección | Qué muestra |
|---|---|
| **Header** | Key, título, prioridad, estado, decisión AMS |
| **Análisis unificado** | Readiness, ETA, próxima acción, criterio N2 |
| **Contexto SAP** | Módulo · proceso · transacción |
| **Especialistas AMS** | 8 agentes especializados por módulo opinan |
| **Paquete N1** | Checklist con acciones que un L1 puede ejecutar |
| **Customer Response** | Respuesta lista para enviar al cliente |
| **Casos históricos** | Tickets similares ya resueltos |
| **Estimación contextual** | Tiempo basado en 30 casos similares de la DB |
| **Audit Trail** | Línea de tiempo de cada acción en el ticket |
| **Knowledge curation** | Sugerencias para convertir en KB |
| **Escalamiento N2** | Botón + paquete completo si aplica |

### Acciones disponibles:
- ✅ **Marcar resuelto N1** (con nota de resolución)
- 🚀 **Escalar a N2** (con paquete completo)
- 🔁 **Reanalizar** (forza re-enrichment IA)
- ✏️ **Editar campos** (con detector de cambios críticos)
- 📤 **Mirror a Jira** (si está integrado)
- 📃 **Generar respuesta al cliente**

---

## 6. Enrichment automático IA

**Qué es**: el agente IA analiza CADA ticket recién creado o editado en cambios críticos.

### Cuándo se dispara:
- Al crear ticket (auto)
- Al editar campos críticos (módulo, transacción, error code)
- Manualmente con botón "🔁 Reanalizar"

### Qué hace el pipeline:
1. Detecta contexto SAP (módulo, proceso, transacción)
2. Busca casos similares en KB (RAG con embeddings)
3. Consulta 8 especialistas IA por módulo
4. Consolida análisis con un orquestador
5. Genera: readiness, ETA, next action, paquete N1, recomendaciones
6. Persiste resultado al ticket
7. Audit trail completo

**Costo**: ~$0.001-0.005 USD por enrichment (depende del tamaño).

---

## 7. Generar respuesta al cliente

**Cuándo**: cuando vas a responder al cliente (por email/Jira/chat) y querés que el agente te arme la respuesta profesional.

### Pasos:
1. En el TCC → sección **"Customer Response"** → botón **"Generar respuesta"**
2. Modal con:
   - Tipo de respuesta (13 tipos): acuse de recibo, solicitud de info, propuesta de solución, resolución, escalamiento, cierre...
   - Audiencia (5 tipos): usuario final, tech lead, gerente, ejecutivo, soporte interno
   - Tone (formal/casual/técnico)
3. Click **"Generar"**
4. El agente IA crea borrador con **Quality Gate de 12 reglas**:
   - Tono adecuado a audiencia
   - Sin información sensible
   - Estructura clara
   - Próximos pasos explícitos
   - etc.
5. Si Quality Gate falla → genera versión "safe" automáticamente
6. **Preview** + edición manual si querés
7. Click **"Aprobar y publicar"** → mirror a Jira como comentario + envío opcional por email

---

## 8. Escalar a N2

**Cuándo**: cuando el ticket excede lo que N1 puede resolver.

### El sistema detecta automáticamente criterios de escalación:
- `no_playbook_available` — no hay procedimiento conocido
- `requires_code_change` — necesita modificar ABAP/customizing
- `requires_basis` — tema de infraestructura
- `requires_module_expert` — funcional especializado
- `data_inconsistency_critical` — corrupción/inconsistencia mayor
- `sla_at_risk` — tiempo crítico

### Pasos para escalar:
1. En TCC → botón **"🚀 Escalar a N2 con paquete completo"**
2. Modal con:
   - Criterio principal (auto-seleccionado por el sistema)
   - Razón del escalamiento (texto libre)
3. Click **"Confirmar escalamiento"**
4. El sistema arma el **paquete N2**:
   - Contexto SAP completo
   - Acciones N1 ya ejecutadas
   - Hipótesis descartadas
   - Datos SAP recolectados
   - Evidencia adjuntada
   - Recomendaciones de los especialistas
5. **Diff visual** con el ticket original (para que N2 vea qué cambió)
6. Mirror automático a Jira con tag `escalated_to_n2`

---

## 9. Cerrar ticket

### Pasos:
1. En TCC → botón **"✓ Cerrar ticket"** (rojo arriba)
2. Modal con:
   - Razón del cierre (resuelto, no reproducible, duplicado, won't fix, escalado a otro equipo)
   - Solución aplicada (texto)
   - Tiempo real invertido (horas) - se compara con la estimación IA
   - Convertir en KB? (sí/no) - si sí, se procesa para alimentar futuras IA
3. Auto-genera customer response de cierre
4. Audit event de cierre
5. Estado → `closed`

---

## 10. Cargar documento al Knowledge Base

### Pasos:
1. Sidebar → **Conocimiento** → **"+ Subir documento"**
2. Drag & drop o seleccionar:
   - PDF, DOCX, MD, TXT
   - Notas de Confluence/SharePoint
3. Llenar metadata:
   - Título
   - Módulo SAP (opcional)
   - Tags
   - Audiencia (consultor / usuario final)
4. Click **"Procesar"**
5. **Automático**: el sistema chunks + embeddings + index → en 1-2 min está disponible para el agente IA

**Usado en**: cada vez que el agente analiza un ticket nuevo, busca chunks relevantes acá.

---

## 11. Document Factory (generar reportes)

### Reportes disponibles:
- 📋 **RCA (Root Cause Analysis)** del ticket
- 📊 **Informe semanal** de tickets por módulo
- 🎯 **Plan de acción** post-incidente
- 📈 **Reporte ejecutivo** mensual
- 📜 **Acta de reunión** estructurada
- 🧪 **Plan de pruebas** para fix
- 📕 **Manual de usuario** específico

### Pasos:
1. Sidebar → **Document Factory** → seleccionar plantilla
2. Configurar inputs (ticket ID, fechas, etc.)
3. Click **"Generar"**
4. El sistema arma el documento con IA + datos reales
5. **Preview** + ediciones
6. Export: PDF, Word, Markdown

---

## 12. Reuniones AMS (transcripción + minuta)

### Para reunión nueva:
1. Sidebar → **Reuniones AMS** → **"+ Nueva reunión"**
2. Subir archivo de audio/video (MP3, M4A, MP4, WAV)
3. (Próximamente) o grabar directo del navegador
4. El sistema procesa con Whisper local:
   - Transcripción texto
   - Diarización (quién habló cuándo)
5. El agente IA genera **minuta estructurada**:
   - Asistentes
   - Temas tratados
   - Decisiones tomadas
   - Acciones (con responsable + fecha)
   - Próximos pasos
6. Export PDF / mail a participantes

---

## 13. Canal Telefónico

**Cuándo**: registrar tickets recibidos por teléfono.

### Pasos:
1. Sidebar → **Canal Telefónico** → **"+ Nueva llamada"**
2. (Opcional) Grabar la llamada → transcripción automática
3. El agente IA detecta:
   - Quién llamó
   - Qué reportó
   - Genera draft de ticket
4. Confirmá / editá el draft
5. Click **"Crear ticket desde llamada"**
6. El ticket queda con `source: "voice"` y attach del audio + transcript

---

## 14. Mission Control (dashboard ejecutivo)

### Sidebar → **Mission Control**

Pantalla full-screen con todos los KPIs en vivo:
- 🎯 Tickets abiertos / cerrados / SLA
- ⏱️ Tiempo promedio de resolución
- 💎 Valor económico generado (USD ahorrado)
- 🤖 Calls Gemini consumidos hoy
- 📊 Heatmap actividad 24/7
- 🚨 Alertas activas

**Pensada para**: TV en pantalla de la mesa de soporte / oficina.

---

## 15. Panel de Costos Gemini (admin)

### Sidebar → **Administración** → **💰 Costos Gemini**

**14 widgets** que muestran cuánto consume el agente IA:

| Widget | Qué muestra |
|---|---|
| 🩺 **Health Score** | 0-100 con 5 dimensiones |
| 🎯 **Recomendaciones IA** | Sugerencias accionables con priority |
| 🔥 **Burn rate** | Última hora vs previa + proyección |
| 🎟️ **Tokens** | Input/Output con % y costo |
| 📅 **vs Lunes pasado** | Comparativa día-vs-día |
| 4 tiles | Hoy / Semana / Mes / Total |
| 🔮 **Forecast** | Proyección fin de mes |
| 💸 **Ahorro potencial** | Si pasaras a flash-lite |
| 🚨 **Anomalías** | Días anómalos detectados |
| 🛡️ **Rate limiter** | 3 ventanas (min/hora/día) |
| 🔥 **Heatmap** | Horario 24h × 7d |
| 📈 **Daily chart** | 30 días con anomalías marcadas |
| 🤖 **Por modelo** | Flash vs flash-lite vs pro |
| 🎯 **Top sources** | Qué módulo consume más |
| 📊 **Distribución** | Histograma costo por call |

**Auto-refresh cada 30s. Export CSV.**

---

## 16. Panel de ROI (admin/aprobador)

### Sidebar → **Administración** → **📈 ROI del Agente**

Combina costos REALES de Gemini con valor económico estimado:

### Widgets:
- **ROI ratio**: "Por cada $1 USD de Gemini, generás $X USD de valor"
- **Ganancia neta mensual** (CLP)
- **Payback period** en días
- **Comparativa visual** Costo vs Valor (barras)
- **Configurador interactivo**: ajustá volumen mensual de tickets/RCAs/etc
- **Desglose por categoría** con horas ahorradas

**Ejemplo real del sistema:**
```
Costo Gemini este mes:  $1.59 USD
Valor generado:         $1,500-$6,000 USD (depende del volumen)
ROI:                    943×
Payback:                <1 día
```

---

## 17. Administración de Usuarios

### Sidebar → **Administración** (solo rol admin)

5 tabs:

| Tab | Para qué |
|---|---|
| **👥 Usuarios** | Crear/editar/desactivar usuarios + asignar rol |
| **🔑 Roles** | Ver/crear roles personalizados |
| **🔒 Matriz de permisos** | Configurar qué rol puede qué en cada pantalla |
| **👁️ Vista previa** | Simular sesión como otro rol para testear |
| **📜 Log de auditoría** | Ver TODOS los eventos del sistema (search + filter) |

---

## 🎯 Atajos de teclado útiles

| Atajo | Acción |
|---|---|
| `Ctrl + K` | Búsqueda global / command palette |
| `Ctrl + /` | Atajos disponibles |
| `Esc` | Cerrar modal activo |
| `Tab` | Navegar entre campos |

---

## 🆘 Cuándo pedir soporte

Contactá a soporte si:
- El agente IA NO enriquece un ticket después de 30 segundos
- Errores rojos persistentes en pantalla
- No podés loguear con credenciales correctas
- Algún panel queda en blanco infinito

**Email**: soporte@tuempresa.cl
**WhatsApp** (plan premium): +56 9 XXXX XXXX

---

## ❓ FAQs

**P: ¿Qué hago si el agente IA recomienda algo y NO estoy de acuerdo?**
R: Las recomendaciones son sugerencias. Vos sos quien decide. El sistema audita tu decisión y aprende.

**P: ¿Los datos de mi cliente se entrenan en el modelo Gemini?**
R: No. Configurado para que Gemini NO use tus prompts para entrenamiento.

**P: ¿Qué pasa si excedo mi budget de Gemini?**
R: El sistema te bloquea las calls automáticamente (rate limiter local + budget cap Google). No hay sorpresas en factura.

**P: ¿Puedo exportar todos mis datos si decido cancelar?**
R: Sí. En cualquier momento podés pedir export JSON. Lo entregamos en 30 días post-cancelación. Después de 90 días eliminamos definitivamente.
