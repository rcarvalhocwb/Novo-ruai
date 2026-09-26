/**
 * Ponta a ponta: borda (zet-ingest) → R2 falso → consumidor → Postgres de verdade, com o papel ingest_writer.
 * Roda só com RUAI_DB_URL apontando para um banco migrado (tools/db-test.sh). No CI, o job "banco" define.
 */
import postgres from 'postgres';
import { describe, expect, it } from 'vitest';
import { type Env as IngestEnv, type IngestMessage, handle } from '../../zet-ingest/src/index';
import { type Env, processBatch } from './index';

const DB = process.env.RUAI_DB_URL;

describe.skipIf(!DB)('ponta a ponta com Postgres', () => {
  it('webhook aceito na borda chega ao inbox uma única vez, pelo papel ingest_writer', async () => {
    const objects = new Map<string, ArrayBuffer>();
    const sent: IngestMessage[] = [];
    const TOKEN = 'e2e'.padEnd(43, 'x');
    const ingestEnv = {
      ZET_URL_TOKEN: TOKEN,
      SOURCE: 'zet_hml',
      RAW: { put: async (k: string, v: ArrayBuffer) => void objects.set(k, v) },
      ZET_QUEUE: { send: async (m: IngestMessage) => void sent.push(m) },
    } as unknown as IngestEnv;

    const body = JSON.stringify({ action: 'CP', e2e: Date.now(), data: { order: { uuid: crypto.randomUUID() } } });
    for (let i = 0; i < 2; i++) {
      const res = await handle(
        new Request(`https://ingest/zet/v1/${TOKEN}`, { method: 'POST', body, headers: { 'cf-connecting-ip': '203.0.113.10' } }),
        ingestEnv,
      );
      expect(res.status).toBe(200);
    }

    const sql = postgres(DB!, { max: 1, prepare: false });
    await sql`set role ingest_writer`;
    const consumerEnv = {
      RAW: { get: async (k: string) => (objects.has(k) ? { arrayBuffer: async () => objects.get(k)! } : null) },
    } as unknown as Env;
    const acks: number[] = [];
    const batch = {
      messages: sent.map((m, i) => ({ body: m, attempts: 1, ack: () => acks.push(i), retry: () => {} })),
    } as unknown as MessageBatch<IngestMessage>;
    await processBatch(batch, consumerEnv, async (m, b64) => {
      await sql`select integ.receive_webhook(${m.source}, ${b64}, ${m.sha256},
                ${sql.json({ 'user-agent': m.user_agent ?? '' })}, ${m.remote_ip ?? ''}, ${m.received_at}::timestamptz)`;
    });
    expect(acks).toEqual([0, 1]);

    // o papel técnico não lê o inbox; a conferência é feita como dono
    await expect(sql`select count(*) from integ.webhook_inbox`).rejects.toThrow(/permission denied/);
    await sql`reset role`;
    const [row] = await sql`select count(*)::int as n, max(host(remote_ip)) as ip
                              from integ.webhook_inbox where body_sha256 = decode(${sent[0]!.sha256}, 'hex')`;
    expect(row).toEqual({ n: 1, ip: '203.0.113.10' });
    await sql.end();
  });
});
