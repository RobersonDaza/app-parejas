-- ============================================================
--  ENSAYO · PASO 5 DE 5
--  Antes de este van: pasos 1 y 2, la migración 001 y la 002.
-- ------------------------------------------------------------
--  ¿El borrado de cuenta hace lo que promete?
--
--  SOLO PARA EL PROYECTO DESECHABLE.
--
--  Lo que se comprueba, en este orden:
--    · Que borrarse de verdad elimine la cuenta de auth.users.
--      Esto es lo primero que hay que verificar: la función necesita
--      un permiso sobre el esquema auth que no está garantizado en
--      todas las versiones de Supabase. Si esta prueba falla, hay
--      que resolverlo con una Edge Function antes de producción.
--    · Que el contenido de quien se va se quede, pero sin dueño.
--    · Que quien se queda pueda borrar ese contenido huérfano.
--    · Que quien se queda reciba un código nuevo para invitar.
--    · Que al irse la última persona desaparezca todo el espacio.
--
--  Termina en ROLLBACK: no deja rastro.
-- ============================================================

begin;

create temp table resultado (
  n serial, prueba text, esperado text, obtenido text, veredicto text
) on commit drop;

do $$
declare
  ana uuid; beto uuid; espacio uuid;
  n int; codigo_antes text; codigo_despues text; hubo_error boolean;
begin
  select id into ana  from auth.users where email = 'ana@ensayo.test';
  select id into beto from auth.users where email = 'beto@ensayo.test';
  if ana is null or beto is null then
    raise exception 'Faltan los datos de ensayo: corre antes el paso 2';
  end if;
  if to_regfunc('public.borrar_mi_cuenta') is null then
    raise exception 'Falta la migración 002: corre antes supabase/002-borrado-de-cuenta.sql';
  end if;

  select pareja_id into espacio from miembros where user_id = ana;
  select codigo_invitacion into codigo_antes from parejas where id = espacio;

  -- ---------- Beto se borra ----------
  perform set_config('request.jwt.claims', json_build_object('sub', beto)::text, true);
  execute 'set local role authenticated';
  begin
    perform borrar_mi_cuenta();
    hubo_error := false;
  exception when others then
    hubo_error := true;
  end;
  execute 'reset role';

  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('La función corre sin errores de permisos',
     'sin error', case when hubo_error then 'FALLÓ' else 'sin error' end,
     case when hubo_error then 'FALLA' else 'OK' end);

  select count(*) into n from auth.users where id = beto;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('La cuenta desaparece de auth.users (permiso sobre el esquema auth)',
     '0', n::text, case when n = 0 then 'OK' else 'FALLA' end);

  select count(*) into n from miembros where user_id = beto;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Beto ya no es miembro del espacio', '0', n::text,
     case when n = 0 then 'OK' else 'FALLA' end);

  select count(*) into n from gratitudes where pareja_id = espacio;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Sus mensajes NO se borran: siguen ahí para Ana', '3', n::text,
     case when n = 3 then 'OK' else 'FALLA' end);

  select count(*) into n from gratitudes where pareja_id = espacio and user_id is null;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Su mensaje queda sin dueño', '1', n::text,
     case when n = 1 then 'OK' else 'FALLA' end);

  select codigo_invitacion into codigo_despues from parejas where id = espacio;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana recibe un código nuevo para invitar a alguien',
     'un código de 6', coalesce(codigo_despues, 'ninguno'),
     case when codigo_despues is not null
            and length(codigo_despues) = 6
            and codigo_despues is distinct from codigo_antes
          then 'OK' else 'FALLA' end);

  -- Ana debe poder limpiar lo que quedó huérfano
  perform set_config('request.jwt.claims', json_build_object('sub', ana)::text, true);
  execute 'set local role authenticated';
  begin
    delete from gratitudes where pareja_id = espacio and user_id is null;
    select count(*) into n from gratitudes where pareja_id = espacio and user_id is null;
    hubo_error := (n > 0);
  exception when others then
    hubo_error := true;
  end;
  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Ana puede borrar el mensaje huérfano si quiere',
     'lo borra', case when hubo_error then 'NO PUDO' else 'lo borra' end,
     case when hubo_error then 'FALLA' else 'OK' end);

  -- ---------- Ahora se borra Ana: era la última ----------
  perform set_config('request.jwt.claims', json_build_object('sub', ana)::text, true);
  execute 'set local role authenticated';
  perform borrar_mi_cuenta();
  execute 'reset role';

  select count(*) into n from parejas where id = espacio;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Al irse la última persona, el espacio desaparece', '0', n::text,
     case when n = 0 then 'OK' else 'FALLA' end);

  select count(*) into n from actividades where pareja_id = espacio;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Y con él, sus planes (borrado en cascada)', '0', n::text,
     case when n = 0 then 'OK' else 'FALLA' end);

  select count(*) into n from calendario_intimo where pareja_id = espacio;
  insert into resultado (prueba, esperado, obtenido, veredicto) values
    ('Y su calendario íntimo', '0', n::text,
     case when n = 0 then 'OK' else 'FALLA' end);
end;
$$;

select n, veredicto, prueba, esperado, obtenido from resultado order by n;

select case when count(*) = 0 then '✅ EL BORRADO HACE LO QUE PROMETE'
            else '❌ HAY ' || count(*) || ' FALLA(S)'
       end as veredicto_final
  from resultado where veredicto = 'FALLA';

rollback;
