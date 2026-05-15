# Checklist de produccion — GCP (mapalab-iieg.app)

Estado y pendientes para validar la VM en GCP tras la migracion del modelo de
buckets a SeaweedFS (acervo 1.22.x+, gateway-hub 1.24.16+, mariachi 1.0.4+).

---

## A. Validacion inmediata (smoke test)

Hard reload (Ctrl+Shift+R) en `https://mapalab-iieg.app/mariachi/` y confirma:

- [ ] `/sistema/plataformas` muestra todas las plataformas verdes con su version
      actual: gateway-hub 1.24.16, acervo 1.22.1, dataengine 1.14.3, huachicol
      1.19.2, geoserver 1.20.1, mariachi 1.0.4, mapalab 1.28.5+, sieej 1.11.0+.
- [ ] `/media` muestra los buckets en el select: **Portal, MapaLab, SIEEJ,
      Mariachi, IIEG** (DataEngine sigue oculto con `is_active=false`).
- [ ] Subir un archivo a Mariachi desde `/media` → aparece en la lista.
- [ ] `/perfil`:
  - "Elegir generico" abre el picker en modo grid con los avatars del bucket
    `iieg/avatars/`.
  - "Subir personalizado" sube al bucket privado `mariachi/avatars/u<id>/` y se
    muestra en el avatar.
  - Tras "Guardar cambios" + recargar la pagina, el avatar persiste.
- [ ] `/sieej/` carga el frontend.
- [ ] `/mapalab/` carga el visor.
- [ ] `https://mapalab-iieg.app/geoserver/ows?service=WMS&request=GetCapabilities`
      devuelve XML (no 403). Un `curl -X POST` a la misma ruta debe devolver
      **405** (WFS-T bloqueado por `limit_except` en gateway-hub 1.24.15+).

> Acervo migro de MinIO a SeaweedFS en `acervo 1.22.0`. La consola web ya no
> existe (`/acervo/console/` fue removida del gateway en `1.24.10`). La
> administracion de archivos se hace por CLI (`mc` o `weed shell` dentro del
> contenedor `acervo-seaweedfs`).

Si algo falla, ver seccion "Diagnostico" mas abajo.

---

## B. Seguridad pendiente (importante antes de tráfico real)

Hoy `SECRET_KEY` y `CSRF_SECRET_KEY` comparten valor entre dev/staging/prod
(anti-patron). `MAPALAB_INTERNAL_TOKEN` debe estar **identico** en
`mariachi/.env.production` y en `mapalab/.env.production` desde mapalab 1.28.5
(el backend rechaza requests sin el token).
`CREATE_SAMPLE_USERS=true` en prod crea usuarios sample (`editora123`,
`disenadora123`) en cada arranque — riesgo en prod.

```bash
cd ~/mariachi

# 1. Generar 3 secrets nuevos:
NEW_SK=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
NEW_CK=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
NEW_TOK=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
echo "SECRET_KEY=$NEW_SK"
echo "CSRF_SECRET_KEY=$NEW_CK"
echo "MAPALAB_INTERNAL_TOKEN=$NEW_TOK"

# 2. Editar .env.production y reemplazar los 3 valores con los recien generados.
#    IMPORTANTE: el mismo MAPALAB_INTERNAL_TOKEN debe ir en mapalab/.env.production
#    (sin el mismo valor en ambos lados, las requests entre mariachi y mapalab
#    fallan con 401 y el tree queda stale hasta el cron 04:00 UTC).

# 3. Desactivar sample users:
sed -i 's|^CREATE_SAMPLE_USERS=true|CREATE_SAMPLE_USERS=false|' .env.production

# 4. Recreate api (toma las nuevas vars):
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```

**Efecto colateral:** rotar `SECRET_KEY` invalida todas las sesiones activas; los
usuarios deberan hacer login de nuevo. Es esperado.

Tambien conviene rotar `ADMIN_PASSWORD` si todavia es `admin123`.

### Rotacion de credenciales SeaweedFS (acervo)

SeaweedFS gestiona las credenciales S3 desde `acervo/config/identities.json`.
Para rotar la admin key o las keys por bucket:

```bash
cd ~/acervo
# Generar nuevas credenciales
NEW_ADMIN_AK=$(openssl rand -hex 16)
NEW_ADMIN_SK=$(openssl rand -hex 32)
# Editar config/identities.json para sustituir las keys del usuario admin y
# por bucket. Sincronizar con mariachi/.env.production
#   ACERVO_<PROYECTO>_ACCESS_KEY y ACERVO_<PROYECTO>_SECRET_KEY.
# Reiniciar:
docker compose restart acervo-seaweedfs
```

---

## C. Configuracion opcional

### Google Tag Manager / Analytics

Mariachi y demas frontends del ecosistema delegan GA4 al `sub_filter` GTM que
inyecta gateway-hub en `text/html`. Para activarlo:

```bash
cd ~/gateway-hub
# Editar .env: GTM_ID=GTM-XXXXXXX
make restart
```

Cualquier frontend que dispare `window.dataLayer.push({...})` empezara a
reportar a GA4 sin tocar codigo de los frontends.

### Sentry

Para instrumentar errores en produccion:

```bash
# En mariachi/.env.production:
VITE_SENTRY_DSN=https://...@sentry.io/...
SENTRY_DSN=https://...@sentry.io/...
SENTRY_ORG=tu-org
SENTRY_PROJECT=mariachi-prod
SENTRY_AUTH_TOKEN=<token>     # solo si quieres subir source maps
SENTRY_TRACES_SAMPLE_RATE=0.1
```

Rebuild requiere admin (cambia el bundle):

```bash
cd ~/mariachi && make build ENV=prod
```

---

## D. Pendientes arquitectonicos (no urgentes)

### Postgres compartido entre mariachi y dataengine

Hoy `mariachi-postgres` tiene una BD `iieg_portal` con tablas mariachi
(`media_buckets`, `projects`, `usuarios`, etc.) y `dataengine-primary` tiene
`iieg_gis` con tablas GIS (mismo cluster fisico, distinta DB).

Esto es legacy y confunde al diagnosticar (ej. `psql -d iieg_gis` no es
deterministico sin saber a que cluster apuntas). Cuando haya tiempo, separar:

- mariachi → BD propia `iieg_portal` en `mariachi-postgres` (estado actual)
- dataengine → BD `iieg_gis` en `dataengine-primary` (no cambia)

Implica rename + actualizar `DATABASE_URL` en `mariachi/.env.production` +
verificar que ningun otro repo apunte al cluster mariachi-postgres por nombre
de BD `iieg_gis`.

### Subdominio dedicado para S3 API (SeaweedFS)

Si en algun momento se necesita generar presigned URLs autenticadas con sigv4
(clientes externos accediendo objects con firma corta), montar
`s3.mapalab-iieg.app` en gateway-hub y configurar SeaweedFS para responder en
ese host. Hoy no hace falta porque acervo usa `anonymous Read` para buckets
`portal`, `mapalab` e `iieg`, y proxy autenticado de mariachi-api para privados.

### Sincronizacion de `platforms_config.py`

`mariachi/api/app/core/platforms_config.py` mantiene `static_version` por
plataforma del ecosistema. Cada bump en otro repo (gateway-hub, acervo,
geoserver, huachicol, dataengine) debe sincronizarse aqui o el dashboard
`/sistema/plataformas` reportara versiones viejas. Hoy es manual; un hook
podria comparar contra los `VERSION` files de los repos hermanos.

### Drop de `public.mapalab_card`

La tabla legacy `public.mapalab_card` sigue viva como staging del ETL del
Google Sheet. **No dropear** hasta que se complete el primer deploy a
produccion donde el Sheet quede congelado y el ETL deje de correr. Tras eso,
seguir el procedimiento de `dataengine/scripts/drop_mapalab_card_validation.sql`.

### Backups dataengine: pasar de semanal a diario

Hoy `dataengine-backup` corre `0 2 * * 0` (semanal, domingos 02:00 UTC). Para
prod conviene diario:

```bash
# En dataengine/backup/crontab:
0 2 * * * /backup.sh
```

Y rebuildear: `cd ~/dataengine && docker compose up -d --build dataengine-backup`.

---

## E. Workflow estandar de actualizaciones

```bash
# mariachi (admin + api):
cd ~/mariachi && git pull && make deploy

# acervo:
cd ~/acervo && git pull && make up ENV=prod

# gateway-hub:
cd ~/gateway-hub && git pull && docker compose build nginx && docker compose up -d --force-recreate nginx

# sieej (solo dist; gateway-hub lo monta):
cd ~/sieej && git pull && make build
# Luego restart gateway-hub para que recoja el dist nuevo:
cd ~/gateway-hub && docker compose restart nginx

# mapalab:
cd ~/mapalab && git pull && make deploy
```

---

## F. Versiones live (snapshot 2026-05-15)

| Repo | Version |
|---|---|
| acervo | 1.22.1 |
| dataengine | 1.14.3 |
| gateway-hub | 1.24.16 |
| geoserver | 1.20.1 |
| huachicol | 1.19.2 |
| mariachi | 1.0.4 |
| mapalab | 1.28.5 |
| sieej | 1.11.0 |

Sincronizar `mariachi/api/app/core/platforms_config.py:static_version` cada vez
que un repo del ecosistema bumpee.

---

## Diagnostico (si algo falla en seccion A)

### "No aparecen buckets" en `/media`

```bash
# 1. Mariachi-api responde el endpoint?
docker logs mariachi-api 2>&1 | grep -iE "error|500|traceback" | tail -20

# 2. Las creds llegan al container?
docker exec mariachi-api env | grep -E "^ACERVO" | sort
# Espera 5 pares ACCESS_KEY+SECRET_KEY: portal, mapalab, mariachi, sieej, iieg.
# Y ACERVO_USE_SSL=false (acervo-seaweedfs:8333 escucha HTTP, no HTTPS).

# 3. La BD tiene los rows correctos?
docker exec -e PGPASSWORD='<password>' mariachi-postgres \
    psql -U gengine_test -d iieg_portal \
    -c "SELECT mb.id, p.slug, mb.acervo_bucket, mb.is_public, mb.is_active FROM media_buckets mb JOIN projects p ON p.id=mb.project_id ORDER BY mb.id;"
# Debe mostrar 6 rows; iieg activo, dataengine inactivo.
```

### "Imagenes salen rotas" en grid view

`ACERVO_PUBLIC_ENDPOINT` debe ser `/acervo` (path relativo) en
`mariachi/.env.production`. Con URL absoluta HTTP el browser bloquea por mixed
content.

```bash
grep ACERVO_PUBLIC_ENDPOINT ~/mariachi/.env.production
# Esperado: /acervo
sed -i 's|^ACERVO_PUBLIC_ENDPOINT=.*|ACERVO_PUBLIC_ENDPOINT=/acervo|' ~/mariachi/.env.production
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```

### "Tree de capas no se actualiza tras editar en mariachi"

Desde `mapalab 1.28.5` los endpoints `/layers/refresh-cache` e
`/layers/invalidate-cache` requieren `X-Internal-Token`. Si la sincronizacion
falla:

```bash
# Confirmar que ambos lados tienen el mismo token:
grep MAPALAB_INTERNAL_TOKEN ~/mariachi/.env.production ~/mapalab/.env.production
# Deben ser identicos. Si difieren:
sed -i "s|^MAPALAB_INTERNAL_TOKEN=.*|MAPALAB_INTERNAL_TOKEN=<valor>|" ~/mariachi/.env.production
sed -i "s|^MAPALAB_INTERNAL_TOKEN=.*|MAPALAB_INTERNAL_TOKEN=<valor>|" ~/mapalab/.env.production
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api  # en mariachi
cd ~/mapalab && make deploy
```

Verificar contador de fallas:

```bash
docker exec mariachi-api curl -s http://localhost:8000/metrics | grep mariachi_tree_notify_failed
```

### "SSL record layer failure" en logs de mariachi-api

`ACERVO_USE_SSL=true` cuando deberia ser `false` (acervo-seaweedfs:8333 escucha
HTTP, no HTTPS).

```bash
sed -i 's|^ACERVO_USE_SSL=.*|ACERVO_USE_SSL=false|' ~/mariachi/.env.production
sed -i 's|^ACERVO_VERIFY_SSL=.*|ACERVO_VERIFY_SSL=false|' ~/mariachi/.env.production
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```

### "Alloy unhealthy" pero alloy funciona

Bug histórico (resuelto en huachicol 1.19.2): el healthcheck usaba `wget` que
no está en la imagen. Tras actualizar a 1.19.2+ el problema desaparece. Si
sigues viendo `unhealthy`:

```bash
cd ~/huachicol
git pull
docker compose up -d --force-recreate alloy
docker inspect alloy --format '{{.State.Health.Status}}'
```
