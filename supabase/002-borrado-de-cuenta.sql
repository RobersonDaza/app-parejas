-- ============================================================
--  MIGRACIÓN 002 — Borrar la propia cuenta
--
--  Se aplica DESPUÉS de la 001.
--
--  QUÉ PASA CUANDO ALGUIEN SE BORRA
--  Se va la persona, no el espacio. Lo que escribió se queda, para
--  que la otra no pierda los recuerdos compartidos sin haberlo
--  pedido, pero deja de tener dueño: aparece como de alguien que ya
--  no está, y quien se queda puede eliminarlo si quiere.
--
--  Si era la última persona del espacio, ahí sí se borra todo: las
--  claves foráneas van en cascada desde "parejas".
--
--  Si queda alguien, se le devuelve un código de invitación nuevo,
--  para que pueda empezar de nuevo con otra persona.
-- ============================================================

begin;

do $$
begin
  if to_regclass('public.miembros') is null then
    raise exception 'Falta la migración 001: corre antes supabase/001-multiples-parejas.sql';
  end if;
end;
$$;

-- ------------------------------------------------------------
--  Quien se queda puede limpiar lo que dejó quien se fue
--
--  Sin esto, los mensajes de la persona borrada serían imborrables
--  para siempre: la política de borrado exige ser su dueño, y ya no
--  hay dueño.
-- ------------------------------------------------------------
drop policy if exists "borrar_gratitudes" on gratitudes;
create policy "borrar_gratitudes" on gratitudes for delete to authenticated
  using (pareja_id = mi_pareja() and (user_id = auth.uid() or user_id is null));

drop policy if exists "borrar_checkins" on checkins;
create policy "borrar_checkins" on checkins for delete to authenticated
  using (pareja_id = mi_pareja() and (user_id = auth.uid() or user_id is null));

-- ------------------------------------------------------------
--  La función que hace el trabajo
--
--  SECURITY DEFINER porque tiene que tocar auth.users, que un
--  usuario normal no puede. Solo puede borrarse a sí misma: no
--  recibe ningún parámetro, se guía por auth.uid().
-- ------------------------------------------------------------
create or replace function borrar_mi_cuenta()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  yo         uuid := auth.uid();
  mi_espacio uuid;
  quedan     int;
begin
  if yo is null then
    raise exception 'Debes iniciar sesión';
  end if;

  select pareja_id into mi_espacio from miembros where user_id = yo;

  if mi_espacio is not null then
    -- Lo escrito se queda, pero sin dueño
    update gratitudes set user_id = null where user_id = yo and pareja_id = mi_espacio;
    update checkins   set user_id = null where user_id = yo and pareja_id = mi_espacio;

    delete from miembros where user_id = yo;

    select count(*) into quedan from miembros where pareja_id = mi_espacio;

    if quedan = 0 then
      -- Era la última persona: el espacio entero se va con ella.
      -- Las claves foráneas borran en cascada planes, gratitud,
      -- check-ins, reuniones, fotos y calendario.
      delete from parejas where id = mi_espacio;
    else
      -- Queda alguien: se le da un código nuevo para invitar a otra persona
      update parejas
         set codigo_invitacion = generar_codigo(),
             codigo_expira     = now() + interval '7 days'
       where id = mi_espacio;
    end if;
  end if;

  delete from auth.users where id = yo;
end;
$$;

revoke all on function borrar_mi_cuenta() from public;
grant execute on function borrar_mi_cuenta() to authenticated;

commit;

-- ------------------------------------------------------------
--  OJO CON LOS ARCHIVOS
--
--  Borrar la fila de "fotos" no borra el archivo del bucket: SQL no
--  alcanza a Storage. La app borra los archivos ANTES de llamar a
--  esta función cuando se va la última persona del espacio. Si esa
--  parte falla, quedan archivos huérfanos ocupando espacio, sin
--  ninguna fila que los relacione con nadie.
--
--  Para encontrarlos algún día:
--    select name from storage.objects
--     where bucket_id = 'fotos'
--       and not exists (select 1 from fotos f where f.ruta = name);
-- ------------------------------------------------------------
