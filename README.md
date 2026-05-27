# supply-chain-ams-stack

> Orquestador único para levantar **agent + platform** con un solo comando, sin tocar los compose individuales de cada proyecto.

## Estructura

```
Desktop/
├── supply-chain-ams-agent/         backend + worker + Whisper + DB + observability
├── supply-chain-ams-platform/      Next.js UI multi-módulo con voz
└── supply-chain-ams-stack/         ← este (solo docker-compose.yml + README)
```

## Levantar todo

```bash
cd "/c/Users/VMATTA/Desktop/supply-chain-ams-stack"
docker compose up -d
docker compose ps
```

Se levantan **13 contenedores**:

| Container | Puerto host |
|---|---|
| supply-chain-ams-frontend (NextJS original del agent) | 6600 |
| supply-chain-ams-backend (Fastify API) | 6601 |
| supply-chain-ams-db (Postgres + pgvector) | 6602 |
| supply-chain-ams-redis | 6603 |
| supply-chain-ams-kibana | 6604 |
| supply-chain-ams-grafana | 6605 |
| supply-chain-ams-prometheus | 6609 |
| supply-chain-ams-logstash | 6610 |
| supply-chain-ams-whisper (ASR local) | 6611 |
| supply-chain-ams-elasticsearch | 6620 |
| supply-chain-ams-platform (UI SaaS) | **6700** |
| supply-chain-ams-worker (BullMQ) | — |

## Comandos útiles

```bash
# Logs en vivo de un servicio
docker compose logs -f backend
docker compose logs -f worker
docker compose logs -f whisper

# Rebuild de uno
docker compose up -d --build --force-recreate backend

# Detener todo (volúmenes se conservan)
docker compose down

# Detener y limpiar todo (PERDÉS LOS DATOS)
docker compose down -v
```

## Si necesitás un proyecto aislado

Los compose individuales siguen funcionando:

```bash
# solo el agent
docker compose -f /c/Users/VMATTA/Desktop/supply-chain-ams-agent/docker-compose.yml up -d

# solo la plataforma
docker compose -f /c/Users/VMATTA/Desktop/supply-chain-ams-platform/docker-compose.yml up -d
```

## Requisito de versión

Docker Compose **2.20+** (para la directiva `include:`). Verificar:

```bash
docker compose version
```

Si tu versión es anterior y no podés actualizar, podés caer al método manual: levantar agent y platform por separado.
