// ==============================================================
//  Mueve las fotos viejas a su ruta nueva.
//
//      antes:   <actividad_id>/archivo.jpg
//      después: <pareja_id>/<actividad_id>/archivo.jpg
//
//  Se corre UNA vez, después de la migración 001 y del despliegue
//  de la app nueva. Cuando termine sin pendientes, se pueden quitar
//  de las políticas de storage las cláusulas `or exists (...)` que
//  hoy sirven de puente para las rutas viejas.
//
//  POR QUÉ HACE FALTA LA CLAVE service_role
//  Mover un archivo en Storage es un UPDATE sobre storage.objects, y
//  las políticas no se lo permiten a un usuario normal. Esta clave se
//  las salta. Trátala como una contraseña maestra: da acceso total a
//  la base. No la pegues en ningún archivo ni la subas a git.
//
//  USO
//    1. Ensáyalo primero (no mueve nada, solo enseña qué haría):
//
//         SUPABASE_URL=https://xxxx.supabase.co \
//         SUPABASE_SERVICE_KEY=... \
//         node scripts/mover-fotos.js
//
//    2. Cuando el listado te cuadre, repítelo con --aplicar
//
//  Es seguro repetirlo: las fotos que ya estén en su sitio se saltan.
// ==============================================================

const URL_BASE = process.env.SUPABASE_URL;
const CLAVE = process.env.SUPABASE_SERVICE_KEY;
const APLICAR = process.argv.includes('--aplicar');
const BUCKET = 'fotos';

if (!URL_BASE || !CLAVE) {
  const faltan = [!URL_BASE && 'SUPABASE_URL', !CLAVE && 'SUPABASE_SERVICE_KEY'].filter(Boolean);
  console.error('\nFalta' + (faltan.length > 1 ? 'n' : '') + ': ' + faltan.join(' y '));
  console.error('\nOjo: hay que exportarlas, no basta con asignarlas. Una asignación');
  console.error('suelta crea una variable del shell que los programas no ven:');
  console.error('\n  export SUPABASE_URL="https://TU-PROYECTO.supabase.co"');
  console.error('  export SUPABASE_SERVICE_KEY="..."');
  console.error('  node scripts/mover-fotos.js');
  console.error('\nLa service_role está en Supabase → Project Settings → API.\n');
  process.exit(1);
}

const cabeceras = {
  apikey: CLAVE,
  Authorization: 'Bearer ' + CLAVE,
  'Content-Type': 'application/json'
};

async function pedir(ruta, opciones = {}) {
  const r = await fetch(URL_BASE + ruta, { ...opciones, headers: cabeceras });
  const texto = await r.text();
  if (!r.ok) throw new Error(`${r.status} ${ruta} → ${texto.slice(0, 200)}`);
  return texto ? JSON.parse(texto) : null;
}

(async () => {
  const fotos = await pedir('/rest/v1/fotos?select=id,ruta,pareja_id&order=created_at');
  console.log(`\n${fotos.length} foto(s) registradas.`);

  const pendientes = fotos.filter((f) => f.pareja_id && !f.ruta.startsWith(f.pareja_id + '/'));
  const yaEstan = fotos.length - pendientes.length;
  if (yaEstan) console.log(`${yaEstan} ya están en su ruta nueva: se saltan.`);

  if (!pendientes.length) {
    console.log('\nNo hay nada que mover. Ya puedes quitar el puente de las políticas.\n');
    return;
  }

  if (!APLICAR) {
    console.log(`\n--- ENSAYO: esto es lo que haría (nada se ha movido) ---`);
    pendientes.forEach((f) => console.log(`  ${f.ruta}\n    → ${f.pareja_id}/${f.ruta}`));
    console.log(`\nSon ${pendientes.length}. Si te cuadra, repite con --aplicar\n`);
    return;
  }

  let movidas = 0;
  const fallos = [];
  for (const f of pendientes) {
    const destino = `${f.pareja_id}/${f.ruta}`;
    let archivoMovido = false;
    try {
      // 1. Mover el archivo
      await pedir('/storage/v1/object/move', {
        method: 'POST',
        body: JSON.stringify({ bucketId: BUCKET, sourceKey: f.ruta, destinationKey: destino })
      });
      archivoMovido = true;

      // 2. Y solo si eso salió bien, apuntar la fila a la ruta nueva
      await pedir(`/rest/v1/fotos?id=eq.${f.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ ruta: destino })
      });
      movidas++;
      console.log(`  ✓ ${f.ruta}`);
    } catch (e) {
      // Si el archivo ya se movió pero la fila no se actualizó, la foto
      // quedaría rota: la base apuntando a un sitio vacío. Se devuelve el
      // archivo a su ruta original para dejarlo como estaba.
      if (archivoMovido) {
        try {
          await pedir('/storage/v1/object/move', {
            method: 'POST',
            body: JSON.stringify({ bucketId: BUCKET, sourceKey: destino, destinationKey: f.ruta })
          });
          console.log(`  ↩ ${f.ruta} → se devolvió a su sitio`);
        } catch (e2) {
          console.log(`  ‼ ${f.ruta} → QUEDÓ DESCUADRADA: el archivo está en ${destino} y la fila apunta a ${f.ruta}`);
          console.log(`     Arréglalo a mano antes de seguir: ${e2.message}`);
        }
      }
      fallos.push({ ruta: f.ruta, motivo: e.message });
      console.log(`  ✗ ${f.ruta} → ${e.message}`);
    }
  }

  console.log(`\nMovidas: ${movidas} de ${pendientes.length}.`);
  if (fallos.length) {
    console.log(`\n${fallos.length} quedaron pendientes. NO quites todavía el puente de las`);
    console.log('políticas: esas fotos dejarían de verse. Revisa los motivos de arriba.\n');
    process.exitCode = 1;
  } else {
    console.log('\nTodo movido. Ahora sí puedes quitar de las políticas fotos_ver y');
    console.log('fotos_borrar las cláusulas `or exists (...)`.\n');
  }
})().catch((e) => {
  console.error('\nSe detuvo: ' + e.message + '\n');
  process.exit(1);
});
