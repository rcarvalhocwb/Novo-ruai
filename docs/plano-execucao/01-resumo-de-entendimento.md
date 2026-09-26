# 1. Resumo de entendimento

> Plano de execução do sistema novo da Rua Iluminada, temporada 2026. Fonte da verdade: `docs/analise-iluminadarua2025/` (00 a 17) e, no `conexao-topdata`, os docs 15, 16, 18, 19 e 22, os ADRs 0002, 0003, 0007, 0022 e 0023 e as migrações SQLite. Escrito em 26/09/2026.

## O que o sistema faz

Controla o **dinheiro** do evento e **fecha cada dia no centavo, com prova**. O sistema responde a cinco perguntas, e cada resposta é o saldo de uma conta do livro-razão, não um número digitado:

| Pergunta | Onde a resposta mora |
|---|---|
| Quanto vendemos hoje (online, máquina da Zet, bilheteria) e quanto foi estornado ou contestado? | Contas de receita e redutoras (4.x), por `business_date` |
| Quanto a Zet ainda nos deve? | Saldo da 1.2.01 "A receber Zet" (pode ficar negativo, R25) |
| Onde está o dinheiro físico agora? | Saldos das contas de caixa (1.1.01 a 1.1.09), Tesouraria (1.1.00) e bancos |
| Quanto cada loja de alimentação deve? | Saldo da 1.2.1N de cada loja (falta de repasse) |
| Quem entrou, e isso confere com o que a bilheteria recebeu? | Espelho das tentativas da catraca (`access.*`). **Informativo, nunca vira valor** (R19) |

No fim do dia, duas pessoas designadas assinam o **mesmo hash** do conteúdo financeiro do dia, e o dia fica travado.

## Para quem

| Papel | O que faz no sistema |
|---|---|
| `operador_caixa` | Abre e fecha o próprio guichê, declara contagem e total da maquininha, registra sangria parcial |
| `gestor` | Entrega fundos, recebe sangrias, lança despesas, vendas das lojas e repasses, pede "Sincronizar com a Zet" |
| `aprovador` | Uma das duas pessoas designadas que assinam o dia (MFA obrigatório) |
| `admin` | Cadastros, designação dos assinantes, reabertura de dia com motivo, baixa de falta de repasse (MFA obrigatório) |
| `importador` | Papel técnico do robô da Zet e dos importadores de extrato |
| `catraca` | Papel técnico do PC das catracas (um segredo por PC) |

Separação de funções garantida pelo banco: quem lança não aprova o mesmo dia, e quem aprova não reabre.

## O que muda em relação a 2025

| 2025 (o que falhou) | 2026 (o que o substitui) | Como se prova |
|---|---|---|
| Centavos divergentes: float, `Math.round(x*100)/100`, rateio por quantidade, dia em UTC, soma no navegador cortada em 1.000 linhas | `bigint` em centavos, `money.ts` único, taxas em basis points, half-up num só lugar, rateio por maior resto, `business_date` gravado uma vez em `America/Sao_Paulo`, toda soma no banco | Testes de propriedade (>10 mil casos) e teste de CI que reprova coluna de dinheiro que não seja `bigint` |
| Webhook da Zet dependia do banco; no apagão, a enxurrada de reenvios travou o banco e corrompeu vendas | Borda durável: Cloudflare Worker responde sem tocar no banco, guarda o corpo cru no R2 e numa fila; o banco recebe no ritmo que aguenta | Teste de carga de 200 req/s com o banco **desligado** e zero perda |
| Sem livro-razão; dados sobrescritos; correções por `UPDATE` | Partidas dobradas append-only, balanceamento por trigger, correção só por estorno, idempotência por chave, dia fechado travado | pgTAP: desbalanceado, `UPDATE`, `DELETE` e lançamento em dia fechado são rejeitados |
| Funções públicas que apagavam dados; RLS `USING (true)`; `service_role` em 81 funções | Só o schema `api` exposto; RLS nega por padrão; toda função checa papel; credenciais técnicas com papel mínimo; nada de `service_role` fora do servidor | Teste de CI que reprova `USING (true)`; checklist `07`, parte B, 100% verde |

## O que entra em 2026 e o que fica para 2027

**Entra:** webhook Zet; importação do export e robô do painel com o botão "Sincronizar com a Zet"; conexão com a catraca (sobe tentativas e saúde, desce configuração e cartões bloqueados); fechamento dos 9 guichês (dinheiro e maquininha); tesouraria e sangria; foods; relatório diário em PDF com duas assinaturas; conta-corrente Zet.

**Fica para 2027:** tela de venda no guichê e modo "por guichê" (R28); aviso de consumo da catraca para a Zet; app nas maquininhas Smart; assistente de IA no fechamento; reconstrução completa do histórico de 2025 no livro-razão (ver `08-plano-de-virada.md`).

## Uma consequência de R28 que o plano assume (confirmar com o dono do evento)

Em 2026 não há registro de venda por guichê. Então **o guichê não tem "dinheiro esperado" independente**: a receita em dinheiro do guichê é derivada do que foi contado.

```
receita em dinheiro do guichê = contado no fechamento + sangrias parciais − fundo de troco
```

Exemplo ilustrativo (fecha no centavo): fundo R$ 200,00; sangria parcial R$ 1.000,00; contado no fechamento R$ 1.450,00 → receita em dinheiro = 1.450,00 + 1.000,00 − 200,00 = **R$ 2.250,00**.

A conferência de verdade da bilheteria em 2026 acontece em dois lugares:
1. **Por guichê, no cartão/PIX:** total declarado pelo operador (relatório da maquininha) × PagBank EDI do terminal em D+1. Aqui valem as tolerâncias R17 (até R$ 1,00; de R$ 1,01 a R$ 50,00; acima de R$ 50,00).
2. **No total dos 9 guichês:** receita da bilheteria × (usos consumidos na catraca por categoria × preço). Aqui valem os limites de 5% e 10% (R13), e a diferença em reais também passa pelas faixas R17 para exigir justificativa e destaque.

A falta ou sobra de dinheiro de um guichê específico só aparece no modo "por guichê" (2027). Isso é uma limitação conhecida e aceita pela decisão R28, não um defeito do sistema. Pergunta D-01 em `10-perguntas-em-aberto.md`.
