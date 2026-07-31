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
| `make up` | Gateway-hub: levanta sin rebuildear |
| `make deploy` | Gateway-hub: down + build + up. Usar tras cambios en config |
| `make down` | Gateway-hub: detener |
| `make ecosystem-up` | Levantar el ecosistema en orden topologico (filtrable con `STACKS=`) |
| `make ecosystem-down` | Detener el ecosistema en orden inverso (filtrable con `STACKS=`) |
| `make ecosystem-deploy` | Pull + down + deploy de todo el ecosistema (filtrable con `STACKS=`) |
| `make ecosystem-status` | Git, Docker y errores recientes en logs del ecosistema |
| `make ecosystem-push` | Push de la rama actual de cada repo, incluido context-ame-esta (filtrable con `STACKS=`) |

`sitio2026` entra al orquestador desde 1.41.0: va justo antes del gateway, porque ocupa `location /` y si no esta arriba la raiz responde 502. Su `make deploy` reconstruye en modo `gcp` — los prefijos del API viajan como build args del bundle, asi que levantarlo sin rebuild no basta.

`minerva` queda fuera y se levanta manualmente (`cd ../minerva && make up`).

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
| `SIEEJ_DIST_PATH` | Ruta host al `dist/` de SIEEJ que se monta como estatico (default `../sieej/frontend/dist`) |
| `REAL_IP_FROM` | CIDR confiable para `set_real_ip_from` (X-Forwarded-For). Default `<CIDR-interno>` (FortiGate estatal) |
| `SEO_ENABLED` | `true` en produccion (robots.txt, sitemap, sin noindex). `false` en dev (bloquea indexacion) |

> Acervo migro de MinIO a SeaweedFS, que no expone consola web: el `upstream
> acervo_console`, las rutas `/acervo/console/` y la variable `ACERVO_CONSOLE_HOST`
> se retiraron del gateway. La administracion de archivos se hace por `mc`/CLI.

## Servicios (contenedores)

| Servicio | Funcion |
|----------|---------|
| `nginx` | Proxy inverso principal (puertos 80, 443) |

Logs: nginx emite a `/dev/stdout` (JSON) y `/dev/stderr`, sin archivo en disco. La recoleccion hacia
Loki via Alloy quedo sin consumidor al apagarse el stack de observabilidad de huachicol el
2026-07-21; hoy la unica retencion es la del driver de logs de Docker.

## Enrutamiento

Inventario completo de namespaces de primer nivel y reglas de integracion para la
app raiz de terceros: `ecosistema/contratos.md` en el repositorio central de contexto.

| Ruta | Upstream / Destino | Acceso |
|------|--------------------|--------|
| `= /` | redirige (302) a `/mapalab/` | Publico |
| `location /` | Portal (MARIACHI) | Publico |
| `/api/` | Portal (MARIACHI) | Publico |
| `/api/administrador/acervo`, `/acervo/thumb/` | MARIACHI (miniaturas WebP) | Publico |
| `/mapalab/` | MapaLab | Publico |
| `/mapalab/assets/` | MapaLab | Publico (cache gateway) |
| `/mapalab/api/download/` | MapaLab | Publico (streaming) |
| `/mapalab/mcp` | MapaLab | Publico (sin bot-protection) |
| `/mapalab/api/layers/refresh-cache` | — | Bloqueado (403) |
| `/mapalab/api/layers/invalidate-cache` | — | Bloqueado (403) |
| `/acervo/` | Acervo (SeaweedFS S3) | Publico |
| `/mariachi/`, `/mariachi/assets/` | MARIACHI | Auth propia |
| `/colibri/` | MARIACHI (widget embebible) | Publico |
| `/sieej/`, `/sieej/assets/` | Estatico (`dist/` montado) | Publico |
| `/geoserver/ows`, `/wfs`, `/wcs`, `/{ws}/wfs`, `/{ws}/wcs` | GeoServer OGC | Publico (con restricciones) |
| `/geoserver/web`, `/rest`, `/j_spring_security` | GeoServer Admin | Auth propia |
| `/ontoy`, `/geoserver/ontoy`, `/acervo/ontoy`, `/huachicol/ontoy`, `/sieej/ontoy` | JSON de version | Publico |
| `/robots.txt`, `/sitemap.xml`, `/.well-known/` | Estatico | Publico |

> `/administrador/` quedo liberada en `1.28.1`: ya no tiene location propia y cae
> al catch-all. No confundir con `/api/administrador/`, que sigue reservado bajo
> `/api/` — su renombrado a `/api/mariachi` esta planeado en
> `historial/2026-07-gateway-rename-api-mariachi.md` del repositorio central.

## Estructura del proyecto

```
gateway-hub/
├── compose.yaml
├── Dockerfile                    # nginx:1.28.2-alpine + entrypoint con envsubst
├── Makefile                      # gateway + orquestacion del ecosistema
├── VERSION
├── .env.example
├── certs/                        # Certificados SSL (self-signed en dev)
├── nginx/
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
- **Monitoreo:** sondeo de `/ontoy` desde el monitor de huachicol. El `nginx-exporter` sigue
  levantado pero ya nadie lo scrapea
- **SSL:** TLSv1.2/1.3, HSTS, OCSP Stapling
- **Seguridad:** CSP, 9 headers de seguridad, bot protection (scrapers, crawlers IA, herramientas CLI)
- **Red:** `iieg-network` (externa, compartida con todos los servicios IIEG)

## Documentacion

| Documento | Descripcion |
|-----------|-------------|
| [CHANGELOG](docs/CHANGELOG.md) | Historial de cambios del repo |
| [Paginas de error](docs/error-pages.md) | Paginas de error personalizadas del gateway |
| [SSH Deploy Keys](docs/ssh-deploy-keys.md) | Configuracion de llaves SSH para despliegue |
| [Arquitectura](docs/arquitectura.mmd) | Diagrama de arquitectura (Mermaid) |
| [Componentes](docs/componentes.mmd) | Diagrama de componentes: containers por repo, sidecars version-api, flujos /ontoy (Mermaid) |
| [Puertos produccion](docs/puertos-produccion.mmd) | Diagrama de conectividad por puertos entre los 4 servidores de produccion (Mermaid) |

El contexto, los contratos y el trabajo pendiente viven en el repositorio central de contexto
(`iieg-oficial/context-ame-esta`):

| Tema | Donde |
|------|-------|
| Contexto del proyecto: que hace el proxy, servicios, variables, cache | `repos/gateway-hub/contexto.md` |
| Rutas reservadas del dominio y prefijos | `ecosistema/contratos.md` |
| Rendimiento: capacidades, limites y stress tests | `repos/gateway-hub/rendimiento.md` |
| Recursos por nodo y tuning por entorno | `ecosistema/topologia.md` |
| Pendientes: tuning multientorno, puertos, evaluacion de k3s, checklist GCP | `repos/gateway-hub/pendientes/` |
| Auditoria de seguridad, rename de `/api/administrador`, evaluacion de IdP | `historial/` |

## Licencia

MIT - IIEG Jalisco
