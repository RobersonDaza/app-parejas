# Guion del corte

Cómo pasar la app real de una pareja a muchas, sin perder nada.

> ## Estado: Corte A hecho el 5 de agosto de 2026
>
> Las migraciones 001, 002 y 003 están aplicadas en producción, la app nueva
> desplegada y las 40 fotos movidas a su ruta por pareja. Los seis conteos
> cuadraron exactamente con los de antes: 5 planes, 26 gratitudes, 8 check-ins,
> 13 fechas, 40 fotos, 0 reuniones.
>
> **Lo que salió mal y hubo que corregir sobre la marcha:** el reparto de
> colores salió invertido. La migración leía el mapa de nombres como `jsonb`,
> que reordena las claves por longitud, así que el terracota se lo llevó quien
> tenía el correo más corto. Y ambos miembros nacían con el mismo `created_at`,
> con lo que el orden del título quedaba al azar. Se arregló en producción con
> un `update` y en el archivo con `json` y `clock_timestamp()`.
>
> **Pendientes de este corte:** ejecutar `004-quitar-puente-fotos.sql` unos
> días después, y más adelante `drop table config`.
>
> **Falta el Corte B**, que espera a la revisión legal y al proveedor de correo.

## Lo primero: son dos cortes, no uno

Meterlo todo en una sola tarde es innecesario y arriesgado. Se separa en dos
momentos que no dependen entre sí:

| | Qué pasa | Qué hace falta |
|---|---|---|
| **Corte A** | La app pasa a la arquitectura nueva. Siguen siendo ustedes dos y nadie lo nota, salvo que ahora cada quien edita su nombre | Nada más que lo que ya está listo |
| **Corte B** | Se abre el registro y entran otras parejas | Revisión legal y proveedor de correo |

**Haz el A ahora y el B cuando quieras.** Vivir unas semanas sobre la
arquitectura nueva antes de que entren desconocidos es la mejor prueba que
existe: si algo se rompe, se rompe con ustedes, que saben perdonar.

---

# CORTE A — a la arquitectura nueva

Dura unos 20 minutos, de los cuales la app está caída unos 3.

## Antes de empezar

- [ ] Avísale a Luisa que la app estará caída un rato. Si está a mitad de
      escribir algo, que lo guarde.
- [ ] Hazlo cuando ninguno la esté usando.
- [ ] Ten esta página abierta y los archivos a mano.

## Paso 0 — El respaldo (no te lo saltes)

**Supabase → Database → Backups.** Descarga el más reciente o genera uno.

Y por si acaso, exporta también a CSV desde **Table Editor** las siete tablas:
`actividades`, `gratitudes`, `checkins`, `config`, `reuniones`, `fotos`,
`calendario_intimo`.

> ⚠️ **Esto es lo único que te permite volver atrás.** Una vez aplicada la
> migración 001, la app vieja ya no funciona contra la base nueva: sus
> escrituras exigen un `pareja_id` que no sabe enviar. Deshacerlo significa
> restaurar el respaldo, no "correr el script al revés".

## Paso 1 — Anota cómo está todo ahora

En **SQL Editor**, y guarda el resultado:

```sql
select 'actividades' as tabla, count(*) from actividades
union all select 'gratitudes',        count(*) from gratitudes
union all select 'checkins',          count(*) from checkins
union all select 'reuniones',         count(*) from reuniones
union all select 'fotos',             count(*) from fotos
union all select 'calendario_intimo', count(*) from calendario_intimo
order by 1;
```

Al terminar el corte tienen que dar exactamente lo mismo.

## Paso 2 — Las tres migraciones

Una por una, en **SQL Editor → New query**, esperando a que cada una termine:

1. `supabase/001-multiples-parejas.sql`
2. `supabase/002-borrado-de-cuenta.sql`
3. `supabase/003-limites-y-consentimiento.sql`

Las tres van en una transacción: si alguna falla, no deja nada a medias y te
puedes detener sin haber roto nada.

**No corras `004`.** Ese va mucho después.

## Paso 3 — Verifica antes de seguir

```sql
select (select count(*) from parejas)  as parejas,     -- 1
       (select count(*) from miembros) as miembros;    -- 2

select m.nombre, m.color, u.email
  from miembros m join auth.users u on u.id = m.user_id
 order by m.created_at;
```

Tiene que salir **una** pareja, **dos** miembros, con sus nombres correctos y
Luisa en `terracota` (para que los colores del frasco no cambien).

Vuelve a correr el conteo del paso 1: los números deben ser idénticos.

> Si algo no cuadra, **detente aquí**. Todavía no has desplegado la app nueva,
> así que restaurar el respaldo te devuelve al punto de partida.

## Paso 4 — Publicar la app nueva

```bash
git checkout main
git merge --no-ff fase-2 -m "Fase 2: la app pasa de una pareja a muchas"
git push origin main
```

El `--no-ff` no es un capricho: obliga a crear un commit de fusión. Sin él la
fusión sería directa, no habría un único punto que deshacer, y el comando de
vuelta atrás del paso siguiente no funcionaría.

Netlify despliega solo en unos 10 o 15 segundos. A partir de aquí la app en
vivo es la nueva.

## Paso 5 — Compruébalo con las manos

Entra al sitio y verifica:

- [ ] La pantalla de login se ve normal.
- [ ] Entras con tu correo y contraseña de siempre.
- [ ] La cabecera dice **Luisa & Roberson**.
- [ ] El frasco de la gratitud tiene todos los mensajes, con Luisa en
      terracota y tú en oliva.
- [ ] Los planes, las reuniones y el calendario están completos.
- [ ] **Las fotos se ven** (siguen en su ruta vieja, autorizadas por el puente).
- [ ] El contador de días desde su fecha de inicio es correcto.
- [ ] En el perfil aparece tu nombre y puedes cambiarlo.

> Si algo falla aquí, lo más rápido es volver la app atrás sin tocar la base:
> ```bash
> git revert -m 1 HEAD && git push origin main
> ```
> Eso republica la app vieja, que **tampoco funcionará** contra la base
> migrada, pero te da tiempo a decidir con calma si restauras el respaldo.

## Paso 6 — Mover las fotos

Con el sitio ya funcionando. Primero en seco, que no mueve nada:

```bash
SUPABASE_URL=https://TU-PROYECTO.supabase.co SUPABASE_SERVICE_KEY=LA_CLAVE node scripts/mover-fotos.js
```

La `service_role` está en **Project Settings → API**. Es la llave maestra: no
la guardes en ningún archivo.

Revisa el listado. Si te cuadra, repite con `--aplicar` al final.

Vuelve a abrir la galería y confirma que las fotos siguen viéndose.

## Paso 7 — Cerrar el puente (unos días después)

Cuando lleves un tiempo tranquilo y las fotos se vean bien, corre
`supabase/004-quitar-puente-fotos.sql`. Comprueba solo que no quede ninguna
foto sin mover y, si queda alguna, se niega a seguir.

Después de esto, la única regla que autoriza una foto es que su ruta empiece
por el id de la pareja. Más simple y más difícil de equivocar.

## Paso 8 — Limpiar (opcional, más adelante)

La tabla `config` ya no la usa nadie: la fecha de inicio vive en `parejas` y
los nombres en `miembros`. Cuando lleves un par de semanas sin sustos:

```sql
drop table config;
```

---

# CORTE B — abrir el registro

Solo cuando estén los tres pendientes. **El último paso es el último a
propósito**: hasta que no lo des, nadie ajeno puede crear una cuenta, y eso es
hoy tu red de seguridad.

## Antes

- [ ] El borrador legal revisado por un abogado y sin `[corchetes]`.
- [ ] Actualizar `VERSION_LEGAL` en `index.html` a la fecha de publicación,
      para que las aceptaciones queden asociadas al texto correcto.
- [ ] Proveedor de correo configurado en **Authentication → Emails → SMTP**.
      Sin esto los correos de confirmación fallan en silencio y la gente se
      queda fuera sin entender por qué. Con correo y contraseña como única
      vía de entrada, este punto es crítico: no hay alternativa si falla.

## Prueba con una pareja de verdad

Antes de abrir del todo, pídele a una pareja conocida que se registre y use la
app una semana. Es la última oportunidad de encontrar lo que ni el ensayo ni
ustedes vieron.

## Abrir

**Authentication → Sign In / Providers → Allow new users to sign up**, activar.

Y a partir de ahí, revisa de vez en cuando cuánto ocupa cada pareja:

```sql
select (storage.foldername(name))[1] as pareja,
       pg_size_pretty(sum((metadata->>'size')::bigint)) as ocupa,
       count(*) as archivos
  from storage.objects
 where bucket_id = 'fotos'
 group by 1
 order by sum((metadata->>'size')::bigint) desc;
```

Con 1 GB en el plan gratuito y 200 MB por pareja, el aviso te llega solo
cuando alguna se acerque a su tope, pero el total del proyecto es cosa tuya.
