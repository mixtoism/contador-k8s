// node --test lambda/   — pruebas de la Lambda con DynamoDB y Bedrock simulados.
const test = require('node:test');
const assert = require('node:assert/strict');
const { crearManejador } = require('./logica');

function dbFalsa() {
  const datos = {};
  return {
    datos,
    async incrementar(k) { return (datos[k] = (datos[k] || 0) + 1); },
    async leerTodo() { return { ...datos }; },
  };
}

const base = { instancia: 'abc12345', entorno: 'dev', version: 'v1' };

test('/api cuenta visitas y por instancia', async () => {
  const db = dbFalsa();
  const h = crearManejador({ ...base, db, ia: null });
  await h({ rawPath: '/api' });
  const r = await h({ rawPath: '/api' });
  assert.equal(r.statusCode, 200);
  const j = JSON.parse(r.body);
  assert.equal(j.visitas, 2);
  assert.equal(j.frase, null);
  assert.equal(db.datos['instancia#abc12345'], 2);
});

test('/stats agrupa por instancia', async () => {
  const db = dbFalsa();
  await crearManejador({ ...base, db, ia: null })({ rawPath: '/api' });
  await crearManejador({ ...base, instancia: 'otra0000', db, ia: null })({ rawPath: '/api' });
  const j = JSON.parse((await crearManejador({ ...base, db, ia: null })({ rawPath: '/stats' })).body);
  assert.deepEqual(j, { visitas: 2, instancias: { abc12345: 1, otra0000: 1 } });
});

test('la frase de Bedrock aparece en la página, escapada', async () => {
  const ia = { async frase(n) { return `¡Visita <${n}>!`; } };
  const r = await crearManejador({ ...base, db: dbFalsa(), ia })({ rawPath: '/' });
  assert.match(r.headers['content-type'], /text\/html/);
  assert.match(r.body, /¡Visita &lt;1&gt;!/);
});

test('si Bedrock falla, la página sale igual', async () => {
  const ia = { async frase() { throw new Error('ThrottlingException'); } };
  const r = await crearManejador({ ...base, db: dbFalsa(), ia })({ rawPath: '/api' });
  assert.equal(r.statusCode, 200);
  assert.equal(JSON.parse(r.body).frase, null);
});

test('si DynamoDB falla, 503', async () => {
  const db = { async incrementar() { throw new Error('ResourceNotFoundException'); } };
  const r = await crearManejador({ ...base, db, ia: null })({ rawPath: '/api' });
  assert.equal(r.statusCode, 503);
});

test('ruta desconocida, 404', async () => {
  const r = await crearManejador({ ...base, db: dbFalsa(), ia: null })({ rawPath: '/nada' });
  assert.equal(r.statusCode, 404);
});
