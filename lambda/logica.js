// Lógica del contador en Lambda, sin dependencias: recibe los servicios ya creados
// (DynamoDB y Bedrock) para poder probarla con dobles en lugar de AWS.
//
// En Kubernetes cada pod tenía un color; aquí lo tiene cada "entorno de ejecución"
// de Lambda (cada copia caliente de la función), que se identifica por su log stream.

function color(texto) {
  let h = 0;
  for (const c of texto) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${h % 360}, 65%, 45%)`;
}

const escapar = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function respuesta(statusCode, tipo, cuerpo) {
  return { statusCode, headers: { 'content-type': tipo }, body: cuerpo };
}
const json = (statusCode, obj) => respuesta(statusCode, 'application/json', JSON.stringify(obj) + '\n');

/**
 * @param {object} deps
 * @param {{ incrementar(clave: string): Promise<number>, leerTodo(): Promise<Record<string, number>> }} deps.db
 * @param {{ frase(visitas: number, entorno: string): Promise<string|null> } | null} deps.ia  null = sin Bedrock
 * @param {string} deps.instancia  identificador del entorno de ejecución
 * @param {string} deps.entorno
 * @param {string} deps.version
 */
function crearManejador({ db, ia, instancia, entorno, version }) {
  async function visita() {
    const visitas = await db.incrementar('visitas');
    await db.incrementar(`instancia#${instancia}`);
    return { visitas, instancia, entorno, version };
  }

  // Bedrock es un adorno: si falla o tarda, la página sale igual, sin frase.
  async function frase(visitas) {
    if (!ia) return null;
    try {
      return await ia.frase(visitas, entorno);
    } catch (err) {
      console.error(`bedrock: ${err.message}`);
      return null;
    }
  }

  return async function handler(evento) {
    const ruta = evento.rawPath || '/';
    try {
      if (ruta === '/healthz') return respuesta(200, 'text/plain', 'ok\n');
      if (ruta === '/api') {
        const v = await visita();
        return json(200, { ...v, frase: await frase(v.visitas) });
      }
      if (ruta === '/stats') {
        const todo = await db.leerTodo();
        const instancias = {};
        for (const [k, n] of Object.entries(todo)) {
          if (k.startsWith('instancia#')) instancias[k.slice('instancia#'.length)] = n;
        }
        return json(200, { visitas: todo.visitas || 0, instancias });
      }
      if (ruta === '/') {
        const v = await visita();
        const f = await frase(v.visitas);
        return respuesta(200, 'text/html; charset=utf-8', `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Contador ${escapar(v.entorno)}</title>
<style>body{margin:0;height:100vh;display:grid;place-items:center;background:${color(instancia)};
color:#fff;font-family:system-ui,sans-serif;text-align:center}h1{font-size:6rem;margin:0}
blockquote{font-style:italic;max-width:40rem;margin:1.5rem auto}</style></head>
<body><div><h1>${v.visitas}</h1><p>visitas</p>
${f ? `<blockquote>${escapar(f)}</blockquote>` : ''}
<p>Lambda <b>${escapar(v.instancia)}</b> · entorno <b>${escapar(v.entorno)}</b> · versión <b>${escapar(v.version)}</b></p></div></body></html>`);
      }
      return respuesta(404, 'text/plain', 'no encontrado\n');
    } catch (err) {
      console.error(`${ruta}: ${err.message}`);
      return json(503, { error: err.message, instancia });
    }
  };
}

module.exports = { crearManejador, color };
