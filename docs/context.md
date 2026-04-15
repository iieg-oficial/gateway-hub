# Gateway Hub - Contexto Completo del Proyecto

> Documento de referencia para Claude Code. Leer este archivo proporciona contexto completo
> del proyecto sin necesidad de explorar el codebase.
>
> Ultima actualizacion: 2026-04-14

---

## 1. Que es Gateway Hub

Gateway Hub es el **proxy inverso central y terminador SSL/TLS** de la infraestructura del
Instituto de Informacion Estadistica y Geografica de Jalisco (IIEG). Es el punto unico de
entrada para todos los servicios publicos e internos. Maneja:

- Enrutamiento de trafico (reverse proxy)
- Terminacion SSL/TLS
- Cache (especialmente para GeoServer)
- Rate limiting
- Control de acceso por IP (VPN)
- Inyeccion de Google Tag Manager
- Logging estructurado (JSON) y envio a Loki
- Metricas para Prometheus

**Repositorio:** `git@github.com:iieg-oficial/gateway-hub.git`
**Ramas:** `develop` (desarrollo activo), `production` (produccion)
**Licencia:** MIT - IIEG Jalisco

---

## 2. Estructura del Proyecto

```
gateway-hub/
├── certs/                          # Certificados SSL (self-signed en dev)
│   ├── cert.pem
│   └── key.pem
├── docs/
│   ├── arquitectura.mmd            # Diagrama de arquitectura (Mermaid)
│   ├── ssh-deploy-keys.md          # Guia de configuracion de llaves SSH
│   ├── error-pages.md              # Documentacion de paginas de error
│   ├── rendimiento.md              # Rate limiting, cache, capacidades y limites
│   ├── recursos-servidores.md      # Hardware y recursos por entorno (GCP y produccion)
│   └── context.md                  # Este archivo
├── nginx/
│   ├── nginx.conf                  # Configuracion principal de Nginx
│   ├── templates/
│   │   └── gateway.conf.template   # Server block principal (usa envsubst)
│   ├── conf.d/
│   │   └── geoserver-upstream.conf.template  # Upstream y cache de GeoServer
│   ├── includes/
│   │   ├── proxy-params.inc        # Headers estandar de proxy
│   │   ├── security-headers.inc    # Headers de seguridad (HSTS, CSP, etc.)
│   │   ├── geoserver-locations.inc # Location blocks de GeoServer
│   │   ├── geoserver-hide-headers.inc # Headers a ocultar de GeoServer
│   │   └── gtm.inc.template        # Google Tag Manager (condicional)
│   ├── error-pages/                # Paginas de error personalizadas (400, 401, 403, 404, 429, 500)
│   └── static/                     # Archivos estaticos (robots.txt, sitemap.xml)
├── promtail/
│   └── promtail-config.yml         # Configuracion de Promtail (logs -> Loki)
├── docker-compose.yml              # Orquestacion de contenedores
├── Dockerfile                      # Imagen Nginx + entrypoint personalizado
├── .env                            # Variables de entorno (dev)
└── .env.example                    # Plantilla de variables
```

---

## 3. Contenedores (docker-compose.yml)

| Servicio | Imagen | Puertos | Funcion |
|----------|--------|---------|---------|
| `nginx` | Build local (nginx:1.28.2-alpine) | 80, 443 | Proxy inverso principal |
| `nginx-exporter` | nginx/nginx-prometheus-exporter | 9090 | Metricas Prometheus via /stub_status |
| `promtail` | grafana/promtail | - | Reenvia logs JSON a Loki |

**Red:** `iieg-network` (externa, compartida con todos los servicios IIEG)
**Volumen:** `nginx_logs` (compartido entre nginx y promtail)

---

## 4. Variables de Entorno

| Variable | Ejemplo (dev) | Descripcion |
|----------|---------------|-------------|
| `APP_DOMAIN` | `192.168.3.13` | Dominio/IP publico del gateway |
| `GTM_ID` | (vacio) | ID de Google Tag Manager (opcional) |
| `SSL_CERTIFICATE` | `/etc/nginx/certs/cert.pem` | Ruta al certificado SSL dentro del contenedor |
| `SSL_CERTIFICATE_KEY` | `/etc/nginx/certs/key.pem` | Ruta a la llave privada |
| `SSL_VOLUME_PATH` | `./certs:/etc/nginx/certs:ro` | Mapeo de volumen host:contenedor |
| `PORTAL_HOST` | `host.docker.internal:8000` | Host del Portal |
| `MAPALAB_HOST` | `mapalab-staging-nginx-1:80` | Host de MapaLab |
| `ACERVO_HOST` | `host.docker.internal:9000` | Host de Acervo (MinIO API) |
| `ACERVO_CONSOLE_HOST` | `host.docker.internal:9001` | Host de Acervo Console (MinIO UI) |
| `MARIACHI_HOST` | `host.docker.internal:8080` | Host de MARIACHI |
| `GEOSERVER_HOST` | `host.docker.internal:8080` | Host de GeoServer |
| `HUACHICOL_HOST` | `host.docker.internal:3000` | Host de Grafana (Huachicol) |
| `LOKI_URL` | `http://loki:3100` | Endpoint de Loki |
| `SEO_ENABLED` | `false` | `true`: robots.txt permite crawlers, sitemap activo. `false`: bloquea indexacion |

---

## 5. Enrutamiento - Todas las Rutas

| Ruta | Upstream | Acceso | Rate Limit | Notas |
|------|----------|--------|------------|-------|
| `/` | portal | Publico | general (10r/s) | Redirige a /mapalab/ |
| `/api/` | portal | Publico | api (10r/s) | API del Portal, cache no-store |
| `/administrador/` | portal | Publico | general | Panel de administracion |
| `/mapalab/assets/` | mapalab | Publico | static (50r/s, burst 200) | Cache gateway 7d, immutable, stale serving |
| `/mapalab/` | mapalab | Publico | general (burst 150) | Interfaz de mapas (timeout 120s) |
| `/mapalab/api/download/` | mapalab | Publico | api (5 burst) | Descargas CSV backend (timeout 600s, sin buffering) |
| `/acervo/` | acervo | Publico | api (100r/s burst) | API de archivos (max 1GB, timeout 300s) |
| `/acervo/console/` | acervo_console | Auth propia | general | Consola MinIO (WebSocket) |
| `/acervo/console/static/` | acervo_console | Auth propia | general | Assets estaticos de la consola |
| `/mariachi/` | mariachi | Auth propia | general | Analitica/monitoreo |
| `/huachicol/` | huachicol | Auth propia | general | Dashboards Grafana |
| `/geoserver/web/` | geoserver | Auth propia | general | Admin UI de GeoServer |
| `/geoserver/rest/` | geoserver | Auth propia | general | REST API de GeoServer |
| `/geoserver/j_spring_security` | geoserver | Auth propia | general | Auth de GeoServer |
| `/geoserver/ows` | geoserver | Publico* | geoserver (10r/s) | WMS/WFS/WCS (cache 6h, validacion referer+UA) |
| `/geoserver/wfs` | geoserver | Publico* | geoserver (10r/s) | WFS directo (timeout 600s, cache 6h, validacion) |
| `/geoserver/wcs` | geoserver | Publico* | geoserver (10r/s) | WCS directo (timeout 600s, cache 6h, validacion) |
| `/geoserver/{workspace}/wfs` | geoserver | Publico* | geoserver (10r/s) | WFS por workspace (timeout 600s, sin cache, validacion) |
| `/geoserver/{workspace}/wcs` | geoserver | Publico* | geoserver (10r/s) | WCS por workspace (timeout 600s, sin cache, validacion) |
| `/robots.txt` | static | Publico | - | SEO_ENABLED=true: permite crawlers. false: Disallow / |
| `/sitemap.xml` | static | Publico | - | SEO_ENABLED=true: sirve sitemap. false: 404 |

*Publico con restricciones: validacion de Referer, bloqueo de User-Agents (bots, scrapers, curl, wget, etc.), bloqueo de WFS-T.

---

## 6. Seguridad

### SSL/TLS
- Protocolos: TLSv1.2 y TLSv1.3 unicamente
- Cifrados: ECDHE (AES-GCM) modernos
- HSTS: max-age=31536000; includeSubDomains; preload
- OCSP Stapling habilitado (resolvers Google DNS)
- Redireccion HTTP -> HTTPS automatica

### Headers de Seguridad
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(self), camera=(), microphone=(), payment=(), usb=()`
- `Cross-Origin-Opener-Policy: same-origin`

### Control de Acceso
- **Autenticacion delegada:** Los endpoints administrativos (Grafana, GeoServer, MinIO Console) dependen de la autenticacion propia de cada servicio. No hay restriccion por IP.
- **Validacion de Referer:** En endpoints OGC de GeoServer.
- **Filtrado de User-Agent:** Bloquea bots, scrapers, herramientas CLI, crawlers de IA.
- **Bloqueo de WFS-T:** Previene transacciones de escritura en GeoServer.
- **Rate Limiting:** Zonas: `general` (10r/s), `api` (10r/s), `static` (50r/s), `geoserver` (10r/s). Todas las rutas tienen rate limiting. Exceso responde HTTP 429 con pagina amigable (countdown 10s).

### Paths Denegados
- `/.` (archivos ocultos) -> 403

---

## 7. Cache

### MapaLab Assets Cache
- **Ubicacion:** `/var/cache/nginx/mapalab_assets`
- **Tamano maximo:** 500MB
- **TTL:** 7 dias
- **Stale serving:** En error, timeout, 500-504 (resiliencia ante caidas del upstream)
- **Cache-Control al cliente:** `public, max-age=31536000, immutable`
- **Header:** `X-Cache-Status` indica HIT/MISS/STALE
- Los assets de Vite usan hash en el nombre, por lo que deploys nuevos generan cache keys nuevas automaticamente

### GeoServer Cache
- **Ubicacion:** `/var/cache/nginx/geoserver`
- **Tamano maximo:** 2GB
- **TTL:** 6 horas para respuestas 200
- **Cache key:** `$request_uri$arg_outputFormat`
- **Lock:** Habilitado (10s timeout) para evitar thundering herd
- **Bypass:** GetFeatureInfo, GetCapabilities, DescribeFeatureType
- **Header:** `X-Cache-Status` indica HIT/MISS/BYPASS

---

## 8. Logging y Monitoreo

### Access Logs
- **Formato JSON** con campos: timestamp, remote_addr, method, URI, status, bytes, referer, user_agent, response_time, upstream_response_time
- **Destinos:** Archivo (`/var/log/nginx/access.log`) + stdout (formato humano)

### Promtail -> Loki
- Parsea logs JSON de acceso
- Extrae labels: `subroute` (primer segmento de ruta), `status`, `request_method`
- Error logs enviados con label `level: error`
- Labels de servicio: `service: gateway-hub`, `environment: production`

### Prometheus
- `nginx-exporter` expone metricas de `/stub_status` en puerto 9090
- Metricas: conexiones activas, requests/s, reading/writing/waiting

---

## 9. Entrypoint del Contenedor

El Dockerfile define un entrypoint que ejecuta en orden:

1. **Procesa templates de GeoServer** con `envsubst`
2. **Genera gateway.conf** desde template con todas las variables de entorno
3. **Genera GTM include** (condicional: solo si `GTM_ID` tiene valor)
4. **Inicia Nginx** en foreground

---

## 10. Upstreams Definidos

| Nombre | Variable de Host | Keepalive | Timeout | Notas |
|--------|-----------------|-----------|---------|-------|
| portal | `PORTAL_HOST` | 32 | 60s | Sitio principal |
| mapalab | `MAPALAB_HOST` | 32 | - | Mapa interactivo |
| acervo | `ACERVO_HOST` | 32 | - | Storage S3 |
| acervo_console | `ACERVO_CONSOLE_HOST` | 32 | - | MinIO UI |
| mariachi | `MARIACHI_HOST` | 32 | - | Analitica |
| huachicol | `HUACHICOL_HOST` | 32 | - | Grafana |
| geoserver | `GEOSERVER_HOST` | 64 | 60s | Servicios OGC (1000 keepalive_requests) |

---

## 11. Ecosistema IIEG - Proyectos Conectados

Todos los proyectos viven en `/home/egar/IIEG/` y comparten `iieg-network`.

### Portal
- **Ruta:** `/` y `/api/` y `/administrador/`
- **Descripcion:** Aplicacion web principal del IIEG, pagina de inicio y panel de administracion
- **Host:** `PORTAL_HOST` (puerto 8000 en dev)

### MapaLab (`/home/egar/IIEG/mapalab/`)
- **Ruta:** `/mapalab/`
- **Stack:** React 19 (Vite) + FastAPI (Python) + PostgreSQL/PostGIS
- **Perfiles Docker:** `dev` (Vite + Uvicorn), `staging` (Nginx + Gunicorn), `build`
- **Dependencias externas:** GeoServer (datos geo), PostgreSQL, Acervo (uploads)
- **Redes:** mapalab-network (interna) + iieg-network (gateway)

### Acervo (`/home/egar/IIEG/acervo/`)
- **Ruta:** `/acervo/` (API) y `/acervo/console/` (UI admin)
- **Stack:** Nginx + MinIO (almacenamiento S3-compatible)
- **Buckets:** Separados por sistema (mapalab, dataengine, portal)
- **Backups:** Diarios automatizados a cloud storage con politica de rotacion

### GeoServer (`/home/egar/IIEG/geoserver/`)
- **Ruta:** `/geoserver/`
- **Imagen:** kartoza/geoserver:2.27.0
- **Servicios OGC:** WMS, WFS, WCS
- **Base de datos:** PostgreSQL/PostGIS (via mapalab-dataengine)
- **Features:** Auto-inicializacion de datastores, plugins (GeoPackage)

### Huachicol (`/home/egar/IIEG/huachicol/`) - Stack de Observabilidad
- **Ruta:** `/huachicol/` (Grafana)
- **Componentes:**
  - Prometheus (9090) - metricas
  - Grafana (3000) - dashboards
  - AlertManager (9093) - alertas a Discord
  - Loki (3100) - logs
  - Tempo (3200) - trazas distribuidas
  - Node Exporter (9100) - metricas de sistema
  - cAdvisor (8080) - metricas de contenedores
- **Retencion:** 30 dias (metricas/logs), 7 dias (trazas)

### MARIACHI
- **Ruta:** `/mariachi/`
- **Descripcion:** Servicio de analitica y monitoreo
- **Host:** `MARIACHI_HOST` (puerto 8080 en dev)

### MapaLab DataEngine (`/home/egar/IIEG/mapalab-dataengine/`)
- **Stack:** PostgreSQL 18 + PostGIS 3.6
- **Componentes:** BD primaria (read/write), replica (read-only), backups automatizados
- **ETL:** mapalab-card para ingesta de CSV
- **SSL requerido** para conexiones externas

### IGIBot (`/home/egar/IIEG/igibot/`)
- **Stack:** K3s/Kubernetes con Traefik ingress
- **Componentes:** Backend LLM, Frontend web, Vector DB
- **URL:** `https://igibot.jalisco.gob.mx`
- **NO pasa por gateway-hub** (cluster K3s separado)

### Olders (`/home/egar/IIEG/olders/`)
- Proyectos legacy archivados (portal anterior, formularios, intranet, etc.)

---

## 12. Arquitectura de Red

```
Internet / Usuarios
        |
        v
  ┌─────────────────────────────────────────────────┐
  │  Gateway Hub (Nginx)                             │
  │  Puertos: 80 (HTTP->HTTPS), 443 (HTTPS)         │
  │  Red: iieg-network                               │
  └──┬──────┬──────┬──────┬──────┬──────┬──────┬────┘
     │      │      │      │      │      │      │
     v      v      v      v      v      v      v
  Portal  MapaLab Acervo GeoSrv Mariachi Huachi Acervo
  :8000   :80     :9000  :8080  :8080   :3000  Console
                                                :9001
                    │      │
                    v      v
              ┌──────────────────┐
              │ PostgreSQL/PostGIS│
              │ (mapalab-dataeng) │
              │ Primary + Replica │
              └──────────────────┘

  [Separado - K3s]
  IGIBot (igibot.jalisco.gob.mx)
```

---

## 13. Flujo del Entrypoint y Templates

El sistema de configuracion es **template-based**:

1. Los archivos `.template` en `nginx/templates/` y `nginx/conf.d/` usan variables `${VAR}`
2. El entrypoint del Dockerfile ejecuta `envsubst` para sustituir variables del `.env`
3. Los archivos procesados se escriben en `/etc/nginx/conf.d/`
4. `gtm.inc` se genera solo si `GTM_ID` tiene valor; si no, se crea vacio

**Importante:** Los archivos en `includes/` que NO son templates (`.inc`) se montan directamente.
Los que son templates (`.inc.template`) se procesan en runtime.

---

## 14. Notas para Desarrollo

- **Agregar un nuevo servicio:** Crear upstream en `gateway.conf.template`, agregar variable de entorno en `.env`/`.env.example`, agregar location block, actualizar entrypoint si necesita envsubst.
- **Cache:** Solo GeoServer tiene cache actualmente. Para agregar cache a otro servicio, definir zona en `nginx.conf` y configurar en el location block.
- **Logs:** Todos los access logs son JSON. Promtail los envia a Loki automaticamente.
- **SSL en dev:** Certificados self-signed en `certs/`. En produccion se montan certificados reales via volumen.
- **Docker network:** Todos los servicios DEBEN estar en `iieg-network` para ser accesibles desde el gateway.
- **host.docker.internal:** Usado para acceder a servicios que corren en el host (no en Docker) o en otro docker-compose. Se mapea via `extra_hosts` en docker-compose.
