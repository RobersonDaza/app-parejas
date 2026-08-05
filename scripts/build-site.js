// ==============================================================
//  Prepara la carpeta "dist" que Netlify publica.
//
//  Copia los archivos del sitio y genera config.js a partir de las
//  variables de entorno configuradas en Netlify. Así la clave nunca
//  pasa por el repositorio.
//
//  Uso local (para probar):
//    SUPABASE_URL=... SUPABASE_ANON_KEY=... node scripts/build-site.js
// ==============================================================
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const DESTINO = path.join(RAIZ, 'dist');
const ARCHIVOS = ['index.html', 'sw.js'];

const { SUPABASE_URL, SUPABASE_ANON_KEY } = process.env;

// Si falta algo, se corta el despliegue. Es a propósito: mejor que
// falle aquí a publicar un sitio que no puede conectarse a Supabase.
const faltantes = [];
if (!SUPABASE_URL) faltantes.push('SUPABASE_URL');
if (!SUPABASE_ANON_KEY) faltantes.push('SUPABASE_ANON_KEY');
if (faltantes.length) {
  console.error('\n✖ Faltan variables de entorno: ' + faltantes.join(', '));
  console.error('  Configúralas en Netlify → Site configuration → Environment variables.');
  console.error('  Los valores salen de Supabase → Project Settings → API.\n');
  process.exit(1);
}
if (SUPABASE_URL.includes('PEGA_AQUI') || SUPABASE_ANON_KEY.includes('PEGA_AQUI')) {
  console.error('\n✖ Las variables todavía tienen los valores de plantilla.\n');
  process.exit(1);
}

fs.rmSync(DESTINO, { recursive: true, force: true });
fs.mkdirSync(DESTINO, { recursive: true });

for (const archivo of ARCHIVOS) {
  fs.copyFileSync(path.join(RAIZ, archivo), path.join(DESTINO, archivo));
}

const contenido = `// Generado automáticamente en cada despliegue. No editar a mano.
window.APP_CONFIG = ${JSON.stringify({ SUPABASE_URL, SUPABASE_ANON_KEY }, null, 2)};
`;
fs.writeFileSync(path.join(DESTINO, 'config.js'), contenido);

console.log('Sitio preparado en dist/:');
for (const archivo of fs.readdirSync(DESTINO)) {
  console.log('  ' + archivo + '  ' + fs.statSync(path.join(DESTINO, archivo)).size + ' bytes');
}
