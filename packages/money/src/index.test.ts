import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { allocate, applyRate, formatBRL, parseBRL, toCentsStrict } from './index';

const RUNS = { numRuns: 10_000 };

describe('toCentsStrict', () => {
  it('casos do plano de testes', () => {
    expect(toCentsStrict(11.2)).toBe(1120n);
    expect(toCentsStrict(33)).toBe(3300n);
    expect(toCentsStrict(0.3)).toBe(30n);
    expect(toCentsStrict(39.6)).toBe(3960n);
    expect(() => toCentsStrict(0.1 + 0.2)).toThrow(/2 casas/);
    expect(() => toCentsStrict(1.005)).toThrow(/2 casas/);
    expect(() => toCentsStrict(Number.NaN)).toThrow();
    expect(() => toCentsStrict(Number.POSITIVE_INFINITY)).toThrow();
  });
  it('ida e volta: todo inteiro de centavos / 100 volta ao mesmo inteiro', () => {
    fc.assert(
      fc.property(fc.integer({ min: -1_000_000_000, max: 1_000_000_000 }), (c) => {
        expect(toCentsStrict(c / 100)).toBe(BigInt(c));
      }),
      RUNS,
    );
  });
});

describe('parseBRL', () => {
  it('casos do plano de testes', () => {
    expect(parseBRL('R$ 1.234,56')).toBe(123456n);
    expect(parseBRL('-10,00')).toBe(-1000n);
    expect(parseBRL('1234.56')).toBe(123456n);
    expect(parseBRL('R$ 39,60')).toBe(3960n);
    expect(parseBRL('R$ 0,00')).toBe(0n);
    expect(() => parseBRL('1,234')).toThrow();
    expect(() => parseBRL('abc')).toThrow();
  });
  it('ida e volta com formatBRL', () => {
    fc.assert(
      fc.property(fc.bigInt({ min: -(10n ** 12n), max: 10n ** 12n }), (c) => {
        expect(parseBRL(formatBRL(c))).toBe(c);
      }),
      RUNS,
    );
  });
});

describe('applyRate', () => {
  it('casos do plano de testes', () => {
    expect(applyRate(123456n, 1500n)).toBe(18518n); // R$ 1.234,56 × 15% = R$ 185,18
    expect(applyRate(1005n, 1000n)).toBe(101n); // meio-para-cima
    expect(applyRate(0n, 1500n)).toBe(0n);
    expect(applyRate(3600n, 1000n)).toBe(360n); // taxa Zet de 10% sobre R$ 36,00
    expect(() => applyRate(-1n, 1n)).toThrow();
  });
  it('igual ao arredondamento meio-para-cima calculado pelo resto', () => {
    fc.assert(
      fc.property(fc.bigInt({ min: 0n, max: 10n ** 12n }), fc.bigInt({ min: 0n, max: 10_000n }), (a, b) => {
        const p = a * b;
        const expected = p / 10_000n + (p % 10_000n >= 5_000n ? 1n : 0n);
        expect(applyRate(a, b)).toBe(expected);
      }),
      RUNS,
    );
  });
});

describe('allocate', () => {
  it('casos do plano de testes', () => {
    expect(allocate(3000n, [2000n, 1000n])).toEqual([2000n, 1000n]); // inteira + meia (antes: 15 + 15)
    expect(allocate(1000n, [1n, 1n, 1n])).toEqual([334n, 333n, 333n]);
    expect(allocate(5400n, [3600n, 1800n])).toEqual([3600n, 1800n]);
    expect(() => allocate(100n, [])).toThrow();
    expect(() => allocate(100n, [0n, 0n])).toThrow();
    expect(() => allocate(-1n, [1n])).toThrow();
  });
  it('a soma é sempre o total e cada parte fica a menos de 1 centavo da ideal', () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: 0n, max: 10n ** 10n }),
        fc.array(fc.bigInt({ min: 0n, max: 10n ** 6n }), { minLength: 1, maxLength: 20 }).filter((w) => w.some((x) => x > 0n)),
        (total, w) => {
          const parts = allocate(total, w);
          const sum = w.reduce((a, b) => a + b, 0n);
          expect(parts.reduce((a, b) => a + b, 0n)).toBe(total);
          parts.forEach((p, i) => {
            // |p − total·w/sum| < 1  ⇔  |p·sum − total·w| < sum
            const diff = p * sum - total * w[i]!;
            expect(diff < sum && -diff < sum).toBe(true);
          });
        },
      ),
      RUNS,
    );
  });
  it('é determinístico', () => {
    fc.assert(
      fc.property(fc.bigInt({ min: 0n, max: 10n ** 9n }), fc.array(fc.bigInt({ min: 1n, max: 1000n }), { minLength: 1, maxLength: 10 }), (t, w) => {
        expect(allocate(t, w)).toEqual(allocate(t, w));
      }),
      { numRuns: 1_000 },
    );
  });
});

describe('formatBRL', () => {
  it('formata sem float', () => {
    expect(formatBRL(123456n)).toBe('R$ 1.234,56');
    expect(formatBRL(-5n)).toBe('-R$ 0,05');
    expect(formatBRL(214125370n)).toBe('R$ 2.141.253,70');
  });
});
