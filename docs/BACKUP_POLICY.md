# Política de Respaldos · AMS Platform

Versión: 1.0 · Fecha: 2026-06-10 · Owner: Vladimir Matta

---

## 🎯 Objetivo

Garantizar que **ningún incidente del VPS, DB, infraestructura o error humano** cause pérdida de datos críticos. Cumplir con SLA implícito hacia clientes AMS (datos corporativos SAP bajo NDA).

## 📐 Estrategia 3-2-1

> **3** copias de los datos · **2** medios distintos · **1** offsite.

| Capa | Copia | Medio | Ubicación | Retención |
|---|---|---|---|---|
| 1 (live) | DB Postgres activa | NVMe SSD del VPS | Arsys (España) | continua |
| 2 (local) | pg_dump cifrado diario | NVMe SSD del VPS | `/opt/ams/backups/` | 7 días |
| 3 (offsite) | Mismo dump replicado | Cold storage cloud | Backblaze B2 (US-East) | 30 días |

---

## ⏱ Métricas objetivo

| Métrica | Valor | Justificación |
|---|---|---|
| **RPO** (Recovery Point Objective) | **24 horas** | Backup diario a 03:00 UTC. Datos posteriores se reconstruyen del cliente |
| **RTO** (Recovery Time Objective) | **1 hora** | Tiempo total: detectar incidente → restore + smoke |
| **Frecuencia backup full** | diario | 03:00 UTC (medianoche Chile) |
| **Frecuencia restore test** | mensual | Primer lunes de cada mes |

---

## 🔄 Flujo del backup automático

```
03:00 UTC  cron en container ams-backup
   ↓
   pg_dump db ams_prod | gzip -9
   ↓
   openssl enc -aes-256-cbc -salt -pbkdf2 -pass env:BACKUP_PASSPHRASE
   ↓
   Archivo local: /opt/ams/backups/ams-{TS}.sql.gz.enc
   ↓
   rclone copy → b2:ams-prod-backups/ams/
   ↓
   Cleanup local > 7 días + remoto > 30 días
   ↓
   Healthcheck endpoint /api/backup/last
```

---

## 🔐 Cifrado

| Capa | Cifrado |
|---|---|
| **At rest local** | LUKS del VPS (si Arsys lo aplica) |
| **Backup file** | AES-256-CBC + PBKDF2 (100k iter) con `BACKUP_PASSPHRASE` |
| **In transit (B2)** | TLS 1.2+ |
| **At rest B2** | Server-side encryption con KMS de Backblaze |

> ⚠️ Si pierdes la `BACKUP_PASSPHRASE`, los backups **NO se pueden descifrar**. Guardarla en password manager + 1 copia offline (papel en caja fuerte / vault físico).

---

## 🧪 Restore test mensual

Cada primer lunes de mes, ejecutar:
```bash
bash scripts/restore-test.sh
```

Lo que hace:
1. Pulls el último backup de B2
2. Levanta DB temporal en network aislada
3. Restaura el dump
4. Verifica integridad: tabla `users`, conteo tickets, audit_events
5. Compara checksums con DB live
6. Reporta éxito/fallo en `/var/log/restore-tests.log`

> Si el test falla 2 meses consecutivos, **bloquear nuevos deploys hasta resolver**.

---

## 🚨 Plan de incidentes

### Escenario A · DB corrupta

```
1. Detectar (alertmanager o monitoreo manual)
2. Notificar clientes (status page)
3. Tomar último backup OK de /opt/ams/backups/
4. bash scripts/rollback.sh <último-tag-prod>
5. Validar smoke test
6. Comunicar restauración
RTO objetivo: 30 min
```

### Escenario B · VPS completo destruido (Arsys down)

```
1. Provisionar VPS nuevo (Contabo, Hetzner, otro)
2. Bootstrap: bash scripts/bootstrap-vps.sh
3. Pull último backup de B2 (rclone)
4. Restore DB: gunzip + openssl + psql
5. Levantar stack con tag -prod más reciente
6. Cambiar DNS roccoai.cl al nuevo VPS
7. Validar
RTO objetivo: 4 horas
```

### Escenario C · Backup propio comprometido (passphrase leak)

```
1. Rotar BACKUP_PASSPHRASE inmediatamente
2. Generar backup nuevo con passphrase nueva
3. Borrar backups antiguos del B2 (mantener 1 último por compliance)
4. Documentar incidente en audit_events
RTO: 1 hora
```

---

## 📋 Checklist mensual

- [ ] Backup automático corrió cada noche del mes (revisar log)
- [ ] Tamaño de backup en rango esperado (alerta si <50% del promedio)
- [ ] Sync a B2 OK (lista contenido del bucket)
- [ ] Restore test mensual ejecutado y exitoso
- [ ] Espacio disponible en VPS y B2 (alerta si <20% libre)
- [ ] Verificar passphrase en password manager (rotación cada 6 meses)

---

## 🔗 Recursos

| Recurso | Path |
|---|---|
| Script backup | `/opt/ams/supply-chain-ams-stack/scripts/backup-db.sh` |
| Script rollback | `/opt/ams/supply-chain-ams-stack/scripts/rollback.sh` |
| Logs | `docker logs ams-backup` |
| Backups locales | `/opt/ams/backups/*.sql.gz.enc` |
| Backups remotos | `b2:ams-prod-backups/ams/` |
| Passphrase | password manager `ams-backup-passphrase` |
| Token B2 | password manager `b2-ams-prod-app-key` |

---

## 📚 Referencias

- **Calmar (referencia comparativa)** — uso similar política: `/opt/Agendamiento/backup/`
- **Migración 005** (multi-tenant) — schema base que debe restaurarse íntegro
- **CHECKLIST_PROD.md** — pre-flight antes de cada deploy
