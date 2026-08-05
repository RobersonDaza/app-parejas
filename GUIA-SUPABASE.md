# Guía: conectar la app a Supabase (datos compartidos en la nube)

> ⚠️ **Esta guía describe el montaje de una sola pareja**, que es como está
> hoy en producción. La fase 2 (varias parejas) cambia parte de esto: los
> nombres pasan de la tabla `config` a `miembros`, y el Paso 5b desaparece
> porque cada quien escoge su nombre al entrar. Mientras la migración
> `supabase/001-multiples-parejas.sql` no esté aplicada, sigue siendo válida
> tal cual. Se reescribirá en el corte.

Con esto, lo que agregue uno lo verá el otro al instante, desde cualquier celular.
Tiempo estimado: 15-20 minutos. Todo es gratis en el plan Free de Supabase.

> Nota: los nombres de los menús de Supabase pueden variar ligeramente según la
> versión del panel, pero la estructura general es la misma.

---

## Paso 1 — Crear la cuenta y el proyecto

1. Entra a https://supabase.com y crea una cuenta (puedes usar tu Google o GitHub).
2. Pulsa **New project**.
3. Completa:
   - **Name**: `app-matrimonial` (o el que quieras).
   - **Database Password**: inventa una contraseña fuerte y **guárdala** (es de la base de datos, no la usarás en la app, pero no la pierdas).
   - **Region**: elige *South America (São Paulo)* si están en Colombia (menor latencia).
4. Pulsa **Create new project** y espera 1-2 minutos a que termine de crearse.

## Paso 2 — Crear las tablas (copiar y pegar)

1. En el menú lateral, abre **SQL Editor**.
2. Pulsa **New query**, pega TODO el bloque de abajo y pulsa **Run**:

```sql
-- ============ TABLAS ============
create table if not exists actividades (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text default '',
  fecha date not null,
  categoria text not null,
  completada boolean not null default false,
  creado_por text default '',
  created_at timestamptz not null default now()
);

create table if not exists gratitudes (
  id uuid primary key default gen_random_uuid(),
  autor text not null,
  texto text not null,
  created_at timestamptz not null default now()
);

create table if not exists checkins (
  id uuid primary key default gen_random_uuid(),
  autor text not null,
  semana date not null,
  comunicacion int not null,
  tiempo int not null,
  animo int not null,
  feliz text default '',
  mejorar text default '',
  created_at timestamptz not null default now()
);

create table if not exists config (
  clave text primary key,
  valor text not null
);

-- ============ SEGURIDAD ============
-- Solo usuarios autenticados (ustedes dos) pueden leer y escribir.
alter table actividades enable row level security;
alter table gratitudes  enable row level security;
alter table checkins    enable row level security;
alter table config      enable row level security;

create policy "pareja_actividades" on actividades for all to authenticated using (true) with check (true);
create policy "pareja_gratitudes"  on gratitudes  for all to authenticated using (true) with check (true);
create policy "pareja_checkins"    on checkins    for all to authenticated using (true) with check (true);
create policy "pareja_config"      on config      for all to authenticated using (true) with check (true);

-- ============ TIEMPO REAL ============
-- Hace que la app del otro se entere al instante de cualquier cambio.
alter publication supabase_realtime add table actividades, gratitudes, checkins, config;
```

3. Debe decir **Success**. Si lo corres dos veces, la parte de "publication" puede
   dar error de "already member" — es normal, ignóralo.

## Paso 3 — Crear los dos usuarios de la pareja

1. En el menú lateral: **Authentication → Users**.
2. Pulsa **Add user → Create new user**.
3. Usuario 1: el correo de la primera persona + una contraseña que recuerde.
   **Marca la casilla "Auto Confirm User"** (para que no necesite confirmar por email).
4. Repite para el usuario 2: el otro correo + su contraseña.

## Paso 4 — Cerrar la puerta a desconocidos

1. Ve a **Authentication → Sign In / Providers** (o "Settings" según la versión del panel).
2. Busca la opción **"Allow new users to sign up"** y **desactívala**.
   Así nadie más podrá crearse una cuenta, aunque conozca la URL.

## Paso 5 — Copiar las claves a la app

1. Ve a **Project Settings** (engranaje) **→ API** (en paneles nuevos: **Data API**).
2. Copia dos valores:
   - **Project URL** → algo como `https://abcdefgh.supabase.co`
   - **anon public** key → una clave larga que empieza por `eyJ...`
3. Haz una copia del archivo `config.example.js` y llámala `config.js`
   (debe quedar en la misma carpeta que `index.html`). Ábrela con el Bloc de
   notas o cualquier editor:

```js
window.APP_CONFIG = {
  SUPABASE_URL:      'PEGA_AQUI_TU_PROJECT_URL',
  SUPABASE_ANON_KEY: 'PEGA_AQUI_TU_ANON_PUBLIC_KEY'
};
```

4. Reemplaza los dos textos `PEGA_AQUI...` por tus valores (entre comillas)
   y guarda el archivo.

   > `config.js` está en `.gitignore`: tus claves no se suben al repositorio.
   > `index.html` no se toca.

5. Los correos y los nombres **no van en este archivo**: se guardan dentro de
   la base de datos, en el Paso 5b. Así la página publicada no expone ningún
   dato personal, ni siquiera en su código fuente.

## Paso 5b — Guardar los nombres dentro de la base de datos

La app necesita saber qué nombre mostrar para cada correo (y cuál va primero,
que es el que usa el color terracota). Eso vive en la tabla `config`, que solo
pueden leer los dos usuarios ya autenticados.

En **SQL Editor → New query**, cambia los dos correos y los dos nombres por los
reales y ejecuta:

```sql
insert into config (clave, valor) values (
  'usuarios',
  '{"correo-de-ella@ejemplo.com":"Nombre1","correo-de-el@ejemplo.com":"Nombre2"}'
)
on conflict (clave) do update set valor = excluded.valor;
```

El orden importa: el primero de la lista es quien aparece con el color
terracota en el frasco de gratitud y en los check-ins.

Si algún día quieren cambiar un nombre, vuelvan a correr esa misma consulta con
el valor nuevo. Mientras esa fila no exista, la app funciona igual pero se
titula "Nuestro Espacio" y muestra la parte del correo antes de la @.

> ¿Es seguro que la clave "anon" quede en el archivo? Sí: esa clave es pública
> por diseño. La protección real son las políticas del Paso 2 (solo usuarios
> autenticados) y el Paso 4 (nadie puede registrarse).

## Paso 6 — Probar y publicar

1. Abre `index.html` en tu navegador. Debe aparecer la pantalla de login.
2. Entra con tu correo y contraseña. La primera vez te pedirá la fecha de inicio
   de la relación (ahora se guarda en la nube, para ambos).
3. Agrega un plan de prueba. Luego entra desde otro navegador o celular con
   el otro usuario: debes ver el mismo plan, y si agregas algo nuevo en uno,
   aparece en el otro en segundos con una notificación.
4. Si todo funciona, sube la carpeta de nuevo a Netlify:
   **tu sitio → Deploys → arrastrar la carpeta**.

## Paso 7 — Cada uno solo puede borrar lo suyo (mejora posterior)

Ejecuta este script en **SQL Editor → New query → Run**. Hace que los mensajes
de gratitud y los check-ins tengan "dueño": ambos pueden leerlo todo, pero solo
quien escribió algo puede eliminarlo (la base de datos lo garantiza, no solo la
pantalla).

```sql
-- 1. Columna que identifica al dueño de cada fila
alter table gratitudes add column if not exists user_id uuid default auth.uid();
alter table checkins   add column if not exists user_id uuid default auth.uid();

-- 2. Asignar dueño a lo ya escrito (por correo de cada uno)
update gratitudes g set user_id = u.id from auth.users u
  where g.user_id is null and (
    (g.autor = 'Nombre1'  and u.email = 'correo-de-ella@ejemplo.com') or
    (g.autor = 'Nombre2'  and u.email = 'correo-de-el@ejemplo.com'));

update checkins c set user_id = u.id from auth.users u
  where c.user_id is null and (
    (c.autor = 'Nombre1'  and u.email = 'correo-de-ella@ejemplo.com') or
    (c.autor = 'Nombre2'  and u.email = 'correo-de-el@ejemplo.com'));

-- 3. Nuevas políticas: leer y crear ambos, borrar solo lo propio
drop policy if exists "pareja_gratitudes" on gratitudes;
create policy "leer_gratitudes"   on gratitudes for select to authenticated using (true);
create policy "crear_gratitudes"  on gratitudes for insert to authenticated with check (user_id = auth.uid());
create policy "borrar_gratitudes" on gratitudes for delete to authenticated using (user_id = auth.uid());

drop policy if exists "pareja_checkins" on checkins;
create policy "leer_checkins"   on checkins for select to authenticated using (true);
create policy "crear_checkins"  on checkins for insert to authenticated with check (user_id = auth.uid());
create policy "borrar_checkins" on checkins for delete to authenticated using (user_id = auth.uid());
```

Los planes (actividades) siguen siendo de los dos: cualquiera puede completarlos
o eliminarlos a propósito, porque son compartidos.

## Paso 8 — Tabla para las reuniones mensuales

La pestaña "Reunión" necesita su propia tabla. Ejecuta en **SQL Editor → New query → Run**:

```sql
create table if not exists reuniones (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  titulo text default '',
  notas text default '',
  items jsonb not null default '[]',
  creado_por text default '',
  created_at timestamptz not null default now()
);

alter table reuniones enable row level security;
create policy "pareja_reuniones" on reuniones for all to authenticated using (true) with check (true);

alter publication supabase_realtime add table reuniones;
```

Las reuniones son compartidas (como los planes): cualquiera de los dos puede
crearlas, marcar acuerdos como cumplidos o eliminarlas.

## Paso 9 — Fotos de los planes (Storage)

La galería "Recuerdos" guarda las fotos en Supabase Storage. Dos partes:

**A. Crear el bucket (carpeta de archivos):**

1. En el menú lateral: **Storage → New bucket**.
2. Nombre: `fotos` (exacto, en minúsculas).
3. Deja **desactivada** la opción "Public bucket" (las fotos serán privadas:
   solo ustedes, ya con sesión iniciada, podrán verlas).
4. Crea el bucket.

**B. Permisos y tabla (SQL Editor → New query → Run):**

```sql
-- Tabla que registra cada foto y a qué plan pertenece
create table if not exists fotos (
  id uuid primary key default gen_random_uuid(),
  actividad_id uuid,
  titulo_plan text default '',
  ruta text not null,
  subido_por text default '',
  created_at timestamptz not null default now()
);

alter table fotos enable row level security;
create policy "pareja_fotos" on fotos for all to authenticated using (true) with check (true);
alter publication supabase_realtime add table fotos;

-- Permisos sobre los archivos del bucket: solo usuarios autenticados
create policy "fotos_ver"    on storage.objects for select to authenticated using (bucket_id = 'fotos');
create policy "fotos_subir"  on storage.objects for insert to authenticated with check (bucket_id = 'fotos');
create policy "fotos_borrar" on storage.objects for delete to authenticated using (bucket_id = 'fotos');
```

> Si las tres últimas líneas dan un error de permisos ("must be owner..."),
> crea esas mismas reglas desde la interfaz: **Storage → fotos → Policies →
> New policy**, permitiendo SELECT, INSERT y DELETE al rol `authenticated`.

**Cómo se usa en la app:** marca un plan como completado → aparece el botón
"📷 Agregar foto" en su tarjeta → elige una o varias fotos del celular. Se
comprimen automáticamente antes de subir. La galería completa está en
**Inicio → Nuestros recuerdos**, agrupada por evento; al tocar una foto se ve
en grande y se puede eliminar.

> Espacio: el plan Free incluye 1 GB. Con la compresión automática
> (~200-400 KB por foto), alcanza para unas 3.000 fotos.

## Paso 10 — Reacciones con emojis en el Frasco de Gratitud

Permite que cada uno responda con un emoji (❤️ 🥹 😂 🙏 😍) al mensaje del otro.
Ejecuta en **SQL Editor → New query → Run**:

```sql
-- Columna donde se guarda la reacción del otro
alter table gratitudes add column if not exists reaccion text default '';

-- Permiso de actualización (necesario para poder reaccionar)
create policy "actualizar_gratitudes" on gratitudes
  for update to authenticated using (true) with check (true);
```

En la app: bajo cada mensaje del otro aparece la fila de emojis; tocas uno para
reaccionar y el mismo de nuevo para quitarla. El autor del mensaje ve la
reacción junto a su nombre.

## Paso 11 — Calendario íntimo

Tabla para la pestaña "Íntimo". Ejecuta en **SQL Editor → New query → Run**:

```sql
create table if not exists calendario_intimo (
  id uuid primary key default gen_random_uuid(),
  fecha date not null unique,
  creado_por text default '',
  created_at timestamptz not null default now()
);

alter table calendario_intimo enable row level security;
create policy "pareja_intimo" on calendario_intimo for all to authenticated using (true) with check (true);
alter publication supabase_realtime add table calendario_intimo;
```

En la app: calendario mensual con navegación entre meses. Tocar un día lo
agenda (queda en terracota); tocarlo de nuevo lo quita. Abajo se listan las 3
próximas fechas. Es compartido: cualquiera de los dos agenda o desagenda.

## Problemas comunes

- **"Correo o contraseña incorrectos"**: verifica que el usuario exista en
  Authentication → Users y que se haya creado con "Auto Confirm User". Si no,
  bórralo y créalo de nuevo.
- **Entra pero no carga datos / error de conexión**: casi siempre es el Paso 2
  sin ejecutar, o la URL/clave mal pegadas (sin comillas, con espacios, o
  incompletas).
- **No se actualiza en tiempo real**: revisa que la última línea del SQL
  (publication) haya corrido sin error. Aun sin tiempo real, los datos sí se
  comparten: basta recargar la página.
- **La fecha del contador no aparece**: entra una vez y guárdala en el modal;
  queda en la tabla `config` para los dos.

## Notas

- `respaldo-version-local.html` es la versión anterior (sin nube), por si
  quieres conservarla o compararla. No hace falta subirla a Netlify.
- Los datos que ya tenías guardados en el celular (localStorage) no se migran
  automáticamente; habría que volver a escribirlos. Si tenías muchos, avísame y
  hacemos un pequeño script de migración.
- Plan Free de Supabase: más que suficiente para dos personas. Si el proyecto
  pasa ~1 semana sin uso puede "pausarse"; se reactiva con un clic en el panel.
