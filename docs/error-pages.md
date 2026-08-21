# Paginas de Error

Paginas de error personalizadas servidas por Nginx cuando un upstream no responde
o la solicitud no puede ser procesada.

## Ubicacion

```
nginx/error-pages/
├── 400.html    # Solicitud no valida
├── 401.html    # Acceso no autorizado
├── 403.html    # Acceso restringido
├── 404.html    # Pagina no encontrada
└── 500.html    # Servidores ocupados (cubre 500, 502, 503, 504)
```

## Configuracion en Nginx

Definidas en `nginx/templates/gateway.conf.template`:

```nginx
error_page 400 /error-pages/400.html;
error_page 401 /error-pages/401.html;
error_page 403 /error-pages/403.html;
error_page 404 /error-pages/404.html;
error_page 500 502 503 504 /error-pages/500.html;
```

## Diseno

Todas las paginas comparten el mismo estilo visual basado en MapaLab:

- **Fondo:** Gradiente blanco a lila (`#FFFFFF` → `#F7F0FA`)
- **Texto:** Azul oscuro `#2E4372`, subtexto `#5a6a8a`
- **Botones:** Pill shape, morado `#703089`, hover `#5C2472`
- **Ilustraciones:** SVG inline (sin dependencias externas)
- **Fuente:** Inter (Google Fonts) con fallback a system-ui
- **Responsive:** `clamp()` para tipografia, layout flex adaptable

## Paginas

| Codigo | Titulo | Mensaje | Acciones |
|--------|--------|---------|----------|
| 400 | No pudimos procesar tu solicitud | Solicitud no valida | Ir al inicio |
| 401 | Acceso no autorizado | Necesitas iniciar sesion | Ir al inicio |
| 403 | Acceso restringido | Sin permisos | Ir al inicio |
| 404 | No encontramos la pagina que estas buscando | URL invalida o recurso movido | Ir al inicio |
| 500 | Estamos trabajando en ello | Alta demanda, reintentar | Reintentar + Ir al inicio |

## Notas

- La pagina 500 usa lenguaje no tecnico para no alarmar al usuario. Cubre todos los errores de servidor (500, 502, 503, 504).
- La pagina 500 incluye una animacion sutil de puntos pulsando que indica actividad del sistema.
- Son HTML autocontenido: se pueden previsualizar abriendo los archivos directamente en el navegador.
- El boton "Reintentar" (`window.location.reload()`) solo aparece en la pagina 500.
- **Las rutas de API no reciben estas paginas, y es a proposito.** `proxy_intercept_errors` solo se
  activa en los bloques que sirven una SPA, donde un 404 tiene que verse como pagina. En una API
  reemplazar el cuerpo destruye el JSON del error y deja al cliente sin el detalle del fallo. Si se
  agrega un bloque nuevo para un backend, la pregunta es quien consume la respuesta: un navegador
  pide pagina, un `fetch` pide JSON.
