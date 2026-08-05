// ==============================================================
//  Servidor estático para probar la app en el navegador.
//
//      node scripts/servidor-local.js
//      → http://localhost:8080
//
//  Hace falta servirla por http (y no abrir el archivo directo)
//  para que funcione el inicio de sesión con Google, que necesita
//  volver a una dirección real después del redirect.
// ==============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const PUERTO = Number(process.env.PUERTO || 8080);
const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'text/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8'
};

http.createServer((req, res) => {
  const pedido = decodeURIComponent(req.url.split('?')[0]);
  const archivo = path.join(RAIZ, pedido === '/' ? 'index.html' : pedido);

  // Nadie debe poder salirse de la carpeta del proyecto
  if (!archivo.startsWith(RAIZ)) { res.writeHead(403); res.end('prohibido'); return; }

  fs.readFile(archivo, (err, datos) => {
    if (err) { res.writeHead(404); res.end('no encontrado: ' + pedido); return; }
    res.writeHead(200, {
      'Content-Type': TIPOS[path.extname(archivo)] || 'application/octet-stream',
      'Cache-Control': 'no-store'
    });
    res.end(datos);
  });
}).listen(PUERTO, () => {
  console.log('App servida en http://localhost:' + PUERTO);
  console.log('Ctrl+C para detener.');
});
