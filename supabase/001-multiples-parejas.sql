-- ============================================================
--  MIGRACIÓN 001 — De una pareja a muchas
--
--  (En el ensayo del proyecto desechable, este archivo es el
--   PASO 3 DE 4. Va después de paso-2-datos-de-ensayo.sql y
--   antes de paso-4-verificar-aislamiento.sql.)
--
--  QUÉ HACE
--  Hoy todas las políticas dicen `using (true)`: cualquier usuario
--  autenticado ve todo. Eso funciona con dos cuentas y el registro
--  cerrado. Esta migración introduce el concepto de "pareja" como
--  dueña de los datos y reescribe TODAS las políticas para que cada
--  quien vea únicamente lo suyo.
--
--  ANTES DE EJECUTAR
--  1. Haz un respaldo: Supabase → Database → Backups, o exporta las
--     tablas a CSV desde Table Editor.
--  2. Léela entera. Toca datos en vivo.
--  3. Ejecútala completa de una sola vez (va en una transacción:
--     si algo falla, no queda nada a medias).
--
--  DESPUÉS DE EJECUTAR
--  La app vieja deja de funcionar: necesita enviar pareja_id. El
--  despliegue de la app nueva y esta migración van juntos.
--
--  Las fotos que ya están en Storage siguen en su ruta antigua y hay
--  que moverlas a  <pareja_id>/...  con el script aparte. Hasta que
--  eso pase, la política de lectura acepta ambas rutas (ver el final).
-- ============================================================

begin;

-- Aviso claro si se corre sobre una base que no es la esperada
do $$
begin
  if to_regclass('public.actividades') is null then
    raise exception 'No encuentro las tablas de la app. Si estás ensayando, corre antes supabase/paso-1-esquema-actual.sql';
  end if;
end;
$$;

-- ------------------------------------------------------------
--  1. Las dos tablas nuevas
-- ------------------------------------------------------------

-- El espacio compartido de una pareja
create table if not exists parejas (
  id                uuid primary key default gen_random_uuid(),
  fecha_inicio      date,                    -- reemplaza config.fecha_inicio
  codigo_invitacion text unique,             -- 6 caracteres; se borra al unirse el segundo
  codigo_expira     timestamptz,
  created_at        timestamptz not null default now()
);

-- Quién pertenece a qué pareja, y cómo se llama dentro de la app.
-- La llave primaria es user_id: cada persona pertenece a un solo espacio.
create table if not exists miembros (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  pareja_id  uuid not null references parejas(id) on delete cascade,
  nombre     text not null default '',
  color      text not null default 'terracota',   -- 'terracota' | 'oliva'
  created_at timestamptz not null default now()
);

create index if not exists miembros_pareja_idx on miembros (pareja_id);

-- ------------------------------------------------------------
--  2. La función en la que se apoyan todas las políticas
--
--  SECURITY DEFINER es imprescindible: sin él, consultar "miembros"
--  desde una política de "miembros" entra en recursión infinita.
-- ------------------------------------------------------------
create or replace function mi_pareja()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select pareja_id from miembros where user_id = auth.uid();
$$;

-- ------------------------------------------------------------
--  3. Alta de espacios: crear uno nuevo o unirse con código
--
--  Van como funciones y no como INSERT directo para que nadie pueda
--  meterse en un espacio ajeno escribiendo en "miembros" a mano.
-- ------------------------------------------------------------

-- Código de 6 caracteres sin letras ni números que se confundan
-- (nada de O/0 ni I/1), pensado para dictarlo o mandarlo por chat.
create or replace function generar_codigo()
returns text
language sql
volatile
as $$
  select string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', floor(random() * 32)::int + 1, 1), ''
  ) from generate_series(1, 6);
$$;

create or replace function crear_pareja()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  nueva  uuid;
  codigo text;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión';
  end if;
  if exists (select 1 from miembros where user_id = auth.uid()) then
    raise exception 'Ya perteneces a un espacio';
  end if;

  loop
    codigo := generar_codigo();
    exit when not exists (select 1 from parejas where codigo_invitacion = codigo);
  end loop;

  insert into parejas (codigo_invitacion, codigo_expira)
    values (codigo, now() + interval '7 days')
    returning id into nueva;

  insert into miembros (user_id, pareja_id, color)
    values (auth.uid(), nueva, 'terracota');

  return nueva;
end;
$$;

create or replace function unirse_con_codigo(codigo_in text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  objetivo uuid;
  cuantos  int;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión';
  end if;
  if exists (select 1 from miembros where user_id = auth.uid()) then
    raise exception 'Ya perteneces a un espacio';
  end if;

  select id into objetivo
    from parejas
   where codigo_invitacion = upper(trim(codigo_in))
     and (codigo_expira is null or codigo_expira > now());

  if objetivo is null then
    raise exception 'Ese código no existe o ya venció';
  end if;

  select count(*) into cuantos from miembros where pareja_id = objetivo;
  if cuantos >= 2 then
    raise exception 'Ese espacio ya tiene dos personas';
  end if;

  insert into miembros (user_id, pareja_id, color)
    values (auth.uid(), objetivo, 'oliva');

  -- El código es de un solo uso
  update parejas set codigo_invitacion = null, codigo_expira = null
   where id = objetivo;

  return objetivo;
end;
$$;

-- ------------------------------------------------------------
--  4. La columna pareja_id en las tablas de datos
-- ------------------------------------------------------------
alter table actividades       add column if not exists pareja_id uuid references parejas(id) on delete cascade;
alter table gratitudes        add column if not exists pareja_id uuid references parejas(id) on delete cascade;
alter table checkins          add column if not exists pareja_id uuid references parejas(id) on delete cascade;
alter table reuniones         add column if not exists pareja_id uuid references parejas(id) on delete cascade;
alter table fotos             add column if not exists pareja_id uuid references parejas(id) on delete cascade;
alter table calendario_intimo add column if not exists pareja_id uuid references parejas(id) on delete cascade;

-- ------------------------------------------------------------
--  5. Migrar los datos que ya existen
--
--  Todo lo que hay hoy pertenece a una sola pareja: la de ustedes.
--  El bloque no hace nada si ya se corrió antes.
-- ------------------------------------------------------------
do $$
declare
  la_pareja uuid;
  -- json y NO jsonb: jsonb reordena las claves por longitud y aquí el orden
  -- es justo lo que decide quién conserva el color terracota.
  mapa      json;
  primero   text;
  u         record;
begin
  if exists (select 1 from parejas) then
    raise notice 'Ya existe al menos una pareja: se omite la migración de datos.';
    return;
  end if;

  -- El mapa correo → nombre que hoy vive en config
  select coalesce((select valor from config where clave = 'usuarios'), '{}')::json into mapa;
  select k into primero from json_object_keys(mapa) k limit 1;

  insert into parejas (fecha_inicio)
    values ((select valor::date from config where clave = 'fecha_inicio'))
    returning id into la_pareja;

  -- Las cuentas que existen hoy son esa pareja. El primer correo del
  -- mapa conserva el color terracota, para que nada cambie de aspecto.
  for u in select id, email from auth.users order by created_at loop
    insert into miembros (user_id, pareja_id, nombre, color, created_at)
    values (
      u.id,
      la_pareja,
      coalesce(mapa ->> lower(u.email), split_part(u.email, '@', 1)),
      case when lower(u.email) = primero then 'terracota' else 'oliva' end,
      -- clock_timestamp() y no now(): now() devuelve la hora de la
      -- transacción, igual para los dos, y entonces el orden del título
      -- ("Fulana & Mengano") quedaría al azar.
      clock_timestamp()
    )
    on conflict (user_id) do nothing;
  end loop;

  update actividades       set pareja_id = la_pareja where pareja_id is null;
  update gratitudes        set pareja_id = la_pareja where pareja_id is null;
  update checkins          set pareja_id = la_pareja where pareja_id is null;
  update reuniones         set pareja_id = la_pareja where pareja_id is null;
  update fotos             set pareja_id = la_pareja where pareja_id is null;
  update calendario_intimo set pareja_id = la_pareja where pareja_id is null;
end;
$$;

-- Ya con los datos asignados, la columna pasa a ser obligatoria
alter table actividades       alter column pareja_id set not null;
alter table gratitudes        alter column pareja_id set not null;
alter table checkins          alter column pareja_id set not null;
alter table reuniones         alter column pareja_id set not null;
alter table fotos             alter column pareja_id set not null;
alter table calendario_intimo alter column pareja_id set not null;

create index if not exists actividades_pareja_idx       on actividades (pareja_id);
create index if not exists gratitudes_pareja_idx        on gratitudes (pareja_id);
create index if not exists checkins_pareja_idx          on checkins (pareja_id);
create index if not exists reuniones_pareja_idx         on reuniones (pareja_id);
create index if not exists fotos_pareja_idx             on fotos (pareja_id);
create index if not exists calendario_intimo_pareja_idx on calendario_intimo (pareja_id);

-- ------------------------------------------------------------
--  6. Arreglar la restricción del calendario íntimo
--
--  Era `unique (fecha)` a secas: si una pareja marcaba el 14 de
--  febrero, ninguna otra podría marcarlo jamás.
-- ------------------------------------------------------------
alter table calendario_intimo drop constraint if exists calendario_intimo_fecha_key;
alter table calendario_intimo
  add constraint calendario_intimo_pareja_fecha_key unique (pareja_id, fecha);

-- ------------------------------------------------------------
--  7. Reescribir TODAS las políticas
--
--  Esta es la parte que de verdad importa. Fuera los `using (true)`.
-- ------------------------------------------------------------
alter table parejas  enable row level security;
alter table miembros enable row level security;

drop policy if exists "ver_mi_pareja"    on parejas;
drop policy if exists "editar_mi_pareja" on parejas;
create policy "ver_mi_pareja"    on parejas for select to authenticated using (id = mi_pareja());
create policy "editar_mi_pareja" on parejas for update to authenticated
  using (id = mi_pareja()) with check (id = mi_pareja());

drop policy if exists "ver_miembros"     on miembros;
drop policy if exists "editar_mi_perfil" on miembros;
-- Cada quien ve a los miembros de su espacio (para mostrar el nombre del otro)
create policy "ver_miembros" on miembros for select to authenticated using (pareja_id = mi_pareja());
-- Pero solo puede editar su propia ficha, y sin cambiarse de espacio
create policy "editar_mi_perfil" on miembros for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and pareja_id = mi_pareja());

-- Planes: compartidos dentro de la pareja
drop policy if exists "pareja_actividades" on actividades;
create policy "pareja_actividades" on actividades for all to authenticated
  using (pareja_id = mi_pareja()) with check (pareja_id = mi_pareja());

-- Gratitud: ambos leen; cada quien crea y borra lo suyo; ambos reaccionan
drop policy if exists "pareja_gratitudes"      on gratitudes;
drop policy if exists "leer_gratitudes"        on gratitudes;
drop policy if exists "crear_gratitudes"       on gratitudes;
drop policy if exists "borrar_gratitudes"      on gratitudes;
drop policy if exists "actualizar_gratitudes"  on gratitudes;
create policy "leer_gratitudes"   on gratitudes for select to authenticated
  using (pareja_id = mi_pareja());
create policy "crear_gratitudes"  on gratitudes for insert to authenticated
  with check (pareja_id = mi_pareja() and user_id = auth.uid());
create policy "actualizar_gratitudes" on gratitudes for update to authenticated
  using (pareja_id = mi_pareja()) with check (pareja_id = mi_pareja());
create policy "borrar_gratitudes" on gratitudes for delete to authenticated
  using (pareja_id = mi_pareja() and user_id = auth.uid());

-- Check-ins: mismo criterio
drop policy if exists "pareja_checkins" on checkins;
drop policy if exists "leer_checkins"   on checkins;
drop policy if exists "crear_checkins"  on checkins;
drop policy if exists "borrar_checkins" on checkins;
create policy "leer_checkins"   on checkins for select to authenticated
  using (pareja_id = mi_pareja());
create policy "crear_checkins"  on checkins for insert to authenticated
  with check (pareja_id = mi_pareja() and user_id = auth.uid());
create policy "borrar_checkins" on checkins for delete to authenticated
  using (pareja_id = mi_pareja() and user_id = auth.uid());

drop policy if exists "pareja_reuniones" on reuniones;
create policy "pareja_reuniones" on reuniones for all to authenticated
  using (pareja_id = mi_pareja()) with check (pareja_id = mi_pareja());

drop policy if exists "pareja_fotos" on fotos;
create policy "pareja_fotos" on fotos for all to authenticated
  using (pareja_id = mi_pareja()) with check (pareja_id = mi_pareja());

drop policy if exists "pareja_intimo" on calendario_intimo;
create policy "pareja_intimo" on calendario_intimo for all to authenticated
  using (pareja_id = mi_pareja()) with check (pareja_id = mi_pareja());

-- ------------------------------------------------------------
--  8. Storage: las fotos también estaban abiertas
--
--  Antes bastaba con estar autenticado para leer CUALQUIER foto del
--  bucket. Ahora las rutas nuevas empiezan por el id de la pareja:
--      <pareja_id>/<actividad_id>/<archivo>.jpg
--
--  Las fotos que ya existen están en  <actividad_id>/<archivo>.jpg,
--  sin el prefijo. El puente para ellas no puede mirar la ruta: mira
--  la tabla `fotos`, donde cada archivo ya tiene su dueño. Es preciso
--  (solo alcanza a las de tu pareja) y se cae solo cuando muevas los
--  archivos y borres las dos cláusulas `or exists (...)`.
-- ------------------------------------------------------------
drop policy if exists "fotos_ver"    on storage.objects;
drop policy if exists "fotos_subir"  on storage.objects;
drop policy if exists "fotos_borrar" on storage.objects;

create policy "fotos_ver" on storage.objects for select to authenticated
  using (
    bucket_id = 'fotos'
    and (
      (storage.foldername(name))[1] = mi_pareja()::text
      or exists (select 1 from fotos f where f.ruta = storage.objects.name and f.pareja_id = mi_pareja())
    )
  );

-- Al subir no hay puente: todo lo nuevo va bajo el id de la pareja
create policy "fotos_subir" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = mi_pareja()::text
  );

create policy "fotos_borrar" on storage.objects for delete to authenticated
  using (
    bucket_id = 'fotos'
    and (
      (storage.foldername(name))[1] = mi_pareja()::text
      or exists (select 1 from fotos f where f.ruta = storage.objects.name and f.pareja_id = mi_pareja())
    )
  );

-- ------------------------------------------------------------
--  9. Tiempo real
-- ------------------------------------------------------------
alter publication supabase_realtime add table parejas, miembros;

commit;

-- ------------------------------------------------------------
--  PENDIENTE, a propósito, para después del despliegue de la app:
--
--  a) Mover las fotos viejas de  <actividad_id>/...  a
--     <pareja_id>/<actividad_id>/...  y luego quitar las cláusulas
--     `or exists (...)` de las políticas fotos_ver y fotos_borrar.
--  b) Eliminar la tabla `config`: fecha_inicio ya vive en `parejas`
--     y los nombres en `miembros`.
--         drop table config;
--  c) Reactivar el registro de usuarios:
--         Authentication → Sign In / Providers → Allow new users to sign up
--     NO lo actives antes de que esta migración esté aplicada y
--     verificada. Es justo lo que hoy sostiene la seguridad.
-- ------------------------------------------------------------
