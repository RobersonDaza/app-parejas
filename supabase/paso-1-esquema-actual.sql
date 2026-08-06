-- ============================================================
--  ENSAYO · PASO 1 DE 4        (los 4 pasos, en orden:)
--    1. supabase/paso-1-esquema-actual.sql        ← estás aquí
--    2. supabase/ensayo/paso-2-datos-de-ensayo.sql
--    3. supabase/001-multiples-parejas.sql        ← ojo: carpeta de arriba
--    4. supabase/ensayo/paso-4-verificar-aislamiento.sql
-- ------------------------------------------------------------
--  EL ESQUEMA DE ANTES DE LA FASE 2
--  (se puede repetir sin dar error: no cambia nada si ya está)
--
--  Ojo: esto ya NO es el estado de producción. Es el punto de
--  partida del que salió la migración 001, y sirve para reproducirlo
--  en un proyecto vacío y poder ensayar. La tabla `config` que crea
--  aquí se eliminó de producción el 5 de agosto de 2026.
--
--  Es la suma de todos los pasos de GUIA-SUPABASE.md, en orden.
--  No hace falta correrlo en el proyecto real: ya está aplicado.
--
--  Sirve para dos cosas:
--    1. Dejar un proyecto vacío en el mismo estado que producción,
--       y poder ensayar ahí la migración 001 sin arriesgar nada.
--    2. Documentar de dónde parte la migración.
--
--  Ojo: todas las políticas dicen `using (true)`. No es un error de
--  transcripción, es lo que hay hoy: la seguridad descansa en que
--  solo existen dos cuentas y el registro está cerrado.
-- ============================================================

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

create table if not exists reuniones (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  titulo text default '',
  notas text default '',
  items jsonb not null default '[]',
  creado_por text default '',
  created_at timestamptz not null default now()
);

create table if not exists fotos (
  id uuid primary key default gen_random_uuid(),
  actividad_id uuid,
  titulo_plan text default '',
  ruta text not null,
  subido_por text default '',
  created_at timestamptz not null default now()
);

create table if not exists calendario_intimo (
  id uuid primary key default gen_random_uuid(),
  fecha date not null unique,          -- unique global: el problema que arregla 001
  creado_por text default '',
  created_at timestamptz not null default now()
);

-- Columnas que se añadieron después (pasos 7 y 10 de la guía)
alter table gratitudes add column if not exists user_id  uuid default auth.uid();
alter table gratitudes add column if not exists reaccion text default '';
alter table checkins   add column if not exists user_id  uuid default auth.uid();

-- ============ SEGURIDAD (la de hoy) ============
alter table actividades       enable row level security;
alter table gratitudes        enable row level security;
alter table checkins          enable row level security;
alter table config            enable row level security;
alter table reuniones         enable row level security;
alter table fotos             enable row level security;
alter table calendario_intimo enable row level security;

drop policy if exists "pareja_actividades" on actividades;
create policy "pareja_actividades" on actividades for all to authenticated using (true) with check (true);
drop policy if exists "pareja_config" on config;
create policy "pareja_config"      on config      for all to authenticated using (true) with check (true);
drop policy if exists "pareja_reuniones" on reuniones;
create policy "pareja_reuniones"   on reuniones   for all to authenticated using (true) with check (true);
drop policy if exists "pareja_fotos" on fotos;
create policy "pareja_fotos"       on fotos       for all to authenticated using (true) with check (true);
drop policy if exists "pareja_intimo" on calendario_intimo;
create policy "pareja_intimo"      on calendario_intimo for all to authenticated using (true) with check (true);

-- Gratitud y check-ins: ambos leen, cada quien borra lo suyo
drop policy if exists "leer_gratitudes" on gratitudes;
create policy "leer_gratitudes"       on gratitudes for select to authenticated using (true);
drop policy if exists "crear_gratitudes" on gratitudes;
create policy "crear_gratitudes"      on gratitudes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "borrar_gratitudes" on gratitudes;
create policy "borrar_gratitudes"     on gratitudes for delete to authenticated using (user_id = auth.uid());
drop policy if exists "actualizar_gratitudes" on gratitudes;
create policy "actualizar_gratitudes" on gratitudes for update to authenticated using (true) with check (true);

drop policy if exists "leer_checkins" on checkins;
create policy "leer_checkins"   on checkins for select to authenticated using (true);
drop policy if exists "crear_checkins" on checkins;
create policy "crear_checkins"  on checkins for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "borrar_checkins" on checkins;
create policy "borrar_checkins" on checkins for delete to authenticated using (user_id = auth.uid());

-- ============ TIEMPO REAL ============
-- "already member" no es un problema: se ignora para poder repetir el script
do $$
declare t text;
begin
  foreach t in array array['actividades','gratitudes','checkins','config',
                           'reuniones','fotos','calendario_intimo'] loop
    begin
      execute format('alter publication supabase_realtime add table %I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end;
$$;

-- ============ ALMACENAMIENTO ============
-- El bucket 'fotos' (privado) se crea desde el panel: Storage → New bucket.
-- Estas son sus políticas actuales: basta con estar autenticado para
-- leer CUALQUIER foto del bucket.
insert into storage.buckets (id, name, public)
  values ('fotos', 'fotos', false)
  on conflict (id) do nothing;

drop policy if exists "fotos_ver" on storage.objects;
create policy "fotos_ver"    on storage.objects for select to authenticated using (bucket_id = 'fotos');
drop policy if exists "fotos_subir" on storage.objects;
create policy "fotos_subir"  on storage.objects for insert to authenticated with check (bucket_id = 'fotos');
drop policy if exists "fotos_borrar" on storage.objects;
create policy "fotos_borrar" on storage.objects for delete to authenticated using (bucket_id = 'fotos');
