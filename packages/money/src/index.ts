/**
 * Dinheiro do sistema: sempre centavos inteiros (bigint). Único módulo que converte, arredonda e rateia.
 * Regras em docs/analise-iluminadarua2025/03-ARQUITETURA-ALVO.md, seção 2.
 */
export type Cents = bigint;

const DECIMAL_2 = /^(-)?(\d+)(?:\.(\d{1,2}))?$/;

/**
 * Converte um número vindo de JSON (ex.: 11.2) em centavos.
 * Usa a representação decimal mais curta do número (String(v)), então 0.3 é aceito
 * e 0.30000000000000004 (resultado de 0.1 + 0.2) é rejeitado por ter mais de 2 casas.
 */
export function toCentsStrict(v: number): Cents {
  if (!Number.isFinite(v)) throw new Error(`valor inválido: ${v}`);
  const m = DECIMAL_2.exec(String(v));
  if (!m) throw new Error(`mais de 2 casas decimais ou formato inválido: ${v}`);
  const cents = BigInt(m[2]!) * 100n + BigInt((m[3] ?? '').padEnd(2, '0'));
  return m[1] ? -cents : cents;
}

/** "R$ 1.234,56" | "1234.56" | "-10,00" | "R$ 39,60" (com espaço não separável) -> centavos. */
export function parseBRL(s: string): Cents {
  const t = s.trim().replace(/\s|R\$/g, '');
  const m = /^(-)?(\d{1,3}(?:\.\d{3})*|\d+)(?:[,.](\d{1,2}))?$/.exec(t);
  if (!m) throw new Error(`formato inválido: ${s}`);
  const int = m[2]!.replace(/\./g, '');
  const frac = (m[3] ?? '').padEnd(2, '0');
  const c = BigInt(int) * 100n + BigInt(frac);
  return m[1] ? -c : c;
}

/** valor × taxa em pontos-base (15% = 1500n), arredondado meio-para-cima. 123456n × 1500n -> 18518n. */
export function applyRate(amount: Cents, bps: bigint): Cents {
  if (amount < 0n || bps < 0n) throw new Error('applyRate espera valores não negativos');
  return (amount * bps + 5_000n) / 10_000n;
}

/** Rateio pelo maior resto: a soma das partes é sempre igual ao total. Empate: menor índice primeiro. */
export function allocate(total: Cents, weights: readonly bigint[]): Cents[] {
  if (total < 0n) throw new Error('total negativo');
  const sum = weights.reduce((a, b) => a + b, 0n);
  if (weights.length === 0 || sum <= 0n || weights.some((w) => w < 0n)) throw new Error('pesos inválidos');
  const parts = weights.map((w) => (total * w) / sum);
  let left = total - parts.reduce((a, b) => a + b, 0n);
  const order = weights
    .map((w, i) => ({ i, r: (total * w) % sum }))
    .sort((a, b) => (b.r > a.r ? 1 : b.r < a.r ? -1 : a.i - b.i));
  for (let k = 0; left > 0n; k++, left--) parts[order[k]!.i]! += 1n;
  return parts;
}

/** Exibição em reais, calculada sobre o bigint (sem passar por float). 123456n -> "R$ 1.234,56". */
export function formatBRL(c: Cents): string {
  const neg = c < 0n;
  const abs = neg ? -c : c;
  const int = (abs / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const frac = (abs % 100n).toString().padStart(2, '0');
  return `${neg ? '-' : ''}R$ ${int},${frac}`;
}
