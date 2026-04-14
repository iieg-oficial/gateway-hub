# Pendiente: Upgrade servidor MapaLab a 8 cores / 16 GB RAM

Cuando el servidor S2 (MapaLab) se actualice de 4 cores / 7.7 GB a 8 cores / 16 GB,
aplicar estos cambios para aprovechar los recursos.

## 1. MapaLab — .env.production

Editar `/IIEG/mapalab/.env.production`:

```
GUNICORN_WORKERS=16
DB_POOL_SIZE=12
DB_MAX_OVERFLOW=12
```

## 2. DataEngine — postgresql.conf

Editar `/IIEG/mapalab-dataengine/postgres/primary/config/postgresql.conf`:

```
max_connections = 400
```

Total conexiones potenciales: 16 workers × 24 (12+12) = 384. Con 400 max_connections
queda margen para GeoServer, backups y mapalab-card.

## 3. Redesplegar

```bash
# En servidor MapaLab
cd /IIEG/mapalab && make deploy

# En servidor DataEngine
cd /IIEG/mapalab-dataengine && make restart
```

## 4. Validar

Correr stress test para confirmar la mejora:

```bash
python stress_test.py --env production --mode ramp --users 300 --ramp-steps 15
```

Resultado esperado: ~200 usuarios estables (vs 100 actuales).

## 5. Actualizar documentacion

- `gateway-hub/docs/recursos-servidores.md` — actualizar specs de S2
- `gateway-hub/docs/rendimiento.md` — agregar resultados del stress test post-upgrade
- `mapalab/docs/context.md` — actualizar tabla de servidores

## Resumen de capacidad esperada

| Metrica | Actual (4 cores) | Post-upgrade (8 cores) |
|---------|-----------------|----------------------|
| Gunicorn workers | 8 | 16 |
| DB pool total | 128 | 384 |
| PostgreSQL max_conn | 200 | 400 |
| Usuarios estables | ~100 | ~200 (estimado) |
| Max RPS | ~350 | ~700 (estimado) |
