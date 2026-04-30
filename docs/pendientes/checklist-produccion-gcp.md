# Checklist de produccion — GCP (mapalab-iieg.app)

Estado y pendientes para que la VM en GCP quede lista en produccion despues de la
migracion del modelo de buckets (mariachi 0.30.30+, acervo 1.20.0+, gateway-hub
1.24.5+).

---

## A. Validacion inmediata (smoke test)

Hard reload (Ctrl+Shift+R) en `https://mapalab-iieg.app/mariachi/` y confirma:

- [ ] `/sistema/plataformas` muestra todas las plataformas verdes con su version.
- [ ] `/media` muestra los 5 buckets en el select: **Portal, MapaLab, SIEEJ,
      Mariachi, IIEG** (DataEngine no aparece porque queda `is_active=false`).
- [ ] Subir un archivo a Mariachi desde `/media` → aparece en la lista.
- [ ] `/perfil`:
  - "Elegir generico" abre el picker en modo grid con los avatars del bucket
    `iieg/avatars/`.
  - "Subir personalizado" sube al bucket privado `mariachi/avatars/u<id>/` y se
    muestra en el avatar.
  - Tras "Guardar cambios" + recargar la pagina, el avatar persiste.
- [ ] `/acervo/console/` carga sin errores `Refused to execute script` (MIME
      type) y permite login.
- [ ] `/sieej/` carga el frontend.
- [ ] `/mapalab/` carga el visor.

Si algo falla, ver seccion "Diagnostico" mas abajo.

---

## B. Seguridad pendiente (importante antes de tráfico real)

Hoy `SECRET_KEY` y `CSRF_SECRET_KEY` comparten valor entre dev/staging/prod
(anti-patron). `MAPALAB_INTERNAL_TOKEN` esta vacio asi que la feature de shares
permanentes responde 503. `CREATE_SAMPLE_USERS=true` en prod crea usuarios
sample (`editora123`, `disenadora123`) en cada arranque — riesgo en prod.

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
#    fallan con 401).

# 3. Desactivar sample users:
sed -i 's|^CREATE_SAMPLE_USERS=true|CREATE_SAMPLE_USERS=false|' .env.production

# 4. Recreate api (toma las nuevas vars):
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```

**Efecto colateral:** rotar `SECRET_KEY` invalida todas las sesiones activas; los
usuarios deberan hacer login de nuevo. Es esperado.

Tambien conviene rotar `ADMIN_PASSWORD` si todavia es `admin123`. La password
actual de los buckets MinIO (`portal-user`, `mapalab-user`, etc.) ya estan
rotadas via `init-buckets.sh --rotate`; si quieres rotarlas otra vez:

```bash
cd ~/acervo
docker compose --env-file .env.gateway -f docker-compose.gateway.yml \
    --profile init run --rm acervo-init --rotate
# Captura las 5 passwords y actualizalas en mariachi/.env.production
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

Hoy `mariachi-postgres` tiene una BD `iieg_gis` con tablas mariachi
(`media_buckets`, `projects`, `usuarios`, etc.) y `dataengine-primary` tiene
**otra** BD tambien llamada `iieg_gis` con tablas GIS (mismo nombre, distinto
volumen, distinto cluster).

Esto es legacy y confunde al diagnosticar (ej. `psql -d iieg_gis` no es
deterministico sin saber a que cluster apuntas). Cuando haya tiempo, separar:

- mariachi → BD propia `iieg_portal` en `mariachi-postgres`
- dataengine → BD `iieg_gis` en `dataengine-primary` (no cambia)

Implica rename + actualizar `DATABASE_URL` en `mariachi/.env.production` +
verificar que ningun otro repo apunte al cluster mariachi-postgres por nombre
de BD `iieg_gis`.

### Subdominio dedicado para S3 API

Si en algun momento se necesita generar presigned URLs autenticadas con sigv4
(clientes externos accediendo objects con firma corta), montar
`s3.mapalab-iieg.app` en gateway-hub y configurar `MINIO_SERVER_URL` apuntando
a ese subdominio. MinIO no soporta path prefix para sigv4 (lo vimos al fallar
el login del console cuando `MINIO_SERVER_URL=https://mapalab-iieg.app/acervo`).
Hoy no hace falta porque acervo usa anonymous GetObject + proxy autenticado de
mariachi-api para privados.

### Pre-commit hook para `platforms_config.py`

`mariachi/api/app/core/platforms_config.py` mantiene un `static_version` por
plataforma del ecosistema. Cada bump en otro repo (acervo, gateway-hub, etc.)
debe sincronizarse aqui o el dashboard `/sistema/plataformas` reportara
versiones viejas. Hoy es manual; un hook podria comparar contra los `VERSION`
files de los repos hermanos.

---

## E. Workflow estandar de actualizaciones

```bash
# mariachi (admin + api):
cd ~/mariachi && git pull && make build ENV=prod

# acervo:
cd ~/acervo && git pull && make up ENV=prod INFRA=gateway

# gateway-hub:
cd ~/gateway-hub && git pull && docker compose build nginx && make restart

# sieej (solo dist; gateway-hub lo monta):
cd ~/sieej && git pull && make build
# Luego restart gateway-hub para que recoja el dist nuevo:
cd ~/gateway-hub && docker compose restart nginx
```

---

## F. Versiones live (snapshot 2026-04-29)

| Repo | Version |
|---|---|
| acervo | 1.20.1 |
| gateway-hub | 1.24.8 |
| mariachi | 0.30.41 |
| sieej | 1.2.1 |

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
# Y ACERVO_USE_SSL=false (no true; mariachi se conecta a acervo-minio:9000 HTTP).

# 3. La BD tiene los rows correctos?
docker exec -e PGPASSWORD='<password>' mariachi-postgres \
    psql -U gengine_test -d iieg_gis \
    -c "SELECT mb.id, p.slug, mb.acervo_bucket, mb.is_public, mb.is_active FROM media_buckets mb JOIN projects p ON p.id=mb.project_id ORDER BY mb.id;"
# Debe mostrar 6 rows con sieej (no sieej-diccionarios), iieg activo,
# dataengine inactivo.
```

### "Imagenes salen rotas" en grid view

`ACERVO_PUBLIC_ENDPOINT` debe ser `/acervo` (path relativo), no
`localhost:9080` (HTTP). Si es absoluto y http://, el browser bloquea por mixed
content (admin va por HTTPS).

```bash
grep ACERVO_PUBLIC_ENDPOINT ~/mariachi/.env.production
# Esperado: /acervo
sed -i 's|^ACERVO_PUBLIC_ENDPOINT=.*|ACERVO_PUBLIC_ENDPOINT=/acervo|' ~/mariachi/.env.production
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```

### "Avatar personalizado se quita al guardar"

Bug arreglado en mariachi 0.30.36. Si lo ves, asegurate de que la VM tiene
0.30.36+ (`docker exec mariachi-api cat /app/pyproject.toml | grep version`).

### "Acervo console: Refused to execute script (MIME type 'text/html')"

`MINIO_SERVER_URL` debe estar **vacio** en `acervo/.env.gateway` (gateway-hub
sirve acervo bajo path prefix `/acervo/`, y MinIO no soporta path prefix para
sigv4). Bug arreglado en acervo 1.18.2+.

```bash
grep MINIO_SERVER_URL ~/acervo/.env.gateway
# Debe estar vacio o ausente. Si tiene valor:
sed -i 's|^MINIO_SERVER_URL=.*|MINIO_SERVER_URL=|' ~/acervo/.env.gateway
docker compose --env-file .env.gateway -f docker-compose.gateway.yml up -d --force-recreate minio
```

### "IsADirectoryError" en logs de mariachi-api

Bug arreglado en mariachi 0.30.38. El bind mount al cert acervo se removio
porque acervo en gateway mode no tiene cert propio. Si ves este error,
`git pull` y `make build ENV=prod` en mariachi.

### "SSL record layer failure" en logs de mariachi-api

`ACERVO_USE_SSL=true` cuando deberia ser `false` (acervo-minio:9000 escucha
HTTP, no HTTPS).

```bash
sed -i 's|^ACERVO_USE_SSL=.*|ACERVO_USE_SSL=false|' ~/mariachi/.env.production
sed -i 's|^ACERVO_VERIFY_SSL=.*|ACERVO_VERIFY_SSL=false|' ~/mariachi/.env.production
docker compose --env-file .env.production -f docker-compose.yml up -d --force-recreate api
```
