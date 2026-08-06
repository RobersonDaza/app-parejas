-- ============================================================
--  MIGRACIÓN 003 — Tope de almacenamiento y consentimiento
--
--  Se aplica DESPUÉS de la 002.
--
--  DOS COSAS QUE HACEN FALTA PARA ABRIR EL REGISTRO
--
--  1. Un tope de fotos por pareja. Sin él, el plan gratuito (1 GB)
--     se agota con unas pocas parejas y se cae para todas.
--
--  2. Constancia del consentimiento para el calendario íntimo.
--     Bajo la Ley 1581 de 2012 los datos sobre vida sexual son
--     sensibles: la autorización tiene que ser explícita, aparte de
--     la general, y hay que poder demostrar cuándo se dio.
-- ============================================================

begin;

do $$
begin
  if to_regproc('public.mi_pareja') is null then
    raise exception 'Falta la migración 001: corre antes supabase/001-multiples-parejas.sql';
  end if;
end;
$$;

-- ------------------------------------------------------------
--  1. Cuánto ocupa cada pareja
--
--  El tamaño de cada archivo lo guarda Storage en metadata->>'size'.
--  SECURITY DEFINER porque storage.objects no es consultable así por
--  un usuario normal; la función solo mira la carpeta de quien
--  pregunta, nunca la de otra pareja.
-- ------------------------------------------------------------
create or replace function uso_fotos()
returns bigint
language sql
stable
security definer
set search_path = public, storage
as $$
  select coalesce(sum((metadata->>'size')::bigint), 0)
    from storage.objects
   where bucket_id = 'fotos'
     and (storage.foldername(name))[1] = mi_pareja()::text;
$$;

revoke all on function uso_fotos() from public;
grant execute on function uso_fotos() to authenticated;

-- El tope, en un solo sitio para poder cambiarlo sin tocar políticas
create or replace function tope_fotos()
returns bigint
language sql
immutable
as $$ select (200 * 1024 * 1024)::bigint; $$;   -- 200 MB por pareja

-- ------------------------------------------------------------
--  2. El tope se aplica en la base, no solo en la pantalla
--
--  La app avisa antes de subir, pero eso solo protege del descuido.
--  Esta política es la que de verdad impide pasarse.
--
--  Se mira el uso ANTES de añadir el archivo nuevo, así que el
--  último puede sobrepasar el tope por su propio tamaño. Es de
--  propósito: preferimos dejar terminar una subida en curso a
--  cortarla a la mitad.
-- ------------------------------------------------------------
drop policy if exists "fotos_subir" on storage.objects;
create policy "fotos_subir" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = mi_pareja()::text
    and uso_fotos() < tope_fotos()
  );

-- ------------------------------------------------------------
--  3. Constancia del consentimiento
--
--  Se guarda cuándo se aceptó y qué versión del documento, porque
--  "aceptó en algún momento" no sirve como prueba si el texto ha
--  cambiado desde entonces.
--
--  La aceptación general de términos vive en los metadatos de la
--  cuenta (se recoge al registrarse, antes de que exista fila en
--  "miembros"). Aquí va solo la del calendario íntimo, que es
--  aparte y se puede revocar sin cerrar la cuenta.
-- ------------------------------------------------------------
alter table miembros add column if not exists acepto_intimo_en      timestamptz;
alter table miembros add column if not exists acepto_intimo_version text;

commit;

-- ------------------------------------------------------------
--  Para vigilar el gasto de vez en cuando:
--
--    select (storage.foldername(name))[1] as pareja,
--           pg_size_pretty(sum((metadata->>'size')::bigint)) as ocupa,
--           count(*) as archivos
--      from storage.objects
--     where bucket_id = 'fotos'
--     group by 1
--     order by sum((metadata->>'size')::bigint) desc;
--
--  Y para subir el tope el día que haga falta, basta con cambiar el
--  número de tope_fotos(): las políticas lo leen de ahí.
-- ------------------------------------------------------------
