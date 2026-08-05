-- ============================================================
--  ENSAYO · PASO 2 DE 4
--  Antes de este va: supabase/paso-1-esquema-actual.sql
-- ------------------------------------------------------------
--  Datos falsos que imitan a producción
--
--  SOLO PARA EL PROYECTO DESECHABLE. Nunca en el real: crea
--  usuarios de mentira escribiendo directamente en auth.users.
--
--  Se corre DESPUÉS del paso 1 y ANTES de la migración 001. Deja el proyecto como está hoy el tuyo: dos
--  personas, sus nombres en config, y contenido repartido entre
--  las dos, para poder comprobar que la migración no pierde nada.
-- ============================================================

-- Aviso claro si se corre fuera de orden
do $$
begin
  if to_regclass('public.config') is null then
    raise exception 'Falta el paso 1: corre antes supabase/paso-1-esquema-actual.sql';
  end if;
end;
$$;

do $$
declare
  id_ana  uuid := gen_random_uuid();
  id_beto uuid := gen_random_uuid();
  plan_1  uuid;
begin
  -- Dos cuentas de prueba. Si esta parte falla por la versión de
  -- Supabase, créalas a mano en Authentication → Users con estos
  -- mismos correos y vuelve a correr el resto del script.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', id_ana,  'authenticated', 'authenticated',
     'ana@ensayo.test',  '', now(), now() - interval '2 days', now()),
    ('00000000-0000-0000-0000-000000000000', id_beto, 'authenticated', 'authenticated',
     'beto@ensayo.test', '', now(), now() - interval '1 day',  now());

  -- Lo que hoy vive en config: nombres y fecha de inicio
  insert into config (clave, valor) values
    ('usuarios', json_build_object('ana@ensayo.test', 'Ana', 'beto@ensayo.test', 'Beto')::text),
    ('fecha_inicio', '2019-03-14')
  on conflict (clave) do update set valor = excluded.valor;

  -- Planes
  insert into actividades (titulo, descripcion, fecha, categoria, completada, creado_por)
  values ('Cita en el parque', 'Llevar picnic', current_date - 10, 'Citas', true, 'Ana')
  returning id into plan_1;

  insert into actividades (titulo, fecha, categoria, creado_por)
  values ('Viaje a la costa', current_date + 30, 'Viajes', 'Beto');

  -- Frasco de la gratitud: dos de Ana, una de Beto
  insert into gratitudes (autor, texto, user_id) values
    ('Ana',  'Gracias por el café de esta mañana', id_ana),
    ('Ana',  'Me encantó cómo me escuchaste ayer',  id_ana),
    ('Beto', 'Gracias por acompañarme al médico',   id_beto);

  -- Check-ins
  insert into checkins (autor, user_id, semana, comunicacion, tiempo, animo, feliz) values
    ('Ana',  id_ana,  date_trunc('week', current_date)::date, 4, 5, 4, 'La caminata del domingo'),
    ('Beto', id_beto, date_trunc('week', current_date)::date, 5, 4, 5, 'Cocinar juntos');

  -- Reunión
  insert into reuniones (fecha, titulo, notas, items, creado_por)
  values (current_date - 5, 'Reunión de julio', 'Todo bien',
          '[{"t":"Ahorrar para el viaje","ok":false}]'::jsonb, 'Ana');

  -- Fotos: en la ruta VIEJA, <actividad_id>/archivo.jpg, que es lo
  -- que hay hoy. Así se puede probar el puente de las políticas.
  insert into fotos (actividad_id, titulo_plan, ruta, subido_por) values
    (plan_1, 'Cita en el parque', plan_1::text || '/1720000000_abc12.jpg', 'Ana'),
    (plan_1, 'Cita en el parque', plan_1::text || '/1720000001_def34.jpg', 'Beto');

  -- Calendario íntimo
  insert into calendario_intimo (fecha, creado_por) values
    (current_date - 3, 'Ana'),
    (current_date - 9, 'Beto');

  raise notice 'Datos de ensayo listos. Ana=% Beto=%', id_ana, id_beto;
end;
$$;

-- Resumen de lo sembrado
select 'actividades' as tabla, count(*) from actividades
union all select 'gratitudes',        count(*) from gratitudes
union all select 'checkins',          count(*) from checkins
union all select 'reuniones',         count(*) from reuniones
union all select 'fotos',             count(*) from fotos
union all select 'calendario_intimo', count(*) from calendario_intimo
union all select 'usuarios',          count(*) from auth.users;
