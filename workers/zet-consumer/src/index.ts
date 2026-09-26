/**
 * Consumidor da fila zet-webhooks (W-02). Lê o corpo cru no R2 e faz 1 INSERT idempotente no inbox,
 * via integ.receive_webhook, com o papel técnico ingest_writer (Hyperdrive). Nunca descarta mensagem:
 * banco fora → retry com espera crescente; depois das tentativas máximas, fila morta + alerta.
 */
import postgres from 'postgres';
import type { IngestMessage } from '../../zet-ingest/src/index';

export interface Env {
  RAW: R2Bucket;
  HYPERDRIVE: Hyperdrive;
}

export type ReceiveFn = (m: IngestMessage, bodyB64: string) => Promise<void>;

function toBase64(buf: ArrayBuffer): string {
  let s = '';
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

/** Espera antes da próxima tentativa: 30 s, 60 s, 120 s ... até 1 h. */
export const retryDelaySeconds = (attempts: number) => Math.min(3600, 30 * 2 ** Math.max(0, attempts - 1));

export async function processBatch(batch: MessageBatch<IngestMessage>, env: Env, receive: ReceiveFn): Promise<void> {
  for (const msg of batch.messages) {
    try {
      const obj = await env.RAW.get(msg.body.key);
      if (!obj) throw new Error(`objeto ${msg.body.key} não está no R2`);
      await receive(msg.body, toBase64(await obj.arrayBuffer()));
      msg.ack();
    } catch (err) {
      console.error(JSON.stringify({ correlation_id: msg.body.sha256, error: String(err), attempts: msg.attempts }));
      msg.retry({ delaySeconds: retryDelaySeconds(msg.attempts) });
    }
  }
}

export default {
  async queue(batch: MessageBatch<IngestMessage>, env: Env) {
    const sql = postgres(env.HYPERDRIVE.connectionString, { max: 2, prepare: false, fetch_types: false });
    const receive: ReceiveFn = async (m, b64) => {
      await sql`select integ.receive_webhook(${m.source}, ${b64}, ${m.sha256},
                  ${sql.json({ 'user-agent': m.user_agent ?? '' })}, ${m.remote_ip ?? ''}, ${m.received_at}::timestamptz)`;
    };
    try {
      await processBatch(batch, env, receive);
    } finally {
      await sql.end({ timeout: 5 });
    }
  },
} satisfies ExportedHandler<Env, IngestMessage>;
