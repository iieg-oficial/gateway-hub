# Gateway Hub

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

## Variables de entorno

Ver `.env.example` para la referencia completa. Las variables principales:

| Variable | Descripcion |
|----------|-------------|
| `APP_DOMAIN` | Dominio/IP publico del gateway |
| `GTM_ID` | ID de Google Tag Manager (opcional) |
| `SSL_CERTIFICATE` | Ruta al certificado SSL |
| `SSL_CERTIFICATE_KEY` | Ruta a la llave privada |
| `PORTAL_HOST` | Host del Portal |
| `MAPALAB_HOST` | Host de MapaLab |
| `ACERVO_HOST` | Host de Acervo (MinIO API) |
| `GEOSERVER_HOST` | Host de GeoServer |
| `HUACHICOL_HOST` | Host de Grafana |
| `LOKI_URL` | Endpoint de Loki |

## Servicios (contenedores)

| Servicio | Funcion |
|----------|---------|
| `nginx` | Proxy inverso principal (puertos 80, 443) |
| `nginx-exporter` | Metricas Prometheus via /stub_status |
| `promtail` | Reenvio de logs JSON a Loki |

## Enrutamiento

| Ruta | Upstream | Acceso |
|------|----------|--------|
| `/` | Portal | Publico |
| `/api/` | Portal | Publico |
| `/mapalab/` | MapaLab | Publico |
| `/acervo/` | Acervo (MinIO) | Publico |
| `/acervo/console/` | MinIO Console | Auth propia |
| `/geoserver/ows` | GeoServer OGC | Publico (con restricciones) |
| `/geoserver/web/` | GeoServer Admin | Auth propia |
| `/mariachi/` | MARIACHI | Auth propia |
| `/huachicol/` | Grafana | Auth propia |

## Estructura del proyecto

```
gateway-hub/
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── certs/                      # Certificados SSL (self-signed en dev)
├── nginx/
│   ├── nginx.conf              # Configuracion principal
│   ├── templates/
│   │   └── gateway.conf.template
│   ├── conf.d/
│   │   └── geoserver-upstream.conf.template
│   ├── includes/               # Modulos reutilizables (.inc)
│   ├── error-pages/            # Paginas de error personalizadas
│   └── static/                 # robots.txt, sitemap.xml
├── promtail/
│   └── promtail-config.yml
└── docs/
```

## Stack

- **Proxy:** Nginx 1.28 (Alpine)
- **Monitoreo:** Prometheus (nginx-exporter) + Promtail → Loki
- **SSL:** TLSv1.2/1.3, HSTS, OCSP Stapling
- **Red:** `iieg-network` (compartida con todos los servicios IIEG)

## Documentacion

| Documento | Descripcion |
|-----------|-------------|
| [Contexto del proyecto](docs/context.md) | Referencia completa: arquitectura, enrutamiento, seguridad |
| [Paginas de error](docs/error-pages.md) | Paginas de error personalizadas del gateway |
| [Rendimiento](docs/rendimiento.md) | Rate limiting, cache, capacidades y limites |
| [Recursos de servidores](docs/recursos-servidores.md) | Hardware, memoria y configuracion por entorno |
| [Pendiente: Upgrade MapaLab](docs/pendientes/upgrade-mapalab-8cores.md) | Pasos a seguir cuando S2 suba a 8 cores / 16 GB |
| [SSH Deploy Keys](docs/ssh-deploy-keys.md) | Configuracion de llaves SSH para despliegue |
| [Arquitectura](docs/arquitectura.mmd) | Diagrama de arquitectura (Mermaid) |

## Licencia

MIT - IIEG Jalisco
