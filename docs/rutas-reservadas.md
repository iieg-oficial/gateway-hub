# Rutas reservadas del dominio

> Inventario de namespaces de primer nivel del dominio y reglas de integración para
> aplicaciones de terceros servidas en la raíz. Fuente de verdad ante cualquier disputa
> de rutas. Basado en las locations de `gateway.conf.template` y en el análisis de
> tráfico real (Loki, 14 días, 2026-07-17).
>
> Última actualización: 2026-07-17

---

## 1. Namespaces reservados (con location propia en el gateway)

Nginx siempre elige la location más específica: estos prefijos **nunca** llegan al
catch-all `location /`, sin importar quién lo ocupe.

| Prefijo | Servicio | Backend |
|---|---|---|
| `/api/` | APIs del ecosistema (admin mariachi, público SIEEJ/colibri, mapalab) | `portal_backend` |
| `/mariachi/` | Panel administrativo (SPA) | `portal_backend` |
| `/mapalab/` | Visor cartográfico | `mapalab_backend` |
| `/sieej/` | Plataforma SIEEJ (estáticos servidos por el gateway) | gateway (disco) |
| `/acervo/` | Acervo (SeaweedFS) y miniaturas (`/acervo/thumb/` → mariachi-api) | `ACERVO_HOST` / `portal_backend` |
| `/geoserver/` | GeoServer (OGC, REST, web UI) | `geoserver` |
| `/huachicol/` | Huachicol | `HUACHICOL_HOST` |
| `/colibri/` | Widget embebible y docs de Colibri (reservado en 1.28.0) | `portal_backend` |
| `/ontoy` y `/*/ontoy` | Endpoints de versión/identidad por servicio | varios |
| `/error-pages/` | Páginas de error del gateway (internal) | gateway |

Archivos de raíz que conserva el gateway con match exacto: `/robots.txt`,
`/sitemap.xml`, `/.well-known/`. Los dotfiles (`~ /\.`) se niegan siempre.

## 2. Namespaces legados

| Prefijo | Estado |
|---|---|
| `/administrador/` | URL antigua del panel admin (renombrado a `/mariachi` en mariachi v0.21.0). Tráfico en 14 días: 0. **Liberada en gateway 1.28.1**: sin location propia, cae al catch-all. El rewrite 301 interno de `mariachi-nginx` quedó retirado en el working tree de mariachi y desaparece con su siguiente release. No confundir con `/api/administrador/`, que sigue reservado bajo `/api` (lo usan el panel admin y el frontend público de SIEEJ). |
| `/assets/`, `/site.webmanifest`, `/favicon-96x96.png`, `/favicon.svg` | Tráfico residual de un build viejo de SIEEJ con base en raíz (hoy 404). Se extingue solo; no reservar. |

## 3. Fuera de este gateway

- **vine** (asistencias RH) corre standalone en otro servidor con sus propios 80/443.
  Sus rutas viven en raíz (`/admin/*`, `/empleado/*`, `/login`); si algún día se monta
  detrás de este gateway necesita basename propio.
- `/favicon.ico` de raíz pertenece a quien ocupe `location /`.

## 4. Reglas de integración para la app raíz de terceros

Requisitos formales para cualquier aplicación externa que ocupe `location /`:

1. **No usar ningún prefijo de las secciones 1 y 2** en rutas, assets, APIs ni enlaces
   generados.
2. **Assets y API bajo prefijo propio** (p. ej. `/app/` o el `base` del bundler), no
   regados en raíz.
3. Si requiere vivir bajo `/api`, se le delega un sub-prefijo específico
   (p. ej. `location ^~ /api/sitio/` → su upstream); nunca `/api/` completo.
4. **Cookies con prefijo propio** (p. ej. `sitio_*`) y con `Path` acotado cuando
   aplique, para no colisionar ni inflar los headers hacia los servicios internos.
5. `robots.txt` y `sitemap.xml` los sirve el gateway; cambios se coordinan aquí.
6. Detrás del proxy: la app debe confiar en `X-Forwarded-Proto/Host/For`
   (`proxy-params.inc`) para URLs absolutas y cookies `Secure`.

## 5. Verificación

Cada servicio expone un endpoint de identidad (`/ontoy`, `/sieej/ontoy`,
`/geoserver/ontoy`, …) que devuelve `service` + `version`; ante cambios de ruteo,
verificar que cada namespace responde con el servicio esperado. Pendiente: script de
smoke test automatizado post-deploy.
