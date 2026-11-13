// El servidor del sandbox: la nube de mentira por HTTP, y la página de prueba.
//
// Contesta `/rest/v1/rpc/<función>` como lo haría Supabase, pero corriendo el SQL
// de la migración en un Postgres de prueba en memoria. Y sirve la prueba compilada
// (`tool/link_delegado_prueba.dart` → `build/link_delegado_prueba`).
//
// Escucha solo en esta PC (127.0.0.1). Cada puerto hace de un aparato distinto,
// porque cada dirección tiene su propia memoria del navegador:
//   8800  lo que hace de programa   (/?panel)
//   8801, 8802, 8803  tres celulares (/?delegado&clave=…)
import http from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { abrir } from './db.mjs';

const nube = await abrir();
const WEB = fileURLToPath(new URL('../../build/link_delegado_prueba/', import.meta.url));
const PUERTOS = [8800, 8801, 8802, 8803];
const TIPOS = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2',
};

const responder = (res, codigo, cuerpo, tipo = 'application/json; charset=utf-8') => {
  res.writeHead(codigo, { 'content-type': tipo, 'cache-control': 'no-store' });
  res.end(typeof cuerpo === 'string' || Buffer.isBuffer(cuerpo) ? cuerpo : JSON.stringify(cuerpo));
};
const leerJson = (req) => new Promise((ok, mal) => {
  let t = '';
  req.on('data', (d) => { t += d; if (t.length > 500_000) req.destroy(); });
  req.on('end', () => { try { ok(t ? JSON.parse(t) : {}); } catch (e) { mal(e); } });
  req.on('error', mal);
});

// Lo que hace de programa (no es parte del SQL de la nube): la grilla.
const delSandbox = {
  sandbox_grilla: (a) => nube.grilla(a.p_evento),
  sandbox_guardar: async (a) => ({ ok: true, guardados: await nube.guardarEnLaGrilla(a.p_evento, a.p_datos) }),
  sandbox_reiniciar: async () => { await nube.reiniciar(); return { ok: true }; },
};

const atender = async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    const rpc = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
    if (rpc && req.method === 'POST') {
      // "Con usuario" es quien manda la clave `jefe`; cualquier otro es anónimo.
      const rol = req.headers.authorization === 'Bearer jefe' ? 'jefe' : 'anon';
      const args = await leerJson(req);
      try {
        if (delSandbox[rpc[1]]) {
          if (rol !== 'jefe') return responder(res, 403, { message: 'permission denied' });
          return responder(res, 200, await delSandbox[rpc[1]](args));
        }
        return responder(res, 200, await nube.rpc(rol, rpc[1], args));
      } catch (e) {
        const sinPermiso = /permission denied|con usuario/.test(e.message);
        return responder(res, sinPermiso ? 403 : 400, { message: e.message, code: sinPermiso ? '42501' : 'P0001' });
      }
    }
    if (req.method === 'GET') {
      const pedido = normalize(decodeURIComponent(url.pathname)).replace(/^([\\/])+/, '');
      const archivo = join(WEB, pedido);
      if (archivo.startsWith(WEB) && pedido && existsSync(archivo) && statSync(archivo).isFile()) {
        return responder(res, 200, readFileSync(archivo), TIPOS[extname(archivo)] ?? 'application/octet-stream');
      }
      const inicio = join(WEB, 'index.html');
      if (!extname(pedido) && existsSync(inicio)) return responder(res, 200, readFileSync(inicio), TIPOS['.html']);
      return responder(res, 404, { message: existsSync(inicio) ? 'No existe' : 'Falta compilar la prueba: ver tool/link_delegado_prueba.dart' });
    }
    return responder(res, 404, { message: 'No existe' });
  } catch (e) {
    return responder(res, 500, { message: e.message });
  }
};

for (const puerto of PUERTOS) http.createServer(atender).listen(puerto, '127.0.0.1');
console.log('Sandbox del delegado. Programa: http://localhost:8800/?panel · celulares: 8801, 8802 y 8803');
