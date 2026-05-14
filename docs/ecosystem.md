# Ecosistema IIEG - Vista Transversal

> Documento de referencia cruzada entre los cuatro proyectos que componen la infraestructura IIEG: `gateway-hub`, `mapalab`, `mariachi` y `dataengine`.
>
> Este archivo NO reemplaza los `docs/context.md` de cada repo — los complementa. Cada repo documenta lo suyo; este documento documenta lo que **solo se ve cuando se miran juntos**: flujos cruzados, acoplamientos, decisiones arquitectonicas compartidas y deuda tecnica coordinada.
>
> Ultima actualizacion: 2026-05-14

---

## 1. Alcance

Los cuatro repos son:

| Repo | Rol | Context local |
|---|---|---|
| `gateway-hub` | Proxy inverso + SSL + cache + rate limiting + SEO | `gateway-hub/docs/context.md` |
| `mapalab` | Visor publico de mapas (frontend + backend FastAPI) | `mapalab/docs/context.md` |
| `mariachi` | CMS del portal + admin de capas + emisor de auth | `mariachi/docs/context.md` |
| `dataengine` | PostgreSQL 18 + PostGIS 3.6 + cron jobs de refresh | `dataengine/docs/context.md` |

Servicios adicionales que aparecen en el ecosistema pero no son repos hermanos: **GeoServer** (externo, kartoza 2.27.0), **Acervo** (SeaweedFS, almacenamiento S3-compatible — migrado desde MinIO), **SIEEJ** (frontend estatico servido por el gateway; backend en `mariachi/api`), **Huachicol** (Grafana + Prometheus + Loki + Alloy), **IGIBot** (K3s, no pasa por gateway).

---

## 2. Topologia fisica y de red

### Produccion (4 servidores en GCP)

| Servidor | CPU | RAM | Disco | Servicios |
|---|---|---|---|---|
| S1 | 8c | 15 GB | 637 GB | gateway-hub + Huachicol + Acervo |
| S2 | 4c | 7.7 GB | 96 GB | mapalab (nginx + backend) |
| S3 | 8c | 15 GB | 490 GB | GeoServer |
| S4 | 4c | 7.7 GB | 490 GB | dataengine (Postgres + jobs) |

Detalles completos en `gateway-hub/docs/recursos-servidores.md`.

### Red logica

Todos los contenedores viven en la red Docker externa `iieg-network`. Gateway enruta por path:

```
Internet :443
   |
   v
gateway-hub (Nginx, S1)
   |
   +-- /                   --> portal (congelado; redirige a /mapalab/)
   +-- /api/               --> backend mariachi (portal publico)
   +-- /administrador/     --> admin mariachi (CMS)
   +-- /mapalab/           --> mapalab-nginx --> mapalab-backend
   +-- /mapalab/api/       --> mapalab-backend (via mapalab-nginx)
   +-- /acervo/            --> Acervo SeaweedFS (API S3)
   +-- /sieej/             --> Frontend SIEEJ (estatico, dist/ montado en el gateway)
   +-- /mariachi/          --> MARIACHI CMS/admin (VPN only)
   +-- /huachicol/         --> Grafana (VPN only)
   +-- /huachicol/public/  --> Grafana dashboards publicos
   +-- /geoserver/ows      --> GeoServer WMS/WFS/WCS (cache 6h)
   +-- /geoserver/{ws}/wfs --> GeoServer WFS por workspace (no cache, timeout 600s)
   +-- /geoserver/{ws}/wcs --> GeoServer WCS por workspace
   +-- /geoserver/web|rest --> Admin GeoServer (auth propia)

mariachi --(SQLAlchemy directo)--> dataengine
mapalab  --(SQLAlchemy directo)--> dataengine
mariachi --(HTTP interno iieg-network)--> mapalab-backend
GeoServer --(SQL)--> dataengine
```

---

## 3. Flujos de datos cruzados criticos

### 3.1. Edicion de una capa

Flujo completo cuando un admin edita una capa del visor desde el CMS:

```
1. Admin abre /administrador/mapalab/layers (mariachi CMS)
2. Mariachi valida cookie JWT + CSRF
   Cookie scope = COOKIE_DOMAIN (subdominio compartido)
3. Mariachi escribe en DataEngine.mapalab.layers
   via engine SQLAlchemy #2 (DATAENGINE_DATABASE_URL)
4. Mariachi dispara notify_tree_changed()
   --> httpx.post(MAPALAB_BACKEND_URL + '/layers/refresh-cache')
   --> llamada directa interna, NO pasa por gateway
   --> debounce 5s, timeout 5s, WARN en log si falla
5. Mapalab backend ejecuta refresh_cache()
   --> regenera mapalab.layer_tree_cache (JSON singleton en DB)
   --> invalida cache en memoria del worker que atendio
6. Frontend recibe tree via GET /mapalab/api/layers/tree (ETag)

Backstop (por si el paso 4 falla):
7. dataengine-jobs cron 04:00 UTC reconstruye layer_tree_cache
```

**Frágil hoy**: pasos 4-5 no tienen retry ni idempotencia cross-servicio. Si el `POST` se pierde, el tree queda stale hasta las 04:00.

### 3.2. Descarga CSV (streaming cross-service)

```
Frontend
  --> gateway (600s timeout, proxy_buffering off, rate limit zone=api burst=5)
    --> mapalab-nginx (600s timeout, proxy_buffering off)
      --> mapalab-backend
        --> PostgreSQL COPY TO STDOUT (streaming)
          <-- CSV en chunks hasta el browser
```

Los tres timeouts estan alineados en 600s. El commit `4d1689b` removio compresion del proxy de mapalab — relevante para mantener streaming sin corrupcion.

### 3.3. GetMap WMS (publico, alto volumen)

```
Frontend OpenLayers
  --> gateway /geoserver/ows (cache key = $request_uri$arg_outputFormat, TTL 6h)
    --> GeoServer (S3)
      --> PostgreSQL PostGIS (S4)
```

Validaciones en gateway antes del cache: Referer + User-Agent + bloqueo WFS-T. Cache hit evita S3 y S4 completos.

### 3.4. Refresh jobs nocturnos (dataengine)

Container `dataengine-jobs` (en S4) corre cron:

| UTC | Job | Resultado |
|---|---|---|
| 03:00 | `run_refresh_periodicity.py` | Reconstruye `public.layer_periodicity` via `SELECT public.refresh_layer_periodicity()` |
| 04:00 | `run_refresh_layer_tree.py` | Reconstruye `mapalab.layer_tree_cache` desde `mapalab.layers` |
| 04:30 | `run_refresh_layer_stats.py` | Ejecuta SQL de `stats_config`, guarda en `layer_stats.values` |

Trigger manual desde `dataengine`: `make refresh-all`.

---

## 4. Capas de cache apiladas

Cinco capas de cache entre el browser y la DB. Entender cual invalida cual importa para debuggear staleness.

| Nivel | Qué cachea | TTL | Invalidacion |
|---|---|---|---|
| Browser | Assets Vite (hash en nombre) | `immutable` 1 año | Nuevo hash en rebuild |
| Gateway | `/mapalab/assets/*` | 7 dias, stale-on-error | Hash-based, auto |
| Gateway | GeoServer WMS/WFS | 6 horas, 2GB max | Solo por TTL |
| mapalab-nginx | gzip + open_file_cache | 30s | Auto |
| mapalab-backend | ETag + dict en memoria del worker | Hasta refresh | `POST /refresh-cache` (ver 4.1) |
| DataEngine | `mapalab.layer_tree_cache` JSON singleton | Hasta refresh | Cron 04:00 + mariachi webhook |
| DataEngine | `mapalab.layer_stats.values` | Hasta refresh | Cron 04:30 |
| DataEngine | `public.layer_periodicity` | Hasta refresh | Cron 03:00 |

### 4.1. Coordinacion de cache entre workers gunicorn (resuelto 2026-04-23)

Mapalab corre 8 workers Gunicorn-async en produccion. `layer_tree_service._MEM_CACHE` es un dict module-level — por proceso, no compartido — asi que cada worker tiene su propia copia.

**Problema original**: `get_cached_state()` servia desde memoria sin validar contra DB. Consecuencias:

- Admin edita capa → mariachi POST `/refresh-cache` → aterriza en **un** worker → ese worker actualiza DB + su memoria. Los otros 7 workers siguen con la version vieja en memoria.
- El cron `dataengine-jobs 04:00` actualiza la DB pero **no toca los workers**. Todos los workers con memoria poblada siguen sirviendo stale indefinidamente.
- Unica mitigacion previa: `POST /invalidate-cache` por worker (el load balancer impide garantizar que alcance a todos).

**Fix aplicado**: `get_cached_state()` ahora hace un SELECT ligero del `etag` de `mapalab.layer_tree_cache` en cada llamada y lo compara contra `_MEM_CACHE['etag']`:

- Match: devuelve memoria (sin re-parseo del tree JSON).
- Mismatch: re-lee la fila completa y repuebla memoria.

Costo: 1 query de indice por request (sub-ms). Beneficio: los 8 workers se autosincronizan contra DB en su siguiente request, sin pub/sub ni signals. Tambien recupera el efecto del cron nocturno — antes perdido para workers en memoria.

Archivo: `mapalab/backend/app/services/layer_tree_service.py::get_cached_state`.

---

## 5. Acoplamientos que hay que conocer

### 5.1. Dos escritores, un schema

El schema `mapalab.*` en DataEngine tiene dos escritores legitimos:

| Tabla | Escritor principal | Lector principal | DDL vive en |
|---|---|---|---|
| `layers` | mariachi (CRUD) | mapalab (tree) | mariachi Alembic (hoy) / bootstrap SQL (historico) |
| `workspaces` | mariachi | mapalab + mariachi | mariachi Alembic |
| `initial_layer_order` | mariachi | mapalab | mariachi Alembic |
| `layer_metadata` | mariachi | mapalab | ambigüo |
| `layer_stats` (config) | mariachi | dataengine-jobs | ambigüo |
| `layer_stats` (values) | dataengine-jobs | mapalab | dataengine bootstrap |
| `layer_tree_cache` | dataengine-jobs + mapalab | mapalab | dataengine bootstrap |
| `layer_periodicity` | dataengine-jobs | mapalab | dataengine scripts |

**Decision pendiente**: ownership unico de migraciones. Ver seccion 7.3.

### 5.2. Auth compartida via cookie

Solo mariachi emite auth. El truco es el scope de cookie:

- `COOKIE_DOMAIN=app.dominio.com` (subdominio compartido)
- Cookie JWT es HttpOnly, Secure, SameSite=lax
- Vale para `/administrador/*` (valida en mariachi con CSRF)
- Vale tambien para `/mapalab/*` **aunque mapalab no la usa** — todos los endpoints publicos de mapalab son anonimos.
- El visor solo la aprovecha para futuras features de preview/admin.

Implicacion: **no existe hoy un endpoint de mapalab que valide auth**. Si mañana se necesita (ej. admin embedded), mapalab tendria que aprender a validar el JWT compartido sin emitirlo.

### 5.3. Endpoints admin de mapalab

Mapalab backend tiene dos endpoints administrativos:

- `POST /layers/refresh-cache` — invocado por mariachi tras editar capas
- `POST /layers/invalidate-cache` — invocacion manual/debug

Ambos son llamados por mariachi **directamente via `iieg-network`** (no via gateway), usando `MAPALAB_BACKEND_URL=http://mapalab-backend:8000`. El gateway bloquea el acceso externo a estos paths con `return 403` (ver `nginx/templates/gateway.conf.template`).

### 5.4. Rename portal --> mariachi a medias (2026-04-22)

Intencional segun `mariachi/docs/context.md`. Resumen:

- **Cambiado**: carpeta, container names, docker networks, archivos compose.
- **No cambiado**: URL `/api/portal`, DB `iieg_portal`, branding UI, upstream `portal` en gateway.

Por que no cambio todo: conflicto de nombres con otro upstream ya existente en el gateway. Mantener `PORTAL_HOST` apuntando a `mariachi-nginx-*` es el compromiso. Para el lector desprevenido del `.env` del gateway, esto parece inconsistente.

---

## 6. Decision arquitectonica: mapalab y mariachi siguen separados

Se evaluo unificar backends. **Decision: NO mergear**.

### Razones

Perfiles de riesgo opuestos:

| | mapalab backend | mariachi backend |
|---|---|---|
| Trafico | Publico, alto volumen | Interno, bajo volumen |
| Auth | Ninguna (todo publico) | JWT + CSRF + cookies |
| Workload tipico | CSV 600s, tiles WMS, metadatos | CRUDs cortos |
| Deps | PostGIS, COPY streaming, httpx GeoServer | S3/SeaweedFS, Redis, bcrypt, Alembic multi-env |
| SLA esperado | Caida = sitio publico roto | Caida = editores esperan |

Un merge significaria que un bug del CMS tira el visor, o un `COPY TO STDOUT` grande bloquea un worker que deberia atender admin. Tambien expande el attack surface publico.

### Como cerramos el gap sin mergear

1. **Proteger endpoints admin** (hecho 2026-04-23): gateway retorna 403 en `/mapalab/api/layers/refresh-cache` e `/invalidate-cache`.
2. **Paquete Python compartido** (pendiente): modelos SQLAlchemy y schemas Pydantic de `mapalab.*` instalados como dep en ambos repos. Evita model drift.
3. **Mover CRUD de capas mariachi --> mapalab** (opcional, mas invasivo): llevar los routers `layers.py`, `layer-metadata.py`, `geoserver.py` de mariachi a mapalab bajo `/mapalab/api/admin/*` con validacion de la cookie compartida. Elimina el HTTP call cross-service y deja mariachi como CMS del portal puro.

---

## 7. Deuda tecnica transversal

Estos items aparecen en mas de un repo y requieren coordinacion.

### 7.1.1. Migracion prod one-shot (preparado 2026-04-23)

Para el deploy a produccion — donde mariachi aun no existe, el Sheet es la fuente de verdad, y dataengine esta en una version LTS anterior — hay un script que orquesta todo en una llamada:

```bash
cd /IIEG/dataengine
make prod-migration            # ETL Sheet + bootstrap + seed + migrate + stamp
# Override del JSON de capas:
make prod-migration PROD_MIGRATION_FLAGS="--layers-json /ruta/custom.json"
# Solo bootstrap (sin ETL, util en dev/staging sin credenciales Google):
make prod-migration PROD_MIGRATION_FLAGS="--skip-etl"
```

Es el **unico target** relacionado al bootstrap (antes habia `bootstrap-v14`, `bootstrap-v14-dry`, `migrate-mapalab-card` — consolidados aqui).

Que hace, en orden:

- **A. Pull final del Google Sheet -> `public.mapalab_card`**: restaura el ETL legacy desde el commit `1f70a88~1` en `jobs/_legacy_etl/` (gitignored), lo corre via `docker compose exec jobs` con `FORCE_LEGACY_ETL=1`, y limpia al terminar. El ETL hace `DELETE + INSERT` — sobrescribe `mapalab_card` completo con el ultimo snapshot del Sheet. **Esta parte es la unica "destructiva" del flujo**.
- **B. Bootstrap v1.4.0**: invoca `scripts/bootstrap-v14.sh` (crea schema, aplica `v14_schema.sql`, seed de layers desde JSON, migracion `mapalab_card -> layer_metadata + layer_stats`, stamp alembic en `dataengine@head`). Todo upsert, **no destructivo**.

**Pre-reqs en `.env` de prod** (si no `--skip-etl`):

- `MAPALAB_CARD_GOOGLE_CREDENTIALS_PATH` — ruta al JSON del service account (no versionado).
- `MAPALAB_CARD_GOOGLE_SHEET_URL` — URL del Sheet.
- `DATAENGINE_DB_*` o `POSTGRES_*` — credenciales DB.

**Warning operativo**: este script esta diseñado para correrse **una vez**, durante la ventana de migracion donde mariachi aun no existe en prod. Re-correrlo DESPUES de que haya ediciones en mariachi sobrescribiria esas ediciones (los upserts del paso B vienen del JSON baseline + mapalab_card, no de mariachi). Post-migracion, **congelar el Sheet** y usar unicamente mariachi.

### 7.1. Drop `public.mapalab_card` (preparado 2026-04-23, ejecucion pendiente)

- **Estado**: tabla viva en produccion como respaldo. MapaLab v1.7.0 ya no la lee. ETL Google Sheets eliminado. Herramienta de migracion idempotente preservada en `dataengine/jobs/bootstrap/run_migrate_mapalab_card.py`.
- **Script de validacion + drop**: `dataengine/scripts/drop_mapalab_card_validation.sql`. Corre 4 checks (conteo comparativo, orfanos, sample de equivalencia, grep externo) antes del DROP, que queda comentado.
- **Workflow para ejecucion**:
  1. `psql -f scripts/drop_mapalab_card_validation.sql` en produccion.
  2. Verificar que la seccion 2 (layer_keys sin layer_metadata) devuelve 0 filas.
  3. Descomentar el bloque `DROP` al final del archivo y re-ejecutar.
  4. Post-drop: borrar `jobs/bootstrap/run_migrate_mapalab_card.py` y limpiar referencias en `scripts/bootstrap-v14.sh`.
- **Owner**: dataengine.

### 7.2. Retry + logging del webhook mariachi --> mapalab (resuelto 2026-04-23)

- **Problema original**: `POST /layers/refresh-cache` fallaba silencioso. Un warning en log y chau — tree stale hasta cron 04:00.
- **Fix aplicado**: `mapalab_notifier._do_notify()` ahora reintenta hasta 3 veces con backoff exponencial (0.5s, 1s). Tras agotar intentos: `logger.error` con mensaje explicito + incremento del counter `mariachi_tree_notify_failed_total` (expuesto en `/metrics` para Loki/Prometheus alertar).
- **Archivos**: `mariachi/api/app/services/mapalab_notifier.py` + counter en `mariachi/api/app/api/metrics.py`.
- **Tests**: `test_notifier_retries_on_failure`, `test_notifier_succeeds_on_retry` en `tests/test_integration_notify.py`. Bonus: se arreglo el patch pattern recursivo que dejaba 4 tests pre-existentes fallando.
- **Pendiente (fix robusto opcional)**: mariachi marca flag `mapalab.layer_tree_dirty=true` en DB; mapalab lee flag antes de servir tree. Hoy el etag-check de mapalab (seccion 4.1) ya cubre el caso general, asi que este fix robusto es baja prioridad.

### 7.3. Ownership de migraciones del schema `mapalab.*` (resuelto 2026-04-23)

**Estado detectado**: DDL duplicado real.

- `dataengine/jobs/bootstrap/v14_schema.sql` (129 lineas, idempotente via `IF NOT EXISTS`)
- `mariachi/api/alembic/versions/dataengine/20260422_000[1-3]_*.py` (266 lineas, branch label `dataengine`)

Ambos crean el mismo schema `mapalab.*`. Riesgo de divergencia al agregar columna/tabla.

**Decision tomada**: **Alembic (en mariachi) es la fuente autoritativa de DDL del schema `mapalab.*` hacia adelante.**

- `v14_schema.sql` queda **frozen**: sirve como baseline idempotente para bootstrap de ambientes nuevos (v1.4.0 schema completo). No se toca mas.
- Cambios futuros de schema viven unicamente en `mariachi/api/alembic/versions/dataengine/` (proximo sera `0004_*`).
- Si alguien necesita cambiar el DDL en dataengine, primero escribe la migracion en mariachi alembic, aprueba/mergea, y luego aplica.
- Bootstrap de ambientes nuevos sigue invocando `scripts/bootstrap-v14.sh` (que corre `v14_schema.sql` + stampea alembic en `dataengine@head` automaticamente si detecta el container mariachi corriendo). Cambios posteriores: `alembic -x db=dataengine upgrade dataengine@head`.

**Guardrail**: `gateway-hub/scripts/check-model-drift.py` (seccion 7.4) detecta drift entre los modelos SQLAlchemy de mapalab y mariachi — sirve de test indirecto para la politica.

**Cleanup futuro opcional** (no urgente): refactor `bootstrap-v14.sh` para correr alembic en vez de `v14_schema.sql`, y luego borrar `v14_schema.sql`. Requiere que el container `dataengine-jobs` tenga acceso a mariachi alembic (exec cross-container o copiar migraciones). Baja prioridad porque el baseline no cambia.

### 7.4. Contrato de modelos mariachi <--> mapalab (resuelto 2026-04-23)

- **Problema**: ambos repos definen SQLAlchemy models para las mismas tablas del schema `mapalab.*`. Drift silencioso si uno agrega o cambia columna.
- **Fix aplicado**: `gateway-hub/scripts/check-model-drift.py`. Parsea ambos archivos con AST (sin importar ninguno de los backends — sin deps), extrae columnas de las tablas compartidas (`workspaces`, `layers`, `initial_layer_order`, `layer_metadata`, `layer_stats`) y reporta cualquier diferencia en nombre o firma (tipo, nullable, default). Exit 0 si alineados, 1 si hay drift.
- **Hoy**: modelos alineados. Verificado con cambios artificiales de columna y de tipo.
- **Uso local**: `gateway-hub/scripts/check-model-drift.py` (asume paths `/IIEG/mapalab/...` y `/IIEG/mariachi/...`; override con `--mapalab` / `--mariachi`).
- **Pendiente**: integrar en CI de ambos repos como un step que hace checkout del otro repo y corre el script. No urgente — puede correrse manualmente pre-PR mientras tanto.
- **Fix estructural opcional**: publicar un paquete Python `iieg-mapalab-schema` interno con los modelos y consumirlo como dep en ambos repos. Elimina la duplicacion en vez de solo detectarla.

### 7.5. Renames pendientes

| Item | Script | Estado |
|---|---|---|
| Repo GitHub `portal` --> `mariachi` | `mariachi/scripts/rename-github-repo.sh` | Listo, no ejecutado. Requiere primero renombrar en GitHub web (`Settings > Repository name`), luego correr el script con `GH_OWNER`, `GH_OLD_REPO`, `GH_NEW_REPO` y `--execute`. El script solo actualiza el remote local. |
| Bucket Acervo | `mariachi/scripts/migrate-acervo-bucket.sh` | Script verificado (syntax OK, dry-run por default). Pre-reqs: `mc` (cliente MinIO) instalado, credenciales en `.env.development`. **Gotcha** (2026-04-23): bucket local se llama `portal` no `portal-dev`. Override con `SOURCE_BUCKET=portal ./scripts/migrate-acervo-bucket.sh --execute`. |
| Credenciales DataEngine prod para mariachi | — | Requiere coordinacion con equipo infra |

### 7.6. Documentacion desalineada (resuelto 2026-04-23)

- **DataEngine README** (verificado): README actual ya dice "dump semanal (domingos 02:00 UTC)" — alineado con crontab y CHANGELOG.
- **DataEngine compose** (verificado): el mount `${BACKUP_DATA}/mapalab_card:/app/data/backups` ya no existe — se removio junto con el ETL legacy.
- **Versionado visible**:
  - `dataengine/README.md`: ya tenia `**Version:** 1.5.0` ✓
  - `mariachi/README.md`: agregado `**Version:** 0.12.0` ✓
  - `gateway-hub/README.md`: versionado rolling (sin tags/CHANGELOG formal), README apunta a `docs/context.md` y `docs/ecosystem.md` para estado actual ✓
  - `mapalab/README.md`: auto-sync desde `package.json` via pre-commit hook (el patron original).

### 7.7. Archivos huerfanos (resuelto 2026-04-23)

Eliminados del working tree (pendiente commit del usuario):

- `dataengine/postgres/replica/start-replica.sh`
- `dataengine/postgres/primary/init/02-init-replication.sh`

### 7.8. Version de PostgreSQL (verificado 2026-04-23)

- Mariachi: `postgres:18-alpine` en `docker-compose.yml` y `docker-compose.dev.yml`.
- DataEngine: PostgreSQL 18 + PostGIS 3.6.

Sin drift. El `mariachi/docs/context.md` mencionaba "prod en 16" pero es documentacion desactualizada — no hay referencia a postgres 16 en el codebase actual.

---

## 8. Indice de contexto por repo

Para detalles operativos (como correr, como desplegar, convenciones internas) ver el `context.md` de cada repo:

| Tema | Repo que lo documenta |
|---|---|
| Stack y endpoints de mapalab backend | `mapalab/docs/context.md` + `mapalab/docs/backend.md` |
| Arquitectura frontend mapalab (providers, hooks, URL sync) | `mapalab/docs/context.md` secciones 4-5 |
| CMS mariachi: paginas, menu, media, revision queue | `mariachi/docs/context.md` + `mariachi/docs/DRAFTS.md` |
| Editor de capas en mariachi (v1.4.0+) | `mariachi/docs/context.md` seccion 8 + 12 |
| Rate limiting, cache, capacidades del gateway | `gateway-hub/docs/context.md` + `gateway-hub/docs/rendimiento.md` |
| Recursos hardware por entorno | `gateway-hub/docs/recursos-servidores.md` |
| Bootstrap v1.4 de MapaLab (seed + migracion) | `dataengine/docs/context.md` + `scripts/bootstrap-v14.sh` |
| Credenciales DataEngine y multi-env Alembic | `mariachi/docs/DATAENGINE_CREDENTIALS.md` + `mariachi/docs/ALEMBIC_MULTI_ENV.md` |
| Cookies, CSRF, modelo de seguridad | `mariachi/docs/COOKIES_CSRF.md` |
| Arquitectura de capas MapaLab (jerarquia, CQL, time) | `mapalab/docs/layers.md` |
| CI/CD mapalab | `mapalab/docs/ci-cd.md` |

---

## 9. Cambios recientes que afectan a mas de un repo

### 2026-05-14

- Acervo migro de **MinIO a SeaweedFS** (`acervo-seaweedfs:8333`, API S3-compatible). SeaweedFS no expone consola web, asi que el gateway retiro el upstream `acervo_console` y las rutas `/acervo/console/`. La administracion de archivos pasa a ser por CLI (`mc`/scripts).
- Gateway: SIEEJ se sirve como **estatico** desde el gateway — el `dist/` del frontend se monta read-only (`SIEEJ_DIST_PATH`) y se expone en `/sieej/`. El backend de SIEEJ vive en `mariachi/api` (schema `sieej`).
- Gateway: zona de rate limit dedicada `huachicol` (30 r/s) y ruta publica `/huachicol/public/` para dashboards abiertos de Grafana.
- Gateway: endpoints `/ontoy` (gateway, geoserver, acervo, sieej) que devuelven JSON de version para el dashboard de plataformas de MARIACHI.

### 2026-04-23

- Gateway: bloqueo externo de `/mapalab/api/layers/refresh-cache` e `/invalidate-cache` (seccion 5.3). Mariachi no se ve afectada porque invoca directo al backend via `iieg-network`.
- Creacion de este documento.
- Mapalab: `layer_tree_service.get_cached_state()` ahora revalida contra DB via etag check por request. Cierra la ventana de staleness cross-workers (seccion 4.1).
- Mariachi: `mapalab_notifier` gana retry con backoff exponencial (3 intentos) + counter de fallos `mariachi_tree_notify_failed_total` (seccion 7.2). Se arreglo patch pattern recursivo que dejaba 4 tests pre-existentes fallando.
- Gateway: `scripts/check-model-drift.py` agregado. Detecta drift entre modelos SQLAlchemy de mapalab y mariachi sobre el schema `mapalab.*` (seccion 7.4).
- DataEngine: `jobs/bootstrap/layers_export.json` generado (250 nodos, 9 temas) recuperando las definitions hardcoded que se removieron en el commit `9631815`. `prod-migration.sh` usa este JSON por default — ya no se requiere pasarlo explicitamente ni el script `export_layers_to_json.mjs` (que nunca existio). Override con `PROD_MIGRATION_FLAGS="--layers-json /ruta/custom.json"` si se necesita otro.
- DataEngine: `scripts/prod-migration.sh` + `make prod-migration` agregados. Orquesta pull final del Sheet + bootstrap v1.4.0 + seed + migrate + stamp alembic en una sola invocacion (seccion 7.1.1). Uso one-shot para la ventana de deploy a produccion donde mariachi aun no existe.
- Mariachi y dataengine: politica de ownership del schema `mapalab.*` formalizada — alembic autoritativo, `v14_schema.sql` frozen (seccion 7.3). Marcas en `v14_schema.sql` y docs de ambos repos.
- Dataengine: eliminados archivos huerfanos de replica streaming (seccion 7.7). Script SQL para drop futuro de `public.mapalab_card` preparado (seccion 7.1).
- Mariachi y gateway-hub: versionado visible en README (0.12.0 y rolling respectivamente, seccion 7.6).
- README drift de dataengine backup verificado (ya estaba correcto).
- Mount obsoleto `${BACKUP_DATA}/mapalab_card` en dataengine compose verificado (ya no existe).
- Confirmado que mapalab backend solo tiene 2 endpoints admin (`refresh-cache`, `invalidate-cache`), ambos bloqueados en gateway.
- PostgreSQL 16 vs 18: falso drift (dataengine y mariachi ambos en 18). `mariachi/docs/context.md` corregido.

### 2026-04-22

- Rename portal --> mariachi (container, red, compose). Ver `mariachi/docs/context.md` seccion 2.
- MapaLab v1.7.0: drop legacy `mapalab_card` del backend. Ver `mapalab/docs/CHANGELOG.md`.
- Mariachi v1.4.0: integracion DataEngine con segundo engine SQLAlchemy lazy.
