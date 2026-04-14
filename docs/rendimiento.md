# Rendimiento y Proteccion contra Saturacion

Configuracion de rendimiento del ecosistema IIEG para manejar carga concurrente
sin degradar la experiencia del usuario.

## Arquitectura del flujo de requests

```
Usuario (navegador)
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  Gateway Hub (Nginx)                                     │
│  ├─ Rate limiting por zona (general, api, static)        │
│  ├─ Cache de assets (mapalab_assets: 500MB, 7 dias)      │
│  ├─ Cache GeoServer (geoserver_cache: 2GB, 12h)          │
│  └─ Paginas de error personalizadas (429, 500)           │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  MapaLab Nginx (interno)                                 │
│  ├─ worker_processes: auto (= CPU cores)                 │
│  ├─ worker_connections: 2048                             │
│  ├─ keepalive al backend: 32 conexiones                  │
│  ├─ Assets estaticos: cache 1 año (immutable)            │
│  └─ open_file_cache: 1000 archivos                       │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  MapaLab Backend (Gunicorn + Uvicorn)                    │
│  ├─ Workers: 8 (async)                                   │
│  ├─ Pool PostgreSQL por worker: 8 + 8 overflow = 16      │
│  └─ Total conexiones DB: 8 workers × 16 = 128 max        │
└───────────────┬─────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│  PostgreSQL / PostGIS                                    │
│  └─ max_connections: verificar >= 150                     │
└─────────────────────────────────────────────────────────┘
```

## Rate Limiting (Gateway Hub)

El rate limiting se aplica por IP del cliente (`$binary_remote_addr`) con tres zonas diferenciadas.

### Zonas

| Zona | Rate | Proposito |
|------|------|-----------|
| `general` | 10 r/s | Navegacion, paginas HTML, rutas generales |
| `api` | 10 r/s | Endpoints de API, descargas |
| `static` | 50 r/s | Assets estaticos de SPAs (JS, CSS, fuentes) |

### Burst por ruta

| Ruta | Zona | Burst | Justificacion |
|------|------|-------|---------------|
| `/mapalab/assets/` | static | 200 | SPA carga ~25 assets en paralelo al abrir |
| `/mapalab/` | general | 150 | Navegacion entre secciones de la SPA |
| `/mapalab/api/download/` | api | 5 | Descargas pesadas, limitar concurrencia |
| `/api/` (Portal) | api | 20 | API general |
| `/acervo/` | api | 100 | Uploads/downloads de archivos grandes |
| `/geoserver/` (OGC) | geoserver | 10 | Servicios WMS/WFS/WCS |
| Demas rutas | general | 20 | Default |

### Respuesta al exceso (HTTP 429)

Todas las zonas responden con **HTTP 429** (Too Many Requests) en lugar de 503. Esto muestra una pagina
amigable que indica al usuario que espere, con un countdown de 10 segundos antes de habilitar el boton
de reintento.

## Cache (Gateway Hub)

### MapaLab Assets

| Parametro | Valor |
|-----------|-------|
| Zona | `mapalab_assets` |
| Tamano maximo | 500 MB |
| TTL | 7 dias |
| Stale serving | Si (en error, timeout, 500-504) |
| Header diagnostico | `X-Cache-Status` (HIT/MISS/STALE) |
| Cache-Control al cliente | `public, max-age=31536000, immutable` |

Los assets de Vite usan hash en el nombre (`app-abc123.js`), por lo que un deploy nuevo
genera nombres nuevos y el cache se renueva automaticamente. No hay riesgo de servir
versiones desactualizadas.

### GeoServer

| Parametro | Valor |
|-----------|-------|
| Zona | `geoserver_cache` |
| Tamano maximo | 2 GB |
| TTL | 6 horas (responses 200) |
| Cache key | `$request_uri$arg_outputFormat` |
| Lock | 10s timeout (previene thundering herd) |
| Bypass | GetFeatureInfo, GetCapabilities, DescribeFeatureType |

## MapaLab Nginx (interno)

Configuracion del Nginx que sirve el frontend y hace proxy al backend de FastAPI.

| Parametro | Valor |
|-----------|-------|
| `worker_processes` | `auto` (= numero de CPU cores) |
| `worker_rlimit_nofile` | 8192 |
| `worker_connections` | 2048 |
| `multi_accept` | on |
| `keepalive_timeout` | 65s |
| `open_file_cache` | max 1000 archivos, validacion cada 30s |
| Upstream keepalive | 32 conexiones persistentes al backend |

### Rutas internas

| Ruta | Destino | Timeout | Notas |
|------|---------|---------|-------|
| `/` | Archivos estaticos (dist/) | - | `try_files` con fallback a `index.html` (SPA) |
| `/api/download/` | Backend :8000 | 600s | `proxy_buffering off` (streaming) |
| `/api/` | Backend :8000 | 120s | Proxy estandar |
| Assets (`.js`, `.css`, etc.) | Archivos locales | - | `expires 1y`, `Cache-Control: immutable` |
| `index.html` | Archivo local | - | `no-cache, no-store` (siempre fresco) |

## MapaLab Backend

### Gunicorn

| Parametro | Valor |
|-----------|-------|
| Workers | 8 |
| Worker class | `uvicorn.workers.UvicornWorker` (async) |
| Bind | `0.0.0.0:8000` |

### Pool de conexiones PostgreSQL (por worker)

| Parametro | Valor |
|-----------|-------|
| `pool_size` | 8 conexiones idle |
| `max_overflow` | 8 conexiones adicionales bajo carga |
| `pool_pre_ping` | Activado (valida conexion antes de usar) |
| **Total por worker** | 16 conexiones max |
| **Total global** | 8 workers × 16 = 128 conexiones max |

## Paginas de error

Todas las paginas de error son HTML autocontenido con estilos inline y SVG.

| Codigo | Titulo | Cuando aparece |
|--------|--------|----------------|
| 400 | No pudimos procesar tu solicitud | Request malformado |
| 401 | Acceso no autorizado | Falta autenticacion |
| 403 | Acceso restringido | Sin permisos |
| 404 | No encontramos la pagina que estas buscando | Recurso no existe |
| 429 | Espera un momento | Rate limit excedido (countdown 10s) |
| 500 | Estamos trabajando en ello | Error de servidor, upstream caido |

La pagina 500 cubre tambien 502, 503 y 504. Usa lenguaje no tecnico para
no alarmar al usuario.

## Capacidades y limites

### Capacidad teorica por componente

| Componente | Capacidad | Limitante |
|-----------|-----------|-----------|
| Gateway Nginx | ~4096 conexiones simultaneas por worker | `worker_connections` |
| MapaLab Nginx | ~2048 conexiones simultaneas por worker | `worker_connections` |
| MapaLab Backend | 8 requests async en paralelo | Workers Gunicorn |
| DB Pool | 128 conexiones totales | `pool_size` × workers |
| PostgreSQL | Depende de `max_connections` | Verificar >= 150 |

### Escenario: carga de pagina de un usuario

Un usuario abriendo MapaLab genera:

1. **1 request** HTML (`/mapalab/mapa`) → zona `general`
2. **~25 requests** assets JS/CSS (`/mapalab/assets/`) → zona `static`, servidos desde cache gateway
3. **2-5 requests** API (`/mapalab/api/`) → zona `general`

Total: ~30 requests. Con los burst actuales, un usuario individual nunca alcanza el limite.

### Escenario: 50 usuarios simultaneos desde misma IP

- Assets: 50 × 25 = 1250 requests → zona `static` a 50r/s + burst 100. Los assets se sirven
  desde cache del gateway (HIT), no llegan al upstream. Sin problema.
- HTML + API: 50 × 6 = 300 requests → zona `general` a 10r/s + burst 50. Algunos podrian
  recibir 429, pero la pagina ya cargo correctamente porque los assets llegaron.

### Estimacion de usuarios concurrentes

Basado en los recursos reales de cada entorno y el flujo de requests de un usuario
tipico de MapaLab (~30 requests: 1 HTML + ~25 assets + 2-5 API).

#### Produccion (4 servidores dedicados)

| Componente | Capacidad | Cuello de botella |
|-----------|-----------|-------------------|
| Gateway (8 cores, 15 GB) | ~500+ conexiones simultaneas | No es limitante |
| MapaLab Nginx (4 cores) | ~8000 conexiones simultaneas | No es limitante |
| MapaLab Backend (8 workers async) | ~80-120 requests API/s | Limitante principal |
| DB Pool (128 conexiones) | ~128 queries simultaneas | Segundo limitante |
| PostgreSQL (200 max_conn, 2 GB shared_buffers) | ~200 queries simultaneas | Holgado |
| Cache gateway (assets) | Ilimitado (servido desde cache) | No es limitante |

**Estimacion: ~80-100 usuarios simultaneos navegando activamente**

- Los assets (90% de requests) se sirven desde cache del gateway → no tocan backend
- Cada usuario genera ~3-5 requests API al navegar
- 100 usuarios × 4 requests API = 400 requests → 8 workers async los manejan sin problema
- El cuello de botella real es si todos hacen queries pesadas (descargas CSV, periodicidad)
- Descargas CSV simultaneas: ~10-15 (cada una ocupa 1 conexion DB por 5-60s)

#### GCP Staging (1 VM, 2 cores, 7.8 GB)

| Componente | Capacidad | Cuello de botella |
|-----------|-----------|-------------------|
| Gateway + MapaLab (comparten 2 cores) | CPU compartida | Limitante principal |
| Backend (4 workers async) | ~30-50 requests API/s | Segundo limitante |
| DB Pool (32 conexiones) | ~32 queries simultaneas | Tercer limitante |
| GeoServer (2.6 GB RAM, mismos 2 cores) | WMS/WFS compiten por CPU | Agrava el cuello |
| PostgreSQL local (200 max_conn) | Holgado | No es limitante |

**Estimacion: ~20-30 usuarios simultaneos navegando activamente**

- GeoServer consumiendo 33% de RAM y compitiendo por CPU es el factor principal
- Con 2 cores, el context switching entre 20+ contenedores degrada todo
- Assets desde cache del gateway ayudan, pero las tiles WMS de GeoServer no se cachean en primer request

#### Comparativa

| Metrica | GCP Staging | Produccion |
|---------|-------------|------------|
| Usuarios simultaneos | ~20-30 | ~80-100 |
| Requests API/s sostenidos | ~30-50 | ~80-120 |
| Descargas CSV simultaneas | ~3-5 | ~10-15 |
| Tiles WMS simultaneas | ~10-20 | ~50-80 |
| Punto de saturacion estimado | ~40 usuarios | ~150 usuarios |

### Resultados de stress test (2026-04-14)

Prueba con modo rampa, 100 usuarios max, 5 pasos, 1 sesion por usuario.
Cada sesion simula un navegador real: HTML + ~25 assets CSS/JS + think time 1-3s.
Criterios de quiebre: error rate > 30% o p95 > 4000ms.

#### Antes de optimizaciones (staging y production sin cambios)

| Metrica | Staging GCP | Produccion |
|---------|-------------|------------|
| Ultima fase estable | 20 usuarios | 20 usuarios |
| Punto de quiebre | 40 usuarios (47.5% errores) | 40 usuarios (47.5% errores) |
| Max RPS servidor | 31.09 rps @ 20 usuarios | 47.30 rps @ 20 usuarios |
| p95 estable | 479 ms | 245 ms |

#### Con optimizaciones (local: gateway cache + rate limit + backend 8 workers + PG tuning)

| Metrica | Local (optimizado) |
|---------|--------------------|
| Ultima fase estable | 100 usuarios (0% errores) |
| Punto de quiebre | 120 usuarios (42.5% errores, rate limit) |
| Max RPS servidor | 348.11 rps @ 100 usuarios |
| p95 estable | 127 ms |

#### Comparativa

| Metrica | Antes (staging/prod) | Despues (optimizado) | Mejora |
|---------|---------------------|---------------------|--------|
| Usuarios estables | 20 | 100 | 5x |
| Punto de quiebre | 40 | 120 | 3x |
| Max RPS | 47 rps | 348 rps | 7.4x |
| p95 latencia | 245-479 ms | 127 ms | 2-4x menor |

El quiebre a 120 usuarios es por rate limiting (HTTP 429), no por saturacion del backend.
El backend mantiene p95 < 130ms incluso a 100 usuarios desde una sola IP.

**Nota:** estas estimaciones asumen usuarios navegando activamente (cargando capas,
haciendo zoom, consultando datos). Usuarios ociosos (pagina abierta sin interaccion)
no generan carga. El punto de saturacion es donde el p95 supera 4 segundos.

### Escalamiento

| Para soportar mas carga | Que ajustar |
|-------------------------|-------------|
| Mas usuarios concurrentes | Aumentar `burst` en gateway y workers en backend |
| Mas requests API | Aumentar `pool_size` en backend y `max_connections` en PostgreSQL |
| Mas servicios detras del gateway | Agregar upstream y zona de rate limit si es necesario |
| Multiples servidores | Agregar mas `server` en el upstream (load balancing round-robin) |
