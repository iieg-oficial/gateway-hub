# Proyecto Minerva — Contexto y Decisiones

> **Nombre:** Minerva
> **Referencia:** La Minerva es el monumento icónico de Guadalajara, Jalisco.
> Representa a la diosa romana de la sabiduría y la protección.
> Se eligió porque el proyecto es un gestor centralizado de identidad y
> autenticación para el ecosistema del instituto, y Minerva encarna
> exactamente eso: protección y sabiduría. Además, el equipo está basado
> en Jalisco y queríamos un nombre que representara nuestra ubicación.

---

## 1. Objetivo del proyecto

Implementar un **gestor de usuarios centralizado** con SSO (Single Sign-On)
para todo el ecosistema de servicios del instituto, en lugar de manejar
usuarios por proyecto individual.

### Servicios del ecosistema que se integrarán:
- **GeoServer** — ya en producción, Docker Compose + PostGIS
- **Mapalab** — proyecto en desarrollo
- **Grafana** — monitoreo y dashboards
- **Mariachi** — servicio interno del instituto
- **SIEEJ** — sistema institucional
- Cualquier servicio nuevo que se agregue al ecosistema en el futuro

---

## 2. Plataforma elegida: Authentik

Se evaluaron tres opciones y se eligió **Authentik** por las siguientes razones:

| Criterio             | Keycloak                  | Authentik                  | FreeIPA                    |
|----------------------|---------------------------|----------------------------|----------------------------|
| Personalización UI   | Temas FreeMarker, tedioso | CSS directo, Flows visual  | No aplica (no es web IAM)  |
| OTP                  | TOTP, sin SMS/email nativo| TOTP + SMS + email + FIDO2 | Kerberos, no web-oriented  |
| Docker               | 2 contenedores            | 4 contenedores             | Complejo en Docker         |
| Seguridad/Madurez    | +10 años, Red Hat         | Desde ~2020, creciendo     | Maduro pero otro enfoque   |
| Protocolo            | OIDC + SAML               | OIDC + SAML                | Kerberos                   |

**Razón principal de elección:** personalización del login más fácil (logo
institucional, colores, flujos custom), OTP completo de fábrica (TOTP, SMS,
email, FIDO2/WebAuthn), interfaz moderna y más ligero que Keycloak.

**Trade-off aceptado:** Authentik tiene menos años de escrutinio de seguridad
que Keycloak, pero es suficientemente seguro para un entorno institucional
con buena configuración (HTTPS, OTP, contraseñas fuertes).

---

## 3. Protocolo de autenticación: OIDC

- **OIDC (OpenID Connect):** protocolo sobre OAuth 2.0 que permite
  autenticación delegada. Las apps redirigen al usuario a Authentik,
  el usuario se autentica ahí, y Authentik devuelve un token JWT
  con la identidad y roles del usuario. Las apps nunca ven la contraseña.
- GeoServer tiene plugin para OIDC (`geoserver-sec-oauth2-openid`).
- Grafana soporta OIDC nativamente via `auth.generic_oauth`.
- Mariachi, SIEEJ y Mapalab se integrarán como clientes OIDC de Authentik.

---

## 4. Arquitectura de red

### Restricción importante
El instituto ya es un subdominio del estado (ejemplo: `instituto.sub.gob.mx`).
**No controlamos el DNS** para crear sub-subdominios propios.
Por lo tanto, Authentik se accede a través de rutas en el gateway, no por
subdominio.

### Topología
```
Internet
   │
   ▼
┌──────────────────────────────────┐
│   gateway-hub (Nginx)            │  ← Único punto expuesto a internet
│   SSL/TLS termination            │
├──────────────────────────────────┤
│ /auth/*       → Authentik (9000) │
│ /geo/*        → GeoServer (8080) │
│ /mapa/*       → Mapalab          │
│ /grafana/*    → Grafana          │
│ /mariachi/*   → Mariachi         │
│ /sieej/*      → SIEEJ            │
└──────────────────────────────────┘
        │  Red interna
        ▼
┌───────────────────────────────────────────┐
│  Docker Compose                           │
│  ├─ authentik-server  (puerto 9000)       │
│  ├─ authentik-worker                      │
│  └─ authentik-redis                       │
│                                           │
│  (GeoServer, Mapalab, Grafana, Mariachi,  │
│   SIEEJ en sus propios compose/containers)│
└───────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────┐
│  Servidor "dataengine"                    │
│  PostgreSQL + PostGIS                     │
│  Bases: authentik, geoserver, mapalab...  │
└───────────────────────────────────────────┘
```

### Puntos clave de la red:
- **Authentik NO está expuesto a internet directamente.**
- Los puertos 9000/9443 solo escuchan en `127.0.0.1`.
- Nginx (`gateway-hub`) es el único punto de entrada desde internet.
- SSL/TLS se maneja solo en `gateway-hub`; la comunicación interna va sin cifrar
  por la red Docker (práctica estándar en redes internas).
- PostgreSQL está en un servidor aparte llamado `dataengine`.
- Authentik usa el Outpost en modo embedded integrado a `gateway-hub` para
  proteger apps que no tienen autenticación propia.

---

## 5. Stack técnico

| Componente     | Tecnología              | Ubicación          |
|----------------|-------------------------|--------------------|
| Gateway        | gateway-hub (Nginx)     | Servidor gateway   |
| IAM            | Authentik (Docker)      | Servidor de apps   |
| Cache/Colas    | Redis 7 Alpine (Docker) | Servidor de apps   |
| Base de datos  | PostgreSQL + PostGIS    | Servidor dataengine|
| OS             | Ubuntu                  | Todos los servers  |

---

## 6. Archivos del proyecto

```
minerva/
├── docker-compose.yml      # Authentik server + worker + Redis
├── .env                    # Variables de entorno (no commitear)
├── env.example             # Plantilla de variables
├── nginx-authentik.conf    # Config de Nginx para gateway-hub
└── README.md               # Guía de instalación paso a paso
```

---

## 7. Decisiones pendientes

- [ ] Solicitar al área de TI del estado el sub-subdominio
      `auth.instituto.sub.gob.mx` (opción ideal, por intentar).
      Si no se consigue, seguir con la ruta `/auth/*` en `gateway-hub`.
- [ ] Definir flujo de OTP: ¿obligatorio para todos o solo admins?
- [ ] Definir roles y grupos iniciales en Authentik
- [ ] Integrar GeoServer con OIDC (plugin oauth2-openid)
- [ ] Integrar Grafana con OIDC (`auth.generic_oauth`)
- [ ] Integrar Mariachi con OIDC
- [ ] Integrar SIEEJ con OIDC
- [ ] Integrar Mapalab con OIDC
- [ ] Personalizar el login con logo y colores institucionales
- [ ] Configurar SMTP para notificaciones y OTP por email

---

## 8. Comandos útiles

```bash
# Generar secret key para Authentik
openssl rand -base64 36

# Levantar el stack
docker compose up -d

# Ver logs
docker compose logs -f authentik-server

# Setup inicial (crear admin)
# Abrir: http://localhost:9000/if/flow/initial-setup/

# Crear la DB en dataengine
psql -h dataengine -U postgres -c "CREATE USER authentik WITH PASSWORD 'contraseña';"
psql -h dataengine -U postgres -c "CREATE DATABASE authentik OWNER authentik;"
```
