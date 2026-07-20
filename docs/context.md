# Gateway Hub - Contexto Completo del Proyecto

> Documento de referencia para Claude Code. Leer este archivo proporciona contexto completo
> del proyecto sin necesidad de explorar el codebase.
>
> Ultima actualizacion: 2026-07-20

---

## 1. Que es Gateway Hub

Gateway Hub es el **proxy inverso central y terminador SSL/TLS** de la infraestructura del
Instituto de Informacion Estadistica y Geografica de Jalisco (IIEG). Es el punto unico de
entrada para todos los servicios publicos e internos. Maneja:

- Enrutamiento de trafico (reverse proxy) por path
- Terminacion SSL/TLS
- Cache (assets de MapaLab y respuestas OGC de GeoServer)
- Rate limiting por IP
- Inyeccion opcional de Google Tag Manager
- Hosting de archivos estaticos (frontend de SIEEJ, robots.txt, sitemap.xml)
- Logging estructurado (JSON) y envio a Loki
- Metricas para Prometheus
- Proteccion contra bots y control de acceso (Referer, User-Agent)

**Repositorio:** `git@github.com:iieg-oficial/gateway-hub.git`
**Ramas:** `develop` (desarrollo activo), `production` (produccion)
**Licencia:** MIT - IIEG Jalisco
**Versionado:** repo con `VERSION` + `docs/CHANGELOG.md` (SemVer), independiente del de Nginx.

---

## 2. Estructura del Proyecto

```
gateway-hub/
├── certs/                          # Certificados SSL (self-signed en dev)
├── docs/
│   ├── arquitectura.mmd            # Diagrama de arquitectura (Mermaid)
│   ├── auditoria-seguridad.md      # Comparativa de seguridad web: sitio anterior vs actual
│   ├── CHANGELOG.md                # Historial de cambios del repo (SemVer)
│   ├── context.md                  # Este archivo
│   ├── ecosystem.md                # Vista transversal IIEG: flujos cruzados y deuda coordinada
│   ├── error-pages.md              # Documentacion de paginas de error
│   ├── minerva.md                  # Propuesta SSO/IAM centralizado (Authentik) — futuro
│   ├── recursos-servidores.md      # Hardware y recursos por entorno (GCP y produccion)
│   ├── rendimiento.md              # Rate limiting, cache, capacidades y limites
│   ├── rutas-reservadas.md         # Namespaces del dominio y reglas para la app raiz de terceros
│   ├── ssh-deploy-keys.md          # Guia de configuracion de llaves SSH
│   ├── componentes.mmd             # Diagrama de componentes por repo (Mermaid)
│   ├── puertos-produccion.mmd      # Diagrama de conectividad por puertos (Mermaid)
│   └── pendientes/
│       ├── checklist-produccion-gcp.md
│       ├── evaluacion-k3s.md
│       ├── perfiles-tuning-multientorno.md
│       ├── rename-api-mariachi.md
│       └── reorganizacion-y-puertos.md
├── nginx/
│   ├── version.json                # Payload JSON servido en /ontoy
│   ├── templates/
│   │   ├── nginx.conf.template     # Configuracion principal (envsubst para REAL_IP_FROM)
│   │   └── gateway.conf.template   # Server block principal (envsubst para hosts/SSL/GTM/SEO)
│   ├── conf.d/
│   │   └── geoserver-upstream.conf.template  # Upstream, zona y cache de GeoServer
│   ├── includes/
│   │   ├── proxy-params.inc        # Headers estandar de proxy
│   │   ├── security-headers.inc    # 9 headers de seguridad (HSTS, CSP, etc.)
│   │   ├── bot-protection.inc      # Bloqueo de bots, scrapers y crawlers IA
│   │   ├── geoserver-locations.inc # Location blocks de GeoServer
│   │   ├── geoserver-hide-headers.inc  # Headers a ocultar de GeoServer
│   │   ├── basic-auth.inc          # Plantilla de auth basic (disponible, sin uso actual)
│   │   └── gtm.inc.template        # Google Tag Manager (condicional, generado en runtime)
│   ├── error-pages/                # Paginas de error personalizadas (400, 401, 403, 404, 429, 500)
│   └── static/                     # robots.txt, sitemap.xml, .well-known/security.txt
├── scripts/
│   ├── check-model-drift.py        # AST diff entre modelos SQLAlchemy mapalab/mariachi
│   ├── gen-version-json.sh         # Genera nginx/version.json desde VERSION + CHANGELOG
│   ├── setup-swap.sh               # Provisiona swap en la VM
│   ├── stress_test.py              # Stress test de carga
│   └── stress_test_multi_ip.py     # Stress test con multiples IPs de origen
├── docker-compose.yml              # Orquestacion de contenedores
├── Dockerfile                      # Imagen Nginx + entrypoint personalizado
├── Makefile                        # up/deploy/down + ecosystem-up/down/deploy/status
├── VERSION                         # Version del repo (SemVer)
├── .env                            # Variables de entorno (dev)
└── .env.example                    # Plantilla de variables
```

---

## 3. Contenedores (docker-compose.yml)

| Servicio | Imagen | Puertos | Funcion |
|----------|--------|---------|---------|
| `nginx` | Build local (`nginx:1.28.2-alpine`) | 80, 443 | Proxy inverso principal |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter` | — (solo red interna) | Metricas Prometheus via `/stub_status` |

**Red:** `iieg-network` (externa, compartida con todos los servicios IIEG)
**Bind mount:** `${SIEEJ_DIST_PATH}` → `/usr/share/nginx/html/sieej` (read-only) — el `dist/`
del frontend de SIEEJ se sirve directamente como estatico.
**Healthcheck:** `curl -fsk https://localhost/` cada 30s.
**extra_hosts:** `host.docker.internal:host-gateway` para alcanzar servicios en el host.
**Logs:** nginx emite access (JSON) a `/dev/stdout` y error a `/dev/stderr`. El `alloy` del stack `huachicol` (red `monitoring`) los recolecta via socket Docker y los publica a Loki con label `container_name=gateway-hub-nginx-1` (desde gateway-hub `1.24.15`, antes habia un servicio `promtail` propio).

---

## 4. Variables de Entorno

| Variable | Ejemplo (dev) | Descripcion |
|----------|---------------|-------------|
| `APP_DOMAIN` | `iieg.local` | Dominio/IP publico del gateway |
| `GTM_ID` | (vacio) | ID de Google Tag Manager. Si esta vacio, no se inyecta GTM |
| `SSL_CERTIFICATE` | `/etc/nginx/certs/cert.pem` | Ruta al certificado SSL dentro del contenedor |
| `SSL_CERTIFICATE_KEY` | `/etc/nginx/certs/key.pem` | Ruta a la llave privada |
| `SSL_VOLUME_PATH` | `./certs:/etc/nginx/certs:ro` | Mapeo de volumen host:contenedor |
| `PORTAL_HOST` | `mariachi-nginx:80` | Host del Portal — apunta al nginx de MARIACHI (ver nota) |
| `MAPALAB_HOST` | `mapalab-nginx-1:80` | Host de MapaLab (nginx interno) |
| `ACERVO_HOST` | `acervo-seaweedfs:8333` | Host de Acervo (API S3 de SeaweedFS) |
| `MARIACHI_HOST` | `mariachi-nginx:80` | Host de MARIACHI |
| `GEOSERVER_HOST` | `host.docker.internal:8080` | Host de GeoServer |
| `HUACHICOL_HOST` | `grafana:3000` | Host de Grafana (Huachicol) |
| `SIEEJ_DIST_PATH` | `../sieej/frontend/dist` | Ruta host al `dist/` de SIEEJ montado como estatico |
| `REAL_IP_FROM` | `10.13.128.0/24` | CIDR confiable para `set_real_ip_from` en `nginx.conf` (FortiGate estatal). Renderizado via envsubst en runtime |
| `SEO_ENABLED` | `false` | `true`: robots.txt permite crawlers, sitemap activo. `false`: bloquea indexacion |

**Nota sobre `PORTAL_HOST`:** el upstream se llama `portal` por motivos historicos, pero
apunta al nginx de MARIACHI. MARIACHI es el CMS/admin que tambien sirve el portal publico
del IIEG. El rename portal → mariachi quedo a medias intencionalmente (ver `ecosystem.md`).

> En la version 1.24.10 se elimino la consola web de Acervo (`upstream acervo_console`,
> rutas `/acervo/console/` y la variable `ACERVO_CONSOLE_HOST`): Acervo migro de MinIO a
> SeaweedFS y su Filer UI no tiene auth propia, asi que no se expone por el gateway. La
> administracion de archivos se hace por `mc`/CLI.

---

## 5. Enrutamiento - Todas las Rutas

Servidor `:80` redirige todo a HTTPS (302/301), excepto los endpoints `/ontoy` (para que
los probes internos los alcancen sin redirect). Servidor `:443` hace el enrutamiento real.

| Ruta | Upstream / Destino | Acceso | Rate Limit | Notas |
|------|--------------------|--------|------------|-------|
| `= /` | redirige 302 → `/mapalab/` | Publico | — | |
| `location /` | portal (MARIACHI) | Publico | general (burst 20) | Portal publico, bot-protection |
| `/api/` | portal (MARIACHI) | Publico | api (burst 20) | API del Portal, `Cache-Control: no-store` |
| `^~ /api/administrador/acervo/thumb` | portal (MARIACHI) | Publico | acervo_thumb (burst 120) | Miniaturas WebP; NO fuerza `no-store` para que el navegador cachee |
| `^~ /api/administrador/acervo` | portal (MARIACHI) | Publico | api (burst 20) | Uploads al Acervo (max 1GB, sin request buffering, timeout 600s) |
| `= /mapalab/api/layers/refresh-cache` | — | — | — | `return 403` (uso interno via iieg-network) |
| `= /mapalab/api/layers/invalidate-cache` | — | — | — | `return 403` (uso interno via iieg-network) |
| `/mapalab/assets/` | mapalab | Publico | static (burst 200) | Cache gateway 7d, immutable, stale serving |
| `/mapalab/api/download/` | mapalab | Publico | api (burst 5) | Descargas CSV (timeout 600s, sin buffering) |
| `^~ /mapalab/mcp` | mapalab | Publico | general (burst 20) | Servidor MCP: sin bot-protection, sin buffering ni cache (timeout 600s) |
| `/mapalab/` | mapalab | Publico | general (burst 150) | Visor de mapas (timeout 120s, `X-Robots-Tag` segun SEO) |
| `^~ /acervo/thumb/` | portal (MARIACHI) | Publico | acervo_thumb (burst 120) | Miniaturas WebP on-the-fly servidas por mariachi-api, no SeaweedFS. Solo buckets publicos |
| `/acervo/` | acervo (SeaweedFS) | Publico | static (burst 200) | API S3 (max 1GB, timeout 300s, sin buffering). `Content-Disposition: attachment` para `.txt`/`.xlsx` |
| `^~ /mariachi/assets/` | mariachi | Publico | static (burst 200) | Assets del admin, `immutable` 1 ano |
| `/mariachi/` | mariachi | Auth propia | general (burst 20) | CMS / admin del ecosistema |
| `^~ /colibri/` | portal (MARIACHI) | Publico | static (burst 200) | Widget embebible y docs de Colibri (reservado en 1.28.0) |
| `= /sieej` | redirige 301 → `/sieej/` | Publico | — | |
| `^~ /sieej/assets/` | estatico (`dist/` montado) | Publico | static (burst 200) | `immutable` 1 ano |
| `/sieej/` | estatico (`dist/` montado) | Publico | static (burst 200) | SPA: `try_files` con fallback a `index.html`, `no-store` |
| `/huachicol/public/` | huachicol | Publico | — | Dashboards publicos de Grafana, cache 7d immutable |
| `/huachicol/` | huachicol | Auth propia | huachicol (burst 200) | Grafana (auth propia, soporta WebSocket) |
| `/geoserver/web`, `/rest`, `/j_spring_security` | geoserver | Auth propia | general (burst 20) | Admin / REST / auth de GeoServer |
| `/geoserver/ows` | geoserver | Publico* | geoserver_download (burst 10) | WMS/WFS/WCS (cache 6h, validacion referer+UA, bloqueo WFS-T) |
| `/geoserver/(wfs\|wcs)` | geoserver | Publico* | geoserver_download (burst 10) | WFS/WCS directo (timeout 600s, cache 6h, validacion) |
| `/geoserver/{ws}/(wfs\|wcs)` | geoserver | Publico* | geoserver_download (burst 10) | WFS/WCS por workspace (timeout 600s, sin cache, validacion) |
| `/geoserver/` (catch-all) | geoserver | — | — | Resto de paths GeoServer (timeout 120s) |
| `/ontoy` | `version.json` | Publico | — | JSON `{slug,label,version}` del gateway |
| `/geoserver/ontoy` | inline `return 200` | Publico | — | JSON de version de GeoServer (hardcoded) |
| `/acervo/ontoy` | inline `return 200` | Publico | — | JSON de version de Acervo (hardcoded; bumpear al cambiar `static_version`) |
| `/huachicol/ontoy` | inline `return 200` | Publico | — | JSON de version de Huachicol (hardcoded) |
| `/sieej/ontoy` | `ontoy.json` del dist | Publico | — | JSON de version de SIEEJ |
| `/robots.txt` | static | Publico | — | `SEO_ENABLED=true`: permite crawlers. `false`: `Disallow /` |
| `/sitemap.xml` | static | Publico | — | `SEO_ENABLED=true`: sirve sitemap. `false`: 404 |
| `/.well-known/` | static | Publico | — | Incluye `security.txt` |
| `/.` (archivos ocultos) | — | — | — | `deny all` |

\* *Publico con restricciones: validacion dinamica de Referer (mismo `$host`, `localhost` o
Referer vacio), bloqueo de User-Agents (bots, scrapers, curl, wget, herramientas, IA),
bloqueo de WFS-T (`request=Transaction` → 403).*

> **`/administrador/` quedo liberada en `1.28.1`.** Era la URL antigua del panel admin
> (renombrado a `/mariachi` en mariachi v0.21.0; trafico 0 en 14 dias de Loki). Ya no
> tiene location propia: cae al catch-all, asi que al ceder `location /` a la app raiz
> de terceros pasara a ella. **No confundir con `/api/administrador/`**, que sigue
> reservado bajo `/api/` y lo consumen el panel admin, el frontend publico de SIEEJ, el
> widget de Colibri y mapalab. Su renombrado a `/api/mariachi` esta planeado en
> [`pendientes/rename-api-mariachi.md`](pendientes/rename-api-mariachi.md).
>
> El inventario completo de namespaces de primer nivel, con las reglas de integracion
> para la app raiz de terceros, vive en [`rutas-reservadas.md`](rutas-reservadas.md).

---

## 6. Seguridad

### SSL/TLS
- Protocolos: TLSv1.2 y TLSv1.3 unicamente
- Cifrados: ECDHE (AES-GCM) modernos, `ssl_prefer_server_ciphers off`
- HSTS: `max-age=31536000; includeSubDomains; preload`
- OCSP Stapling habilitado (resolvers Google DNS `8.8.8.8`, `8.8.4.4`)
- `ssl_session_cache shared:SSL:10m`, tickets off
- Redireccion HTTP → HTTPS automatica
- HTTP/2 habilitado en `:443`

### Headers de Seguridad (`security-headers.inc`)
Nueve headers aplicados en el server `:443`:

- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(self), camera=(), microphone=(), payment=(), usb=()`
- `Cross-Origin-Opener-Policy: same-origin`
- `X-Permitted-Cross-Domain-Policies: none`
- `Content-Security-Policy`: `default-src 'self'` + whitelist para Google Tag Manager /
  Analytics, Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`) y tiles de CartoDB.
  Incluye `upgrade-insecure-requests`, `object-src 'none'`, `frame-ancestors 'self'`.

### Real IP
`nginx.conf.template` define `set_real_ip_from ${REAL_IP_FROM}` con `real_ip_header X-Forwarded-For`
y `real_ip_recursive on`. El CIDR se inyecta en runtime via envsubst desde `REAL_IP_FROM` en
`.env` (default `10.13.128.0/24`, el rango del FortiGate estatal). En GCP/prod el FortiGate
reenvia la IP real del cliente en `X-Forwarded-For`; esto la recupera para logs y rate limiting.

### Control de Acceso
- **Autenticacion delegada:** los endpoints administrativos (Grafana, GeoServer admin,
  MARIACHI) dependen de la autenticacion propia de cada servicio. El gateway no impone
  restriccion por IP — el control de acceso a la VPN lo hace el FortiGate aguas arriba.
- **Validacion de Referer:** en endpoints OGC de GeoServer, via `if` + captura de regex
  (no `valid_referers`, que no expande `$host`).
- **Filtrado de User-Agent:** bloquea bots, scrapers, herramientas CLI y crawlers de IA.
- **Bloqueo de WFS-T:** dos capas combinadas: (a) `limit_except GET HEAD OPTIONS { deny all; }`
  rechaza con `405` cualquier metodo que no sea de lectura sobre `/geoserver/ows|wfs|wcs`,
  cubriendo el POST XML estandar de WFS-T; (b) `if ($arg_request ~* "Transaction")` retorna
  `403` si alguien intenta el bypass por query string (`?request=Transaction`).
- **Endpoints admin de MapaLab:** `/mapalab/api/layers/refresh-cache` e
  `/invalidate-cache` retornan 403 en el gateway. MARIACHI los invoca directo via
  `iieg-network` con el header `X-Internal-Token` (ver `ecosystem.md` § 5.3).
- **Rate Limiting:** ver seccion 7.

### Proteccion contra bots (`bot-protection.inc`)
Cuatro bloques `if` sobre `$http_user_agent` que retornan 403:
1. Scrapers y herramientas (scrapy, httpclient, mechanize, httrack, nikto, etc.)
2. Crawlers de IA y bots SEO agresivos (GPTBot, ClaudeBot, CCBot, SemrushBot, AhrefsBot, etc.)
3. Librerias HTTP CLI (`^curl`, `^wget`, python-requests, aiohttp)
4. User-Agent vacio

Se incluye en las rutas publicas (`/`, `/api/`, `/mapalab/`,
`/mapalab/api/download/`). Nota: `/mapalab/mcp` queda **fuera** a proposito — es un
endpoint de servidor MCP y sus clientes son herramientas, no navegadores.
GeoServer tiene su propio filtrado mas estricto en
`geoserver-locations.inc`. Permite navegadores reales y bots SEO legitimos (Googlebot, Bingbot).

### Paths Denegados
- `/.` (archivos ocultos) → `deny all`

---

## 7. Rate Limiting

Zonas definidas por `$binary_remote_addr` (IP del cliente). `limit_req_status 429`.

| Zona | Definida en | Rate | Uso |
|------|-------------|------|-----|
| `general` | `nginx.conf` | 10 r/s | Portal, `/mapalab/`, `/mapalab/mcp`, `/mariachi/`, GeoServer admin |
| `api` | `nginx.conf` | 10 r/s | `/api/`, `/api/administrador/acervo`, `/mapalab/api/download/` |
| `static` | `nginx.conf` | 50 r/s | `/mapalab/assets/`, `/acervo/`, `/mariachi/assets/`, `/colibri/`, `/sieej/` |
| `huachicol` | `nginx.conf` | 30 r/s | `/huachicol/` |
| `acervo_thumb` | `nginx.conf` | 30 r/s | `/acervo/thumb/`, `/api/administrador/acervo/thumb` — zona propia para no ahogar el API con la rafaga de miniaturas por pagina |
| `geoserver_download` | `conf.d/geoserver-upstream.conf.template` | 10 r/s | `/geoserver/ows`, `/wfs`, `/wcs` y por workspace |

El `burst` se ajusta por ruta (ver tabla de enrutamiento). El exceso responde **HTTP 429**
con la pagina de error amigable (countdown de 10s antes de habilitar el reintento).

---

## 8. Cache

### MapaLab Assets Cache
- **Zona:** `mapalab_assets` (`keys_zone=mapalab_assets:5m`)
- **Ubicacion:** `/var/cache/nginx/mapalab_assets`
- **Tamano maximo:** 500MB · **inactive:** 7 dias
- **TTL:** `proxy_cache_valid 200 7d`
- **Stale serving:** en `error timeout updating http_500 http_502 http_503 http_504`
- **Cache-Control al cliente:** `public, max-age=31536000, immutable`
- **Header:** `X-Cache-Status` (HIT/MISS/STALE)
- Los assets de Vite usan hash en el nombre, por lo que deploys nuevos generan cache keys nuevas.

### GeoServer Cache
- **Zona:** `geoserver_cache` (`keys_zone=geoserver_cache:20m`)
- **Ubicacion:** `/var/cache/nginx/geoserver`
- **Tamano maximo:** 2GB · **inactive:** 12h
- **TTL:** `proxy_cache_valid 200 6h`
- **Cache key:** `$request_uri$arg_outputFormat`
- **Lock:** habilitado (`proxy_cache_lock_timeout 10s`) para evitar thundering herd
- **Bypass / no_cache:** `GetFeatureInfo`, `GetCapabilities`, `DescribeFeatureType`
  (via map `$geoserver_no_cache`)
- **Header:** `X-Cache-Status` (HIT/MISS/BYPASS)
- Aplica a `/geoserver/ows` y `/geoserver/(wfs|wcs)`. Los WFS/WCS por workspace **no** cachean.

---

## 9. Logging y Monitoreo

### Access Logs
- **Formato JSON** (`json_logs`, `escape=json`): `time`, `remote_addr`, `request_method`,
  `request_uri`, `status`, `body_bytes_sent`, `http_referer`, `http_user_agent`,
  `request_time`, `upstream_response_time`, `upstream_addr`, `upstream_cache_status`.
- **Destino:** unicamente `/dev/stdout` (JSON) y `/dev/stderr` (errores). Sin archivo en disco.

### Recoleccion → Loki (via Alloy, desde gateway-hub 1.24.15)
- El stack `huachicol` corre `alloy` (`grafana/alloy:v1.16.1`) que lee logs Docker via socket
  y los pushea a Loki con label `container_name=gateway-hub-nginx-1` y `job=docker`. No requiere
  configuracion local en este repo.
- Para queries en Grafana: `{container_name="gateway-hub-nginx-1"}` o `|~ "\"request_uri\":\"/mapalab/"`
  para filtrar por ruta. El parseo JSON estructurado (extraer `subroute` como label) se quito junto
  con el promtail propio; si se necesita, se reactiva en la pipeline de alloy o en una query LogQL.

### Prometheus
- `nginx-exporter` consume `http://nginx:8080/stub_status`.
- El server interno `:8080` expone `/stub_status` con `allow 127.0.0.1` + `allow 172.16.0.0/12`.

---

## 10. Entrypoint del Contenedor

El `Dockerfile` (`nginx:1.28.2-alpine` + `gettext` para `envsubst`) define un `CMD` que
ejecuta en orden:

1. **Genera `nginx.conf`** desde `nginx.conf.template` con `envsubst` sobre `${REAL_IP_FROM}`.
   Whitelist explicita para no tocar variables nginx (`$remote_addr`, `$binary_remote_addr`, etc).
2. **Procesa los templates de `conf.d/`** (`geoserver-upstream.conf.template`) con `envsubst`
   sustituyendo `${GEOSERVER_HOST}` → escribe en `/etc/nginx/conf.d/`.
3. **Genera `gateway.conf`** desde `gateway.conf.template` con `envsubst` sobre todas las
   variables (`PORTAL_HOST`, `MAPALAB_HOST`, `ACERVO_HOST`, `MARIACHI_HOST`,
   `GEOSERVER_HOST`, `HUACHICOL_HOST`, `APP_DOMAIN`, `SSL_*`, `GTM_ID`, `SEO_ENABLED`).
4. **Genera `gtm.inc`**: si `GTM_ID` tiene valor, procesa `gtm.inc.template`; si no, crea
   el include vacio.
5. **Inicia Nginx** en foreground (`daemon off`).

---

## 11. Upstreams Definidos

| Nombre | Variable de Host | Definido en | Keepalive | Notas |
|--------|------------------|-------------|-----------|-------|
| `portal` | `PORTAL_HOST` | `gateway.conf.template` | 32 | Apunta al nginx de MARIACHI (portal publico) |
| `mapalab` | `MAPALAB_HOST` | `gateway.conf.template` | 32 | Visor de mapas (nginx interno) |
| `acervo` | `ACERVO_HOST` | `gateway.conf.template` | 32 | Storage S3 (SeaweedFS) |
| `mariachi` | `MARIACHI_HOST` | `gateway.conf.template` | 32 | CMS / admin del ecosistema |
| `huachicol` | `HUACHICOL_HOST` | `gateway.conf.template` | 32 | Grafana |
| `geoserver` | `GEOSERVER_HOST` | `conf.d/geoserver-upstream.conf.template` | 64 | Servicios OGC (`keepalive_requests 1000`) |

Todos con `keepalive_timeout 60s`. El upstream `acervo_console` fue **eliminado** junto con
las rutas de la consola MinIO (Acervo migro a SeaweedFS, sin consola web).

---

## 12. Ecosistema IIEG - Proyectos Conectados

Todos los proyectos viven en `/IIEG/` y comparten la red Docker externa `iieg-network`.

### MARIACHI (`/IIEG/mariachi/`)
- **Rutas:** `location /`, `/api/`, `/colibri/` y `/acervo/thumb/` (como upstream `portal`) y `/mariachi/`.
- **Que es:** nucleo del ecosistema — CMS del portal publico + panel de administracion +
  API central que administra Portal, MapaLab y SIEEJ. Emite la autenticacion compartida.
- **Stack:** admin React + Ant Design, API FastAPI, PostgreSQL (`mariachi`), Redis, cron.
- **Containers:** `mariachi-nginx`, `mariachi-api`, `mariachi-postgres`, `mariachi-redis`,
  `mariachi-cron-sieej`.

### MapaLab (`/IIEG/mapalab/`)
- **Ruta:** `/mapalab/`
- **Stack:** React 19 (Vite) + FastAPI (Gunicorn/Uvicorn) + nginx interno. Datos en
  PostgreSQL/PostGIS (dataengine) y GeoServer.
- **Containers (staging/prod):** `mapalab-nginx`, `mapalab-backend`.
- **Redes:** `mapalab-network` (interna) + `iieg-network`.

### Acervo (`/IIEG/acervo/`)
- **Ruta:** `/acervo/` (API S3)
- **Stack:** **SeaweedFS 4.23** (almacenamiento S3-compatible). Migrado desde MinIO.
- **Container:** `acervo-seaweedfs` (API S3 en `:8333`). **No tiene consola web.**
- **Buckets:** separados por sistema (portal, mapalab, sieej, mariachi, iieg, dataengine).

### GeoServer (`/IIEG/geoserver/`)
- **Ruta:** `/geoserver/`
- **Imagen:** `kartoza/geoserver:2.27.0` · **Container:** `geoserver` (`:8080`)
- **Servicios OGC:** WMS, WFS, WCS. Plugins GeoPackage incluidos.
- **Base de datos:** PostgreSQL/PostGIS (dataengine).

### SIEEJ (`/IIEG/sieej/`)
- **Ruta:** `/sieej/` — el gateway lo sirve como **estatico** desde el `dist/` montado.
- **Que es:** Sistema de Informacion Estadistica del Estado de Jalisco — frontend de
  captura de datos por dependencias.
- **Stack:** React 19 + Vite + Tailwind. No tiene compose propio de produccion: genera
  genera `frontend/dist/` y el gateway lo monta. El backend vive en `mariachi/api` (schema `sieej`).

### Huachicol (`/IIEG/huachicol/`) — Stack de Observabilidad
- **Ruta:** `/huachicol/` (Grafana) y `/huachicol/public/` (dashboards publicos)
- **Componentes:** Prometheus, Grafana, Loki, AlertManager (alertas a Discord), Alloy,
  Node Exporter, cAdvisor, `nginx-auth` (auth proxy para Prometheus/Loki).
- **Red:** `monitoring` (interna) + `iieg-network`. Retencion: 30 dias.

### MapaLab DataEngine (`/IIEG/dataengine/`)
- **Stack:** PostgreSQL + PostGIS 3.6, PgBouncer (pooler), backups semanales a Acervo,
  container `jobs` con cron de refresh (periodicidad 03:00, layer_tree 04:00, stats 04:30 UTC).
- **No pasa por el gateway** — acceso directo via `iieg-network` desde mapalab/mariachi/geoserver.

### IGIBot (`/IIEG/igibot/`)
- **Stack:** chatbot LLM, backend Python + frontend, desplegado en **K3s/Kubernetes** con
  Traefik ingress.
- **URL:** `https://igibot.jalisco.gob.mx` — **NO pasa por gateway-hub** (cluster separado).

### Otros proyectos en `/IIEG/`
`REPD` (Registro Estatal de Personas Desaparecidas), `intranet` (sistema web interno, no
detras del gateway), `frigate`, `urlschiquitas`, `estilos-coropleticos-mapalab`,
`DevAgents-main`, `utils`, `docs`. No estan enrutados por el gateway.

---

## 13. Arquitectura de Red

```
Internet / Usuarios
        |
        v
   FortiGate estatal  (VPN + X-Forwarded-For + WAF)
        |
        v
  ┌─────────────────────────────────────────────────┐
  │  Gateway Hub (Nginx, S1)                         │
  │  Puertos: 80 (HTTP->HTTPS), 443 (HTTPS)          │
  │  Red: iieg-network                               │
  └──┬──────┬──────┬──────┬──────┬──────┬────────────┘
     │      │      │      │      │      │
     v      v      v      v      v      v
  Portal  MapaLab Acervo  Geo-   Mariachi Huachicol
 (Mariachi nginx) (Seaweed Server  (CMS)  (Grafana)
            │      FS)      │
            │               │
            v               v
      ┌──────────────────────┐
      │ PostgreSQL/PostGIS    │
      │ (dataengine)  │  <- acceso directo, no via gateway
      └──────────────────────┘

  SIEEJ -> servido como estatico desde el propio gateway (dist/ montado)

  [Separado - K3s]
  IGIBot (igibot.jalisco.gob.mx)
```

---

## 14. Flujo de Templates

El sistema de configuracion es **template-based** (ver seccion 10):

1. Los archivos `.template` en `nginx/templates/` y `nginx/conf.d/` usan variables `${VAR}`.
2. El entrypoint ejecuta `envsubst` sustituyendo variables del `.env`. Cada `envsubst` usa
   **whitelist explicita** del subset de variables aplicables, para no tocar accidentalmente
   las variables de nginx en runtime (`$remote_addr`, `$binary_remote_addr`, `$request_uri`, etc).
3. `nginx.conf.template` se procesa con `${REAL_IP_FROM}` y se escribe en `/etc/nginx/nginx.conf`.
4. Los `.conf.template` de `conf.d/` se procesan con `${GEOSERVER_HOST}` (zona/upstream geoserver)
   y se escriben en `/etc/nginx/conf.d/`.
5. `gateway.conf.template` se procesa con los hosts upstream + SSL + GTM + SEO.
6. `gtm.inc` se genera solo si `GTM_ID` tiene valor; si no, se crea vacio.

**Importante:** los includes `.inc` (no templates) se copian tal cual en la imagen y se
referencian con `include`. Solo `gtm.inc.template`, `nginx.conf.template` y los `.conf.template`
se procesan en runtime.

---

## 15. Notas para Desarrollo

- **Agregar un nuevo servicio:** crear upstream en `gateway.conf.template`, agregar la
  variable de host en `.env`/`.env.example`, agregar el `location` block, agregar la
  variable a la lista de `envsubst` del `Dockerfile`, y una zona de rate limit si aplica.
- **Cache:** solo MapaLab assets y GeoServer tienen cache. Para otro servicio, definir la
  zona en `nginx.conf.template` y configurarla en el `location`.
- **Logs:** todos los access logs son JSON a `/dev/stdout`; el `alloy` del stack `huachicol`
  los recolecta automaticamente via socket Docker y los pushea a Loki.
- **SSL en dev:** certificados self-signed en `certs/`. En produccion se montan certificados
  reales (wildcard `*.jalisco.gob.mx` de DigiCert) via volumen.
- **Docker network:** todo servicio enrutado DEBE estar en `iieg-network`.
- **`host.docker.internal`:** para alcanzar servicios en el host o en otro compose; se mapea
  via `extra_hosts` en `docker-compose.yml`.
- **Endpoints `/ontoy`:** sirven JSON de version para que el dashboard de plataformas de
  MARIACHI verifique el estado del ecosistema. Los de GeoServer y Acervo estan hardcodeados
  inline en `gateway.conf.template` — al cambiar el `static_version` de esos repos hay que
  actualizar el `return 200` y bumpear gateway-hub.
- **Despliegue:** en la VM de produccion solo se ejecuta (`git pull`, `make deploy`);
