# Pendiente: Optimizacion servidores MapaLab y DataEngine

Configuracion optimizada basada en diagnostico real de produccion (2026-06-03).

## Diagnostico actual

| Servidor | Cores | RAM | Uso RAM | PostgreSQL |
|----------|-------|-----|---------|------------|
| **MapaLab** (S2) | 8 | 16 GB | 4 GB (25%) | — |
| **DataEngine** (S1) | 4 | 7.7 GB | 4.1 GB (53%) | 200 max, 89 activas (80 idle) |
| **Mariachi** (S3) | ? | ? | ? | 200 max, 22 activas |

## 1. MapaLab — .env.production

Editar `/IIEG/mapalab/.env.production`:

```
GUNICORN_WORKERS=12
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=10
```

Pool potencial: 12 workers × 20 (pool+overflow) = **240 conexiones**

## 2. DataEngine — .env

Editar `/IIEG/dataengine/.env`:

```
POSTGRES_MAX_CONNECTIONS=300
POSTGRES_SHARED_BUFFERS=2GB
POSTGRES_EFFECTIVE_CACHE_SIZE=5632MB
```

Total conexiones potenciales: 240 desde MapaLab + conexiones de GeoServer y otros servicios < 300 max_connections.

## 3. Redesplegar

```bash
# En servidor DataEngine
cd /IIEG/dataengine && make restart

# En servidor MapaLab
cd /IIEG/mapalab && make deploy
```

## 4. Validar

Confirmar configuracion aplicada:

```bash
# En DataEngine — confirmar PostgreSQL
docker exec -e PGPASSWORD='...' dataengine-primary psql -U gengine_user -d iieg_gis -c "SHOW max_connections;"
docker exec -e PGPASSWORD='...' dataengine-primary psql -U gengine_user -d iieg_gis -c "SHOW shared_buffers;"
docker exec -e PGPASSWORD='...' dataengine-primary psql -U gengine_user -d iieg_gis -c "SHOW effective_cache_size;"

# En MapaLab — confirmar workers
docker top mapalab-backend-1 | grep gunicorn | wc -l
# Esperado: 13 lineas (1 master + 12 workers)
```

Opcional: correr stress test para confirmar la mejora:

```bash
python stress_test.py --env production --mode ramp --users 300 --ramp-steps 15
```

Resultado esperado: ~200 usuarios estables (vs 100 actuales).

## 5. Actualizar documentacion

- `gateway-hub/docs/recursos-servidores.md` — actualizar specs de S2
- `gateway-hub/docs/rendimiento.md` — agregar resultados del stress test post-upgrade
- `mapalab/docs/context.md` — actualizar tabla de servidores

## Resumen de capacidad esperada

| Metrica | Antes | Despues |
|---------|-------|---------|
| Gunicorn workers | 8 | 12 |
| DB pool total | 128 | 240 |
| PostgreSQL max_conn (DataEngine) | 200 | 300 |
| PostgreSQL shared_buffers | default | 2GB |
| PostgreSQL effective_cache_size | default | 5632MB |
| Usuarios estables (estimado) | ~100 | ~200 |
| Max RPS (estimado) | ~350 | ~700 |
