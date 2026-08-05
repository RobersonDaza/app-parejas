-- ============================================================
--  MIGRACIÓN 004 — Quitar el puente de las fotos viejas
--
--  NO SE CORRE EN EL CORTE. Va después, y solo cuando
--  scripts/mover-fotos.js haya terminado sin pendientes.
--
--  Mientras las fotos estaban en su ruta antigua, las políticas de
--  storage las autorizaban consultando la tabla "fotos". Eso era un
--  puente temporal: funciona, pero deja la puerta de que una fila
--  mal escrita autorice un archivo que no le corresponde.
--
--  Ya movidas todas, la única regla que queda es la simple y
--  robusta: la ruta tiene que empezar por el id de tu pareja.
--
--  ANTES DE CORRERLO, comprueba que no queda ninguna atrás:
--
--    select count(*) as fotos_sin_mover
--      from fotos
--     where ruta not like pareja_id::text || '/%';
--
--  Tiene que dar 0. Si da más, esas fotos dejarían de verse.
-- ============================================================

begin;

do $$
declare pendientes int;
begin
  select count(*) into pendientes
    from fotos
   where ruta not like pareja_id::text || '/%';

  if pendientes > 0 then
    raise exception 'Hay % foto(s) sin mover: corre antes scripts/mover-fotos.js --aplicar', pendientes;
  end if;
end;
$$;

drop policy if exists "fotos_ver" on storage.objects;
create policy "fotos_ver" on storage.objects for select to authenticated
  using (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = mi_pareja()::text
  );

drop policy if exists "fotos_borrar" on storage.objects;
create policy "fotos_borrar" on storage.objects for delete to authenticated
  using (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = mi_pareja()::text
  );

commit;
