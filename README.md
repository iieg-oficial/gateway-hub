# Gateway Hub

**Version:** ver [`VERSION`](VERSION) y [`docs/CHANGELOG.md`](docs/CHANGELOG.md). El versionado del repo es independiente del de Nginx.

Proxy inverso central y terminador SSL/TLS de la infraestructura del IIEG Jalisco.
Punto unico de entrada para todos los servicios publicos e internos.

## Requisitos

- Docker >= v28.2.2
- Docker Compose >= v2.36.2
- Git >= 2.48

## Inicio rapido

### 1. Clonar y configurar

```bash
git clone git@github.com:iieg-oficial/gateway-hub.git
cd gateway-hub
cp .env.example .env
# Editar .env con tus valores (dominios, hosts, SSL, etc.)
```

### 2. Desarrollo (certificados self-signed)

```bash
docker compose up -d --build
# HTTPS: https://localhost
# HTTP:  http://localhost (redirige a HTTPS)
```

### 3. Produccion

```bash
# Montar certificados reales via SSL_VOLUME_PATH en .env
docker compose up -d --build
```

El `Makefile` ofrece dos niveles:

| Comando | Alcance |
|---------|---------|
| `make up` / `down` / `restart` / `logs` / `ps` | Solo gateway-hub. `up` usa la imagen actual (rapido) |
| `make deploy` | Solo gateway-hub: `docker compose up -d --build`. Usar tras cambios en `nginx/templates/`, `includes/`, `Dockerfile`, `.env`, etc. |
| `make build` | Solo rebuildea la imagen, sin levantar containers |
| `make ecosystem-up` / `ecosystem-down` / `ecosystem-restart` / `ecosystem-status` | Todo el stack production local (acervo, huachicol, dataengine, geoserver, sieej dist, mariachi, mapalab, gateway-hub) en orden topologico |

Los servicios `sitio2026` y `minerva` quedan fuera del orquestador y se levantan manualmente (`cd ../sitio2026 && make up ENV=gcp` y `cd ../minerva && make up` respectivamente).

## Variables de entorno

Ver `.env.example` para la referencia completa. Las variables principales:

| Variable | Descripcion |
|----------|-------------|
| `APP_DOMAIN` | Dominio/IP publico del gateway |
| `GTM_ID` | ID de Google Tag Manager (opcional; si esta vacio no se inyecta) |
| `SSL_CERTIFICATE` | Ruta al certificado SSL dentro del contenedor |
| `SSL_CERTIFICATE_KEY` | Ruta a la llave privada dentro del contenedor |
| `SSL_VOLUME_PATH` | Mapeo de volumen `host:contenedor:ro` para los certificados |
| `PORTAL_HOST` | Host del Portal (apunta al nginx de MARIACHI) |
| `MAPALAB_HOST` | Host de MapaLab |
| `ACERVO_HOST` | Host de Acervo (API S3 de SeaweedFS) |
| `MARIACHI_HOST` | Host de MARIACHI |
| `GEOSERVER_HOST` | Host de GeoServer |
| `HUACHICOL_HOST` | Host de Grafana |
| `SIEEJ_DIST_PATH` | Ruta host al `dist/` de SIEEJ que se monta como estatico (default `../sieej/frontend/dist`) |
| `REAL_IP_FROM` | CIDR confiable para `set_real_ip_from` (X-Forwarded-For). Default `10.13.128.0/24` (FortiGate estatal) |
| `SEO_ENABLED` | `true` en produccion (robots.txt, sitemap, sin noindex). `false` en staging/dev (bloquea indexacion) |

> Acervo migro de MinIO a SeaweedFS, que no expone consola web: el `upstream
> acervo_console`, las rutas `/acervo/console/` y la variable `ACERVO_CONSOLE_HOST`
> se retiraron del gateway. La administracion de archivos se hace por `mc`/CLI.

## Servicios (contenedores)

| Servicio | Funcion |
|----------|---------|
| `nginx` | Proxy inverso principal (puertos 80, 443) |
| `nginx-exporter` | Metricas Prometheus via `/stub_status` |

Logs: nginx emite a `/dev/stdout` (JSON) y `/dev/stderr`; el `alloy` del stack `huachicol` los recolecta automaticamente via socket Docker. No requiere promtail propio (eliminado en `1.24.15`).

## Enrutamiento

| Ruta | Upstream / Destino | Acceso |
|------|--------------------|--------|
| `/` | redirige (302) a `/mapalab/` | Publico |
| `location /` | Portal (MARIACHI) | Publico |
| `/api/` | Portal (MARIACHI) | Publico |
| `/administrador/` | Portal (MARIACHI) | Publico |
| `/mapalab/` | MapaLab | Publico |
| `/mapalab/assets/` | MapaLab | Publico (cache gateway) |
| `/mapalab/api/download/` | MapaLab | Publico (streaming) |
| `/mapalab/api/layers/refresh-cache` | — | Bloqueado (403) |
| `/mapalab/api/layers/invalidate-cache` | — | Bloqueado (403) |
| `/acervo/` | Acervo (SeaweedFS S3) | Publico |
| `/mariachi/` | MARIACHI | Auth propia |
| `/sieej/` | Estatico (`dist/` montado) | Publico |
| `/huachicol/` | Grafana | Auth propia |
| `/huachicol/public/` | Grafana | Publico (dashboards publicos) |
| `/geoserver/ows`, `/wfs`, `/wcs`, `/{ws}/wfs`, `/{ws}/wcs` | GeoServer OGC | Publico (con restricciones) |
| `/geoserver/web`, `/rest`, `/j_spring_security` | GeoServer Admin | Auth propia |
| `/ontoy`, `/geoserver/ontoy`, `/acervo/ontoy`, `/sieej/ontoy` | JSON de version | Publico |
| `/robots.txt`, `/sitemap.xml`, `/.well-known/` | Estatico | Publico |

## Estructura del proyecto

```
gateway-hub/
├── docker-compose.yml
├── Dockerfile                    # nginx:1.28.2-alpine + entrypoint con envsubst
├── Makefile                      # gateway + orquestacion del ecosistema
├── VERSION
├── .env.example
├── certs/                        # Certificados SSL (self-signed en dev)
├── nginx/
│   ├── version.json              # Payload de /ontoy
│   ├── templates/
│   │   ├── nginx.conf.template   # Configuracion principal (envsubst REAL_IP_FROM)
│   │   └── gateway.conf.template # Server block principal (envsubst hosts/SSL/GTM/SEO)
│   ├── conf.d/
│   │   └── geoserver-upstream.conf.template
│   ├── includes/                 # Modulos reutilizables (.inc / .inc.template)
│   ├── error-pages/              # Paginas de error personalizadas
│   └── static/                   # robots.txt, sitemap.xml, .well-known/
├── scripts/                      # check-model-drift, setup-swap, stress tests
└── docs/
```

## Stack

- **Proxy:** Nginx 1.28.2 (Alpine)
- **Monitoreo:** Prometheus (nginx-exporter) + Alloy (huachicol) → Loki
- **SSL:** TLSv1.2/1.3, HSTS, OCSP Stapling
- **Seguridad:** CSP, 9 headers de seguridad, bot protection (scrapers, crawlers IA, herramientas CLI)
- **Red:** `iieg-network` (externa, compartida con todos los servicios IIEG)

## Documentacion

| Documento | Descripcion |
|-----------|-------------|
| [Contexto del proyecto](docs/context.md) | Referencia completa: arquitectura, enrutamiento, seguridad |
| [Ecosistema IIEG](docs/ecosystem.md) | Vista transversal: flujos cruzados, acoplamientos, deuda coordinada |
| [CHANGELOG](docs/CHANGELOG.md) | Historial de cambios del repo |
| [Paginas de error](docs/error-pages.md) | Paginas de error personalizadas del gateway |
| [Rendimiento](docs/rendimiento.md) | Rate limiting, cache, capacidades y limites |
| [Recursos de servidores](docs/recursos-servidores.md) | Hardware, memoria y configuracion por entorno |
| [Auditoria de seguridad](docs/auditoria-seguridad.md) | Comparativa de seguridad web: sitio anterior vs actual |
| [Arquitectura](docs/arquitectura.mmd) | Diagrama de arquitectura (Mermaid) |
| [Componentes](docs/componentes.mmd) | Diagrama de componentes: containers por repo, sidecars version-api, flujos /ontoy (Mermaid) |
| [SSH Deploy Keys](docs/ssh-deploy-keys.md) | Configuracion de llaves SSH para despliegue |
| [Proyecto Minerva](docs/minerva.md) | Propuesta de SSO/IAM centralizado (Authentik) para el ecosistema |
| [Pendiente: Upgrade MapaLab](docs/pendientes/upgrade-mapalab-8cores.md) | Pasos cuando S2 suba a 8 cores / 16 GB |
| [Pendiente: Checklist produccion GCP](docs/pendientes/checklist-produccion-gcp.md) | Validacion y pendientes del despliegue en GCP |

## Licencia

MIT - IIEG Jalisco
