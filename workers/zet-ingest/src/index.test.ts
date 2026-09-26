import { describe, expect, it } from 'vitest';
import { type Env, type IngestMessage, MAX_BODY, handle, tokenMatches } from './index';

const TOKEN = 'a'.repeat(43);
const URL_OK = `https://ingest.ruailuminada.com/zet/v1/${TOKEN}`;

function fakeEnv(opts: { r2Fails?: boolean; queueFails?: boolean } = {}) {
  const objects = new Map<string, ArrayBuffer>();
  const sent: IngestMessage[] = [];
  const env = {
    ZET_URL_TOKEN: TOKEN,
    SOURCE: 'zet',
    RAW: {
      put: async (key: string, value: ArrayBuffer) => {
        if (opts.r2Fails) throw new Error('R2 fora');
        objects.set(key, value);
        return {};
      },
    },
    ZET_QUEUE: {
      send: async (m: IngestMessage) => {
        if (opts.queueFails) throw new Error('fila fora');
        sent.push(m);
      },
    },
  } as unknown as Env;
  return { env, objects, sent };
}

const post = (url: string, body: string, headers: Record<string, string> = {}) =>
  new Request(url, { method: 'POST', body, headers: { 'cf-connecting-ip': '203.0.113.10', 'user-agent': 'axios/0.27.2', ...headers } });

const CP = JSON.stringify({ action: 'CP', data: { order: { uuid: 'x', totalValue: 33, totalTax: 3 } } });
const fixedNow = () => new Date('2026-10-16T15:00:00.000Z');

describe('zet-ingest', () => {
  it('corpo válido: grava no R2, enfileira e responde 200', async () => {
    const { env, objects, sent } = fakeEnv();
    const res = await handle(post(URL_OK, CP), env, fixedNow);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ received: true });
    expect(objects.size).toBe(1);
    expect(sent).toHaveLength(1);
    const msg = sent[0]!;
    expect(msg.key).toMatch(/^zet\/2026-10-16\/[0-9a-f]{64}\.json$/);
    expect(new TextDecoder().decode(objects.get(msg.key)!)).toBe(CP);
    expect(msg.remote_ip).toBe('203.0.113.10'); // IP real da Zet, gravado na borda (S-22)
    expect(msg.source).toBe('zet');
  });

  it('o sha256 da mensagem é o do corpo cru', async () => {
    const { env, sent } = fakeEnv();
    await handle(post(URL_OK, CP), env, fixedNow);
    const expected = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(CP)))]
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    expect(sent[0]!.sha256).toBe(expected);
  });

  it('token errado ou ausente: 404 e nada gravado', async () => {
    for (const url of [
      `https://ingest.ruailuminada.com/zet/v1/${'b'.repeat(43)}`,
      'https://ingest.ruailuminada.com/zet/v1/',
      'https://ingest.ruailuminada.com/',
      `https://ingest.ruailuminada.com/zet/v1/${TOKEN}/extra`,
    ]) {
      const { env, objects, sent } = fakeEnv();
      const res = await handle(post(url, CP), env);
      expect(res.status).toBe(404);
      expect(objects.size).toBe(0);
      expect(sent).toHaveLength(0);
    }
  });

  it('método diferente de POST: 405 (só depois de o token conferir)', async () => {
    const { env } = fakeEnv();
    expect((await handle(new Request(URL_OK, { method: 'GET' }), env)).status).toBe(405);
  });

  it('corpo acima de 64 KB: 413, pelo cabeçalho ou pelo tamanho real', async () => {
    const big = 'x'.repeat(MAX_BODY + 1);
    const a = fakeEnv();
    expect((await handle(post(URL_OK, big), a.env)).status).toBe(413);
    expect(a.objects.size).toBe(0);
    const b = fakeEnv();
    expect((await handle(post(URL_OK, 'x', { 'content-length': String(MAX_BODY + 1) }), b.env)).status).toBe(413);
  });

  it('corpo vazio: 400', async () => {
    const { env } = fakeEnv();
    expect((await handle(post(URL_OK, ''), env)).status).toBe(400);
  });

  it('R2 fora: 503 e nada na fila (nunca 200 sem o corpo guardado)', async () => {
    const { env, sent } = fakeEnv({ r2Fails: true });
    expect((await handle(post(URL_OK, CP), env)).status).toBe(503);
    expect(sent).toHaveLength(0);
  });

  it('fila fora: 503, mas o corpo já está no R2 para a reconciliação', async () => {
    const { env, objects } = fakeEnv({ queueFails: true });
    expect((await handle(post(URL_OK, CP), env)).status).toBe(503);
    expect(objects.size).toBe(1);
  });

  it('mesmo corpo 2×: mesma chave no R2 (idempotente)', async () => {
    const { env, objects, sent } = fakeEnv();
    await handle(post(URL_OK, CP), env, fixedNow);
    await handle(post(URL_OK, CP), env, fixedNow);
    expect(objects.size).toBe(1);
    expect(sent[0]!.key).toBe(sent[1]!.key);
  });

  it('tokenMatches recusa token esperado fraco (menos de 32 caracteres)', async () => {
    expect(await tokenMatches('curto', 'curto')).toBe(false);
    expect(await tokenMatches(TOKEN, TOKEN)).toBe(true);
    expect(await tokenMatches(TOKEN + 'x', TOKEN)).toBe(false);
  });
});
