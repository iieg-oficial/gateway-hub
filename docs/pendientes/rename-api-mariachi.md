# Pendiente: renombrar `/api/administrador` → `/api/mariachi`

> Plan aprobado en concepto (2026-07-17), sin fecha. El prefijo actual miente:
> además del panel admin lo consumen el frontend público de SIEEJ, el widget de
> Colibri (vía `/api/public`) y llamadas internas de mapalab. Conviene ejecutarlo
> **antes** de integrar la app raíz de terceros y de que aparezcan más consumidores.

## Inventario de referencias (medido 2026-07-17)

| Repo | Referencias |
|---|---|
| mariachi api | `app/core/settings.py:30` (`admin_prefix`, **mueve los ~30 routers con 1 línea**); hardcodeadas: `app/services/acervo.py:200` y `app/api/routes/geoserver.py:426` (deberían usar el setting). Tests: 0 referencias hardcodeadas. |
| mariachi admin | `VITE_ADMIN_API_URL` en `.env.production`, `.env.development`, `.env.staging` y examples; fallback en `admin/src/shared/services/api.js:3`; 2 menciones en textos de `features/documentacion`. |
| mariachi nginx | `nginx/conf.d/mariachi.conf`: location `^~ /api/administrador/acervo`. |
| sieej | `VITE_BACKEND_API_HOST` en `.env.production`, `.env.development`, `.env.example` (este último lo exige textual) + `scripts/smoke_wizard.py` (2 refs). Requiere rebuild del dist (montado en el gateway). |
| mapalab | Llamadas internas directas a `mariachi-api:8000` (NO pasan por nginx): `backend/app/services/access_logger.py:110`, `api_key_validator.py:113`, `api_key_quota.py:120`, `servers/telemetry.py:98`. |
| gateway-hub | `gateway.conf.template`: locations `^~ /api/administrador/acervo/thumb` y `^~ /api/administrador/acervo`. |

## Pieza clave: rewrite de compatibilidad en mariachi-nginx

```nginx
location ^~ /api/administrador/ {
    rewrite ^/api/administrador/(.*)$ /api/mariachi/$1 break;
    proxy_pass http://$mariachi_api;
    # mismos proxy_set_header que la location /api/
}
```

Cubre bundles viejos del admin y de SIEEJ y cualquier URL
`/api/administrador/acervo/proxy/...` persistida en contenido de páginas.
**No cubre a mapalab** (llama directo al backend): sus 4 referencias van en
lockstep con el deploy del api.

## Fases

1. mariachi api (`admin_prefix` + las 2 refs hardcodeadas) + rewrite compat en
   mariachi-nginx + las 4 refs de mapalab → un deploy coordinado. Desde aquí
   funcionan ambos prefijos.
2. Sin prisa: admin (`VITE_ADMIN_API_URL`), sieej (`VITE_BACKEND_API_HOST` +
   rebuild), gateway (duplicar las 2 locations especiales de acervo para
   `/api/mariachi/acervo*`; durante la transición existen para ambos prefijos).
3. Uno o dos releases después: retirar el rewrite compat y las locations viejas
   del prefijo anterior.

Estimación: un día de trabajo, la mayor parte en verificación y deploys
coordinados. Riesgo con el rewrite compat: prácticamente cero.
