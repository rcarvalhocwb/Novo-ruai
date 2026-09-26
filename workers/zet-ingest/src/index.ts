/**
 * Borda do webhook da Zet (W-01). NÃO toca o banco: confere o token, guarda o corpo cru no R2,
 * enfileira e responde. Com o banco ou a AWS fora, os webhooks continuam sendo aceitos e guardados.
 * Ver docs/analise-iluminadarua2025/04-INTEGRACAO-ZET.md e docs/plano-execucao/02.
 *
 * Regra de ouro: nunca responder 200 sem o corpo gravado no R2.
 */
export interface Env {
  ZET_URL_TOKEN: string; // segredo (wrangler secret put ZET_URL_TOKEN)
  SOURCE: 'zet' | 'zet_hml';
  RAW: R2Bucket;
  ZET_QUEUE: Queue<IngestMessage>;
}

export interface IngestMessage {
  source: 'zet' | 'zet_hml';
  key: string; // objeto no R2
  sha256: string; // hex do corpo
  received_at: string; // ISO UTC
  remote_ip: string | null; // aqui, na borda, é o IP real da Zet
  user_agent: string | null;
}

export const MAX_BODY = 64 * 1024;
const PATH = /^\/zet\/v1\/([A-Za-z0-9_-]{32,128})$/;

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');

/** Compara em tempo constante: compara os SHA-256 (mesmo tamanho) dos dois valores. */
export async function tokenMatches(given: string, expected: string): Promise<boolean> {
  if (!expected || expected.length < 32) return false; // recusa operar com token fraco
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(given)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i]! ^ y[i]!;
  return diff === 0;
}

const json = (status: number, body?: unknown) =>
  new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
  });

export async function handle(req: Request, env: Env, now: () => Date = () => new Date()): Promise<Response> {
  const url = new URL(req.url);
  const m = PATH.exec(url.pathname);
  // token errado, ausente ou caminho desconhecido: 404, sem gravar nada
  if (!m || !(await tokenMatches(m[1]!, env.ZET_URL_TOKEN))) return json(404);
  if (req.method !== 'POST') return json(405);

  const declared = Number(req.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY) return json(413);
  const raw = await req.arrayBuffer();
  if (raw.byteLength > MAX_BODY) return json(413);
  if (raw.byteLength === 0) return json(400);

  const sha = hex(await crypto.subtle.digest('SHA-256', raw));
  const receivedAt = now().toISOString();
  const key = `zet/${receivedAt.slice(0, 10)}/${sha}.json`;
  const msg: IngestMessage = {
    source: env.SOURCE,
    key,
    sha256: sha,
    received_at: receivedAt,
    remote_ip: req.headers.get('cf-connecting-ip'),
    user_agent: req.headers.get('user-agent'),
  };

  try {
    // cópia imutável do corpo cru; o mesmo corpo gera a mesma chave (idempotente)
    await env.RAW.put(key, raw, {
      httpMetadata: { contentType: 'application/json' },
      customMetadata: { received_at: receivedAt, remote_ip: msg.remote_ip ?? '', user_agent: msg.user_agent ?? '' },
    });
  } catch {
    return json(503); // sem cópia no R2 não há 200: a Zet reenvia
  }
  try {
    await env.ZET_QUEUE.send(msg);
  } catch {
    // o corpo já está no R2; a reconciliação diária R2 × inbox recupera. Pedimos reenvio mesmo assim.
    return json(503);
  }
  return json(200, { received: true });
}

export default {
  fetch: (req: Request, env: Env) => handle(req, env),
} satisfies ExportedHandler<Env>;
