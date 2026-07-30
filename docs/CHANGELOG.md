# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato esta basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semantico](https://semver.org/lang/es/). El
versionado del repo `gateway-hub` es independiente del de Nginx; aqui registramos los
cambios sobre las rutas, certificados, headers de seguridad, rate limits y la
configuracion de promtail. Bumps por caracteristica registrada en commit.

## [No publicado]

---

## [1.35.1] - 2026-07-30

### Corregido: `/mapalab/api/ontoy` seguia alcanzable desde internet

mapalab 1.99.1 agrego un `deny all` sobre `= /mapalab/api/ontoy` en su propio nginx para cerrar
una exposicion a internet. **En produccion no surtia efecto.** El gateway reescribe el prefijo
antes de hacer proxy:

```nginx
rewrite ^/mapalab/(.*) /$1 break;
proxy_pass http://mapalab_backend;
```

La peticion llega al nginx de mapalab como `/api/ontoy`, que matchea su `location /api/` —sin
bloqueo— y el `deny` nunca se evalua. Verificado en produccion el 2026-07-30 tras desplegar
mapalab 1.100.0: `https://<dominio>/mapalab/api/ontoy` respondia **200**, exponiendo version,
`deployed_at` y los contadores de `client_errors` y `embeds`.

El bloqueo tiene que vivir aqui, donde se evalua **antes** del rewrite. Mismo patron que ya usaban
`refresh-cache` e `invalidate-cache`:

```nginx
location = /mapalab/api/ontoy {
    return 403;
}
```

**No sirve bloquearlo del lado de mapalab con `allow` por IP:** el gateway y `huachicol-monitor`
corren en el mismo nodo y llegan con la misma IP de origen. Solo el gateway distingue los dos
caminos.

#### Corregido

- `location = /mapalab/api/ontoy` devuelve **403**. El monitor no se ve afectado: sondea el puerto
  del nginx de mapalab directo, sin pasar por el gateway.

---

## [1.35.0] - 2026-07-30

### Agregado: `make ecosystem-push`

Cierra el ciclo de los targets `ecosystem-*`: ya se podia levantar, bajar, desplegar y ver el
estatus de todo el ecosistema desde aqui, pero para subir el trabajo habia que entrar repo por
repo. Cada uno vive en una rama distinta (`production`, `develop`, `main`), asi que el error
facil era pushear desde la rama equivocada.

`./scripts/ecosystem-push.sh` recorre los ocho repos del ecosistema mas `context-ame-esta` y
sube **la rama en la que cada uno esta parado**, con `push -u origin <rama>`. Reporta una tabla
con repo, rama y resultado.

- **Nunca `--force` ni `--all`.** Solo la rama actual de cada repo.
- **Omite** los repos al dia, los que no son repo git y los que estan en `HEAD` detached.
- **Avisa** al final si algun repo tiene cambios sin commitear, porque esos se quedan en local.
- Acepta el mismo filtro que el resto: `STACKS=mariachi,mapalab make ecosystem-push`.
- Sale con codigo distinto de cero si algun push falla.

---

## [1.34.1] - 2026-07-30

### Eliminado: el perfil staging de las pruebas de carga

El entorno staging se retiro de todo el ecosistema. En este repo no habia infraestructura de
staging que quitar —ningun `.conf`, ningun profile de compose, ningun target de `make`— pero si
quedaban dos rastros.

#### Eliminado

- El perfil `--env staging` y la variable `STRESS_TEST_STAGING_URL` de `scripts/stress_test.py` y
  `scripts/stress_test_multi_ip.py`. Quedan `local` y `production`.
- Permisos residuales de `.claude/settings.local.json` para `make staging`, `make down-staging` y
  `COMPOSE_PROFILES=staging`, que nunca correspondieron a targets ni profiles de este repo.

#### Cambiado

- La descripcion de `SEO_ENABLED` en el README ya no menciona staging.

---

## [1.34.0] - 2026-07-30

### Eliminado: `nginx-exporter`

El contenedor exponia las metricas de `stub_status` para que Prometheus las scrapeara. huachicol
retiro su stack de observabilidad en la 2.0.0 (2026-07-21) y desde entonces el exporter corria sin
un solo consumidor —el propio README lo documentaba asi—. Se retiran el servicio del compose y el
`server` de `stub_status` en el puerto 8080 de `nginx.conf.template`, que existia solo para
alimentarlo.

### Cambiado: nginx a 1.30.4-alpine

De `nginx:1.28.2-alpine`, vulnerable a **CVE-2026-42533** (CVSS 9.2, desbordamiento de heap con
posible ejecucion remota de codigo, parchado el 15 de julio de 2026), **CVE-2026-60005** (lectura de
memoria no inicializada en `ngx_http_slice_module`) y **CVE-2026-56434** (use-after-free en
`ngx_http_ssi_module`). La imagen se reconstruyo y las plantillas siguen resolviendo sin cambios.

### Nota de despliegue

`docker compose up -d --build` reconstruye nginx y elimina el contenedor `nginx-exporter`. Si queda
huerfano, `docker compose down --remove-orphans` lo limpia.

---

## [1.33.2] - 2026-07-29

### El contexto se movio al repo central y `HUACHICOL_HOST` se retiro

Documentacion y limpieza; sin cambios en el ruteo ni en los certificados.

#### Eliminado

- **Variable `HUACHICOL_HOST`** de `.env.example`, `docker-compose.yml` y la allowlist de
  `envsubst` del `Dockerfile`. Ninguna plantilla la usaba desde que se retiraron las `location`
  de Grafana: como el ecosistema prohibe defaults inline, el compose la exigia y quien levantara
  un entorno nuevo tenia que inventar un valor para un Grafana que ya no existe.
- `docs/context.md`, `ecosystem.md`, `rutas-reservadas.md`, `rendimiento.md`,
  `recursos-servidores.md`, `auditoria-seguridad.md`, `minerva.md` y `docs/pendientes/`
  completo. Su contenido vive ahora en el repositorio central de contexto
  (`iieg-oficial/context-ame-esta`): el contexto y el rendimiento en `repos/gateway-hub/`, las
  rutas reservadas en `ecosistema/contratos.md`, los recursos y el tuning por entorno en
  `ecosistema/topologia.md`, y la auditoria, el rename del prefijo y la evaluacion de IdP en
  `historial/`.

#### Corregido

- **README:** se retiraron las filas de `/huachicol/` hacia Grafana y las menciones a Alloy y
  Loki, que describian el stack apagado el 2026-07-21. El `nginx-exporter` queda anotado como
  **sin consumidor**: sigue en el compose pero ya nadie lo scrapea.
- Indice de documentacion del README: apuntaba a los ocho documentos migrados con enlaces
  rotos.

---

## [1.33.1] - 2026-07-28

### Navegar una carpeta de Recursos devolvia 429 y nunca cacheaba

Las dos `location` de `/api/*/geoserver/files` que agrego la 1.33.0 heredaron dos
cosas del patron equivocado: la zona `api` (10 r/s, compartida con todo el API) y
un `add_header Cache-Control "no-store" always`.

El grid de Recursos pide una miniatura por archivo, asi que abrir una carpeta de
simbologia —cientos de SVGs— agotaba el burst y devolvia **429**. Peor: el
`no-store` pisaba el `public, max-age=86400, immutable` que manda el API, de modo
que el navegador no guardaba nada y **cada** regreso a la carpeta repetia la
rafaga entera.

- Zona propia `geoserver_files` (30 r/s, `burst=200`), como ya se hizo con
  `acervo_thumb`. Tambien absorbe los POST seguidos de una subida por partes.
- Se retira el `no-store`: el API decide el cacheo por respuesta, igual que en
  `location ^~ /api/administrador/acervo/thumb`.

Requiere mariachi >= 1.97.1 (responde 304 ante `If-None-Match` y sube el limite
del scope de descarga).

## [1.33.0] - 2026-07-28

### Subidas sin tope a los recursos de GeoServer (`/api/*/geoserver/files`)

La pagina Recursos de Sextante (mariachi) sube archivos a `styles/` de GeoServer. Hasta
ahora topaba en 200 MB del lado del API; con el tope removido para publicar rasters de
varios GB, esas rutas caian al catch-all `location /api/`, que hereda el
`client_max_body_size 100M` del server y los timeouts por defecto: el PUT final a
GeoServer de un archivo grande tarda minutos y se cortaba.

Se agregan dos `location` propias (prefijo nuevo y el legacy `/api/administrador/`) con
`client_max_body_size 0`, `proxy_request_buffering off` y `proxy_read_timeout` /
`proxy_send_timeout` de 1800s. El `burst` del rate limit sube a 40 porque una subida por
partes son muchos requests seguidos del mismo cliente.

Requiere mariachi >= 1.96.0.

## [1.32.0] - 2026-07-23

### Cache de tiles WMS de GeoServer (`/geoserver/{workspace}/wms`)

La zona `geoserver_cache` existía pero solo estaba aplicada a `location ~ ^/geoserver/ows`, un endpoint que **nadie usa**. Todo el tráfico real del visor va a `/geoserver/{workspace}/wms`, que no matchea ninguna de las locations anidadas (`ows`, `wfs|wcs`) y caía al bloque padre `^~ /geoserver/`, sin `proxy_cache`.

Medido sobre 24 h de acceso: **11 560 peticiones** a `/geoserver/raster/wms`, **ninguna** cacheada (`upstream_cache_status` vacío en todas) y **86.6 % de URLs repetidas** — 10 010 de 11 560, con la misma URL pedida hasta 24 veces. Ese tráfico llegaba íntegro al renderizador y contribuía a los 429 de control-flow.

Nueva location `~ ^/geoserver/([^/]+/)?wms` con `proxy_cache geoserver_cache`, `proxy_cache_lock` (colapsa las ráfagas concurrentes idénticas del zoom rápido en una sola petición al upstream) y `proxy_cache_background_update`. Reutiliza el map `$geoserver_no_cache` ya existente para no cachear `GetFeatureInfo`/`GetCapabilities`/`DescribeFeatureType`.

Verificado: MISS → HIT, y una ráfaga de 200 peticiones sobre 40 tiles únicos con 30 en paralelo baja a 40 peticiones al upstream, sin errores.

No se añadieron las restricciones de referer/user-agent que llevan `ows` y `wfs|wcs`: la location padre no las aplicaba a `wms` y agregarlas habría cambiado el comportamiento para clientes legítimos (QGIS y similares).

> El include `nginx/includes/geoserver-locations.inc` va **dentro de la imagen** (`COPY nginx/includes/`), no montado: tras editarlo hay que `docker compose build nginx && up -d nginx` o el cambio se pierde al recrear el contenedor.

---

## [1.31.2] - 2026-07-22

### Seguridad: ofuscar IPs reales en el repo

Se removieron las IPs reales (hosts, rangos LAN y las IPs publicas de los registros A) de la documentacion y la config versionada, reemplazandolas por placeholders (`<S1>`…`<S4>`, `<LAN-interna>`, `<CIDR>`, `<IP-publica>`). Afecta `docs/CHANGELOG.md`, `README.md`, `docs/auditoria-seguridad.md`, `docs/context.md`, `docs/puertos-produccion.mmd`, `.env.example` y `scripts/stress_test_multi_ip.py`. Los valores reales quedan unicamente en el runbook no versionado.

---

## [1.31.1] - 2026-07-22

### Fail-fast en la location `^~ /mapalab/` (timeout 120s → 30s)

Tras un incidente en que el backend de MapaLab se colgo respondiendo `/api/layers/tree` e
`/api/layers/initial-order` (la BD dejo de responder), cada peticion quedaba colgada hasta
120s en el gateway y las conexiones se acumulaban. Se baja `proxy_read_timeout` y
`proxy_send_timeout` de la location catch-all `^~ /mapalab/` de 120s a **30s** para liberar
rapido las peticiones colgadas (las APIs de layers responden en ms). **No afecta** descargas
ni MCP: tienen sus propias locations (`^~ /mapalab/api/download/` y `^~ /mapalab/mcp`) con
600s. Complementa el fix de resiliencia del cache en el backend de mapalab (1.82.4).

---

## [1.31.0] - 2026-07-22

### Rename `/api/administrador` → `/api/mariachi`: locations de acervo (Fase 2)

Se duplican las 2 locations especiales del Acervo para el prefijo nuevo: `^~ /api/mariachi/acervo/thumb` (zona `acervo_thumb`, sin `no-store`, para que el navegador cachee las miniaturas) y `^~ /api/mariachi/acervo` (upload: `client_max_body_size 1G`, `proxy_request_buffering off`, timeouts 600s). Son **aditivas**: las de `/api/administrador/acervo*` siguen vivas durante la transición, así que desplegar esto no rompe nada. Necesario **antes** de que el admin de mariachi y SIEEJ cambien su `VITE_*` a `/api/mariachi`, o las miniaturas caerían al catch-all `/api/` y perderían su rate-limit dedicado (429). Las locations viejas se retiran en una fase posterior, cuando ningún cliente use el prefijo anterior.

---

## [1.30.0] - 2026-07-22

### Subida interna al Acervo desde plataformas externas (`/api/internal/acervo/`)

Nueva `location ^~ /api/internal/acervo/` (antes del catch-all `/api/`) para que una
plataforma externa (el Portal) suba archivos al Acervo vía mariachi-api. La location omite
`bot-protection.inc` a propósito (el cliente es server-to-server) y aplica settings de
upload (`client_max_body_size 1G`, `proxy_request_buffering off`, timeouts 600s). La
autenticación la hace mariachi-api con el header `X-Internal-Token`; el gateway no filtra
por IP. Se documenta la ruta en `docs/context.md`.

---

## [1.29.0] - 2026-07-21

### Retiro del proxy a Grafana (apagado del stack de observabilidad)

Como parte del apagado del stack de observabilidad de huachicol, se eliminan las locations
`/huachicol/` y `/huachicol/public/` que proxeaban a Grafana (`HUACHICOL_HOST`) y la zona de
rate limit `huachicol` asociada. Se conserva `/huachicol/ontoy`, que el monitor sigue
sondeando para reportar el estado del propio gateway y del ecosistema.

---

## [1.28.2] - 2026-07-20

### Docs: sincronizar documentación con las rutas vigentes

Las tablas de enrutamiento del `README.md` y `docs/context.md` seguían listando `/administrador/` como ruta activa (liberada desde `1.28.1`) y omitían locations reales del gateway. Se agregan a la documentación `/colibri/`, `/acervo/thumb/`, `/api/administrador/acervo`, `/mapalab/mcp`, `/mariachi/assets/`, `/sieej/assets/`, `/huachicol/ontoy` y la zona de rate limit `acervo_thumb`. Se enlaza `docs/rutas-reservadas.md` desde el índice y se refresca la sección de versiones del checklist de producción.

### Chore: limpiar `robots.txt`

Se retiran las reglas `Disallow: /administrador/` y `Disallow: /acervo/console/`, ambas de rutas que ya no existen en el gateway. Actualizado `docs/auditoria-seguridad.md`.

### Docs: pendientes

Se elimina `docs/pendientes/upgrade-mapalab-8cores.md` (ejecutado). La reorganización de servidores queda descartada: `docs/pendientes/reorganizacion-y-puertos.md` se conserva solo como referencia del inventario de puertos FortiGate.

---

## [1.28.1] - 2026-07-17

### Chore: liberar el namespace `/administrador/`

Se retira la `location /administrador/` (URL antigua del panel admin, renombrado a `/mariachi` en mariachi v0.21.0; tráfico 0 en 14 días de Loki). Mientras la raíz siga en `portal_backend` el 301 interno de `mariachi-nginx` mantiene el comportamiento; ese rewrite también quedó retirado en el repo de mariachi y saldrá con su siguiente release. Al ceder `location /` a la app de terceros, `/administrador/*` pasará a ella. Actualizado `docs/rutas-reservadas.md`.

---

## [1.28.0] - 2026-07-17

### Feat: reservar `/colibri/` en el gateway y documentar los namespaces de raíz

Preparación para ceder `location /` a una aplicación de terceros: auditoría de todas las rutas de primer nivel del dominio (locations del gateway + 44,511 requests de 14 días en Loki + fuentes de los frontends).

- **Nueva `location ^~ /colibri/`** → `portal_backend` (zona `static`). El widget embebible de Colibri (`/colibri/widget/colibri-widget.v1.js`, cargado por SIEEJ, mapalab y sitios externos) dependía del catch-all `location /`; al ceder la raíz habría dejado de servirse.
- **Nuevo `docs/rutas-reservadas.md`**: inventario de namespaces reservados, legados (`/administrador` con tráfico 0 en 14 días, liberable) y reglas de integración para la app raíz (assets/API bajo prefijo propio, sub-delegación de `/api/<scope>/`, cookies con prefijo).
- Pendiente decidido aparte: acotar `Path` de la cookie de sesión de mariachi antes de ceder la raíz.

---

## [1.27.9] - 2026-07-17

### Fix: re-resolución DNS en upstreams keepalive (elimina IPs obsoletas tras recrear backends)

Los upstreams estáticos introducidos en 1.27.8 resolvían el DNS de los backends una sola vez al arrancar; si `mariachi-nginx`, `mapalab-nginx-1` o `geoserver` se recreaban con IP nueva fuera de `ecosystem-deploy`, el gateway seguía proxyando a la IP muerta y respondía `502` (mostrado como página 500) hasta recargarlo a mano. Evidencia en Loki: 502 continuos hacia `172.18.0.7` el 2026-07-16 (16:29 y 19:59–20:13 UTC) resueltos solo al reiniciar el gateway.

- `portal_backend` y `mapalab_backend` agregan `zone` + `server ... resolve` + `resolver 127.0.0.11 valid=10s` en el bloque `upstream` (soportado en nginx OSS ≥ 1.27.3; la imagen usa 1.28.2). Se conserva el `keepalive` de 1.27.8.
- `geoserver` permanece estático: `GEOSERVER_HOST` es `host.docker.internal` (entrada de `extra_hosts` en `/etc/hosts`, invisible para el resolver 127.0.0.11 que usa `resolve`) y su IP de host-gateway no cambia entre recreaciones.
- Nginx re-resuelve los hosts respetando el TTL (`valid=10s`) sin reiniciar workers: ya no aplica la nota operativa de 1.27.8 sobre recargar el gateway tras recrear backends.
- Validado con `nginx -t` sobre la imagen construida y prueba de recreación de `mariachi-nginx` con cambio de IP.

---

## [1.27.8] - 2026-07-16

### Perf: reutilizar conexiones a backends con upstreams keepalive

Los backends internos de mayor tráfico (`mariachi-nginx` y `mapalab-nginx-1`) pasan de resolución dinámica por request (`set $var` + `resolver`, que abre una conexión TCP nueva por petición) a bloques `upstream` con `keepalive`, replicando el patrón que ya usaba GeoServer.

- **Nuevo** `nginx/conf.d/internal-upstreams.conf.template` con `portal_backend` y `mapalab_backend` (`keepalive 32`, `keepalive_requests 1000`).
- Las 10 `location` de portal/mariachi y mapalab pasan a `proxy_pass http://portal_backend|mapalab_backend`; acervo/mariachi-assets/huachicol conservan resolución dinámica por resiliencia.
- El `Dockerfile` extiende el `envsubst` de `conf.d` con `${PORTAL_HOST} ${MAPALAB_HOST}`.
- **Nota operativa:** como GeoServer, el gateway ahora resuelve esos hosts al arrancar; si se recrean con IP nueva fuera de `ecosystem-deploy` hay que recargar el gateway.
- `docker-compose.yml`: `nginx-exporter` fijado a `1.5.1` (antes `latest`).
- Validado con `nginx -t` sobre la imagen construida.

---

## [1.27.7] - 2026-07-10

### Feat: miniaturas del Acervo servidas por mariachi (no SeaweedFS)

Nueva `location ^~ /acervo/thumb/` que enruta las miniaturas WebP on-the-fly del Acervo a `mariachi-nginx` en lugar de a SeaweedFS.

- **Problema:** `location ^~ /acervo/` reescribe y proxya todo `/acervo/*` a `acervo-seaweedfs`, así que la ruta pública de miniaturas `/acervo/thumb/{bucket}/{path}?w=` caía en SeaweedFS (bucket inexistente `thumb`) y devolvía `403`.
- **Fix:** `location ^~ /acervo/thumb/` (prefijo más largo → gana el matcheo `^~`) hacia `${PORTAL_HOST}` sin reescribir el path; reusa la zona `acervo_thumb` (burst 120).
- Depende de que mariachi-api sirva el endpoint público anónimo (mariachi api 1.51.0+).

---

## [1.27.6] - 2026-07-07

### Docs: diagrama de conectividad por puertos entre los 4 servidores de produccion

Nuevo `docs/puertos-produccion.mmd` (Mermaid) con el mapa real de puertos inter-servidor en produccion, levantado con sondeos `nc` desde los cuatro hosts.

- **Servidores:** S1 Gateway-hub/Acervo `<S1>`, S2 MapaLab `<S2>`, S3 GeoServer `<S3>` (LAN `<LAN-interna>`); S4 DataEngine `<S4>` (LAN `<LAN-interna>`).
- **Hallazgo:** el flujo saliente `S4 -> S1:8333` (backup DataEngine -> Acervo S3) esta BLOQUEADO por firewall asimetrico: la red `192.168.13.x` entra a `S4:5432` pero S4 no puede salir hacia `192.168.13.x`. Mismo caso para `S4 -> S1:3101` (logs a Loki).
- **Notas:** en produccion `mapalab-nginx` expone `:8081`; en S1 coexisten `acervo-minio` y `acervo-seaweedfs`; el puerto de metricas `:12345` no escucha en ningun host.
- Referenciado en el README.

---

## [1.27.5] - 2026-07-02

### Docs: recuperar entradas 1.27.3 y 1.27.4 del changelog

Los bumps `1.27.3` y `1.27.4` se commitearon sin su entrada en este archivo, por lo que
`gen-version-json.sh` emitía `WARN: no se encontro entrada ...` en cada deploy y
`version.json` quedaba sin `released_at`.

- Entradas `[1.27.3]` y `[1.27.4]` reconstruidas a partir de los commits `62a65fb` y `4fc0677`.

---

## [1.27.4] - 2026-07-02

### Fix: verificar la red iieg-network en ecosystem-up y ecosystem-deploy

`ecosystem-up` y `ecosystem-deploy` asumían que la red externa `iieg-network` ya existía; en una VM recién provisionada los stacks fallaban al arrancar porque el compose declara la red como `external`.

- Ambos targets ahora verifican la red al inicio: si existe la reportan (`Red ya existe`), y si no, la crean (`Red creada`) antes de levantar los stacks.

---

## [1.27.3] - 2026-06-19

### Fix: ecosystem-down baja mariachi forzando ENV=prod

`mariachi down` respetaba su `ENV ?= dev` y apuntaba al proyecto compose `mariachi-dev`, dejando arriba los contenedores de producción (proyecto `mariachi`) que había levantado `deploy`.

- Campo extra opcional (5º) en `ECOSYSTEM_STEPS` para argumentos de make; mariachi recibe `ENV=prod`, propagado en los loops de `ecosystem-up` y `ecosystem-down`.

---

## [1.27.2] - 2026-06-19

### Fix: rate-limit dedicado para las miniaturas del Acervo (429 en buckets con muchas imágenes)

El endpoint de miniaturas on-the-fly de mariachi (`GET /api/administrador/acervo/thumb/...`, v1.42.0) se servía por `^~ /api/administrador/acervo`, que usa la zona `api` (10 r/s, burst 20) y además fuerza `add_header Cache-Control "no-store"`. Al abrir un bucket con muchas imágenes (p. ej. `portal`), el grid dispara una ráfaga de miniaturas que supera el burst → `429`; y el `no-store` impedía que el navegador cacheara, así que cada render repetía la ráfaga completa.

- Nueva zona `limit_req_zone ... zone=acervo_thumb:10m rate=30r/s` en `nginx.conf.template`.
- Nueva `location ^~ /api/administrador/acervo/thumb` (más específica, gana por prefijo) con `limit_req zone=acervo_thumb burst=120 nodelay` y **sin** `add_header Cache-Control "no-store"`: se deja pasar el `Cache-Control: immutable` que emite el thumbnail, de modo que el navegador lo cachee y no repita la ráfaga en cada render.

Mismo patrón que el fix de los chunks lazy del admin en `[1.27.1]`. Validado con `nginx -t`.

---

## [1.27.1] - 2026-06-15

### Fix: rate-limit dedicado para los assets del admin de mariachi (429 en chunks lazy)

La primera carga del CMS pedía la ráfaga de chunks `lazy()` del bundle por `^~ /mariachi/`,
que usa la zona `general` (10 r/s, burst 20). Al superar el burst, Nginx devolvía `429` y el
navegador fallaba con `Failed to fetch dynamically imported module`.

#### Agregado

- **`location ^~ /mariachi/assets/`** nueva, antes de `^~ /mariachi/`: usa la zona `static`
  (50 r/s, burst 200) — el mismo trato que `^~ /mapalab/assets/`. Los assets de Vite llevan hash
  de contenido en el nombre, así que además se sirven con `Cache-Control: public, max-age=31536000,
  immutable` (`proxy_hide_header Cache-Control` para sobreescribir el `no-cache` del upstream). El
  `index.html` queda fuera de `/assets/` y conserva su `no-cache`.

Acompaña al lote de hardening de routing de mariachi (`api 1.39.0 / admin 1.39.0`).

## [1.27.0] - 2026-06-08

### Refactor del Makefile: salida compacta, spinner con cronometro y totales acumulados

Reescritura completa de la experiencia del orquestador. Todos los targets muestran ahora una interfaz unificada con colores, spinner braille `⣾⣽⣻⢿⡿⣟⣯⣷` y cronometro `MM:SS` por paso. Los comandos de build/up corren en background con la salida capturada; solo se muestra en caso de error. Al final de cada seccion y del total general se imprimen los tiempos acumulados.

#### Agregado

- **Spinner con cronometro**: cada paso largo (`up`, `Build+Up`, `ecosystem-up`, `ecosystem-down`, pull) muestra spinner braille + `MM:SS` en tiempo real. La linea se limpia al terminar y se reemplaza con `ok`/`fail` + tiempo total.
- **Totales acumulados**: `ecosystem-deploy` imprime `Pull total`, `Down total`, `Up total` y `Total` general. `deploy` imprime el total al cerrar.
- **Errores en logs via `ecosystem-status`**: el script `ecosystem-status.sh` ahora escanea las ultimas 15 lineas de cada contenedor buscando `error|fatal|critical|panic` y solo muestra si hay hallazgos.
- **Salida estilizada**: todos los headers usan colores ANSI (bold, dim, green, red, yellow, cyan) consistentes con `ecosystem-status.sh`.

#### Cambiado

- **`deploy`**: ahora hace `down` (sin `--volumes`) + `build` + `up`. Incluye validacion condicional de red, `version-json` y `check-sieej-dist` inline.
- **`up`**: mantiene `up -d` sin rebuild. Mismo estilo visual que `deploy`.
- **`ecosystem-up` / `ecosystem-down`**: salida compacta con spinner por repo. `ecosystem-down` ahora tambien usa spinner.
- **`ecosystem-deploy`**: reemplaza a `ecosystem-restart`. Incluye `git pull --ff-only` + `ecosystem-down` + `ecosystem-up` en un solo paso, con STACKS filtrable en las tres fases.

#### Eliminado

- **`build`** standalone (integrado en `deploy`)
- **`restart`**, **`logs`**, **`ps`** (integrados en `ecosystem-status`)
- **`network`**, **`urls`**, **`version-json`** (inlineados en `deploy`)
- **`ecosystem-restart`** (reemplazado por `ecosystem-deploy`)
- **`ecosystem-pull`**, **`ecosystem-update`**, **`ecosystem-pull-others`** (integrados en `ecosystem-deploy`)
- **`ecosystem-down-options`** (no funcional)
- Frases redundantes `Ecosistema arriba.` / `Ecosistema abajo.`

---

## [1.26.3] - 2026-06-04

### Makefile: contador en ecosystem-down, validaciones .env/scripts y target interactivo ecosystem-down-options

Mejoras de robustez y ergonomia en el Makefile del orquestador. `ecosystem-down` ahora muestra progreso `[I/N]` como su contraparte `ecosystem-up`. Los targets que leen `.env` (`check-sieej-dist`, `urls`) advierten si el archivo no existe en lugar de fallar silenciosamente. `version-json` valida que `scripts/gen-version-json.sh` sea ejecutable antes de invocarlo. Nuevo target `ecosystem-down-options` que detecta qué servicios están levantados via `docker compose ps` y presenta un menú interactivo (`select`) para bajar uno, todos o salir; tras bajar uno la lista se refresca automáticamente.

#### Agregado

- **`ecosystem-down-options`**: target interactivo que detecta contenedores activos de cada repo del ecosistema, muestra menú numerado con `bash select` y ejecuta el target `down` correspondiente. Bucle de refresco tras cada bajada.

#### Cambiado

- **`Makefile`**: `ecosystem-down` ahora itera con contador `[I/TOTAL]` al igual que `ecosystem-up`. `check-sieej-dist` y `urls` emiten warning si falta `.env`. `version-json` verifica existencia y permisos del script antes de ejecutarlo.

#### Por qué patch

Solo afecta targets de Makefile usados en desarrollo local. No altera rutas, contratos, endpoints, configuracion de Nginx ni el comportamiento en produccion.

---

## [1.26.2] - 2026-06-03

### ecosystem-status: tabla de estatus git+docker del ecosistema

El target `make ecosystem-status` ahora muestra una tabla compacta con el estado de cada repo del ecosistema: rama, cambios locales, sync con remote (push/pull pendientes) y contenedores Docker corriendo. Reemplaza el `docker compose ls` anterior que solo listaba proyectos de compose sin información de git.

#### Agregado

- **`scripts/ecosystem-status.sh`**: script que recorre los 8 repos del ecosistema y consulta `git status`, `git rev-list` (ahead/behind vs upstream) y `docker compose ps` para construir una tabla con columnas centradas. Incluye resumen final con contadores de repos limpios, con cambios, sin push y sin pull.

#### Cambiado

- **`Makefile`**: target `ecosystem-status` ahora invoca `./scripts/ecosystem-status.sh` en lugar de `docker compose ls`.

#### Por qué patch

Cambio interno de tooling que no altera rutas, contratos ni endpoints. Solo afecta el output de un target de Makefile usado en desarrollo local.

---

## [1.26.1] - 2026-05-26

### gzip: comprimir respuestas `text/csv`

Se agrega `text/csv` a la directiva `gzip_types` en `nginx.conf.template`. Los CSVs servidos desde `/mapalab/api/download/` (descargas de capas de MapaLab) son texto y comprimen 5–10×; sin esto, las descargas viajaban sin comprimir y la latencia percibida en `http_request_duration_seconds` (que mide hasta el cierre del response) saturaba el bucket superior del histograma del backend, generando alertas `HighLatency` que no reflejaban un problema real sino el tiempo de transferencia al cliente.

#### Cambiado

- **`nginx/templates/nginx.conf.template`**: `gzip_types` ahora incluye `text/csv` junto con los formatos de texto ya comprimidos.

#### Por qué patch

Cambio interno de configuración que no altera rutas, contratos ni endpoints; solo cómo se transmite la carga. Compatible con `proxy_buffering off` del location de download (nginx comprime por chunks).

---

## [1.26.0] - 2026-05-21

### ontoy: schema homologado del endpoint `/ontoy`

El JSON expuesto en `/ontoy` se alinea con el formato que ya servían los `version-api` de huachicol, acervo y geoserver: `{version, service, released_at}`. Se eliminan los campos `slug` y `label`, que duplicaban información que el consumidor (Mariachi `/sistema/plataformas`) ya tiene hardcoded en `platforms_config.py`.

#### Cambiado

- **`scripts/gen-version-json.sh`**: el `printf` final ahora emite `{"version","service","released_at"}` en ese orden. Se elimina la constante `LABEL` (ya no se usa) y se renombra el orden para que `version` sea el primer campo, igual que el resto del ecosistema.

#### Por qué bump minor

Cambio en el contrato público de `/ontoy`. Aunque el consumidor único conocido (Mariachi) sólo lee `version`, otros clientes externos podrían depender de `slug`/`label` — el bump avisa la ruptura.

---

## [1.25.4] - 2026-05-19

### Tooling: limpieza del Makefile (sin cambios funcionales en Nginx)

Refactor del `Makefile` y extraccion del generador de `version.json`. No toca rutas, certificados, headers, rate limits ni la imagen de nginx — solo la ergonomia del orquestador local. El bump es porque `make version-json` regenera el JSON con la nueva version del repo.

#### Anadido

- **`scripts/gen-version-json.sh`**: extraido del heredoc multilinea que vivia dentro del target `version-json` del Makefile. Ahora es ejecutable standalone, con `set -euo pipefail` y resolucion absoluta de `$ROOT` para correrse desde cualquier directorio.
- **Target `urls`**: imprime las rutas publicas del gateway leyendo `APP_DOMAIN` desde `.env` (fallback `iieg.local`). Se invoca automaticamente al final de `make up`, `make deploy` y `make ecosystem-up`.
- **Filtro `STACKS`** en `ecosystem-up` y `ecosystem-down`: `STACKS=mariachi,mapalab make ecosystem-up` levanta solo esos stacks (respetando el orden topologico). Sin la variable, comportamiento original (todos).
- **Guard `check-sieej-dist`**: dependencia de `up` y `deploy`. Falla rapido con mensaje claro si `SIEEJ_DIST_PATH` no existe en disco, en vez de levantar el gateway con un bind mount vacio que sirve 404 silencioso en `/sieej/`.
- **Target `ecosystem-pull-others`**: `git pull --ff-only` en todos los repos del orquestador EXCEPTO gateway-hub. Util cuando hay cambios locales no commiteados aqui.

#### Cambiado

- **Help auto-generado**: el bloque `help:` ya no es una pared de `@echo` manual. Un parser `awk` extrae la descripcion `## ...` al lado de cada target y las secciones `##@ ...`. Renombrar un target ya no requiere actualizar la doc por separado.
- **Tabla `ECOSYSTEM_STEPS`**: los 8 pasos del `ecosystem-up` ahora viven en una variable como tabla `nombre:dir:target-up:target-down`. El loop de bash itera sobre ella y deriva el contador `[I/TOTAL]` dinamicamente (antes era `[1/7]`…`[8/8]` hardcodeado e inconsistente).
- **`ecosystem-down` delega a subrepos**: ahora corre `make -C <dir> down` de cada uno en orden inverso, en vez de duplicar `docker compose down` con flags hardcodeados. Si el subrepo cambia su logica de teardown, este Makefile lo respeta automaticamente. Elimina las variables `MARIACHI_FILES/ENV` y `MAPALAB_FILES/ENV` que solo existian para este caso.
- **`down` del gateway** ahora usa `$(GATEWAY_FILES)` explicito (simetria con `up`/`build`/`deploy`).
- **Shell estricto**: `SHELL := bash` + `.SHELLFLAGS := -eu -o pipefail -c`. Las recetas shell que fallan a media linea ahora abortan en vez de seguir silenciosamente.
- **`MAKEFLAGS += --no-print-directory`**: elimina el ruido `make[1]: Entering directory '…'` al delegar a subrepos.
- **`.DEFAULT_GOAL := help`** explicito (antes funcionaba por coincidencia del orden de declaracion).

#### Verificacion

`make help`, `make urls`, `make version-json` corren OK localmente. El filtro `STACKS` se valido standalone con la lista de pasos. `make ecosystem-up` real (con subrepos) queda pendiente de probarse en proxima sesion de despliegue.

---

## [1.25.3] - 2026-05-18

### Fix: los 5 upstreams (portal, mapalab, acervo, mariachi, huachicol) ahora resuelven DNS en runtime

Mismo bug latente que `1.25.1` arreglo para los 3 sidecars version-api, pero aplicaba tambien a los 5 upstreams "principales" del gateway. Los bloques `upstream portal { server ${PORTAL_HOST}; ... }` (idem para mapalab/acervo/mariachi/huachicol) eran resueltos por nginx **al parsear el config** y la IP del container destino quedaba cacheada hasta el siguiente restart de nginx. Cuando cualquier container destino se recreaba (mariachi-nginx, grafana, acervo-seaweedfs, mapalab-nginx) y Docker le asignaba otra IP, el gateway seguia intentando la IP vieja → `502 Connection refused` constante. Observado en staging post-restart de huachicol: `grafana` paso de `172.18.0.4` a `172.18.0.3`, gateway seguia apuntando a `172.18.0.4` (que ahora era `nginx-auth`).

#### Cambiado

- **`nginx/templates/gateway.conf.template`**:
  - Removidos los 5 bloques `upstream portal/mapalab/acervo/mariachi/huachicol`.
  - Cada `location` que hacia `proxy_pass http://NAME` ahora declara `set $NAME_upstream "${NAME_HOST}"` y usa `proxy_pass http://$NAME_upstream`. Resolucion DNS por request (via `resolver 127.0.0.11`), no por parse.
  - Para los 4 locations que removian prefijo de path (`proxy_pass http://mapalab/` reemplazaba `/mapalab/` con `/`), se agrega `rewrite ^/mapalab/(.*) /$1 break;` antes del `proxy_pass`. Sin esto, nginx con variable mantiene el URI original — cambio de semantica que rompia el routing al upstream. Aplica a `/mapalab/assets/`, `/mapalab/api/download/`, `/mapalab/` y `/acervo/`. Los locations `/mariachi/`, `/huachicol/` y `/huachicol/public/` no tenian path en el proxy_pass original, asi que siguen igual.
  - **Resolver HTTPS reducido a solo `127.0.0.11`** (antes era `127.0.0.11 8.8.8.8 8.8.4.4`). Nginx hace round-robin entre los nameservers configurados: cuando le tocaba 8.8.8.8/8.8.4.4 intentaba resolver hostnames internos de Docker (`grafana`, `mariachi-nginx`, `geoserver-version-api`) por Google DNS y obtenia NXDOMAIN, causando 502 intermitente (~2 de cada 3 requests). El `127.0.0.11` (Docker embedded DNS) ya recursa hacia los DNS del host para hostnames publicos, asi que OCSP stapling sigue funcionando sin el fallback explicito.

#### Trade-off

- Se pierde el `keepalive 32; keepalive_timeout 60s;` que tenian los upstream blocks. Para el trafico actual (gobierno, picos modestos), el impacto es despreciable: la conexion TCP+TLS al upstream se establece por request en vez de reusarse del pool. Si en el futuro se ve carga sostenida que justifique reanudar keepalive, se puede combinar con resolver dinamico via `upstream` + `keepalive` + `resolve` (requiere `nginx-plus`, no aplica aqui) o mediante un sidecar tipo `consul-template`.

#### Verificacion

Tras `make deploy`, ningun container destino requiere restart del gateway aunque cambie de IP. Si un upstream cae, ese endpoint da 502 pero el resto del gateway sigue arriba.

---

## [1.25.2] - 2026-05-18

### Fix: `X-Forwarded-Host` ahora refleja el host real del request

`nginx/includes/proxy-params.inc` enviaba `X-Forwarded-Host: $server_name` a los upstreams. `$server_name` devuelve el **primer nombre declarado en el server block**, no el `Host` header del request — siempre era `${APP_DOMAIN}` (en staging: `iieg.local`) sin importar como llegara la peticion. En produccion no se notaba porque `APP_DOMAIN` y el host real coinciden; en staging cualquier backend que generara URLs absolutas desde ese header (canonical, redirects, emails) recibia `iieg.local` aunque el cliente entrara por IP de la VM o `iieg-staging.example.com`.

#### Cambiado

- **`nginx/includes/proxy-params.inc`**: `proxy_set_header X-Forwarded-Host $server_name;` → `proxy_set_header X-Forwarded-Host $host;`. `$host` es el header `Host` del request entrante (o `$server_name` como fallback si no viene), que es el comportamiento esperado del header `X-Forwarded-Host` segun convencion HTTP.

#### Impacto

- `APP_DOMAIN` queda **solo como server_name decorativo** (el server block es `default_server` con `_` como catch-all, asi que no filtra trafico). Si en el futuro se quiere eliminar la variable, se puede sin afectar funcionamiento — pero conservarla no cuesta.
- Mariachi, Mapalab y demas upstreams ahora reciben el host real. Validar que ningun backend dependa de recibir `iieg.local` literal en staging.

---

## [1.25.1] - 2026-05-18

### Fix: nginx crashea al startup si un sidecar `version-api` aun no resuelve

Bug introducido en `1.25.0`. Los `upstream geoserver_ontoy { server geoserver-version-api:8088; }` (idem para acervo y huachicol) declaraban hostnames Docker que nginx **resuelve al parsear el config**, no por request. Si el sidecar correspondiente no estaba listo cuando nginx arrancaba (race comun en `docker compose up` o restart de la VM), nginx fallaba con `[emerg] host not found in upstream "geoserver-version-api:8088"` y entraba en restart loop infinito — tumbaba **TODO el gateway**, no solo ese endpoint. Observado en VM staging post-deploy de 1.25.0.

#### Cambiado

- **`nginx/templates/gateway.conf.template`**: removidos los 3 bloques `upstream geoserver_ontoy/acervo_ontoy/huachicol_ontoy`. Los locations `/geoserver/ontoy`, `/acervo/ontoy`, `/huachicol/ontoy` ahora usan el patron Docker DNS dinamico: `set $..._upstream "host:8088"` + `proxy_pass http://$..._upstream/ontoy`. Resolucion es por request (no por parse), asi que si el sidecar no esta, ese endpoint devuelve 502 pero nginx sigue arriba.
- **`nginx/templates/gateway.conf.template`** (server HTTP, server HTTPS): agregado `resolver 127.0.0.11 valid=10s ipv6=off;` (Docker embedded DNS). En el server HTTPS se preserva 8.8.8.8/8.8.4.4 como fallback para OCSP stapling: `resolver 127.0.0.11 8.8.8.8 8.8.4.4`.

#### Verificacion

```bash
docker stop geoserver-version-api
docker exec gateway-hub-nginx-1 curl -s -o /dev/null -w "%{http_code}\n" http://localhost/geoserver/ontoy   # antes: nginx crasheaba; ahora: 502
docker exec gateway-hub-nginx-1 curl -s -o /dev/null -w "%{http_code}\n" http://localhost/                  # 302 → mapalab (gateway sigue arriba)
docker start geoserver-version-api
sleep 3
docker exec gateway-hub-nginx-1 curl -s http://localhost/geoserver/ontoy                                    # vuelve a responder JSON
```

---

## [1.25.0] - 2026-05-18

### `/{servicio}/ontoy` ahora hace `proxy_pass` real + auto-regen de `nginx/version.json`

Hasta `1.24.21` el gateway eclipsaba las versiones reales de geoserver y acervo con `return 200 '...'` hardcoded en `gateway.conf.template` (`geoserver` quedo congelado en `1.14.1` real `1.20.1+`, `acervo` en `1.20.1` real `1.22.4+`), y `/huachicol/ontoy` ni existia. Ademas `nginx/version.json` se sincronizaba a mano con `VERSION`, asi que tambien podia desfasarse.

#### Agregado

- **`nginx/templates/gateway.conf.template`**:
  - upstreams `geoserver_ontoy`, `acervo_ontoy`, `huachicol_ontoy` apuntando a los sidecars `*-version-api:8088` en `iieg-network` (creados en `geoserver/1.21.0`, `acervo/1.23.0`, `huachicol/1.20.0`).
  - location `/huachicol/ontoy` en los dos server blocks (HTTP y HTTPS), antes no existia.
- **`Makefile`**: target `version-json` que regenera `nginx/version.json` leyendo `VERSION` y la fecha de `docs/CHANGELOG.md`. Hookeado a `up`, `build` y `deploy` como prerequisito.

#### Cambiado

- **`nginx/templates/gateway.conf.template`** (HTTP y HTTPS): `location = /geoserver/ontoy` y `location = /acervo/ontoy` cambian de `return 200 '<hardcode>'` a `proxy_pass http://{servicio}_ontoy/ontoy` con `keepalive`. Ahora la version que se ve por `https://dominio/{servicio}/ontoy` viene del repo de cada servicio.
- **`Makefile`** (`ecosystem-up`, paso `[4/7] geoserver`): `cd $(GEOSERVER_DIR) && docker compose up -d` reemplazado por `$(MAKE) -C $(GEOSERVER_DIR) up` para que el `version-json` de geoserver se regenere en cada despliegue del ecosistema (mismo patron que ya usaban acervo, huachicol y dataengine).
- **`.gitignore`**: `nginx/version.json` ahora se ignora (se regenera por `make version-json`). El archivo se removio del index con `git rm --cached`; el `Dockerfile` lo sigue copiando porque los hooks de `build`/`deploy` garantizan que existe antes del build.

#### Notas

`mariachi` debe eliminar los `static_version` de `geoserver`, `acervo`, `huachicol`, `gateway-hub` y `dataengine` en `platforms_config.py` para que la version mostrada en el dashboard de ecosistema venga 100 % en vivo. Si el sidecar de un servicio no esta arriba, el probe ya distingue (devuelve `healthy: false` en vez de un hardcode mentiroso).

---

## [1.24.21] - 2026-05-15

### `ecosystem-pull` y `ecosystem-update`: git pull + up en un solo comando

#### Agregado

- **`Makefile`**: dos targets nuevos en el orquestador.
  - `ecosystem-pull`: itera sobre los 8 repos (`gateway-hub`, `acervo`, `huachicol`, `dataengine`, `geoserver`, `mariachi`, `mapalab`, `sieej`) y corre `git pull --ff-only` en cada uno. Si el working tree esta sucio o la rama esta divergente, imprime warning sin abortar (continua con los siguientes repos).
  - `ecosystem-update`: alias de `ecosystem-pull && ecosystem-up`. Caso de uso: la VM de produccion donde el operador quiere "actualizar todo desde GitHub y desplegar".
- Help del Makefile documenta los dos nuevos verbos.

---

## [1.24.20] - 2026-05-15

### `make up` deja de rebuildear; nuevo `make deploy` para cambios reales

Refinamiento del refactor anterior. En `1.24.19` agregue `--build` al `make up` para resolver un drift entre VERSION en disco y el container en runtime. Pero eso forzaba un build cada vez que se levantaba el gateway, aunque no hubiera cambios — incoherente con el patron del resto del ecosistema (`mariachi`, `mapalab`, `acervo`, `sitio2026`: `up` sin build, `deploy` con build).

#### Cambiado

- **`Makefile`**:
  - `up`: vuelve a `docker compose up -d` (sin `--build`). Rapido, usa la imagen actual.
  - `deploy` (NUEVO): `docker compose up -d --build`. Mismo verbo y comportamiento que `mariachi`/`mapalab`. Usar tras cambios en `nginx/templates/`, `includes/`, `error-pages/`, `Dockerfile`, etc.
  - `build` (NUEVO): solo rebuildea la imagen sin tocar containers. Util en CI o para validar que el build no este roto.
  - `ecosystem-up` paso `[8/8]` ahora invoca `$(MAKE) deploy` en lugar de `$(MAKE) up`. Asi el unico camino del orquestador que rebuildea son los tres servicios cuyo codigo/config puede cambiar entre runs: `mariachi deploy`, `mapalab deploy`, `gateway-hub deploy`. Los demas (`acervo`, `dataengine`, `geoserver`, `huachicol`) levantan con su imagen actual — coherente con el feedback "el restart NO debe rebuildear todo".
- Help del Makefile documenta los tres verbos (`up` / `build` / `deploy`) y cuando usar cada uno.

#### Notas

- La consecuencia visible: `make ecosystem-restart` corre mas rapido en el caso comun (sin cambios). Solo paga el costo de build cuando realmente hay codigo/template nuevos en mariachi, mapalab o gateway-hub.
- Si quieres forzar un rebuild de los demas servicios (acervo, dataengine, geoserver, huachicol), llamar `make build` de cada uno o usar `docker compose build` directo en su carpeta.

---

## [1.24.19] - 2026-05-15

### Orquestador `ecosystem-up` reescrito y `make up` con auto-rebuild

`make local-up` se renombro a `make ecosystem-up` (y simetricos `ecosystem-down`, `ecosystem-restart`, `ecosystem-status`) para que el nombre describa lo que hace. Se removieron bugs heredados de la era MinIO y se delego a los `make deploy` de los repos hijos en lugar de duplicar `docker compose` directo.

#### Cambiado

- **`Makefile`** (orquestador):
  - `local-up` → `ecosystem-up`, `local-down` → `ecosystem-down`, `local-restart` → `ecosystem-restart`, `local-status` → `ecosystem-status`.
  - Removida la linea `docker network connect $(NETWORK_NAME) acervo-minio 2>/dev/null || true` (el container `acervo-minio` ya no existe desde acervo 1.22.0; acervo-seaweedfs gestiona su red desde su propio compose).
  - `mariachi` y `mapalab` ahora se invocan via `$(MAKE) -C <repo> deploy` en lugar de `docker compose ... up -d` directo. El comportamiento es el mismo (`.env.production` + build + up con profile staging para mapalab) pero el orquestador deja de duplicar conocimiento que ya vive en los Makefile hijos.
  - `acervo` se invoca con `make up` (sin `ENV=prod`; ese parametro nunca existio en el Makefile de acervo).
  - Header del help actualizado y se documentan explicitamente los servicios NO incluidos: `sitio2026` (corre con su propio `make up ENV=gcp`) y `minerva` (pendiente de integracion al ecosistema, se levanta manual).
  - Numeracion de pasos corregida `[1/8] ... [8/8]`.
- **`Makefile`** (`up:` del propio gateway-hub): agregado `--build` al `docker compose up -d`. Antes, levantar gateway sin un rebuild previo dejaba el contenedor con la imagen vieja del filesystem (visto hoy: el container reportaba `1.24.16` mientras `VERSION` en disco decia `1.24.18`). Con `--build`, cada `make up` regenera la imagen y aplica los cambios de nginx/templates, includes, error-pages, etc.

#### Notas

- El `make ecosystem-up` corrio end-to-end limpio en ~2:40 (cold cache parcial: builds frescos de mapalab-backend, mariachi-api, gateway-hub). Smoke test post-restart: gateway `/ontoy` reporta version correcta, mariachi → mapalab `/refresh-cache` con token responde 200 con 250 layers.

---

## [1.24.18] - 2026-05-15

### Contrato del `MAPALAB_INTERNAL_TOKEN` documentado en `ecosystem.md`

#### Agregado

- **`docs/ecosystem.md`** § 5.3: subseccion "`MAPALAB_INTERNAL_TOKEN` — contrato compartido" con tabla cliente/servidor, reglas operativas (rotacion coordinada, generacion, deteccion via `MariachiTreeNotifyFailures`), endpoints adicionales que comparten el patron (`shares.pin-permanent`, `embed.quota-check`) y bloque de diagnostico rapido. Cierra el gap documental que dejaba al proximo dev sin contexto sobre por que ambos `.env` exigen el mismo valor literal.

---

## [1.24.17] - 2026-05-15

### Checklist de produccion actualizado a SeaweedFS

`docs/pendientes/checklist-produccion-gcp.md` reescrito de punta a punta. La version anterior describia el modelo MinIO + consola web, ambos retirados en `acervo 1.22.0` y `gateway-hub 1.24.10` respectivamente. El runbook actual:

- Snapshot de versiones del ecosistema en seccion F (gateway-hub 1.24.16, acervo 1.22.1, mariachi 1.0.4, etc.).
- Smoke test seccion A incluye verificacion explicita de WFS-T bloqueado (`POST /geoserver/ows` debe responder 405) y de versiones reportadas en `/sistema/plataformas`.
- Seccion D: nueva entrada para `Drop de public.mapalab_card` con la condicion "no dropear hasta el primer go-live", `Backups dataengine` semanal→diario, y `Sincronizacion de platforms_config.py` como deuda manual.
- Seccion de diagnostico: agregado el flujo "Tree de capas no se actualiza tras editar" cubriendo el `MAPALAB_INTERNAL_TOKEN` requerido por mapalab 1.28.5+; y "Alloy unhealthy" para el bug del healthcheck `wget` (huachicol < 1.19.2).
- Removidas las secciones obsoletas de "Acervo console: assets MIME type", "MINIO_BROWSER_REDIRECT_URL", `mc admin user add` y `init-buckets.sh --rotate` (todas MinIO-specific).

#### Cambiado

- **`docs/pendientes/checklist-produccion-gcp.md`** (rewrite completo).

---

## [1.24.16] - 2026-05-15

### `REAL_IP_FROM` parametrizable via `.env`

#### Cambiado

- **`nginx/nginx.conf`** → **`nginx/templates/nginx.conf.template`** (renombrado + tratamiento via `envsubst`). La directiva `set_real_ip_from <CIDR-interno>;` ahora es `set_real_ip_from ${REAL_IP_FROM};`. Antes el rango trusted estaba hardcoded; cualquier ajuste (segundo balanceador, IPv6, prod multi-LAN) requeria editar el archivo y rebuildear.
- **`Dockerfile`**: el `COPY nginx/nginx.conf` se reemplazo por el template; el CMD ahora corre `envsubst '${REAL_IP_FROM}'` antes de los otros templates para generar `/etc/nginx/nginx.conf`. La whitelist explicita evita que envsubst toque `$remote_addr`, `$binary_remote_addr`, etc.
- **`.env`, `.env.example`** y **`docker-compose.yml`** (environment del servicio `nginx`): variable `REAL_IP_FROM` con default `<CIDR-interno>`. Si esta vacia, `set_real_ip_from` queda sin valor y nginx falla al arrancar — el default cubre el caso de `.env` heredado sin la variable.

#### Notas

- En local el real_ip queda inerte (no entra trafico via XFF desde <CIDR-interno>), pero la directiva es valida y no rompe. En GCP prod sigue siendo el rango del FortiGate estatal.
- Para mas de un CIDR (escenario futuro con multi-balanceador): la sintaxis nginx requiere multiples directivas `set_real_ip_from`. Si llega ese caso, evolucionar el template a un loop en el entrypoint sobre una variable separada por comas. Hoy no hace falta.

---

## [1.24.15] - 2026-05-15

### Bloqueo de WFS-T por metodo HTTP + remocion de promtail

Dos cambios independientes en un mismo bump.

#### Cambiado

- **`includes/geoserver-locations.inc`** (`/geoserver/ows`, `/geoserver/(wfs|wcs)`, `/geoserver/[^/]+/(wfs|wcs)`): agregado `limit_except GET HEAD OPTIONS { deny all; }` al inicio de cada location. El filtro previo `if ($arg_request ~* "Transaction") { return 403; }` solo inspeccionaba el query string; un POST XML estandar de WFS-T (`<wfs:Transaction>...</wfs:Transaction>` en el body) lo bypasea-ba y llegaba a GeoServer. Verificado en local: `curl -X POST .../geoserver/ows -d "<wfs:Transaction.../>"` ahora responde **HTTP 405**. Ningun cliente del ecosistema (mariachi, mapalab, sieej, dataengine) hace POST a `/geoserver/ows|wfs|wcs` — todo el trafico OGC del visor es GET. El filtro de query string se mantiene como defensa en profundidad por si alguien intenta `?request=Transaction` via GET.

#### Removido

- **Servicio `promtail` del `docker-compose.yml`** + volumen nombrado `nginx_logs` + bind mount en el servicio `nginx`. Razon: el `alloy` del stack `huachicol` (introducido en huachicol 1.18.0, commit `a6f7c5c`) ya recolecta logs de todos los contenedores Docker via `loki.source.docker` (socket Docker) y los publica a Loki con label `container_name`. Promtail estaba leyendo el `access.log` JSON del volumen `nginx_logs`, pero su `LOKI_URL=http://host.docker.internal:3100` no resolvia desde `iieg-network` (el servicio promtail no tenia `extra_hosts: host-gateway`), generando un loop de errores `dial tcp: lookup host.docker.internal on 127.0.0.11:53: no such host`. Cero logs llegando a Loki via promtail desde el rebuild de iieg-network; los logs nunca se perdieron del todo porque alloy los toma del stdout del container.
- **`nginx/nginx.conf`** (`access_log`, `error_log`): dirigidos exclusivamente a `/dev/stdout` (JSON) y `/dev/stderr`. Removidos los dos `access_log /var/log/nginx/access.log json_logs;` y `error_log /var/log/nginx/error.log warn;` (no tenian lector tras quitar promtail).
- **`Dockerfile`** (CMD entrypoint): removido el `rm -f /var/log/nginx/access.log /var/log/nginx/error.log` previo al arranque. Ya no hay archivos reales que limpiar — los symlinks de la imagen base `nginx:alpine` apuntan a `/dev/stdout` y `/dev/stderr`, que es exactamente lo que ahora queremos.
- **`LOKI_URL`** en `.env` y `.env.example`. Sin uso tras la remocion.
- **Carpeta `promtail/`** completa (`promtail-config.yml`).

#### Trade-off

Promtail extraia labels estructuradas del JSON (`subroute`, `status`, `request_method`); alloy no las extrae automaticamente. Los dashboards que filtran por `subroute` (`gateway-subroutes.json`, ya removido en huachicol 1.19.0) perderian esa dimension. Los logs siguen llegando a Loki con label `container_name=gateway-hub-nginx-1` y `job=docker`; las queries por path se hacen ahora con regex (`{container_name="gateway-hub-nginx-1"} |~ "\"request_uri\":\"/mapalab/"`).

---

## [1.24.14] - 2026-05-15

### Corregida la metodologia de validacion JVM en recursos-servidores

Tras aplicar el tuning en GCP staging y observar `M=99 %` en `jstat -gcutil` con valores correctos (`MU=137 MB` de un cap de 512 MB), confirmamos que el porcentaje de `gcutil` reporta `used / committed`, no `used / max`. Era guia engañosa que podia hacer creer que habia un problema cuando no lo habia.

#### Changed

- **`docs/recursos-servidores.md`** (seccion "Tuning de la JVM de GeoServer", bloque de validacion): cambiada la recomendacion de `jstat -gcutil 1 5s 5` a `jstat -gc 1`. Documentadas las columnas relevantes (`OC`/`OU` y `MC`/`MU` en KB), el indicador clave `FGC = 0`, y advertencia explicita: NO usar `gcutil` porque su percentage de Metaspace es vs committed, no vs max. Espejo del cambio aplicado en el repo `geoserver` (1.20.1).

---

## [1.24.13] - 2026-05-15

### Corregido tuning JVM de GeoServer: usar variables nativas de kartoza

El enfoque inicial (1.24.12) recomendaba flags raw en `JAVA_OPTS`. Al aplicarlo en GCP staging fallo con `Invalid maximum heap size: -Xmx2g-XX:MaxMetaspaceSize=512m`: el script `scripts/entrypoint.sh` de la imagen `kartoza/geoserver` ya define `-Xms`/`-Xmx`/`-XX:+UseG1GC` en su bloque `GEOSERVER_OPTS` interno y luego concatena con nuestro `JAVA_OPTS`, produciendo doble definicion y parsing roto.

#### Changed

- **`docs/recursos-servidores.md`** (seccion "Tuning de la JVM de GeoServer"): reemplazada la recomendacion de `JAVA_OPTS="-Xms... -Xmx..."` por las variables nativas de kartoza: `INITIAL_MEMORY`, `MAXIMUM_MEMORY` y `ADDITIONAL_JAVA_STARTUP_OPTIONS`. Incluye tabla de mapeo a flags JVM, valores recomendados por entorno y advertencia explicita "no usar JAVA_OPTS raw — colisiona con GEOSERVER_OPTS". Espejo del cambio en el repo `geoserver` (1.20.0).

---

## [1.24.12] - 2026-05-15

### Documentado tuning de JVM para GeoServer en `recursos-servidores.md`

Diagnostico reciente en GCP staging mostro que la JVM de GeoServer corre con defaults sin caps explicitos: Old gen y Metaspace saturados al 99 %, concurrent GC compitiendo con el render por CPU. La causa raiz no estaba documentada en este repo; cualquier persona dimensionando un nuevo host repetia el agujero. Se agrega seccion explicita con `JAVA_OPTS` recomendado por entorno.

#### Added

- **`docs/recursos-servidores.md`**: nueva subseccion "Tuning de la JVM de GeoServer" dentro de "Configuracion final por entorno". Tabla con `JAVA_OPTS` recomendado para staging (VM compartida, conservador) y produccion S3 (VM dedicada, generoso). Incluye comando `jstat -gcutil` para validar post-cambio. Cierra el loop con el commit correspondiente del repo `geoserver` (1.19.0) donde se aplica el cambio.

---

## [1.24.11] - 2026-05-15

### Afinacion del cache de GeoServer y observabilidad de cache_status

Conjunto de ajustes al `proxy_cache geoserver_cache` que sirve los `GetMap` de los visores (incluyendo los frames del loop temporal de capas raster de mapalab). El cache ya estaba en gateway-hub, estos cambios mejoran su efectividad bajo carga, limpian directivas muertas y exponen el hit-rate por linea de log.

#### Changed

- **`includes/geoserver-locations.inc`** (`/geoserver/ows`): `proxy_cache_lock_timeout` subido de `10s` a `30s` y agregado `proxy_cache_lock_age 30s`. Reduce el riesgo de estampida hacia GeoServer cuando el primer render de un tile pesado supera los 10 s: los clientes que esperan el lock siguen esperando hasta 30 s a que el originador llene el cache, en lugar de soltarse y pegar todos al upstream simultaneamente. El `proxy_read_timeout 120s` heredado del bloque externo `/geoserver/` deja margen para que el render originador alcance a terminar.
- **`includes/geoserver-locations.inc`** (`/geoserver/ows`): `proxy_cache_key "$request_uri$arg_outputFormat"` simplificado a `"$request_uri"`. El `$arg_outputFormat` ya formaba parte de `$request_uri`; la concatenacion duplicaba el parametro en la key sin cambiar el comportamiento. Limpieza, no afecta entradas existentes (siguen siendo validas porque la key para GetMap nunca tuvo `outputFormat`).
- **`nginx.conf`** (`log_format json_logs`): agregado el campo `"upstream_cache_status":"$upstream_cache_status"`. Cada linea de log JSON emite ahora `HIT`/`MISS`/`BYPASS`/`STALE`/`EXPIRED`/`UPDATING`/`REVALIDATED` (o vacio para rutas no cacheadas), agregable desde promtail/Loki para calcular hit-rate del cache de GeoServer.

#### Removed

- **`includes/geoserver-locations.inc`** (`/geoserver/(wfs|wcs)`): removidas 9 directivas `proxy_cache*` y el `add_header X-Cache-Status` que eran letra muerta. La location tiene `proxy_buffering off` (necesario para streaming de descargas WCS grandes y respuestas WFS pesadas), y nginx no cachea cuando el buffering esta desactivado. Las directivas quedaron tras el move de `mapalab/nginx/conf.d/` a este repo pero nunca actuaron. Eliminarlas evita confusion al leer la config y previene activacion accidental si alguien quitara el `proxy_buffering off` sin entender la dependencia.

#### Notas

- Validar antes de deployar: `docker compose exec nginx nginx -t` dentro del contenedor.
- Sin invalidacion reactiva del cache; sigue dependiendo de `inactive=12h` o del rm manual de `/var/cache/nginx/geoserver` en caso de stale en datos editables. Riesgo asumido conscientemente.

---

## [1.24.10] - 2026-05-14

### Removed

- **`nginx/templates/gateway.conf.template`**: eliminados el `upstream acervo_console` y los `location ^~ /acervo/console/static/` y `^~ /acervo/console/`. Acervo migro de MinIO a SeaweedFS, cuya Filer UI no tiene autenticacion propia y no debe exponerse sin una capa de auth; la administracion de archivos se hace por `mc`/CLI con credenciales admin. nginx fallaba al arrancar (`host not found in upstream "acervo-minio:9001"`) porque el contenedor MinIO ya no existe.
- **`.env.example`, `docker-compose.yml`, `Dockerfile`**: retirada la variable `ACERVO_CONSOLE_HOST`, ya sin uso tras eliminar el upstream.

---

## [1.24.9] - 2026-05-12

### Fixed

- **`nginx/includes/geoserver-locations.inc`**: la directiva `valid_referers server_names *.$host $host localhost;` en los 3 bloques (`/geoserver/ows`, `/geoserver/(wfs|wcs)`, `/geoserver/[^/]+/(wfs|wcs)`) no expandia `$host` (limitacion documentada de nginx: las variables no se evaluan en `valid_referers`, solo `server_names` y literales). Reemplazada por validacion dinamica via `if + capture`: extrae el host del Referer con regex, lo compara contra `$host` (que si se expande en contexto `if =`), y permite tambien `localhost` y Referer vacio. Mantiene proteccion CSRF (cross-origin sigue dando 403), sin hardcodear hosts/IPs por entorno. Habilita WFS `DescribeFeatureType` desde el frontend cuando se accede por dominios no listados en `server_name` (ej. acceso por IP en staging).

---

## [1.24.8] - 2026-04-29

### Changed

- **`location = /acervo/ontoy`** actualizado al `static_version` de acervo 1.20.1 (mariachi privado, avatars al bucket compartido `iieg`).

---

## [1.24.7] - 2026-04-29

### Changed

- **`location = /acervo/ontoy`** actualizado al `static_version` de acervo 1.20.0 (bucket compartido `iieg` para assets institucionales + rename `sieej-diccionarios` -> `sieej`). Sin cambios en la logica del gateway.

---

## [1.24.6] - 2026-04-29

### Changed

- **`location = /acervo/ontoy`** actualizado al `static_version` de acervo 1.19.0 (bucket `mariachi` + flag `--rotate` en `init-buckets.sh`). Sin cambios en la logica.

---

## [1.24.5] - 2026-04-29

### Agregado

- **`location = /acervo/ontoy`** en bloques `:80` y `:443` con `return 200 '{"slug":"acervo","label":"Acervo","version":"1.18.1"}'`. Mismo patron que ya existe para `/geoserver/ontoy`. En modo `INFRA=gateway` no hay `acervo-nginx` (que es quien servia el `/ontoy` propio en el modo standalone), asi que el dashboard `/sistema/plataformas` de mariachi no podia probar el estado de Acervo. Solucion: gateway-hub responde el ontoy inline. Cuando el `static_version` cambie en `acervo` hay que actualizar este `return 200` y bumpear gateway-hub (igual que con geoserver). El bloque `:80` permite que el probe interno de `mariachi-api` lo alcance sin redirect a HTTPS.

---

## [1.24.4] - 2026-04-29

### Corregido

- **Acervo console: assets siguen retornando HTML tras 1.24.3**: el fix anterior (`proxy_pass http://acervo_console;` sin path) preservaba el URI completo y mandaba `/acervo/console/static/...` al upstream. Diagnostico via `wget` directo a `acervo-minio:9001` desde gateway-hub mostro que MinIO sirve los assets bajo **`/static/js/main.<hash>.js`** (Content-Type `text/javascript`, 2.3 MB), no bajo `/console/static/...` ni `/acervo/console/static/...` (ambos devolvian HTML del SPA fallback con 1.3 KB). Fix: `proxy_pass http://acervo_console/static/;` y `proxy_pass http://acervo_console/;` para mapear el prefijo del gateway a la raiz del console.

### Notas — patron correcto de proxy para MinIO console

Cuando MinIO console se configura con `MINIO_BROWSER_REDIRECT_URL=https://<dominio>/<prefijo>/console`, MinIO **emite** URLs absolutas con ese prefijo en el HTML del console (ej. `<base href="/<prefijo>/console/">`). Pero **internamente** sigue sirviendo los archivos bajo la raiz del puerto (no bajo el prefijo). El proxy debe entonces:

1. Atender el prefijo publico (`location ^~ /<prefijo>/console/`).
2. Reescribir el path al strip-ear el prefijo antes de hablar con MinIO (`proxy_pass http://upstream/`).

Lo que controla `MINIO_BROWSER_REDIRECT_URL` es la URL que aparece en las paginas servidas; lo que controla el comportamiento de los assets es el path real bajo el cual MinIO los expone (siempre `/static/`, `/styles/`, etc.).

---

## [1.24.3] - 2026-04-29

### Corregido

- **Acervo console: assets retornan HTML (`MIME type 'text/html' is not executable/supported stylesheet`)**: el `proxy_pass http://acervo_console/console/...` reescribia el path strip-eando el prefijo `/acervo/console/` y dejando solo `/console/...`. Cuando MinIO se configura con `MINIO_BROWSER_REDIRECT_URL=https://<dominio>/acervo/console` y `MINIO_SERVER_URL=https://<dominio>/acervo` (lo correcto cuando esta detras de un reverse proxy con prefijo), MinIO emite URLs absolutas con el prefijo `/acervo/console/...` y SOLO reconoce ese prefijo internamente. Con el `proxy_pass` reescribiendo a `/console/...`, MinIO devolvia su SPA `index.html` (200) para todas las rutas no reconocidas y el browser veia `Content-Type: text/html` en lugar del JS/CSS/manifest correctos. Fix: cambiar `proxy_pass http://acervo_console/console/...` a `proxy_pass http://acervo_console;` (sin path) en `location ^~ /acervo/console/static/` y `location ^~ /acervo/console/`. Sin path en el `proxy_pass`, nginx preserva el URI completo del request al upstream, y MinIO recibe el prefijo que ya espera.

### Notas

- Requiere que el operador configure `MINIO_BROWSER_REDIRECT_URL=https://<dominio>/acervo/console` y `MINIO_SERVER_URL=https://<dominio>/acervo` en el `.env.gateway` de acervo (>= acervo v1.18.1) y haga `docker compose up -d --force-recreate minio` para que los assets carguen sin error de MIME type.

---

## [1.24.2] - 2026-04-29

### Corregido

- **Warning de nginx `duplicate MIME type "text/html"`**: removidas las dos directivas redundantes `sub_filter_types text/html;` (`gtm.inc.template:4` y `gateway.conf.template:218` en el `location ^~ /acervo/console/`). nginx ya considera `text/html` como tipo MIME implicito por default para `sub_filter_types`; declararlo explicitamente cuando ambos contextos se aplican al mismo server resulta en duplicacion. El comportamiento del filter (sustitucion del CSP en la consola de Acervo y la inyeccion del snippet GTM en HTML) no cambia.

---

## [1.24.1] - 2026-04-29

### Corregido

- **Promtail spam de errores `failed to start tailer`**: el volumen nombrado `nginx_logs` se inicializo con los symlinks que la imagen `nginx:alpine` trae por default (`access.log -> /dev/stdout`, `error.log -> /dev/stderr`). Esos symlinks apuntan a `/proc/<PID>/fd/...` del proceso nginx **dentro del container de nginx**, inalcanzables desde el container de promtail. Resultado: cada 10s `lstat /proc/1/fd/pipe:[...]: no such file or directory` para `access.log` y `error.log`. Fix: el `CMD` del Dockerfile ahora hace `rm -f /var/log/nginx/access.log /var/log/nginx/error.log` antes de arrancar nginx, asi el daemon crea archivos reales en su lugar y promtail puede tail-earlos. Sigue habiendo `access_log /dev/stdout main` para que Docker capture stdout.

---

## [1.24.0] - 2026-04-29

`gateway-hub` ahora sirve el frontend estatico de SIEEJ directamente. Antes se hospedaba via `mariachi-nginx` con un `location ^~ /sieej` que montaba un bind del dist; eso rompia la separacion de capas (mariachi es una plataforma del ecosistema, no un proxy de plataformas). Ahora el dist se monta en gateway-hub y se sirve con `alias`, mismo patron que un ingress nginx con un dist puro.

### Agregado
- **`location ^~ /sieej/`** en `nginx/templates/gateway.conf.template` (bloque :443) con `alias /usr/share/nginx/html/sieej/` y `try_files $uri $uri/ /sieej/index.html` para SPA fallback. `Cache-Control: no-cache` en respuestas.
- **`location = /sieej`** redirect 301 a `/sieej/`.
- **`location = /sieej/ontoy`** en bloques `:80` y `:443` que sirve `ontoy.json` directo desde el dist (`application/json`). El bloque `:80` es necesario para que el probe HTTP interno desde `mariachi-api` (`SIEEJ_ONTOY_URL=http://gateway-hub-nginx-1/sieej/ontoy`) no sea redirigido a HTTPS.
- **`SIEEJ_DIST_PATH`** en `.env` (`../sieej/frontend/dist`); permite override en CI o cuando el dist viene de otro path.
- **Bind mount** en `docker-compose.yml`: `${SIEEJ_DIST_PATH:-../sieej/frontend/dist}:/usr/share/nginx/html/sieej:ro`.

### Notas

- mariachi en su bump correspondiente quito el bind mount de SIEEJ, el `location /sieej` de su `nginx/conf.d/mariachi.conf` y la variable `SIEEJ_DIST_PATH` de su `.env.production`. Su `SIEEJ_ONTOY_URL` ahora apunta a `gateway-hub-nginx-1`.
- sieej (repo) actualizo su documentacion (`README.md`, `docs/gateway.md`, `docs/context.md`, `docs/frontend.md`, `docs/analytics.md`, `Makefile`) para reflejar el nuevo origen del dist.

---

## [1.23.0] - 2026-04-28

`gateway-hub` ahora orquesta el ecosistema completo en local con `make local-up` y `make local-down`. Endpoint `/ontoy` propio. Cuatro bug fixes de routing detras del gateway.

### Agregado
- **`Makefile`** con reglas para levantar/tumbar el stack en local: `make local-up`/`local-down`/`local-restart`/`local-status`. `local-up` levanta en orden topologico `acervo` → `huachicol` → `mapalab-dataengine` → `geoserver` → builds dist (`sieej`, `mapalab`) → `mariachi` → `mapalab` (profile `staging`) → `gateway-hub`. Conecta `acervo-minio` a `iieg-network` (necesario para que `mariachi-api` use el SDK de MinIO directo, no via nginx).
- **`/ontoy`** propio (`alias /etc/nginx/version.json`) en `:80` y `:443` para que servicios internos lo probeen via `iieg-network` sin TLS.
- **`/geoserver/ontoy`** estatico: GeoServer no tiene endpoint nativo, gateway responde con `{"slug":"geoserver","version":"1.14.1"}`.
- `nginx/version.json` (trackeable en git).

### Corregido
- **HTTP→HTTPS redirect rompia el host original**: cambio de `https://$server_name` a `https://$host` para preservar el host del request (LAN IP, `localhost`, custom domain).
- **`server_name ${APP_DOMAIN};` no respondia a otros hosts**: agregado `_` como catch-all + `listen ... default_server`.
- **`Welcome to nginx!` en cualquier ruta**: la imagen `nginx:1.28.2-alpine` ships con `default.conf` (server_name `localhost`) que ganaba como default. Fix: `RUN ... && rm -f /etc/nginx/conf.d/default.conf` en `Dockerfile`.
- **`/mariachi/` redirigia a HTTP**: `proxy_pass http://mariachi/` (con slash) strip-eaba el prefix; mariachi-nginx recibia `GET /` y respondia 302 a `/mariachi/` en HTTP. Fix: `proxy_pass http://mariachi` (sin slash) preserva el path.
- **`/acervo/console/` 502 + AccessDenied**: `proxy_pass http://acervo_console/` strip-eaba `/acervo/console/`; acervo recibia `/login` que caia en MinIO API. Fix: `proxy_pass http://acervo_console/console/`.

---

## [1.22.0] - 2026-04-23

### Agregado
- **`docs/ecosystem.md`** — overview cross-project del ecosistema IIEG. Sirve como autoridad sobre el versionado visible en cada plataforma y el contexto transversal (interacciones entre repos, deploy targets, owners). Pointer en el README a la version actual.

---

## [1.21.0] - 2026-04-23

### Agregado
- **`scripts/check_model_drift.py`** — checker de drift entre los modelos SQLAlchemy de `mariachi.api.app.models.mapalab` y `mapalab-dataengine`. Detecta divergencias en columnas/tipos/constraints antes del deploy.

---

## [1.20.0] - 2026-04-23

### Cambiado
- **Bloqueo de endpoints admin-only de MapaLab desde acceso externo**: rutas que solo deben llegar via la red interna (ej. `/mapalab/api/layers/refresh-cache`) ahora retornan 403 si el request viene desde fuera del rango trusted.

---

## [1.19.0] - 2026-04-16

### Agregado
- **`scripts/stress-test/`** — set de scripts para simular comportamiento de usuarios reales (browser flows) y benchmarks de carga. Util para validar limits de `rate_req` y degradacion del stack bajo carga.

### Corregido
- **`/mapalab/` rompia content processing por compresion**: el upstream ya gzipea, y el gateway lo reapretaba duplicando algunos headers. Fix: `proxy_set_header Accept-Encoding ""` en el location (deshabilita compresion en respuesta del proxy para que el cliente la reciba intacta).

---

## [1.18.0] - 2026-04-15

### Agregado
- **Bot protection middleware** centralizado en `nginx/includes/bot-protection.inc` — bloquea por User-Agent (scrapers, AI bots, libs HTTP comunes como `^curl`/`^wget`/`python-requests`).
- **`/.well-known/security.txt`** servido directamente por nginx para divulgacion responsable de vulnerabilidades.

---

## [1.17.0] - 2026-04-15

### Agregado
- **`SEO_ENABLED`** env var: cuando `true` sirve `robots.txt` permisivo + `sitemap.xml`; cuando `false` retorna `User-agent: * / Disallow: /` y bloquea acceso al sitemap. Util para staging/preview que no deben indexarse.

---

## [1.16.0] - 2026-04-14

### Agregado
- **Documentacion comprehensiva** en `docs/` — `arquitectura.mmd`, `auditoria-seguridad.md`, `context.md`, `error-pages.md`, `pendientes`, `recursos-servidores.md`, `rendimiento.md`, `ssh-deploy-keys.md`.
- **Custom error pages** (`nginx/error-pages/400|401|403|404|429|500.html`) servidas via `error_page` directive con `internal`.
- **Server optimization scripts** en `scripts/` para tuning de kernel/nginx en el host.

---

## [1.15.0] - 2026-04-13

### Cambiado
- **Acervo console**: aumentado `limit_req zone=general burst=1000 nodelay`, removido `Content-Security-Policy` custom (deja que MinIO emita el suyo) y agregado `sub_filter "script-src 'self'" "script-src 'self' 'unsafe-inline' 'unsafe-eval'"` para que la UI de MinIO funcione sin CSP violations.

---

## [1.14.0] - 2026-04-13

### Cambiado
- **Removido control de acceso por VPN** en endpoints administrativos; reemplazado con rate limiting agresivo (`zone=admin burst=...`). `VPN_ALLOWED_IPS` queda como env opcional para escenarios mixtos.

---

## [1.13.0] - 2026-04-13

### Agregado
- **Filtros de seguridad WFS/WCS** en el location de `/geoserver/`: bloquea operations que listen workspaces internos o ejecuten queries no autorizadas.
- **`/mapalab/api/download/`** proxy con `proxy_buffering off` + timeouts extendidos (600s) para soportar streaming de CSVs grandes.
- Actualizada `docs/arquitectura.mmd` reflejando el nuevo flujo de download.

---

## [1.12.0] - 2026-04-02

### Cambiado
- **Mapalab proxy**: aumentado `proxy_send_timeout`/`proxy_read_timeout` a `120s` (default `60s` no alcanzaba para algunas capas pesadas) y removido el header stripping redundante (`proxy_set_header Connection ""` ya viene de `proxy-params.inc`).

---

## [1.11.0] - 2026-03-30

### Agregado
- **`extra_hosts: host.docker.internal:host-gateway`** en `docker-compose.yml` para que el container de gateway pueda hablar con servicios del host en dev/local.
- **Conditional GTM** — `gtm.inc` solo se inyecta si `GTM_ID` esta seteado; vacio en otros environments.

---

## [1.10.0] - 2026-03-25

### Cambiado
- **Removida basic auth** del gateway: el approach final es VPN allowlist + rate limiting + bot-protection. `apache2-utils` ya no es dependency del Dockerfile.
- Las locations afectadas fueron `acervo/console`, `mariachi`, `huachicol` y `geoserver` (web/security, j_spring_security, REST). Para REST de geoserver se preservo VPN allowlist.

### Notas de incidente
La basic auth se introdujo el 2026-03-24 como capa rapida de proteccion (commit `d7e834b`), pero generaba friccion para herramientas internas que no soportaban basic. Se decidio remover en bloque el 2026-03-25 una vez que VPN+rate limit cubrieron la misma superficie.

---

## [1.9.0] - 2026-03-24

### Agregado
- **Huachicol/Grafana proxy** (`location /huachicol/`): integracion del stack de monitoreo via subpath. Variables `HUACHICOL_HOST` y env del compose para apuntar al upstream correcto.
- Hotfix posterior: removido el trailing slash de `proxy_pass http://huachicol/` y deshabilitado `proxy_intercept_errors` (Grafana mostraba pagina de error del gateway en vez de su propia 401).

---

## [1.8.0] - 2026-03-24

### Agregado
- **Logging a Loki via Promtail** (`promtail/promtail-config.yml`) — todos los logs de nginx (access + error, formato JSON) se envian a Loki para consulta unificada en Grafana.
- **`nginx-exporter`** (Prometheus) en el compose — exposicion de metricas de nginx (`stub_status`) en `:8080/stub_status` para que Prometheus las scrappee.

---

## [1.7.0] - 2026-03-24

### Agregado
- **`sitemap.xml`** y **`robots.txt`** servidos directamente por nginx desde `nginx/static/`. Configuracion para que se sirvan con `Cache-Control` apropiado y sin pasar por upstream.

---

## [1.6.0] - 2026-03-24

### Agregado
- **Google Tag Manager** integrado via `sub_filter` en `nginx/includes/gtm.inc.template`. Configurable via `GTM_ID` env var; si esta vacio el include queda vacio y no se inyecta nada en el HTML.

### Cambiado
- Movido `proxy_set_header Accept-Encoding ""` desde `gtm.inc.template` hacia los `location` blocks especificos que necesitan el `sub_filter` (evita deshabilitar compresion globalmente).

---

## [1.5.0] - 2026-03-23

### Agregado
- **Content-Disposition forzado** para `.txt` y `.xlsx` desde `/acervo/` (browsers tienden a renderizarlos inline en vez de descargar; el header `Content-Disposition: attachment` los forza).
- **`proxy_intercept_errors on`** para el upstream de acervo (deja que nginx decida que pagina de error mostrar en vez de la del MinIO).

### Cambiado
- **Removido `limit_req` de `/acervo/console/`** — la consola hace muchos requests cortos (assets, polling) y caia rapidamente en rate limit. Sigue protegido por VPN allowlist.

---

## [1.4.0] - 2026-03-23

### Agregado
- **`VPN_ALLOWED_IPS`** env var para configurar el allowlist de redes internas (formato CIDR separado por comas). Aplica a locations administrativas (`/administrador/`, `/acervo/console/`, partes de `/geoserver/`).

---

## [1.3.0] - 2026-03-23

### Agregado
- **Rate limiting para descargas de GeoServer** (`limit_req zone=geoserver_download`) — protege contra abuse de WFS/WCS que pueden generar payloads grandes.
- **Bot blocking refinado**: lista actualizada de User-Agents bloqueados.
- **Manejo centralizado de error pages** via `error_page` directive con paginas custom.
- **`docs/ssh-deploy-keys.md`** — documentacion del flujo de generacion y rotacion de SSH deploy keys para CI/CD.

### Corregido
- **`ignore_invalid_headers off`** movido al server block (antes estaba en http block, no aplicaba a server-level overrides).

---

## [1.2.0] - 2026-03-20

### Agregado
- **Servicio Acervo Console** (`location /acervo/console/`) — proxy hacia el console de MinIO con su propio rate limiting y headers ajustados.
- Refinado el proxy de Acervo API (`location /acervo/`).

---

## [1.1.0] - 2026-03-19

### Agregado
- **Redirect del root** `/` → `/mapalab/` (302) para que el dominio raiz lleve al visor por defecto.
- `.gitignore` ajustado para manejar archivos `.env` correctamente.

---

## [1.0.0] - 2026-03-13

Primera version del gateway-hub.

### Agregado
- **Nginx gateway hub** con Docker support: nginx 1.28.2-alpine, configuracion modular (`nginx.conf` + `conf.d/` + `templates/` + `includes/`).
- **GeoServer configuration** — proxy completo hacia GeoServer con caching para tiles WMS.
- **Custom error pages** iniciales.
- **Diagrama arquitectural** (`docs/arquitectura.mmd`).
- **SSL configurable** via `SSL_CERTIFICATE`/`SSL_CERTIFICATE_KEY` env vars.
- Compose con `extra_hosts: host.docker.internal:host-gateway`, network `iieg-network` external.
