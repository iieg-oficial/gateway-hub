# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato esta basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semantico](https://semver.org/lang/es/). El
versionado del repo `gateway-hub` es independiente del de Nginx; aqui registramos los
cambios sobre las rutas, certificados, headers de seguridad, rate limits y la
configuracion de promtail. Bumps por caracteristica registrada en commit.

## [No publicado]

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

- **`nginx/nginx.conf`** → **`nginx/templates/nginx.conf.template`** (renombrado + tratamiento via `envsubst`). La directiva `set_real_ip_from 10.13.128.0/24;` ahora es `set_real_ip_from ${REAL_IP_FROM};`. Antes el rango trusted estaba hardcoded; cualquier ajuste (segundo balanceador, IPv6, prod multi-LAN) requeria editar el archivo y rebuildear.
- **`Dockerfile`**: el `COPY nginx/nginx.conf` se reemplazo por el template; el CMD ahora corre `envsubst '${REAL_IP_FROM}'` antes de los otros templates para generar `/etc/nginx/nginx.conf`. La whitelist explicita evita que envsubst toque `$remote_addr`, `$binary_remote_addr`, etc.
- **`.env`, `.env.example`** y **`docker-compose.yml`** (environment del servicio `nginx`): variable `REAL_IP_FROM` con default `10.13.128.0/24`. Si esta vacia, `set_real_ip_from` queda sin valor y nginx falla al arrancar — el default cubre el caso de `.env` heredado sin la variable.

#### Notas

- En local el real_ip queda inerte (no entra trafico via XFF desde 10.13.128.0/24), pero la directiva es valida y no rompe. En GCP prod sigue siendo el rango del FortiGate estatal.
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
