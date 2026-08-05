# Ensayo de la migración en un proyecto desechable

El objetivo es que la migración `001` y la app de la fase 2 se encuentren por
primera vez **lejos de los datos reales**. Al final sabremos si las políticas
nuevas aíslan de verdad a una pareja de otra.

Todo esto se hace en un proyecto de Supabase **nuevo y de usar y tirar**. El
plan gratuito permite dos proyectos, así que no cuesta nada. Cuando termines,
lo borras.

> Ninguno de estos scripts debe correrse jamás en el proyecto real: crean
> usuarios de mentira escribiendo directamente en `auth.users`.

## 1. Crear el proyecto desechable

En supabase.com → **New project**. Nombre: `app-parejas-ensayo`. Cualquier
región sirve. Anota la **Project URL** y la clave **anon public**.

## 2. Dejarlo igual que producción

En **SQL Editor → New query**, pega y ejecuta, en este orden:

| # | Archivo | Qué hace |
|---|---|---|
| 1 | [`../000-esquema-actual.sql`](../000-esquema-actual.sql) | Crea las tablas y políticas tal como están hoy en tu proyecto real |
| 2 | [`010-datos-de-ensayo.sql`](010-datos-de-ensayo.sql) | Siembra dos personas y contenido de mentira |

Después del segundo verás un resumen con cuántas filas quedaron en cada tabla.
Anótalo: la migración no debe perder ninguna.

## 3. Migrar

| # | Archivo | Qué hace |
|---|---|---|
| 3 | [`../001-multiples-parejas.sql`](../001-multiples-parejas.sql) | La migración de verdad, la misma que irá a producción |

Si algo falla, no queda nada a medias: va en una transacción.

## 4. Comprobar el aislamiento

| # | Archivo | Qué hace |
|---|---|---|
| 4 | [`020-verificar-aislamiento.sql`](020-verificar-aislamiento.sql) | Crea una segunda pareja e intenta espiar a la primera |

Devuelve una tabla con una fila por comprobación y, al final, un veredicto.
**Solo se sigue adelante si dice `✅ TODO EN ORDEN`.** Si alguna prueba dice
`FALLA`, hay un agujero en las políticas y hay que arreglarlo antes de tocar
producción.

Este script termina en `rollback`: no deja rastro.

Lo que comprueba, una por una:

- El alta con código mete a las dos personas en el mismo espacio.
- El código deja de servir en cuanto se usa.
- Cada quien ve su propio contenido completo.
- Ninguno ve gratitudes, planes, check-ins, reuniones, calendario ni fotos
  de la otra pareja.
- Nadie puede escribir en el espacio ajeno.
- Nadie puede mudarse al espacio ajeno.
- Quien acaba de registrarse, sin espacio todavía, no ve absolutamente nada.
- Quien ya tiene espacio no puede crear otro.
- Dos parejas pueden marcar la misma fecha en el calendario íntimo.

## 5. Probar la app con las manos

Los scripts prueban la base de datos. Falta comprobar que la app funciona
contra ella.

```bash
git checkout fase-2
```

Edita `config.js` y pon la URL y la clave **del proyecto desechable** (no las
del real). Luego:

```bash
node scripts/servidor-local.js
```

Abre `http://localhost:8080` y recorre el camino completo:

1. **Crear cuenta** con un correo cualquiera.
2. **Crear nuestro espacio** → apunta el código que aparece.
3. Ponle un nombre y entra. Agrega un plan, un mensaje de gratitud, una foto.
4. Abre una **ventana de incógnito**, crea una segunda cuenta y **únete con el
   código**. Deben verse los datos del paso 3, y el título con los dos nombres.
5. Abre una **tercera** cuenta y crea *otro* espacio. No debe ver nada de los
   anteriores. Esta es la prueba que importa.

## 6. Limpiar

Borra el proyecto desechable y devuelve tu `config.js` a los valores reales.
Ojo: `config.js` está en `.gitignore`, así que este cambio no se sube, pero sí
afecta a la app que abras en tu computador.
