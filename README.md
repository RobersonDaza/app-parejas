# App Parejas

Aplicación web privada para parejas: un espacio compartido para organizar planes,
recordar fechas importantes y cuidar la relación con hábitos sencillos.

Es una app **mobile-first** en un solo archivo (`index.html`) con
Tailwind CSS por CDN y **Supabase** como base de datos, autenticación y
almacenamiento de fotos. Los dos usuarios ven lo mismo y los cambios aparecen
en tiempo real.

## Módulos

- **Inicio** — contador de años, meses y días juntos, y próximos eventos.
- **Planes** — metas y actividades de pareja (citas, viajes, hogar, crecimiento)
  con fecha objetivo, categoría y estado.
- **Frasco de la gratitud** — notas rápidas de agradecimiento en un feed compartido.
- **Check-in emocional semanal** — evaluación de comunicación, mejoras y
  momentos felices.
- **Recuerdos** — galería de fotos guardadas en Supabase Storage.
- **Calendario íntimo** y **reuniones de pareja**.
- **Ruleta de citas** — generador aleatorio de planes para romper la rutina.
- Modo claro/oscuro (preferencia local de cada dispositivo).

## Puesta en marcha

1. Clona el repositorio.
2. Crea tu proyecto de Supabase y las tablas siguiendo
   [GUIA-SUPABASE.md](GUIA-SUPABASE.md) (incluye todo el SQL, las políticas RLS
   y la configuración de Storage).
3. Copia la plantilla de configuración y complétala con tus datos:

   ```bash
   cp config.example.js config.js
   ```

   En `config.js` pon tu `SUPABASE_URL` y tu clave `anon public`. Los correos
   y los nombres no van ahí: cada persona escoge su nombre la primera vez que
   entra y se guarda en la tabla `miembros`.
4. Abre `index.html` en el navegador (o sírvelo con cualquier servidor estático)
   e inicia sesión con esos correos.

Si `config.js` no existe, la app arranca y muestra un aviso de "falta configurar
Supabase" en lugar de fallar.

## Despliegue

El sitio se publica solo en Netlify con cada `push` a `main`. La configuración
está en [netlify.toml](netlify.toml): Netlify ejecuta `node scripts/build-site.js`,
que copia `index.html` y `sw.js` a `dist/` y genera ahí un `config.js` a partir
de dos variables de entorno del panel de Netlify:

| Variable | De dónde sale |
|---|---|
| `SUPABASE_URL` | Supabase → Project Settings → API |
| `SUPABASE_ANON_KEY` | la clave `anon public` de esa misma pantalla |

Si alguna falta, el build falla y **no** se publica nada: es preferible a dejar
en línea un sitio que no puede conectarse.

Para reproducir el build en local:

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... node scripts/build-site.js
```

## Configuración y seguridad

`config.js` está en `.gitignore` y **nunca se sube al repositorio**. Solo se
publica la plantilla `config.example.js`.

La clave `anon public` de Supabase está pensada para vivir en el cliente: lo que
realmente protege los datos son las políticas **RLS** de la base de datos. Aun
así, este proyecto la mantiene fuera del repositorio.

Los **correos y los nombres no están en el código**. Se guardan en la tabla
`config` de la base de datos y la app los pide una vez iniciada la sesión, ya
autenticada. Por eso ni el repositorio ni el código fuente del sitio publicado
contienen datos personales: antes del login la app se llama "Nuestro Espacio".

## Estructura

```
index.html          La aplicación completa (HTML + Tailwind + JS)
config.example.js   Plantilla de configuración (copiar a config.js)
sw.js               Service worker
GUIA-SUPABASE.md    Guía paso a paso para montar el backend
AGENTS.md           Instrucciones de contexto para asistentes de IA
```

Los nombres que se muestran (título, cabecera y colores de cada autor) salen de
`USUARIOS` en `config.js`. El código no lleva nombres propios: si no hay
configuración, la app muestra "Nuestro Espacio".

## Tecnologías

HTML + JavaScript (sin framework, sin build), Tailwind CSS (CDN),
Supabase (Postgres, Auth, Storage y Realtime).
