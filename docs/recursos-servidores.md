# Recursos de Servidores

Inventario de hardware y uso de recursos por entorno. Referencia para dimensionar
configuraciones de workers, pools, cache y limites.

> Ultima actualizacion: 2026-05-06

## GCP — Staging (1 servidor)

Todos los servicios corren en una sola VM.

| Recurso | Valor |
|---------|-------|
| Hostname | GCP VM (staging) |
| CPU | 2 cores |
| RAM | 7.8 GB |
| Disco | 145 GB (58% usado) |
| Swap | No configurado |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.17.0-1010-gcp |

### Uso de memoria por contenedor

| Contenedor | RAM | % del total | Notas |
|------------|-----|-------------|-------|
| geoserver | 2.6 GB | 33.8% | Mayor consumidor |
| dataengine-primary | 422 MB | 5.3% | PostgreSQL + PostGIS |
| mapalab-backend-1 | 234 MB | 2.9% | Gunicorn + Uvicorn |
| prometheus | 157 MB | 15.4% | Limitado a 1 GB |
| acervo-minio | 117 MB | 1.5% | MinIO S3 |
| grafana | 112 MB | 21.8% | Limitado a 512 MB |
| cadvisor | 127 MB | 49.6% | Limitado a 256 MB |
| loki | 67 MB | 6.5% | Limitado a 1 GB |
| promtail | 22 MB | 0.3% | Logs a Loki |
| alertmanager | 21 MB | 0.3% | Alertas |
| gateway-hub-nginx-1 | 13 MB | 0.2% | Proxy central |
| node-exporter | 15 MB | 11.7% | Limitado a 128 MB |
| alertmanager-discord | 13 MB | 4.9% | Limitado a 256 MB |
| nginx-exporter | 10 MB | 0.1% | Metricas Nginx |
| mapalab-nginx-1 | 3 MB | 0.04% | Proxy interno |
| nginx-auth | 2 MB | 1.8% | Limitado a 128 MB |
| **Total estimado** | **~4.1 GB** | **~53%** | |

### Configuracion recomendada para GCP (2 cores)

| Componente | Valor recomendado | Justificacion |
|-----------|-------------------|---------------|
| Gunicorn workers | 4 | 2 × cores = 4 (async workers) |
| DB pool por worker | 4 + 4 overflow | Pool conservador para no saturar PostgreSQL local |
| Total conexiones DB | 4 × 8 = 32 | Dentro de max_connections=200 |
| PostgreSQL max_connections | 200 | Suficiente para todos los servicios locales |

---

## Produccion — 4 Servidores

### S1: Gateway + Huachicol + Acervo

| Recurso | Valor |
|---------|-------|
| Hostname | S1 (Gateway) |
| CPU | 8 cores |
| RAM | 15 GB |
| Disco | 637 GB (4% usado) |
| Swap | 3.7 GB (102 MB usados) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-100-generic |

**Servicios:**

| Contenedor | RAM | % del total |
|------------|-----|-------------|
| prometheus | 156 MB | 15.2% (limit 1 GB) |
| cadvisor | 88 MB | 34.3% (limit 256 MB) |
| grafana | 80 MB | 15.6% (limit 512 MB) |
| acervo-minio | 70 MB | 0.4% |
| loki | 38 MB | 3.7% (limit 1 GB) |
| promtail | 26 MB | 0.2% |
| gateway-hub-nginx-1 | 20 MB | 0.1% |
| alertmanager | 17 MB | 0.1% |
| alertmanager-discord | 13 MB | 5.2% (limit 256 MB) |
| node-exporter | 8 MB | 6.3% (limit 128 MB) |
| nginx-exporter | 6 MB | 0.04% |
| nginx-auth | 3 MB | 2.4% (limit 128 MB) |
| **Total estimado** | **~525 MB** | **~3.4%** |

**Nota:** Este servidor tiene mucho margen (15 GB RAM, solo 525 MB en uso). Gateway Hub y el stack
de monitoreo consumen muy poco.

### S2: MapaLab

| Recurso | Valor |
|---------|-------|
| Hostname | S2 (MapaLab) |
| CPU | 8 cores |
| RAM | 15 GB |
| Disco | 96 GB (24% usado) |
| Swap | 3.7 GB (106 MB usados) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-100-generic |

**Servicios:**

| Contenedor | RAM | % del total |
|------------|-----|-------------|
| mapalab-backend-1 | 573 MB | 3.6% |
| mapalab-nginx-1 | 14 MB | 0.09% |
| **Total estimado** | **~587 MB** | **~3.7%** |

**Nota:** Server con amplio margen. Con 8 workers de Gunicorn (~70 MB cada uno = ~560 MB total),
el uso estimado se mantiene en ~600 MB — aun muy holgado con 15 GB disponibles.

### S3: GeoServer

| Recurso | Valor |
|---------|-------|
| Hostname | S3 (GeoServer) |
| CPU | 8 cores |
| RAM | 15 GB |
| Disco | 490 GB (12% usado) |
| Swap | 3.7 GB (471 MB usados) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-100-generic |

**Servicios:**

| Contenedor | RAM | % del total |
|------------|-----|-------------|
| geoserver | 1.4 GB | 8.8% |
| **Total estimado** | **~1.4 GB** | **~8.8%** |

**Nota:** En GCP, GeoServer consume 2.6 GB (con cache lleno). En produccion con su propio servidor
de 15 GB tiene margen para crecer. El mayor uso de swap (471 MB) sugiere picos de carga ocasionales.

### S4: DataEngine

| Recurso | Valor |
|---------|-------|
| Hostname | S4 (DataEngine) |
| CPU | 4 cores |
| RAM | 7.7 GB |
| Disco | 490 GB (14% usado) |
| Swap | 4 GB (1.5 GB usados) |
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.8.0-100-generic |
| PostgreSQL max_connections | 200 |

**Servicios:**

| Contenedor | RAM | % del total |
|------------|-----|-------------|
| dataengine-primary | 620 MB | 7.9% |
| cadvisor | 50 MB | 0.6% |
| dataengine-mapalab-card | 3 MB | 0.04% |
| node-exporter | ~1 MB | 0.01% |
| postgres-exporter | ~1 MB | 0.01% |
| dataengine-backup | ~1 MB | 0.01% |
| **Total estimado** | **~676 MB** | **~8.6%** |

**Nota:** PostgreSQL consume 620 MB con `shared_buffers=256MB` y `effective_cache_size=768MB`.
El uso de swap (1.5 GB de 4 GB) indica que PostgreSQL esta usando mas memoria de la visible
en el contenedor (buffer/page cache del OS). Con `max_connections=200` y 128 conexiones
potenciales de MapaLab, tiene margen de 72 conexiones para otros servicios (GeoServer, backups, etc.).

---

## Configuracion final por entorno

### Produccion (8 cores en MapaLab)

| Componente | Valor |
|-----------|-------|
| Gunicorn workers | 8 |
| DB pool por worker | 8 + 8 overflow = 16 |
| Total conexiones DB max | 128 |
| Nginx workers (MapaLab) | auto (= 4) |
| Nginx worker_connections (MapaLab) | 2048 |
| Nginx keepalive al backend | 32 |
| Gateway rate limit (mapalab/) | general 10r/s burst 150 |
| Gateway rate limit (mapalab/assets/) | static 50r/s burst 200 |
| Gateway cache mapalab_assets | 500 MB, 7 dias |
| PostgreSQL max_connections | 200 |

### GCP Staging (2 cores, todo en 1 VM)

| Componente | Valor recomendado | Valor actual |
|-----------|-------------------|--------------|
| Gunicorn workers | 4 | 4 (via GUNICORN_WORKERS en .env.staging) |
| DB pool por worker | 4 + 4 overflow = 8 | 4 + 4 = 8 (via DB_POOL_SIZE en .env.staging) |
| Total conexiones DB max | 32 | 32 |
| PostgreSQL max_connections | 200 | 200 |

Workers y pool son configurables via variables de entorno (`GUNICORN_WORKERS`, `DB_POOL_SIZE`,
`DB_MAX_OVERFLOW`) en los archivos `.env.staging` y `.env.production` de MapaLab.

---

## Resumen visual

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PRODUCCION (4 servidores)                       │
│                                                                     │
│  S1: Gateway+Huachicol+Acervo    S2: MapaLab                       │
│  ┌───────────────────────────┐   ┌───────────────────────────┐     │
│  │ 8 cores  ·  15 GB RAM    │   │ 8 cores  ·  15 GB RAM    │     │
│  │ 637 GB disco             │   │ 96 GB disco              │     │
│  │ Uso: ~525 MB (3.4%)      │   │ Uso: ~587 MB (3.7%)      │     │
│  └───────────────────────────┘   └───────────────────────────┘     │
│                                                                     │
│  S3: GeoServer                   S4: DataEngine                     │
│  ┌───────────────────────────┐   ┌───────────────────────────┐     │
│  │ 8 cores  ·  15 GB RAM    │   │ 4 cores  ·  7.7 GB RAM   │     │
│  │ 490 GB disco             │   │ 490 GB disco              │     │
│  │ Uso: ~1.4 GB (8.8%)      │   │ Uso: ~676 MB (8.6%)      │     │
│  └───────────────────────────┘   └───────────────────────────┘     │
│                                                                     │
│              Total: 28 cores  ·  53 GB RAM  ·  1.7 TB disco        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     GCP STAGING (1 servidor)                        │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ 2 cores  ·  7.8 GB RAM  ·  145 GB disco  ·  Sin swap        │ │
│  │ Todos los servicios  ·  Uso: ~4.1 GB (53%)                  │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```
