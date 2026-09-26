# 7. Plano de testes

Regra geral: **todo exemplo numérico de teste fecha no centavo**, e toda trava é testada violando-a de propósito (o teste tem de reprovar sem a trava).

## 7.1 Unidade (Vitest + fast-check), no CI em todo PR

| Alvo | Casos fixos | Propriedades (10.000 casos cada) |
|---|---|---|
| `toCentsStrict` | `11.2 → 1120n`; `0.30000000000000004` (resultado de `0.1 + 0.2`) → erro "mais de 2 casas"; `NaN` → erro | Para todo inteiro `c` seguro, `toCentsStrict(c/100) === c` |
| `parseBRL` | `"R$ 1.234,56" → 123456n`; `"-10,00" → -1000n`; `"1234.56" → 123456n`; `"R$ 39,60"` com espaço não separável → `3960n`; `"1,234"` → erro | Ida e volta com `formatBRL` |
| `applyRate` | `(123456n,1500n) → 18518n`; `(1005n,1000n) → 101n`; `(0n, x) → 0n` | Resultado = arredondamento half-up de `amount × bps / 10000` calculado em racional exato |
| `allocate` | `(3000n,[2000n,1000n]) → [2000n,1000n]`; `(1000n,[1n,1n,1n]) → [334n,333n,333n]`; `(5400n,[3600n,1800n]) → [3600n,1800n]` | `sum === total`; cada parte difere da ideal em menos de 1 centavo; determinístico |
| `zet-schema` | Payload real anonimizado de CP, ES total, ES parcial, cortesia (`totalTax = 0`), sem CPF, sem e-mail | Campos extras não quebram; `qr`/`voucher` sempre texto |
| Parser do export | Linha `"R$ 39,60"`, `"R$ 3,60"`, `"R$ 0,00"`, `"R$ 36,00"` → válida; `Total − Taxa − Desconto ≠ Líquido` → arquivo rejeitado | — |

## 7.2 pgTAP (banco), no CI em todo PR

| Grupo | Testes |
|---|---|
| Livro-razão | Lançamento com D ≠ C rejeitado no COMMIT; lançamento com 1 partida rejeitado; `UPDATE`, `DELETE`, `TRUNCATE` em `journal_entries` e `postings` rejeitados; `amount_cents ≤ 0` rejeitado; mesma `idempotency_key` 2× → 1 lançamento; `reverse_entry` gera espelho exato e só uma vez |
| Período | Lançamento em dia `closed` rejeitado; `close_period` com 1 assinatura falha; assinatura sobre hash antigo não conta; assinante fora da vigência rejeitado; reabertura sem admin ou com motivo curto rejeitada |
| Segurança | `anon` sem acesso a nada; `authenticated` sem papel não executa RPC; operador não vê outro guichê; quem lançou no dia não assina; quem assinou não reabre; nenhuma policy `true`; nenhuma função `security definer` sem `search_path` |
| Inbox | Mesmo `sha256` 2× → 1 linha; `raw_body` imutável; `DELETE` rejeitado |
| Zet | CP novo → pedido, itens rateados, lançamento; CP repetido igual → nada; CP repetido diferente → exceção, nada sobrescrito; ES parcial → só os vouchers citados; ES repetido → nada; ES antes de CP → exceção e nova tentativa; CP depois de ES → exceção, não reverte; taxa fora da tolerância → exceção sem bloquear; evento sem de-para → `failed`; pedido sem CPF → gravado |
| Concorrência | 50 CPs iguais em paralelo (via `dblink` ou script `psql` paralelo no CI) → 1 pedido e 1 lançamento; 2 ES iguais em paralelo → 1 estorno |
| Bilheteria | Fórmula da receita em dinheiro (exemplo de `01`); quebra quando contado + sangrias < fundo; `box_office_check` com o exemplo de `05` (T-04) |
| Foods | `185,18`; FIFO; falta de repasse; crédito de loja; mudança de percentual não altera dia anterior |
| Catracas | Tentativa com `id` repetido → `repetido`; append-only; cursor por sequência sem buracos visíveis ao cliente |

## 7.3 Carga e queda do webhook (k6), em hml, antes de 13/10 e antes do ensaio geral

Cenário **"banco desligado"**:
1. Pausar o consumidor (`zet-consumer`) e bloquear o Hyperdrive (simula banco fora).
2. k6: **200 req/s por 5 minutos = 60.000 requisições**, corpos distintos (uuid diferente em cada), token válido.
3. Esperado durante o teste: 100% de respostas 200; p95 < 100 ms; 60.000 objetos no R2; 60.000 mensagens na fila.
4. Religar o consumidor. Esperado: fila drena sem erro; **60.000 linhas no inbox**; conexões do banco nunca acima do limite configurado para `ingest_writer`.
5. Repetir 10.000 das requisições (reenvio): nenhuma linha nova no inbox.

Cenários adicionais: 1.000 req/s com token **inválido** (o WAF/rate limit corta; nada no R2); corpo de 65 KB (413); 1 hora de banco fora seguida de religamento (drenagem no ritmo configurado).

Referência de escala: o maior dia de 2025 teve 943 pedidos. 200 req/s é mais de 10.000 vezes a média daquele dia; o teste mede a folga contra enxurrada, não o uso normal.

## 7.4 Contrato com as catracas

1. `packages/contracts/exemplos/` tem, para cada chamada, pares requisição/resposta: normal, lote com item inválido, reenvio, segredo errado, lote grande, paginação de 3 páginas, cartão com zero à esquerda (`"00123"`).
2. O CI deste repositório valida a `catracas-api` contra os exemplos; o CI do `conexao-topdata` valida o conector deles contra os **mesmos** arquivos (cópia versionada com número de versão do contrato).
3. **Ensaio conjunto em hml** (C-05), nunca em produção:
   - o PC de bancada puxa `configuracao` e mostra as categorias e preços;
   - passa 20 cartões (10 inteira, 6 meia, 4 social) → 20 tentativas `consumido` na nuvem com a categoria certa;
   - tira o cabo de rede, passa mais 10, recoloca → 10 chegam, nenhuma duplicada;
   - reenvia o lote inteiro → todos `repetidos`;
   - o relatório do dia em hml mostra a conferência bilheteria × catraca com os 30 usos.

## 7.5 Robô contra o export de 2025

Em ambiente local, fora do repositório (os arquivos têm dados pessoais):
1. Importar `data.xlsx` de 2025 por R-01 → **27.451 pedidos, R$ 2.141.253,70**.
2. Com o backup de webhooks já processado (W-05), `recon.v_zet_export_diff` reproduz a ponte de `15`, seção 2: 226 estornados com ES (−R$ 17.975,50), 13 contestações (−R$ 975,00), 23 fora do export sem ES (−R$ 1.680,50), 1.161 da máquina (+R$ 60.952,50), 136 antes do backup (+R$ 11.291,20), 187 sem webhook (+R$ 14.422,00), 81 sem data (+R$ 7.511,50), 37 cortesias (R$ 0,00). Conta: 2.067.707,50 − 17.975,50 − 975,00 − 1.680,50 + 60.952,50 + 11.291,20 + 14.422,00 + 7.511,50 = **2.141.253,70** ✅.
3. Robô contra uma **cópia estática** das telas (HTML salvo sem dados pessoais) com botões "Validar", "Nova venda" e "Solicitar saque": o robô nunca clica neles e aborta diante de um formulário inesperado.
4. Contra o painel real, só com usuário só leitura (ou acompanhado, ver `06`, 6.3).

## 7.6 Ensaio de um dia completo (G-01)

Em hml, com um dia de 2025 anonimizado e os 9 guichês simulados por pessoas reais da equipe:

| Etapa | Resultado esperado |
|---|---|
| Webhooks do dia reenviados para `ingest-hml` | Vendas e estornos iguais ao export do dia |
| Retirada do banco para fundos, abertura dos 9 guichês | Tesouraria e caixas com os fundos certos |
| Sangrias parciais e fechamento dos 9 | Caixas zerados; receita em dinheiro pela fórmula |
| EDI (ou CSV) simulado de D+1 | Declarado × EDI dentro das faixas; MDR lançado |
| Tentativas de catraca | `box_office_check` calculado |
| Foods: 3 lojas, uma paga a menos | Falta de repasse com alerta |
| Sincronizar com a Zet | Bloco "Zet no dia" |
| Duas assinaturas, dia travado, sangria para banco | Tesouraria **R$ 0,00** |
| Conferência final | Saldo de cada conta = extratos simulados: **diferença R$ 0,00** |

O ensaio só passa com diferença zero. Qualquer centavo vira defeito a corrigir antes da abertura.
