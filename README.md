# supply-chain-ams-stack

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Active-success)]()
[![Docker Compose](https://img.shields.io/badge/Docker_Compose-2.20+-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![13 containers](https://img.shields.io/badge/Containers-13-2496ED)]()
[![Made with Claude Code](https://img.shields.io/badge/Made_with-Claude_Code-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code)

> **Orquestador único** para levantar `supply-chain-ams-agent` + `supply-chain-ams-platform` con un solo `docker compose up`, sin tocar los compose individuales de cada proyecto.
>
> Usa la directiva `include:` de Compose 2.20+ para mantener los proyectos aislados pero con ciclo de vida unificado.

## 🧭 Repos relacionados

| Repo | Rol |
|---|---|
| [`supply-chain-ams-agent`](https://github.com/vladyrap/supply-chain-ams-agent) | Backend Fastify + LLM + DB + workers + Twilio Voice |
| [`supply-chain-ams-platform`](https://github.com/vladyrap/supply-chain-ams-platform) | UI Next.js — 23 módulos, war-room 3D, Jaimito, voz |
| [`supply-chain-ams-stack`](https://github.com/vladyrap/supply-chain-ams-stack) **← estás aquí** | Orquestador `include:` para levantar todo junto |

## 🚀 Quickstart

Los 3 repos como hermanos en el mismo parent directory:

```bash
git clone https://github.com/vladyrap/supply-chain-ams-agent
git clone https://github.com/vladyrap/supply-chain-ams-platform
git clone https://github.com/vladyrap/supply-chain-ams-stack
cd supply-chain-ams-stack
# Editar ../supply-chain-ams-agent/.env con tu GEMINI_API_KEY
docker compose up -d
docker compose ps     # ve los 13 contenedores
```

UI en http://localhost:6700.

## 📁 Estructura

```
parent/
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
