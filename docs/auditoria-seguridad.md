# Auditoria de Seguridad Web — Comparativa

Comparacion entre el sitio anterior (`iieg.gob.mx`) y la infraestructura actual
(`iieg.jalisco.gob.mx`) gestionada por gateway-hub.

> Fecha de auditoria: 2026-04-15

## Resumen ejecutivo

| Categoria | Sitio anterior (iieg.gob.mx) | Sitio actual (iieg.jalisco.gob.mx) |
|-----------|------------------------------|-------------------------------------|
| **SSL/TLS** | Certificado invalido (unable to verify) | Wildcard DigiCert, TLS 1.2/1.3, OCSP Stapling |
| **HSTS** | Error (no se pudo verificar) | max-age=31536000; includeSubDomains; preload |
| **Security Headers** | No verificables (SSL roto) | 8 headers configurados |
| **Content Security Policy** | No verificable | Configurado con whitelist |
| **DNSSEC** | No configurado (NXDOMAIN) | Parcial (DNSKEY/DS presentes, RRSIG refused) |
| **WAF** | No verificable | FortiGate en la red (no detectado como WAF) |
| **robots.txt** | Error (SSL roto) | Configurado con rutas admin bloqueadas |
| **Tiempo de respuesta** | No medido | 753 ms |
| **Estado** | Activo con SSL roto | Activo y saludable |

## SSL/TLS

| Aspecto | iieg.gob.mx | iieg.jalisco.gob.mx |
|---------|-------------|---------------------|
| Estado | **Certificado no verificable** | Valido (DigiCert) |
| Emisor | — | DigiCert Global G2 TLS RSA SHA256 2020 CA1 |
| Tipo | — | Wildcard (*.jalisco.gob.mx) |
| Vigencia | — | Sep 2025 - Oct 2026 |
| Bits | — | 2048 RSA |
| Protocolos | — | TLS 1.2, TLS 1.3 |
| OCSP Stapling | — | Habilitado |

**Impacto:** El sitio anterior tenia un certificado SSL que no podia ser verificado por los
navegadores, lo que generaba advertencias de seguridad y bloqueaba el acceso a informacion
como headers HTTP, robots.txt y metricas de seguridad. El sitio actual tiene un certificado
valido emitido por una CA reconocida.

## Headers de Seguridad HTTP

| Header | iieg.gob.mx | iieg.jalisco.gob.mx |
|--------|-------------|---------------------|
| Strict-Transport-Security | No verificable | max-age=31536000; includeSubDomains; preload |
| X-Frame-Options | No verificable | SAMEORIGIN |
| X-Content-Type-Options | No verificable | nosniff |
| X-XSS-Protection | No verificable | 1; mode=block |
| Referrer-Policy | No verificable | strict-origin-when-cross-origin |
| Permissions-Policy | No verificable | geolocation=(self), camera=(), microphone=(), payment=(), usb=() |
| Cross-Origin-Opener-Policy | No verificable | same-origin |
| X-Permitted-Cross-Domain-Policies | No verificable | none |
| Content-Security-Policy | No verificable | Configurado (self + GTM + CartoDB) |
| Server header | No verificable | nginx (version oculta) |

**Resultado del escaneo:**

| Check | iieg.gob.mx | iieg.jalisco.gob.mx |
|-------|-------------|---------------------|
| strictTransportPolicy | Error | Habilitado |
| xFrameOptions | Error | Habilitado |
| xContentTypeOptions | Error | Habilitado |
| xXSSProtection | Error | Habilitado |
| contentSecurityPolicy | Error | Habilitado |

## DNS

| Aspecto | iieg.gob.mx | iieg.jalisco.gob.mx |
|---------|-------------|---------------------|
| Registro A | 201.131.6.124 | 201.131.6.122 |
| IPv6 (AAAA) | No | No |
| Registros MX | Google (5 servidores) | No (subdominio) |
| Registros TXT | SPF, Facebook, Microsoft | No (subdominio) |
| NS | AWS Route 53 (4 servidores) | — |
| DNSSEC DNSKEY | No encontrado | Encontrado |
| DNSSEC DS | No encontrado | Encontrado |
| DNSSEC RRSIG | No encontrado | No (REFUSED por NS) |

**Nota:** `iieg.gob.mx` es el dominio raiz con registros DNS completos (MX, SPF, etc.).
`iieg.jalisco.gob.mx` es un subdominio del dominio estatal, por lo que los registros DNS
son gestionados a nivel de `jalisco.gob.mx`.

## HSTS Preload

| Aspecto | iieg.gob.mx | iieg.jalisco.gob.mx |
|---------|-------------|---------------------|
| Compatible | Error (SSL roto) | Compatible con HSTS preload list |
| Header | — | max-age=31536000; includeSubDomains; preload |

## Cookies

| Aspecto | iieg.gob.mx | iieg.jalisco.gob.mx |
|---------|-------------|---------------------|
| Cookies de sesion | — | cookiesession1 (FortiGate) |
| HttpOnly | — | Si |
| Secure | — | No (inyectada por FortiGate, fuera de nuestro control) |
| SameSite | — | No (inyectada por FortiGate) |

## Robots.txt

| Aspecto | iieg.gob.mx | iieg.jalisco.gob.mx |
|---------|-------------|---------------------|
| Estado | Error (SSL roto) | Configurado |
| User-agent | — | * (todos) |
| Allow | — | / |
| Disallow | — | /administrador/, /acervo/console/, /geoserver/web/, /geoserver/rest/, /mariachi/, /huachicol/ |
| Sitemap | — | Incluido |

## Puertos

| Puerto | iieg.gob.mx | iieg.jalisco.gob.mx |
|--------|-------------|---------------------|
| 80 (HTTP) | Abierto | Abierto (redirige a HTTPS) |
| 443 (HTTPS) | Abierto | Abierto |
| 22 (SSH) | Cerrado | Cerrado |
| 8080, 3000, 3306, etc. | Cerrados | Cerrados |

Ambos sitios exponen unicamente los puertos 80 y 443, que es lo correcto.

## Amenazas

| Check | iieg.gob.mx | iieg.jalisco.gob.mx |
|-------|-------------|---------------------|
| PhishTank | No en base de datos | No en base de datos |
| Block lists (17 servicios) | No bloqueado | No bloqueado |

## Social Tags / SEO

| Tag | iieg.gob.mx | iieg.jalisco.gob.mx |
|-----|-------------|---------------------|
| title | Error (SSL) | Mapalab |
| description | Error (SSL) | Sistema de Mapas Interactivos del Estado de Jalisco |
| og:type | Error (SSL) | website |
| og:site_name | Error (SSL) | Mapalab |
| twitter:card | Error (SSL) | summary_large_image |
| theme-color | Error (SSL) | #5C2472 |
| viewport | Error (SSL) | width=device-width, initial-scale=1.0 |

## Ranking web (iieg.gob.mx)

El sitio anterior tiene ranking global Tranco de ~2.1M-2.4M con tendencia descendente
(de 2,473,371 en marzo a 2,195,967 en abril 2026), lo cual indica una caida gradual de
trafico hacia el dominio antiguo conforme los usuarios migran al nuevo.

## Hallazgos que requieren accion externa

Estos puntos no se pueden resolver desde gateway-hub:

## Proteccion contra bots

Implementada en `nginx/includes/bot-protection.inc` y aplicada en todas las rutas publicas.
Bloquea scrapers, crawlers de IA, herramientas CLI y requests sin User-Agent.
Permite navegadores reales y bots SEO legitimos (Googlebot, Bingbot).
Ver `docs/rendimiento.md` para la lista completa de User-Agents bloqueados/permitidos.

---

## Hallazgos que requieren accion externa

| Hallazgo | Responsable | Accion |
|----------|-------------|--------|
| Cookie sin Secure/SameSite | Equipo FortiGate | Configurar flags en la cookie de sesion |
| DNSSEC RRSIG refused | Equipo DNS estatal | Completar firma DNSSEC en nameservers |
| IPv6 no disponible | Red estatal | Habilitar AAAA records |
| SSL 2048-bit RSA | Secretaria de Administracion | Renovar con 4096 RSA o ECDSA |
| WAF no detectado | Equipo FortiGate | Habilitar reglas WAF visibles |
| Certificado SSL roto en iieg.gob.mx | Administrador del sitio anterior | Renovar o redireccionar |
