// ==============================================================
//  Conversor de Markdown a HTML, mínimo y a propósito.
//
//  Solo entiende lo que usa legal/privacidad-y-terminos.md:
//  títulos, párrafos, negrita, código, enlaces, citas, listas,
//  tablas y separadores. No pretende ser completo.
//
//  Existe para que el texto legal viva en un solo archivo y la
//  página publicada se genere de ahí, sin copiarlo a mano.
// ==============================================================

const escapar = (t) => t.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

// Negrita, código y enlaces dentro de una línea ya escapada
function enLinea(t) {
  return escapar(t)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

const celdas = (linea) => linea.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
const esSeparadorTabla = (l) => /^\|[\s:|-]+\|$/.test(l.trim());

function convertir(md) {
  // Se normalizan los finales de línea antes de nada. En Windows git puede
  // dejar los archivos con CRLF, y en una expresión regular el punto no casa
  // con \r: los títulos dejarían de reconocerse y el bucle de abajo no
  // avanzaría nunca.
  const lineas = md.replace(/\r\n?/g, '\n').split('\n');
  const salida = [];
  let i = 0;

  while (i < lineas.length) {
    const anterior = i;
    const l = lineas[i];

    if (!l.trim()) { i++; continue; }

    // Separador
    if (/^---+$/.test(l.trim())) { salida.push('<hr />'); i++; continue; }

    // Títulos
    const titulo = l.match(/^(#{1,4})\s+(.*)$/);
    if (titulo) {
      const n = titulo[1].length;
      salida.push(`<h${n}>${enLinea(titulo[2])}</h${n}>`);
      i++; continue;
    }

    // Tabla
    if (l.trim().startsWith('|') && esSeparadorTabla(lineas[i + 1] || '')) {
      const encabezado = celdas(l).map((c) => `<th>${enLinea(c)}</th>`).join('');
      i += 2;
      const filas = [];
      while (i < lineas.length && lineas[i].trim().startsWith('|')) {
        filas.push('<tr>' + celdas(lineas[i]).map((c) => `<td>${enLinea(c)}</td>`).join('') + '</tr>');
        i++;
      }
      salida.push(`<table><thead><tr>${encabezado}</tr></thead><tbody>${filas.join('')}</tbody></table>`);
      continue;
    }

    // Cita (puede ocupar varias líneas seguidas)
    if (l.trim().startsWith('>')) {
      const trozos = [];
      while (i < lineas.length && lineas[i].trim().startsWith('>')) {
        trozos.push(lineas[i].trim().replace(/^>\s?/, ''));
        i++;
      }
      salida.push(`<blockquote>${enLinea(trozos.join(' ')).replace(/\s{2,}/g, ' ')}</blockquote>`);
      continue;
    }

    // Lista (incluidas las casillas "- [ ]")
    if (/^\s*-\s+/.test(l)) {
      const puntos = [];
      while (i < lineas.length && /^\s*-\s+/.test(lineas[i])) {
        let texto = lineas[i].replace(/^\s*-\s+/, '');
        const casilla = texto.match(/^\[( |x)\]\s+(.*)$/);
        puntos.push(casilla
          ? `<li class="casilla">${casilla[1] === 'x' ? '☑' : '☐'} ${enLinea(casilla[2])}</li>`
          : `<li>${enLinea(texto)}</li>`);
        i++;
      }
      salida.push(`<ul>${puntos.join('')}</ul>`);
      continue;
    }

    // Párrafo: se junta hasta la línea en blanco
    const parrafo = [];
    while (i < lineas.length && lineas[i].trim()
           && !/^(#{1,4}\s|>|\s*-\s|---+$|\|)/.test(lineas[i])) {
      parrafo.push(lineas[i].trim());
      i++;
    }
    if (parrafo.length) salida.push(`<p>${enLinea(parrafo.join(' '))}</p>`);

    // Red de seguridad: si una línea no la consume ninguna rama, el bucle se
    // quedaría girando en el sitio. Mejor un error claro que un build colgado.
    if (i === anterior) {
      throw new Error(
        `El conversor no supo qué hacer con la línea ${i + 1}: ${JSON.stringify(lineas[i].slice(0, 60))}`
      );
    }
  }

  return salida.join('\n');
}

// Página completa, con el mismo aire que la app
function pagina(md, titulo) {
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>${escapar(titulo)}</title>
<style>
  :root { color-scheme: light dark; }
  body { margin:0 auto; max-width:44rem; padding:2rem 1.25rem 5rem;
         font-family:Nunito,system-ui,sans-serif; line-height:1.65;
         color:#26201A; background:#FAF6EF; }
  @media (prefers-color-scheme: dark) { body { color:#EDE3D4; background:#26201A; } }
  h1,h2,h3 { color:#C2603C; line-height:1.25; margin:2rem 0 .5rem; }
  h1 { font-size:1.9rem; margin-top:0; }
  h2 { font-size:1.4rem; } h3 { font-size:1.1rem; }
  a { color:#7A8450; }
  code { background:rgba(128,128,128,.18); padding:.1em .35em; border-radius:.3em; font-size:.9em; }
  blockquote { margin:1.25rem 0; padding:.85rem 1rem; border-left:4px solid #C2603C;
               background:rgba(194,96,60,.09); border-radius:.5rem; }
  table { width:100%; border-collapse:collapse; margin:1rem 0; font-size:.92rem; display:block; overflow-x:auto; }
  th,td { border:1px solid rgba(128,128,128,.35); padding:.5rem .6rem; text-align:left; }
  hr { border:none; border-top:1px solid rgba(128,128,128,.35); margin:2.5rem 0; }
  ul { padding-left:1.2rem; } li { margin:.3rem 0; }
  li.casilla { list-style:none; margin-left:-1.2rem; }
  .volver { display:inline-block; margin-bottom:1.5rem; font-weight:bold; text-decoration:none; }
</style>
</head>
<body>
<a class="volver" href="index.html">← Volver a la app</a>
${convertir(md)}
</body>
</html>
`;
}

module.exports = { convertir, pagina };
