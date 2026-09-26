import { describe, expect, it, vi } from 'vitest';
import type { IngestMessage } from '../../zet-ingest/src/index';
import { type Env, processBatch, retryDelaySeconds } from './index';

const body = '{"action":"CP"}';

function message(key: string, attempts = 1) {
  return {
    body: { source: 'zet', key, sha256: 'ab'.repeat(32), received_at: '2026-10-16T15:00:00.000Z', remote_ip: null, user_agent: null } as IngestMessage,
    attempts,
    ack: vi.fn(),
    retry: vi.fn(),
  };
}

const env = {
  RAW: {
    get: async (key: string) =>
      key === 'existe' ? { arrayBuffer: async () => new TextEncoder().encode(body).buffer } : null,
  },
} as unknown as Env;

const batchOf = (...msgs: ReturnType<typeof message>[]) => ({ messages: msgs }) as unknown as MessageBatch<IngestMessage>;

describe('zet-consumer', () => {
  it('banco ok: grava no inbox com o corpo do R2 e confirma a mensagem', async () => {
    const m = message('existe');
    const receive = vi.fn(async () => {});
    await processBatch(batchOf(m), env, receive);
    expect(receive).toHaveBeenCalledWith(m.body, btoa(body));
    expect(m.ack).toHaveBeenCalled();
    expect(m.retry).not.toHaveBeenCalled();
  });

  it('banco fora: não confirma, pede nova tentativa com espera (nada é descartado)', async () => {
    const m = message('existe', 3);
    await processBatch(batchOf(m), env, async () => {
      throw new Error('connection refused');
    });
    expect(m.ack).not.toHaveBeenCalled();
    expect(m.retry).toHaveBeenCalledWith({ delaySeconds: 120 });
  });

  it('objeto ausente no R2: nova tentativa, sem gravar', async () => {
    const m = message('nao-existe');
    const receive = vi.fn(async () => {});
    await processBatch(batchOf(m), env, receive);
    expect(receive).not.toHaveBeenCalled();
    expect(m.retry).toHaveBeenCalled();
  });

  it('uma falha no lote não impede as outras mensagens', async () => {
    const ok = message('existe');
    const ruim = message('nao-existe');
    await processBatch(batchOf(ruim, ok), env, async () => {});
    expect(ruim.retry).toHaveBeenCalled();
    expect(ok.ack).toHaveBeenCalled();
  });

  it('espera crescente com teto de 1 hora', () => {
    expect([1, 2, 3, 4].map(retryDelaySeconds)).toEqual([30, 60, 120, 240]);
    expect(retryDelaySeconds(20)).toBe(3600);
  });
});
