// Cliente Redis mínimo, sin dependencias: habla RESP (el protocolo de Redis) por TCP,
// o por TLS si REDIS_TLS=1 (ElastiCache con contraseña exige cifrado en tránsito).
// Lo usan el servidor (contenedor y Elastic Beanstalk) y la Lambda.
const net = require('net');
const tls = require('tls');

const REDIS_HOST = process.env.REDIS_HOST || '127.0.0.1';
// Si llega algo como "tcp://10.43.0.5:6379" (service links de Kubernetes), se ignora.
const REDIS_PORT = Number(process.env.REDIS_PORT) || 6379;
const REDIS_PASSWORD = process.env.REDIS_PASSWORD || '';
const REDIS_TLS = process.env.REDIS_TLS === '1';

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
  const sock = REDIS_TLS
    ? tls.connect({ host: REDIS_HOST, port: REDIS_PORT, servername: net.isIP(REDIS_HOST) ? undefined : REDIS_HOST })
    : net.createConnection(REDIS_PORT, REDIS_HOST);
  const c = { sock, pendientes: [], buffer: Buffer.alloc(0) };
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

function cerrar() {
  if (conexion) conexion.sock.end();
}

module.exports = { redis, cerrar };
