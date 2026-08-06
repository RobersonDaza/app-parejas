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
declare
  pendientes int;
  descolocados int;
  huerfanos int;
begin
  -- 1. Lo que dice la tabla: ninguna fila puede apuntar a la ruta vieja
  select count(*) into pendientes
    from fotos
   where ruta not like pareja_id::text || '/%';

  if pendientes > 0 then
    raise exception 'Hay % foto(s) sin mover: corre antes scripts/mover-fotos.js --aplicar', pendientes;
  end if;

  -- 2. Lo que hay de verdad en el bucket. Comprobar solo la tabla sería mirar
  --    el índice y no el estante: si un archivo quedó en otro sitio del que
  --    dice su fila, dejaría de verse en cuanto quitemos el puente.
  select count(*) into descolocados
    from storage.objects o
   where o.bucket_id = 'fotos'
     and (storage.foldername(o.name))[1] not in (select id::text from parejas);

  if descolocados > 0 then
    raise exception 'Hay % archivo(s) en el bucket fuera de la carpeta de su pareja. Revísalos antes de quitar el puente.', descolocados;
  end if;

  -- 3. Archivos sin ninguna fila que los reclame. No impiden seguir, pero
  --    conviene saber que están ahí ocupando espacio.
  select count(*) into huerfanos
    from storage.objects o
   where o.bucket_id = 'fotos'
     and not exists (select 1 from fotos f where f.ruta = o.name);

  if huerfanos > 0 then
    raise notice 'Aviso: % archivo(s) en el bucket sin fila en la tabla fotos. No estorban, pero ocupan.', huerfanos;
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
