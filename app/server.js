// Contador de visitas: cada petición incrementa un contador en Redis.
// Cada pod pinta la página de un color distinto para ver qué réplica responde.
// Sin dependencias: el cliente de Redis (redis.js) habla RESP directamente por TCP.
const http = require('http');
const os = require('os');
const { redis, cerrar } = require('./redis');

const PORT = Number(process.env.PORT || 8080);
const ENTORNO = process.env.ENTORNO || 'local';
const VERSION = process.env.APP_VERSION || 'v1';
const POD = os.hostname();

// ---------- HTTP ----------
function color(texto) {
  let h = 0;
  for (const c of texto) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${h % 360}, 65%, 45%)`;
}

async function visita() {
  const visitas = await redis('INCR', 'visitas');
  await redis('HINCRBY', 'pods', POD, 1);
  return { visitas, pod: POD, entorno: ENTORNO, version: VERSION };
}

function responder(res, codigo, tipo, cuerpo) {
  // Connection: close → cada recarga abre conexión nueva y puede caer en otro pod.
  res.writeHead(codigo, { 'Content-Type': tipo, Connection: 'close' });
  res.end(cuerpo);
}

const json = (res, codigo, obj) => responder(res, codigo, 'application/json', JSON.stringify(obj) + '\n');

const servidor = http.createServer(async (req, res) => {
  const ruta = new URL(req.url, 'http://x').pathname;
  try {
    if (ruta === '/healthz') return responder(res, 200, 'text/plain', 'ok\n');
    if (ruta === '/readyz') {
      await redis('PING');
      return responder(res, 200, 'text/plain', 'ok\n');
    }
    if (ruta === '/api') return json(res, 200, await visita());
    if (ruta === '/stats') {
      const plano = (await redis('HGETALL', 'pods')) || [];
      const pods = {};
      for (let i = 0; i < plano.length; i += 2) pods[plano[i]] = Number(plano[i + 1]);
      return json(res, 200, { visitas: Number(await redis('GET', 'visitas')) || 0, pods });
    }
    if (ruta === '/') {
      const v = await visita();
      return responder(res, 200, 'text/html; charset=utf-8', `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Contador ${v.entorno}</title>
<style>body{margin:0;height:100vh;display:grid;place-items:center;background:${color(POD)};
color:#fff;font-family:system-ui,sans-serif;text-align:center}h1{font-size:6rem;margin:0}</style></head>
<body><div><h1>${v.visitas}</h1><p>visitas</p>
<p>pod <b>${v.pod}</b> · entorno <b>${v.entorno}</b> · versión <b>${v.version}</b></p></div></body></html>`);
    }
    return responder(res, 404, 'text/plain', 'no encontrado\n');
  } catch (err) {
    console.error(`${ruta}: ${err.message}`);
    return json(res, 503, { error: err.message, pod: POD });
  }
});

servidor.listen(PORT, () => console.log(`contador ${VERSION} (${ENTORNO}) escuchando en :${PORT} — pod ${POD}`));

// Cierre ordenado: Kubernetes manda SIGTERM antes de matar el pod.
process.on('SIGTERM', () => {
  console.log('SIGTERM: cerrando…');
  servidor.close(() => {
    cerrar();
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 5000).unref();
});
