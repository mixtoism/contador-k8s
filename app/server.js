// Contador de visitas: cada petición incrementa un contador en Redis.
// Cada pod pinta la página de un color distinto para ver qué réplica responde.
// Sin dependencias: habla RESP (el protocolo de Redis) directamente por TCP.
const http = require('http');
const net = require('net');
const os = require('os');

const PORT = Number(process.env.PORT || 8080);
const REDIS_HOST = process.env.REDIS_HOST || '127.0.0.1';
// Si llega algo como "tcp://10.43.0.5:6379" (service links de Kubernetes), se ignora.
const REDIS_PORT = Number(process.env.REDIS_PORT) || 6379;
const REDIS_PASSWORD = process.env.REDIS_PASSWORD || '';
const ENTORNO = process.env.ENTORNO || 'local';
const VERSION = process.env.APP_VERSION || 'v1';
const POD = os.hostname();

// ---------- Cliente Redis mínimo ----------
function parsear(buf, i) {
  const fin = buf.indexOf('\r\n', i);
  if (fin < 0) return null;
  const tipo = String.fromCharCode(buf[i]);
  const linea = buf.toString('utf8', i + 1, fin);
  let p = fin + 2;
  switch (tipo) {
    case '+': return { valor: linea, fin: p };
    case '-': return { valor: new Error(linea), fin: p };
    case ':': return { valor: Number(linea), fin: p };
    case '$': {
      const n = Number(linea);
      if (n < 0) return { valor: null, fin: p };
      if (buf.length < p + n + 2) return null;
      return { valor: buf.toString('utf8', p, p + n), fin: p + n + 2 };
    }
    case '*': {
      const n = Number(linea);
      if (n < 0) return { valor: null, fin: p };
      const lista = [];
      for (let k = 0; k < n; k++) {
        const r = parsear(buf, p);
        if (!r) return null;
        lista.push(r.valor);
        p = r.fin;
      }
      return { valor: lista, fin: p };
    }
    default: throw new Error(`Respuesta RESP desconocida: ${tipo}`);
  }
}

// Una conexión cada vez; si se cae, la siguiente petición abre otra.
// Cada conexión lleva su propia cola y buffer para que una vieja no pise a la nueva.
let conexion = null;

function conectar() {
  const c = { sock: net.createConnection(REDIS_PORT, REDIS_HOST), pendientes: [], buffer: Buffer.alloc(0) };
  // Timeout sólo para conectar; una vez conectada, la conexión puede estar inactiva.
  c.sock.setTimeout(3000, () => c.sock.destroy(new Error('timeout conectando a Redis')));
  c.sock.on('connect', () => c.sock.setTimeout(0));
  c.sock.on('data', (datos) => {
    c.buffer = Buffer.concat([c.buffer, datos]);
    let r;
    while (c.pendientes.length && (r = parsear(c.buffer, 0))) {
      c.buffer = c.buffer.subarray(r.fin);
      const { resolve, reject } = c.pendientes.shift();
      r.valor instanceof Error ? reject(r.valor) : resolve(r.valor);
    }
  });
  const cerrar = (err) => {
    if (conexion === c) conexion = null;
    for (const p of c.pendientes) p.reject(err || new Error('conexión con Redis cerrada'));
    c.pendientes = [];
  };
  c.sock.on('error', cerrar);
  c.sock.on('close', () => cerrar());
  conexion = c;
  if (REDIS_PASSWORD) enviar(c, ['AUTH', REDIS_PASSWORD]).catch(() => {});
  return c;
}

function enviar(c, args) {
  return new Promise((resolve, reject) => {
    c.pendientes.push({ resolve, reject });
    c.sock.write(`*${args.length}\r\n` + args.map((a) => `$${Buffer.byteLength(String(a))}\r\n${a}\r\n`).join(''));
  });
}

function redis(...args) {
  return enviar(conexion || conectar(), args);
}

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
    if (conexion) conexion.sock.end();
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 5000).unref();
});
