# Perfiles de tuning multientorno — ecosistema IIEG

> **Estado:** propuesta, no implementada. Documento de diseno para sostener la
> configuracion de recursos (heap JVM, shared_buffers, maxmemory, workers,
> pools, retention, cache sizes, etc.) a traves de tres entornos con hardware
> distinto y diez repos del ecosistema.
>
> **Autor de la evaluacion:** sesion 2026-05-22.
> **Disparador:** boost temporal de la VM GCP de `e2-standard-2` (2c/8GB) a
> `e2-standard-8` (8c/32GB) en `mapalab` (us-central1-c). El boost expuso que
> ningun repo (excepto parcialmente `mariachi` y `mapalab`) tiene mecanismo
> formal para cambiar de perfil sin editar a mano.

---

## 1. Problema

Tres entornos con hardware muy distinto consumen los mismos repos pero
necesitan distinto tuning. Hoy no hay forma sistematica de cambiar de un
perfil a otro:

- En 7 de 10 repos el tuning vive mezclado con secrets en un solo `.env`.
- 2 repos (`mariachi`, `mapalab`) tienen `.env.{dev,staging,prod}` pero sin
  perfil de "boost" para GCP escalado temporalmente.
- 1 repo (`sieej`) es frontend estatico y no requiere tuning.
- Multiples componentes criticos no tienen variables expuestas para tunear
  (nginx workers en todos los repos, CKAN Gunicorn, Solr JVM, SeaweedFS
  master/volume, Authentik workers, etc.).

Sintomas concretos:

- **Drift silencioso**: cuando se desescala el boost, los `.env` pueden quedarse
  con valores que asfixian a la VM normal (ej. `INITIAL_MEMORY=4G` sobre 8 GB
  compartidos).
- **Mezcla secrets/tuning**: cualquier ajuste de heap mueve el mismo archivo
  que tiene `POSTGRES_PASSWORD` — friccion en diff/commit y riesgo de leaks.
- **Componentes sin perilla**: aunque haya doc, no hay forma de aplicar el
  valor recomendado sin tocar el Dockerfile o el `nginx.conf` interno.
- **Sin source-of-truth operativo**: la matriz en
  [recursos-servidores.md](../recursos-servidores.md) tiene los numeros
  correctos pero no esta conectada a los archivos que el compose efectivamente
  lee.

---

## 2. Inventario de entornos

| Entorno | Maquinas | Recursos | Caracteristica |
|---|---|---|---|
| **workstation** | `hpsota` y similares | 20c / 30 GB | Todo corre junto, dev local. Sin red administracion. |
| **gcp-staging** | `mapalab` (us-central1-c) | 2c / 8 GB | VM compartida, todo el ecosistema en una sola maquina. |
| **gcp-boost** | `mapalab` (us-central1-c) | 8c / 32 GB | Temporal — escalado manual para pruebas de carga o demos. |
| **admin** | 4 servidores S1-S4 | S1: 8c/15GB · S2: 8c/15GB · S3: 8c/15GB · S4: 4c/7.7GB | Cada servicio en su servidor dedicado. |

La asimetria clave es **co-tenencia**: en GCP todo corre junto, en admin esta
separado. Esto cambia el reparto de RAM por componente, no es solo "mas RAM
en prod".

### Reparto de RAM por entorno (resumen)

```
GCP STAGING (8 GB total, todo junto)
SO+kernel:    ~1 GB
GeoServer:    ~2 GB  ████████
DataEngine:   ~512 MB  ██
Mariachi PG:  ~128 MB  ▌
Mariachi API: ~250 MB × 4 workers = ~1 GB  ████
Mapalab API:  ~250 MB × 4 workers = ~1 GB  ████
Huachicol:    ~600 MB (todos monitoreo)  ███
Acervo:       ~120 MB  ▌
Gateway:      ~20 MB
Buffer/cache: ~1.5 GB

GCP BOOST (32 GB total, todo junto)
SO+kernel:    ~2 GB
GeoServer:    ~19 GB (heap 16G + off-heap)  ████████████████████████
DataEngine:   ~7 GB (sb 3G + cache 4G)  ████████
Mariachi PG:  ~2 GB  ██
Mariachi API: ~2 GB (8 workers)  ██
Redis:        ~512 MB  ▌
Otros:        ~1.5 GB
Margen:       ~2 GB

ADMIN (separado, total 53 GB en 4 servers)
S1 Gateway+Mariachi  (8c/15GB):  ~2 GB  ██
S2 Mapalab           (8c/15GB):  ~600 MB  ▌
S3 GeoServer         (8c/15GB):  ~9 GB (heap 8G dedicado)  ████████████
S4 DataEngine        (4c/7.7GB): ~7 GB (sb 2G + cache 5.5G)  ████████
```

---

## 3. Inventario del ecosistema y estado actual de tuning

Diez repos. Esfuerzo de migracion a perfiles segun lo que ya esta expuesto.

| Repo | Servicios criticos | Vars hoy | Vars necesarias | Complejidad |
|---|---|---|---|---|
| `geoserver` | kartoza/geoserver | `INITIAL_MEMORY`, `MAXIMUM_MEMORY`, `ADDITIONAL_JAVA_STARTUP_OPTIONS` | ya estan todas | **A — trivial** |
| `dataengine` | postgis 18 + pgbouncer | `MAX_CONNECTIONS`, `SHARED_BUFFERS`, `EFFECTIVE_CACHE_SIZE` | + `work_mem`, `maintenance_work_mem`, `parallel_workers`, `random_page_cost`, `io_concurrency` | **B — extender command** |
| `mariachi` | postgres 18 + redis 7 + FastAPI | `GUNICORN_WORKERS`, `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `POSTGRES_*` (3 vars) | + `REDIS_MAXMEMORY`, `POSTGRES_WORK_MEM`, etc. | **B — extender command + comando redis** |
| `mapalab` | nginx + FastAPI + MCP | `GUNICORN_WORKERS`, `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `MCP_*` | + `NGINX_WORKER_PROCESSES`, `NGINX_WORKER_CONNECTIONS` | **C — nginx.conf con envsubst** |
| `gateway-hub` | nginx (proxy central) + nginx-exporter | (ninguna de tuning) | `NGINX_WORKER_PROCESSES`, `NGINX_WORKER_CONNECTIONS`, `KEEPALIVE_CONNECTIONS`, `PROXY_CACHE_*` | **C — nginx.conf con envsubst** |
| `huachicol` | prometheus + grafana + loki + alloy + cadvisor + alertmanager + node-exporter | `mem_limit` / `cpus` por servicio (hardcoded en compose) | mover limits a `.env`; exponer `PROMETHEUS_RETENTION`, `LOKI_RETENTION` | **B — limits via env + command flags** |
| `acervo` | seaweedfs + version-api | (ninguna de tuning) | `SEAWEEDFS_VOLUME_MAX`, `SEAWEEDFS_MASTER_MEM`, `SEAWEEDFS_VOLUME_MEM` | **B — flags al command de seaweed** |
| `sitio2026` | nginx + postgres 18 + redis 8 + ckan-db + ckan-solr + ckan + FastAPI | (ninguna de tuning) | `POSTGRES_*`, `REDIS_MAXMEMORY`, `CKAN_GUNICORN_WORKERS`, `SOLR_HEAP_SIZE`, nginx workers | **D — varios componentes sin envs nativos** |
| `minerva` | postgres 18 + redis 8 + authentik server + authentik worker | (ninguna de tuning) | `POSTGRES_*`, `REDIS_MAXMEMORY`, `AUTHENTIK_WORKERS`, posibles vars Authentik | **C — Authentik tiene env vars propias** |
| `sieej` | vite frontend (build estatico) | `VITE_PORT`, `FRONTEND_PORT` | ninguna (frontend estatico) | **A — sin tuning** |

Leyenda complejidad:
- **A**: ya esta listo, solo separar archivos.
- **B**: ya hay imagen tuneable; falta exponer flags en `command:` + `.env`.
- **C**: requiere convertir un archivo de config interno a template procesado
  con `envsubst` o `gomplate` al arranque, o usar imagenes que ya soportan
  templating.
- **D**: requiere combinaciones de B+C, mas variables propias de la app
  (Solr JVM, CKAN ini).

---

## 4. Propuesta — patron "tuning como capa, no como entorno"

### 4.1. Estructura por repo

```
<repo>/
├── .env                       # secrets, hosts, DBs (igual en todos lados)
├── tuning/
│   ├── README.md              # explica que perfil corresponde a que maquina
│   ├── workstation.env        # local 20c/30GB
│   ├── gcp-staging.env        # GCP normal 2c/8GB
│   ├── gcp-boost.env          # GCP escalado 8c/32GB (temporal)
│   └── admin.env              # servidor dedicado correspondiente al repo
└── Makefile                   # `make up PROFILE=gcp-boost` o auto-detect
```

Docker Compose v2 admite multiples `--env-file`; los posteriores ganan. El
`tuning/<perfil>.env` se carga **despues** del `.env` base y solo sobrescribe
variables de recursos.

### 4.2. Seleccion de perfil (3 fuentes, en orden)

1. **Flag explicito**: `make up PROFILE=gcp-boost` — siempre gana.
2. **Variable de host**: `IIEG_PROFILE=admin` en `~/.bashrc` de cada maquina.
3. **Auto-deteccion**: `scripts/detect-profile.sh` resuelve por:
   - Metadata GCP (`curl metadata.google.internal`) → `gcp-staging` o
     `gcp-boost` (segun `machine-type`).
   - Hostname conocido (S1-S4) → `admin`.
   - Fallback → `workstation`.

### 4.3. Makefile (snippet generico)

```makefile
PROFILE ?= $(shell ../gateway-hub/scripts/detect-profile.sh 2>/dev/null || echo workstation)
COMPOSE = docker compose --env-file .env --env-file tuning/$(PROFILE).env

up:
	@echo "Perfil de tuning: $(PROFILE)"
	$(COMPOSE) up -d

tuning-show:
	@echo "=== tuning/$(PROFILE).env ==="
	@cat tuning/$(PROFILE).env

tuning-list:
	@ls tuning/*.env | sed 's|tuning/||; s|.env||'
```

`detect-profile.sh` vive una sola vez en `gateway-hub/scripts/` y los otros
repos lo invocan via path relativo o symlink.

### 4.4. Templating de archivos de config (complejidad C)

Para servicios cuyos parametros NO son envs sino archivos de config (nginx,
ckan, prometheus.yml), el patron es:

```
service/
├── conf/
│   ├── nginx.conf.template     # con ${VAR}
│   └── prometheus.yml.template
└── entrypoint.sh               # envsubst < template > config && exec
```

`docker-compose.yml` monta el directorio y el `entrypoint.sh` corre `envsubst`
al arranque. Variables en `tuning/<perfil>.env`.

Alternativa: imagenes oficiales que ya soportan templates (`nginx:1.27` con
`/etc/nginx/templates/*.template` activa envsubst nativamente — usar eso donde
sea posible).

---

## 5. Tablas de valores por repo y perfil

> Todas las tablas son **propuestas iniciales** derivadas de
> `recursos-servidores.md` y consumos observados. Se calibran tras el primer
> ciclo de uso real.

### 5.1. `geoserver`

| Variable | workstation | gcp-staging | gcp-boost | admin (S3) |
|---|---|---|---|---|
| `INITIAL_MEMORY` | `2G` | `1G` | `4G` | `2G` |
| `MAXIMUM_MEMORY` | `8G` | `2G` | `16G` | `8G` |
| `ADDITIONAL_JAVA_STARTUP_OPTIONS` | `-XX:MaxMetaspaceSize=1g` | `-XX:MaxMetaspaceSize=512m` | `-XX:MaxMetaspaceSize=1g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseStringDeduplication` | `-XX:MaxMetaspaceSize=1g` |

### 5.2. `dataengine`

| Variable | workstation | gcp-staging | gcp-boost | admin (S4) |
|---|---|---|---|---|
| `POSTGRES_MAX_CONNECTIONS` | 200 | 100 | 200 | 200 |
| `POSTGRES_SHARED_BUFFERS` | `2GB` | `256MB` | `3GB` | `2GB` |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `8GB` | `768MB` | `8GB` | `5632MB` |
| `POSTGRES_WORK_MEM` (nuevo) | `16MB` | `4MB` | `16MB` | `8MB` |
| `POSTGRES_MAINTENANCE_WORK_MEM` (nuevo) | `512MB` | `64MB` | `512MB` | `256MB` |
| `POSTGRES_MAX_WORKER_PROCESSES` (nuevo) | 16 | 2 | 8 | 4 |
| `POSTGRES_MAX_PARALLEL_WORKERS` (nuevo) | 12 | 2 | 6 | 4 |
| `POSTGRES_MAX_PARALLEL_WORKERS_PER_GATHER` (nuevo) | 4 | 1 | 3 | 2 |
| `POSTGRES_RANDOM_PAGE_COST` (nuevo) | 1.1 | 1.1 | 1.1 | 1.1 |
| `POSTGRES_EFFECTIVE_IO_CONCURRENCY` (nuevo) | 200 | 200 | 200 | 200 |

### 5.3. `mariachi`

| Variable | workstation | gcp-staging | gcp-boost | admin (S1) |
|---|---|---|---|---|
| `GUNICORN_WORKERS` | 8 | 4 | 8 | 8 |
| `DB_POOL_SIZE` | 8 | 4 | 8 | 5 (default SQLAlchemy) |
| `DB_MAX_OVERFLOW` | 8 | 4 | 8 | 10 (default SQLAlchemy) |
| `POSTGRES_MAX_CONNECTIONS` | 200 | 100 | 200 | 200 |
| `POSTGRES_SHARED_BUFFERS` | `512MB` | `128MB` | `1GB` | `512MB` |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `2GB` | `512MB` | `3GB` | `2GB` |
| `POSTGRES_WORK_MEM` (nuevo) | `8MB` | `4MB` | `8MB` | `8MB` |
| `POSTGRES_MAINTENANCE_WORK_MEM` (nuevo) | `256MB` | `64MB` | `256MB` | `128MB` |
| `REDIS_MAXMEMORY` (nuevo) | `512mb` | `256mb` | `512mb` | `512mb` |

### 5.4. `mapalab`

| Variable | workstation | gcp-staging | gcp-boost | admin (S2) |
|---|---|---|---|---|
| `GUNICORN_WORKERS` | 8 | 4 | 8 | 8 |
| `DB_POOL_SIZE` | 8 | 4 | 8 | 8 |
| `DB_MAX_OVERFLOW` | 8 | 4 | 8 | 8 |
| `MCP_WORKERS` | 4 | 2 | 4 | 4 |
| `MCP_DB_POOL_SIZE` | 4 | 2 | 4 | 4 |
| `NGINX_WORKER_PROCESSES` (nuevo) | `auto` | 2 | `auto` | `auto` |
| `NGINX_WORKER_CONNECTIONS` (nuevo) | 2048 | 1024 | 2048 | 2048 |

### 5.5. `gateway-hub`

| Variable | workstation | gcp-staging | gcp-boost | admin (S1) |
|---|---|---|---|---|
| `NGINX_WORKER_PROCESSES` (nuevo) | `auto` | 2 | `auto` | `auto` |
| `NGINX_WORKER_CONNECTIONS` (nuevo) | 2048 | 1024 | 2048 | 2048 |
| `KEEPALIVE_CONNECTIONS` (nuevo) | 32 | 16 | 32 | 32 |
| `PROXY_CACHE_MAX_SIZE_MAPALAB` (nuevo) | `1g` | `500m` | `1g` | `500m` |
| `RATE_LIMIT_GENERAL` (nuevo, opcional) | `10r/s burst=150` | `5r/s burst=50` | `10r/s burst=150` | `10r/s burst=150` |

### 5.6. `huachicol`

Hoy los limits viven hardcoded en `deploy.resources.limits.memory` y `cpus`.
Pasar a env vars:

| Servicio | workstation | gcp-staging | gcp-boost | admin |
|---|---|---|---|---|
| `PROMETHEUS_MEM_LIMIT` | `2G` | `1G` | `2G` | `1G` |
| `PROMETHEUS_RETENTION` | `90d` | `30d` | `30d` | `90d` |
| `GRAFANA_MEM_LIMIT` | `1G` | `512M` | `1G` | `512M` |
| `LOKI_MEM_LIMIT` | `2G` | `1G` | `2G` | `1G` |
| `LOKI_RETENTION_PERIOD` | `744h` (31d) | `168h` (7d) | `168h` | `744h` |
| `ALLOY_MEM_LIMIT` | `512M` | `256M` | `512M` | `256M` |
| `CADVISOR_MEM_LIMIT` | `512M` | `256M` | `512M` | `512M` |
| `NODE_EXPORTER_MEM_LIMIT` | `128M` | `128M` | `128M` | `128M` |
| `ALERTMANAGER_MEM_LIMIT` | `256M` | `128M` | `256M` | `256M` |

### 5.7. `acervo`

| Variable | workstation | gcp-staging | gcp-boost | admin (S1) |
|---|---|---|---|---|
| `SEAWEEDFS_VOLUME_MAX` (nuevo) | 100 | 30 | 100 | 100 |
| `SEAWEEDFS_MASTER_MEM_LIMIT` (nuevo) | `512M` | `256M` | `512M` | `256M` |
| `SEAWEEDFS_VOLUME_MEM_LIMIT` (nuevo) | `1G` | `512M` | `1G` | `512M` |
| `SEAWEEDFS_FILER_MEM_LIMIT` (nuevo) | `512M` | `256M` | `512M` | `256M` |

### 5.8. `sitio2026`

CKAN es el componente mas pesado. Solr JVM por defecto suele estar bajo.

| Variable | workstation | gcp-staging | gcp-boost | admin |
|---|---|---|---|---|
| `POSTGRES_MAX_CONNECTIONS` | 100 | 50 | 100 | 100 |
| `POSTGRES_SHARED_BUFFERS` | `512MB` | `128MB` | `1GB` | `512MB` |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `2GB` | `512MB` | `3GB` | `2GB` |
| `CKAN_DB_MAX_CONNECTIONS` | 100 | 50 | 100 | 100 |
| `CKAN_DB_SHARED_BUFFERS` | `512MB` | `128MB` | `1GB` | `512MB` |
| `REDIS_MAXMEMORY` (nuevo) | `512mb` | `128mb` | `512mb` | `256mb` |
| `CKAN_GUNICORN_WORKERS` (nuevo) | 8 | 2 | 8 | 4 |
| `SOLR_HEAP_SIZE` (nuevo, via `SOLR_HEAP`) | `2g` | `512m` | `2g` | `1g` |
| `API_GUNICORN_WORKERS` (nuevo) | 4 | 2 | 4 | 4 |
| `NGINX_WORKER_PROCESSES` (nuevo) | `auto` | 2 | `auto` | `auto` |
| `NGINX_WORKER_CONNECTIONS` (nuevo) | 1024 | 512 | 1024 | 1024 |

### 5.9. `minerva` (Authentik)

| Variable | workstation | gcp-staging | gcp-boost | admin |
|---|---|---|---|---|
| `POSTGRES_MAX_CONNECTIONS` | 100 | 50 | 100 | 100 |
| `POSTGRES_SHARED_BUFFERS` | `256MB` | `128MB` | `512MB` | `256MB` |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `1GB` | `512MB` | `2GB` | `1GB` |
| `REDIS_MAXMEMORY` (nuevo) | `256mb` | `128mb` | `512mb` | `256mb` |
| `AUTHENTIK_SERVER_WORKERS` (nuevo, si Authentik lo expone) | 4 | 2 | 4 | 4 |
| `AUTHENTIK_WORKER_CONCURRENCY` (nuevo) | 4 | 2 | 4 | 4 |

> **A validar antes de implementar**: confirmar nombres exactos de variables
> que acepta Authentik 2025.8 (las que detecte el inventario eran tentativas).

### 5.10. `sieej`

Sin tuning de runtime — frontend estatico servido por gateway. Solo variables
de path/port. **No requiere `tuning/`** por repo.

---

## 6. Cambios necesarios al `docker-compose.yml` por repo

### 6.1. `geoserver` — sin cambios estructurales

Kartoza ya respeta `INITIAL_MEMORY`, `MAXIMUM_MEMORY` y
`ADDITIONAL_JAVA_STARTUP_OPTIONS`. Solo separar el `.env` actual.

### 6.2. `dataengine` — extender `command:`

Agregar a `postgres-primary`:

```yaml
command: ["postgres",
          "-c", "config_file=/etc/postgresql/postgresql.conf",
          "-c", "max_connections=${POSTGRES_MAX_CONNECTIONS}",
          "-c", "shared_buffers=${POSTGRES_SHARED_BUFFERS}",
          "-c", "effective_cache_size=${POSTGRES_EFFECTIVE_CACHE_SIZE}",
          "-c", "work_mem=${POSTGRES_WORK_MEM}",
          "-c", "maintenance_work_mem=${POSTGRES_MAINTENANCE_WORK_MEM}",
          "-c", "max_worker_processes=${POSTGRES_MAX_WORKER_PROCESSES}",
          "-c", "max_parallel_workers=${POSTGRES_MAX_PARALLEL_WORKERS}",
          "-c", "max_parallel_workers_per_gather=${POSTGRES_MAX_PARALLEL_WORKERS_PER_GATHER}",
          "-c", "random_page_cost=${POSTGRES_RANDOM_PAGE_COST}",
          "-c", "effective_io_concurrency=${POSTGRES_EFFECTIVE_IO_CONCURRENCY}"]
```

### 6.3. `mariachi` — extender `command:` (postgres + redis)

Mismo patron para `mariachi-postgres`. Para `mariachi-redis`:

```yaml
command: ["redis-server",
          "--maxmemory", "${REDIS_MAXMEMORY}",
          "--maxmemory-policy", "allkeys-lru",
          "--save", "",
          "--appendonly", "no"]
```

### 6.4. `mapalab` — `nginx.conf` a template

Renombrar `nginx/nginx-main.conf` → `nginx/nginx-main.conf.template`. En el
template usar `${NGINX_WORKER_PROCESSES}` y `${NGINX_WORKER_CONNECTIONS}`.

Servicio `nginx` en compose:

```yaml
nginx:
  image: nginx:1.27-alpine   # soporta /etc/nginx/templates nativo
  environment:
    NGINX_WORKER_PROCESSES: ${NGINX_WORKER_PROCESSES}
    NGINX_WORKER_CONNECTIONS: ${NGINX_WORKER_CONNECTIONS}
  volumes:
    - ./nginx/nginx-main.conf.template:/etc/nginx/templates/nginx-main.conf.template:ro
```

### 6.5. `gateway-hub` — `nginx.conf` a template

Igual patron que mapalab. Mas complejo porque hay multiples archivos en
`nginx/conf.d/`. Convertir solo los que tienen tuning (`nginx.conf` principal,
los de `proxy_cache_path`).

### 6.6. `huachicol` — limits via env

Cambiar:

```yaml
deploy:
  resources:
    limits:
      memory: 1G
      cpus: '1.0'
```

por:

```yaml
deploy:
  resources:
    limits:
      memory: ${PROMETHEUS_MEM_LIMIT}
      cpus: '${PROMETHEUS_CPUS}'
```

Y para Prometheus retention, anadir al `command:`:

```yaml
command:
  - "--storage.tsdb.retention.time=${PROMETHEUS_RETENTION}"
  - "--storage.tsdb.path=/prometheus"
  # resto de flags
```

Loki: cambiar `retention_period` en `loki-config.yml` a template.

### 6.7. `acervo` — flags al command de seaweedfs

```yaml
command:
  - "server"
  - "-master.volumeSizeLimitMB=${SEAWEEDFS_VOLUME_SIZE_LIMIT}"
  - "-volume.max=${SEAWEEDFS_VOLUME_MAX}"
  - "-volume.minFreeSpacePercent=5"
deploy:
  resources:
    limits:
      memory: ${SEAWEEDFS_MEM_LIMIT}
```

> SeaweedFS no tiene flag de heap directo (es Go, GC dinamico); el control
> efectivo es via `mem_limit` del contenedor.

### 6.8. `sitio2026` — multiples cambios

- `postgres` y `ckan-db`: extender `command:` igual que dataengine.
- `redis`: anadir `--maxmemory` igual que mariachi.
- `ckan-solr`: pasar `SOLR_HEAP=${SOLR_HEAP_SIZE}` como env (ckan/ckan-solr
  imagen lo respeta).
- `ckan`: anadir `CKAN_GUNICORN_WORKERS` como override del CMD (puede requerir
  un entrypoint custom o cambiar el CMD del compose).
- `api`: si usa Gunicorn, exponer `API_GUNICORN_WORKERS`.
- `nginx`: template como mapalab/gateway-hub.

Este repo es el de mayor complejidad. Probablemente requiere dividir la
implementacion en dos fases (primero PG/Redis/Solr, luego CKAN/Nginx).

### 6.9. `minerva` — investigar Authentik

Authentik 2025.8 expone variables `AUTHENTIK_POSTGRESQL__*` y
`AUTHENTIK_REDIS__*`. Verificar si tiene control de workers via env. Si no,
el escalado es horizontal (varias replicas del servicio `worker`).

- `db` y `redis`: igual patron que mariachi (extender command).
- `server` y `worker`: investigar antes de migrar.

### 6.10. `sieej` — sin cambios

No requiere `tuning/`.

---

## 7. Fuente de verdad y anti-drift

`recursos-servidores.md` queda como **la** referencia documentada. Los
archivos `tuning/*.env` derivan de su matriz.

Mecanismos anti-drift (no exclusivos):

1. **Validacion CI** (`scripts/validate-tuning.sh` por repo):
   - Verifica que existan los 4 perfiles obligatorios.
   - Verifica que todas las variables esperadas esten presentes en cada uno.
   - Falla el build si un perfil tiene variable faltante o sintaxis invalida.

2. **Test de coherencia entre repos** (en `gateway-hub`):
   - Script que valida que la suma de `mem_limit` por perfil no exceda la RAM
     declarada del entorno en la doc. Ej. en `gcp-staging` la suma de mem
     limits de huachicol + estimados de geoserver/dataengine/etc no debe
     pasar de 8 GB.
   - Corre en CI de `gateway-hub` cuando se cambian `.env` de tuning de
     cualquier repo (via hook o action que itera repos).

3. **Anclaje doc → archivos** (opcional, fase tardia):
   - Script `scripts/sync-tuning-from-doc.sh` que parsea las tablas de la doc
     y regenera los `.env` de tuning. Solo si la doc se vuelve la unica fuente
     editable.

Flujo recomendado sin sync automatico:
- Cambio de recursos en una VM → actualizar `recursos-servidores.md` primero
  → actualizar archivos de tuning de los repos afectados → bump de patch
  version → commit `chore(tuning): ...`.

---

## 8. Plan de implementacion sugerido

Total estimado: **~12-14 horas** distribuidas en 7 fases. Cada fase deja el
ecosistema funcional; pueden separarse en sprints distintos.

### Fase 0 — Infraestructura compartida (~1 h)

1. Crear `gateway-hub/scripts/detect-profile.sh` con logica de auto-detect.
2. Crear `gateway-hub/scripts/validate-tuning.sh` (template para los demas).
3. Documentar el patron en este mismo archivo (cuando se implemente, mover a
   `docs/` raiz como referencia).

### Fase 1 — Piloto `geoserver` (~30 min, complejidad A)

Validar el patron con el repo mas simple. Si funciona, escalar.

1. Crear `tuning/{workstation,gcp-staging,gcp-boost,admin}.env`.
2. Limpiar `.env` y `.env.example` dejando solo secrets/hosts.
3. Anadir target `up` y `tuning-show` al `Makefile`.
4. Probar `make up PROFILE=gcp-boost` y `make up PROFILE=gcp-staging`.
5. Actualizar `README.md` con seccion "Perfiles de tuning".

### Fase 2 — `dataengine` + `mariachi` (~2 h, complejidad B)

1. Extender `command:` de PG (`-c work_mem`, etc.) en ambos.
2. Anadir `command:` con `--maxmemory` al Redis de mariachi.
3. Crear `tuning/*.env` con los valores propuestos.
4. Validar con `EXPLAIN ANALYZE` sobre query GIS conocida en dataengine.
5. Validar memoria de Redis con `redis-cli info memory`.

### Fase 3 — `huachicol` (~1.5 h, complejidad B)

1. Mover `deploy.resources.limits` hardcoded a `${VAR}`.
2. Anadir `command:` con `--storage.tsdb.retention.time` parametrizado en
   Prometheus.
3. Template de `loki-config.yml` para retention.
4. Crear `tuning/*.env`.

### Fase 4 — `acervo` (~1 h, complejidad B)

1. Flags `-volume.max` y `mem_limit` parametrizados.
2. Crear `tuning/*.env`.

### Fase 5 — `mapalab` + `gateway-hub` (~2-3 h, complejidad C)

1. Convertir `nginx-main.conf` (mapalab) y `nginx.conf` (gateway-hub) a
   templates con `${NGINX_*}`.
2. Usar imagen `nginx:1.27-alpine` que soporta `/etc/nginx/templates/`.
3. Validar con `nginx -t` dentro del contenedor.
4. Crear `tuning/*.env`.

### Fase 6 — `sitio2026` (~3-4 h, complejidad D)

Por ser el mas complejo, dividir en sub-fases:

- 6a: PG + ckan-db + redis (~1 h).
- 6b: Solr heap (`SOLR_HEAP` env) (~30 min).
- 6c: CKAN Gunicorn workers (puede requerir entrypoint custom) (~1.5 h).
- 6d: Nginx template (~30 min).

### Fase 7 — `minerva` (~1.5 h, complejidad C)

1. PG + Redis (igual patron que el resto).
2. Investigar variables nativas de Authentik 2025.8 para workers/concurrency.
3. Si Authentik no expone tuning de procesos, documentar que se escala con
   `deploy.replicas`.

### Fase 8 — Anti-drift CI (~1 h)

1. `scripts/validate-tuning.sh` en cada repo, llamado desde `make check` o el
   pre-commit existente.
2. Script en gateway-hub que valida coherencia inter-repos (suma de
   `mem_limit` por perfil ≤ RAM declarada).

### Fase 9 — Doc final (~30 min)

1. Anadir seccion "Perfiles de tuning" a `recursos-servidores.md` con link
   bidireccional.
2. Mover este documento a `docs/` raiz (de `pendientes/` a referencia
   permanente) cuando se cierre.

---

## 9. Decisiones abiertas

| # | Pregunta | Opciones |
|---|---|---|
| D1 | ¿Auto-detect en `make up` o requerir flag explicito? | (a) auto-detect con fallback workstation, (b) forzar `IIEG_PROFILE` o `PROFILE=` sin default. |
| D2 | ¿Los `tuning/*.env` se commitean o se generan? | (a) commiteados (transparencia, diff util), (b) generados desde la doc (anti-drift, opaco). |
| D3 | ¿`admin.env` por repo apunta al servidor donde corre, o varios `admin-Sx.env`? | (a) un `admin.env` (geoserver→S3, dataengine→S4, etc.), (b) `admin-s1.env`, `admin-s2.env`, etc. — solo necesario si un servicio puede correr en >1 server. |
| D4 | ¿Que hacer con sidecars (version-api, alertmanager-discord, etc.)? | Probablemente no necesitan perfil; defaults hardcoded en el compose. Confirmar. |
| D5 | ¿`make boost` / `make unboost` como atajos en gateway-hub? | Atajo orquestador que sube perfil de los repos afectados al boost / lo baja a staging. Util si el boost se usa frecuente. |
| D6 | ¿`gcp-boost` se borra cuando el boost se vuelva permanente? | Si se aprueba upgrade definitivo de mapalab a 8c/32GB, `gcp-boost` se convierte en el nuevo `gcp-staging` y se elimina el archivo viejo. |
| D7 | ¿Como manejar perfiles intermedios futuros (4c/16GB)? | (a) crear `gcp-medium.env`, (b) interpolar valores en runtime via script que calcule desde RAM detectada. Por ahora no es necesario. |
| D8 | ¿Anti-drift via script (`sync-tuning-from-doc.sh`) o solo via CI de validacion? | (a) sync automatico desde doc (mas robusto, requiere parser), (b) solo validacion (mas simple, drift posible). Empezar con (b). |
| D9 | ¿Que pasa con `sitio2026/.env.production` que ya existe? ¿Se rompe el flujo actual? | Plan de migracion gradual: mantener `.env.production` cargando primero, `tuning/admin.env` cargando despues. Si todas las vars de tuning se eliminan de `.env.production`, no hay conflicto. |
| D10 | ¿`huachicol` retention de Prometheus distinta en GCP vs admin? | Si retenes solo 7-30 dias en GCP, en admin se pueden tener 90d porque hay 490 GB de disco. Definir politica. |

---

## 10. Costo y beneficio

**Costo total estimado**: ~12-14 horas de implementacion distribuidas en 9
fases.

**Costo de mantenimiento ongoing**: cuando cambien recursos reales hay que
ajustar 4 archivos por repo. La matriz vive en la doc, asi que es trabajo
mecanico. Si se implementa el sync script, son 0 minutos por cambio.

**Beneficios**:

- **Boost/unboost en 1 comando**: `make up PROFILE=gcp-boost` vs.
  `make up PROFILE=gcp-staging` por repo, o `make boost` orquestado desde
  gateway-hub.
- **Sin edits manuales** al revertir el boost — el riesgo actual de dejar
  `INITIAL_MEMORY=4G` en una VM de 8 GB desaparece.
- **Nuevo colaborador**: clona repo → `make up` detecta perfil → arranca con
  valores apropiados a su maquina sin tunear nada.
- **Separacion secrets/tuning**: `.env` deja de moverse cuando se ajusta
  memoria; menos conflictos de merge.
- **Exposicion de palancas invisibles**: hoy nginx workers, Solr heap, CKAN
  workers, Authentik workers, SeaweedFS, Prometheus retention NO son
  tuneables — esta migracion los expone.
- **Anti-drift**: CI detecta divergencias doc ↔ archivos.
- **Escala a nuevos entornos**: anadir un `gcp-medium.env` o `admin-spare.env`
  toma 5 minutos por repo.
- **Camino a K3s/Kustomize**: el patron de perfiles se traduce 1:1 a
  `overlays/<env>/` de Kustomize si eventualmente migra (ver
  [evaluacion-k3s.md](evaluacion-k3s.md)).

**Riesgos**:

- Fase 6 (`sitio2026`) es la mas larga y con mas componentes nuevos
  (Solr/CKAN). Puede dar problemas el primer arranque.
- Fase 5 (`mapalab` + `gateway-hub`) introduce templating de nginx; si se
  rompe, todo el ecosistema queda sin proxy. Validar en staging primero,
  rollback siempre disponible (volver al `.conf` literal).
- Cambios al `command:` de Postgres requieren reiniciar el contenedor; en
  admin (S4) eso interrumpe queries GIS de todos los consumidores. Coordinar
  ventana.

---

## 11. Referencias

- [docs/recursos-servidores.md](../recursos-servidores.md) — matriz oficial
  de hardware y tuning por entorno.
- [docs/pendientes/evaluacion-k3s.md](evaluacion-k3s.md) — si migra a K3s,
  este patron se vuelve `overlays/<env>/`.
- [docs/pendientes/checklist-produccion-gcp.md](checklist-produccion-gcp.md)
  — validaciones post-deploy que aplican al cambiar de perfil.
- [docs/pendientes/reorganizacion-y-puertos.md](reorganizacion-y-puertos.md)
  — contexto del modelo de un solo `.env` vs separacion.
