-- ============================================================
--  ENSAYO · PASO 4 DE 4
--  Antes de este van, en orden: paso 1, paso 2 y la migración 001
-- ------------------------------------------------------------
--  ¿De verdad una pareja no ve nada de la otra?
--
--  SOLO PARA EL PROYECTO DESECHABLE.
--  Se corre DESPUÉS de la migración 001.
--
--  Crea una segunda pareja (Carla y Dani) usando las funciones
--  reales de alta, siembra contenido suyo, y luego se hace pasar
--  por cada usuario para contar qué alcanza a ver.
--
--  Cómo se hace pasar por alguien: `set local role authenticated`
--  más el claim `sub` del usuario. Es la misma vía por la que la
--  app llega a la base de datos, así que las políticas se evalúan
--  igual que en producción. Sin cambiar de rol la prueba no valdría:
--  el dueño de las tablas se salta RLS.
--
--  Todo ocurre dentro de una transacción que termina en ROLLBACK:
--  al acabar, el proyecto queda como estaba.
-- ============================================================

begin;

create temp table resultado (
  n serial, prueba text, esperado text, obtenido text, veredicto text
) on commit drop;

do $$
declare
  ana uuid; carla uuid; dani uuid;
  pareja_a uuid; pareja_b uuid;
  codigo text; plan_b uuid;
  n int; hubo_error boolean; storage_sembrado boolean := true;
  fecha_repetida date;
begin
  select id into ana from auth.users where email = 'ana@ensayo.test';
  if ana is null then
    raise exception 'Falta el paso 2: corre antes supabase/ensayo/paso-2-datos-de-ensayo.sql (y antes de él, el paso 1)';
  end if;

  select pareja_id into pareja_a from miembros where user_id = ana;
  if pareja_a is null then
    raise exception 'Falta el paso 3: corre antes supabase/001-multiples-parejas.sql';
  end if;

  -- ---------- Segunda pareja, por el camino real ----------
  carla := gen_random_uuid();
  dani  := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', carla, 'authenticated', 'authenticated',
     'carla@ensayo.test', '', now(), now(), now()),
    ('00000000-0000-0000-0000-000000000000', dani,  'authenticated', 'authenticated',
     'dani@ensayo.test',  '', now(), now(), now());

  -- Carla crea el espacio
  perform set_config('request.jwt.claims', json_build_object('sub', carla)::text, true);
  execute 'set local role authenticated';
  perform crear_pareja();
  execute 'reset role';

  select pareja_id into pareja_b from miembros where user_id = carla;
  select codigo_invitacion into codigo from parejas where id = pareja_b;

  -- Dani se une con el código
  perform set_config('request.jwt.claims', json_build_object('sub', dani)::text, true);
  execute 'set local role authenticated';
  perform unirse_con_codigo(codigo);
  execute 'reset role';

  select count(*) into n from miembros where pareja_id = pareja_b;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('El alta con código mete a las dos personas en el mismo espacio',
     '2', n::text, case when n = 2 then 'OK' else 'FALLA' end);

  select codigo_invitacion into codigo from parejas where id = pareja_b;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('El código queda inutilizado tras usarse',
     'nulo', coalesce(codigo, 'nulo'), case when codigo is null then 'OK' else 'FALLA' end);

  -- Contenido de la segunda pareja
  insert into actividades (titulo, fecha, categoria, creado_por, pareja_id)
    values ('Cena de Carla y Dani', current_date + 3, 'Citas', 'Carla', pareja_b)
    returning id into plan_b;
  insert into gratitudes (autor, texto, user_id, pareja_id)
    values ('Carla', 'Secreto de Carla', carla, pareja_b);
  insert into fotos (actividad_id, titulo_plan, ruta, subido_por, pareja_id)
    values (plan_b, 'Cena', pareja_b::text || '/' || plan_b::text || '/foto.jpg', 'Carla', pareja_b);

  -- Misma fecha que ya usó la pareja A: antes lo impedía un unique global
  select fecha into fecha_repetida from calendario_intimo where pareja_id = pareja_a limit 1;
  begin
    insert into calendario_intimo (fecha, creado_por, pareja_id)
      values (fecha_repetida, 'Carla', pareja_b);
    hubo_error := false;
  exception when others then
    hubo_error := true;
  end;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Dos parejas pueden marcar la misma fecha en el calendario íntimo',
     'se permite', case when hubo_error then 'lo rechazó' else 'se permite' end,
     case when hubo_error then 'FALLA' else 'OK' end);

  -- Objetos de storage: los de la pareja A con la ruta vieja (sin
  -- prefijo) y el de la B con la nueva. Si la versión de Supabase no
  -- deja insertarlos a mano, las pruebas de fotos se marcan como
  -- omitidas en vez de tumbar todo el bloque.
  begin
    insert into storage.objects (bucket_id, name)
    select 'fotos', ruta from fotos where pareja_id in (pareja_a, pareja_b);
  exception when others then
    storage_sembrado := false;
  end;

  -- ---------- Lo que ve cada quien ----------

  -- ANA (pareja A)
  perform set_config('request.jwt.claims', json_build_object('sub', ana)::text, true);
  execute 'set local role authenticated';
  select count(*) into n from gratitudes;         execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana ve las gratitudes de su pareja', '3', n::text, case when n = 3 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from actividades;        execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana ve sus planes y ninguno ajeno', '2', n::text, case when n = 2 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from miembros;           execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana ve solo a las dos personas de su espacio', '2', n::text, case when n = 2 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from parejas;            execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana ve un solo espacio: el suyo', '1', n::text, case when n = 1 then 'OK' else 'FALLA' end);

  if storage_sembrado then
    execute 'set local role authenticated';
    select count(*) into n from storage.objects where bucket_id = 'fotos';  execute 'reset role';
    insert into resultado (prueba, esperado, obtenido, veredicto) values
      ('Ana alcanza sus 2 fotos viejas y ninguna ajena (puente de rutas)',
       '2', n::text, case when n = 2 then 'OK' else 'FALLA' end);
  else
    insert into resultado (prueba, esperado, obtenido, veredicto) values
      ('Ana alcanza sus 2 fotos viejas y ninguna ajena (puente de rutas)',
       '2', 'no se pudo sembrar storage', 'OMITIDA');
  end if;

  -- CARLA (pareja B): lo mismo, del otro lado
  perform set_config('request.jwt.claims', json_build_object('sub', carla)::text, true);
  execute 'set local role authenticated';
  select count(*) into n from gratitudes;         execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Carla NO ve las gratitudes de Ana', '1', n::text, case when n = 1 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from actividades;        execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Carla NO ve los planes de Ana', '1', n::text, case when n = 1 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from checkins;           execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Carla NO ve los check-ins de Ana', '0', n::text, case when n = 0 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from calendario_intimo;  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Carla NO ve el calendario íntimo de Ana', '1', n::text, case when n = 1 then 'OK' else 'FALLA' end);

  execute 'set local role authenticated';
  select count(*) into n from reuniones;          execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Carla NO ve las reuniones de Ana', '0', n::text, case when n = 0 then 'OK' else 'FALLA' end);

  if storage_sembrado then
    execute 'set local role authenticated';
    select count(*) into n from storage.objects where bucket_id = 'fotos';  execute 'reset role';
    insert into resultado (prueba, esperado, obtenido, veredicto) values
      ('Carla NO alcanza las fotos de Ana', '1', n::text, case when n = 1 then 'OK' else 'FALLA' end);
  else
    insert into resultado (prueba, esperado, obtenido, veredicto) values
      ('Carla NO alcanza las fotos de Ana', '1', 'no se pudo sembrar storage', 'OMITIDA');
  end if;

  -- ---------- Intentos de colarse ----------

  -- Ana escribiendo en el espacio de Carla
  perform set_config('request.jwt.claims', json_build_object('sub', ana)::text, true);
  execute 'set local role authenticated';
  begin
    insert into gratitudes (autor, texto, user_id, pareja_id)
      values ('Ana', 'mensaje colado', ana, pareja_b);
    hubo_error := false;
  exception when others then
    hubo_error := true;
  end;
  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana NO puede escribir en el espacio de Carla',
     'rechazado', case when hubo_error then 'rechazado' else 'LO PERMITIÓ' end,
     case when hubo_error then 'OK' else 'FALLA' end);

  -- Ana cambiándose de espacio a la fuerza
  execute 'set local role authenticated';
  begin
    update miembros set pareja_id = pareja_b where user_id = ana;
    select count(*) into n from miembros where user_id = ana and pareja_id = pareja_b;
    hubo_error := (n = 0);
  exception when others then
    hubo_error := true;
  end;
  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana NO puede mudarse al espacio de Carla',
     'rechazado', case when hubo_error then 'rechazado' else 'LO PERMITIÓ' end,
     case when hubo_error then 'OK' else 'FALLA' end);

  -- Alguien sin espacio no debe ver nada
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid())::text, true);
  execute 'set local role authenticated';
  select count(*) into n from gratitudes;         execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Un usuario recién registrado, sin espacio, no ve nada',
     '0', n::text, case when n = 0 then 'OK' else 'FALLA' end);

  -- Y no debe poder unirse dos veces
  perform set_config('request.jwt.claims', json_build_object('sub', ana)::text, true);
  execute 'set local role authenticated';
  begin
    perform crear_pareja();
    hubo_error := false;
  exception when others then
    hubo_error := true;
  end;
  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Quien ya tiene espacio no puede crear otro',
     'rechazado', case when hubo_error then 'rechazado' else 'LO PERMITIÓ' end,
     case when hubo_error then 'OK' else 'FALLA' end);
end;
$$;

-- ---------- Resultado ----------
select n, veredicto, prueba, esperado, obtenido from resultado order by n;

select case when count(*) = 0 then '✅ TODO EN ORDEN: ninguna prueba falló'
            else '❌ HAY ' || count(*) || ' FALLA(S): revísalas antes de tocar producción'
       end as veredicto_final
  from resultado where veredicto = 'FALLA';

rollback;
