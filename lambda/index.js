// Punto de entrada de la Lambda: crea los clientes reales y se los pasa a la lógica.
//  - DynamoDB: @aws-sdk/client-dynamodb ya viene en el runtime nodejs22.x de Lambda.
//  - Bedrock: SDK oficial de Anthropic para Bedrock (@anthropic-ai/bedrock-sdk),
//    que hay que empaquetar (make lambda).
const { DynamoDBClient, UpdateItemCommand, ScanCommand } = require('@aws-sdk/client-dynamodb');
const { crearManejador } = require('./logica');

const TABLA = process.env.TABLA;
const MODELO = process.env.MODELO_BEDROCK || '';

// Cada entorno de ejecución tiene su propio log stream: "2026/11/10/[$LATEST]3f9c…".
const instancia = (process.env.AWS_LAMBDA_LOG_STREAM_NAME || 'local').slice(-8);

const dynamo = new DynamoDBClient({});

const db = {
  async incrementar(clave) {
    const r = await dynamo.send(new UpdateItemCommand({
      TableName: TABLA,
      Key: { id: { S: clave } },
      UpdateExpression: 'ADD n :uno',
      ExpressionAttributeValues: { ':uno': { N: '1' } },
      ReturnValues: 'UPDATED_NEW',
    }));
    return Number(r.Attributes.n.N);
  },
  async leerTodo() {
    // Tabla diminuta (un elemento por instancia): un Scan basta.
    const todo = {};
    let desde;
    do {
      const r = await dynamo.send(new ScanCommand({ TableName: TABLA, ExclusiveStartKey: desde }));
      for (const it of r.Items) todo[it.id.S] = Number(it.n.N);
      desde = r.LastEvaluatedKey;
    } while (desde);
    return todo;
  },
};

let ia = null;
if (MODELO) {
  const { AnthropicBedrockMantle } = require('@anthropic-ai/bedrock-sdk');
  // La Lambda tiene 15 s: que Bedrock no se coma todo el tiempo.
  const claude = new AnthropicBedrockMantle({ awsRegion: process.env.AWS_REGION, timeout: 8000, maxRetries: 1 });
  ia = {
    async frase(visitas, entorno) {
      const r = await claude.messages.create({
        model: MODELO,
        max_tokens: 2000,
        output_config: { effort: 'low' },
        messages: [{
          role: 'user',
          content: `Escribe una sola frase corta y divertida, en español, para celebrar la visita número ${visitas} ` +
            `a una página de ejemplo (entorno ${entorno}) de una clase de despliegue en la nube. Sólo la frase.`,
        }],
      });
      if (r.stop_reason === 'refusal') return null;
      const texto = r.content.find((b) => b.type === 'text');
      return texto ? texto.text.trim() : null;
    },
  };
}

exports.handler = crearManejador({
  db,
  ia,
  instancia,
  entorno: process.env.ENTORNO || 'local',
  version: process.env.APP_VERSION || 'v1',
});
