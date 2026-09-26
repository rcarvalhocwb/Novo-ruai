# Venda × entrada: seguir o dinheiro, não a catraca

## 1. O problema

O relatório de fechamento do sistema antigo mistura duas coisas que acontecem em dias diferentes:

- **Venda** (o dinheiro): acontece no dia do pagamento.
- **Entrada** (o uso do ingresso): acontece no dia da visita, que pode ser dias depois.

O código faz isto (`src/hooks/useTurnstileReconciliation.ts` + `TurnstileReconciliationForm.tsx`):
1. pega **todas** as validações de catraca do dia, de online e de bilheteria juntas;
2. multiplica por um preço fixo por tipo (inteira R$ 36, meia R$ 18, social R$ 25, Gazeta R$ 32,50, codificados como padrão);
3. trata o resultado como "valor" do dia e **subtrai do dinheiro esperado no caixa** (a tela avisa: "O valor total de ingressos validados será subtraído do caixa na etapa final").

Isso transforma **quem entrou** em **quanto se faturou**, o que está errado sempre que a compra e a visita não acontecem no mesmo dia.

## 2. O tamanho do problema, com os dados reais

No backup de webhooks (79.495 ingressos online, 22/10/2025 a 04/01/2026):

| Compra × visita | Ingressos | % |
|---|---|---|
| Comprado no mesmo dia da visita | 48.255 | 60,7% |
| Comprado de 1 a 7 dias antes | 25.804 | 32,5% |
| Comprado de 8 a 30 dias antes | 4.700 | 5,9% |
| Comprado com mais de 30 dias | 699 | 0,9% |
| Visita **antes** da confirmação do pagamento (exceção a investigar) | 37 | 0,0% |

**Quase 4 em cada 10 ingressos online são usados em outro dia.** Exemplos:

| Dia | Ingressos online **vendidos** no dia | Ingressos online **com visita** no dia | Diferença |
|---|---|---|---|
| 20/12/2025 | 2.829 | 3.832 | +35% |
| 21/12/2025 | 2.880 | 3.065 | +6% |
| 21/11/2025 | 2.620 | 2.930 | +12% |

No dia 20/12, calcular o faturamento pelas entradas daria cerca de **1.000 ingressos a mais** do que o dinheiro que realmente entrou naquele dia. Esse dinheiro entrou em dias anteriores e já tinha sido contado lá. Somado ao longo do evento, conta o mesmo dinheiro duas vezes em alguns dias e deixa outros dias sem ele.

## 3. A recomendação: três visões separadas, que nunca se misturam

Em eventos, a prática correta é separar **três relógios**:

| Visão | Pergunta que responde | Data que manda | Para que serve | Entra no fechamento financeiro? |
|---|---|---|---|---|
| **1. Caixa (o dinheiro)** | Quanto dinheiro entrou, saiu e onde está? | Data do **pagamento**, do **estorno** e do **recebimento** | Fechamento diário, sangria, conciliação bancária, prestação de contas | **Sim. É o fechamento.** |
| **2. Acesso (as pessoas)** | Quem entrou, com qual ingresso? Alguém entrou sem pagar? | Data da **visita** | Controle de fraude, lotação, no-show, operação | Não. É um relatório operacional ao lado |
| **3. Competência (contábil)** | Quanto da receita já foi "entregue" ao cliente? | Data da **visita** | Contabilidade e resultado do evento (ingressos vendidos para datas futuras são receita a realizar) | Não. Relatório contábil, para o contador |

A regra central, que é exatamente o que você descreveu: **o fechamento financeiro segue o dinheiro**. O que entrou pela catraca serve para controle, **nunca** para calcular faturamento nem para somar ou subtrair do caixa.

### 3.1 Visão 1: caixa (o que o fechamento assina)

| Linha do fechamento | Data usada |
|---|---|
| Vendas da bilheteria por guichê (dinheiro, cartão, PIX) | Dia da venda (que, na bilheteria, é também o dia da visita) |
| Vendas online do dia (líquido) | `paymentConfirmeDate` em horário de Brasília |
| Estornos online do dia | Data do estorno |
| Comissões recebidas das lojas | Dia do recebimento |
| Sangrias, despesas e transferências | Dia do movimento |
| Repasses da Zet e liquidações do PagBank que caíram na conta | Data do crédito no extrato |

Com isso, o fechamento de cada dia bate com a Zet (vendas do dia no relatório dela) e com o banco (créditos do dia no extrato). É isso que o livro-razão (`03-ARQUITETURA-ALVO.md`) já faz: todo lançamento carrega a data do fato financeiro.

### 3.2 Visão 2: acesso (relatório operacional, ao lado do fechamento)

A catraca continua sendo muito útil, com as perguntas certas:

| Conferência | Como | O que revela |
|---|---|---|
| Entrada sem ingresso | Toda passagem autorizada tem de corresponder a um cartão RFID vendido **naquele dia** na bilheteria ou a um voucher online **válido para aquela data** | Fraude, cartão não devolvido, voucher repetido |
| Bilheteria: quantidade por tipo | Entradas por cartão RFID de cada tipo × cartões vendidos de cada tipo nos 9 guichês | Tipo errado (meia vendida como inteira), cartão que não passou na catraca |
| Online: comparecimento | Vouchers usados no dia × vouchers com visita marcada para o dia; entradas online separadas em "compradas hoje" e "compradas antes" | No-show, lotação, previsão para os próximos dias |

**Somente na bilheteria** faz sentido comparar entradas com dinheiro, porque ali a compra e a entrada acontecem no mesmo dia e o cartão RFID tem tipo. Mesmo assim, é uma **conferência de quantidade**, que aponta divergência para investigar. **Ela nunca altera o valor do caixa.** O dinheiro do guichê é o que foi contado e o que a maquininha registrou.

### 3.3 Visão 3: competência (para o contador)

Um ingresso online vendido hoje para visita daqui a 10 dias é dinheiro **recebido**, mas ainda não é receita **realizada**: o evento ainda deve a visita ao cliente. Contabilmente (CPC 47 / IFRS 15), essa receita é reconhecida na data da visita; até lá, é um **adiantamento de clientes** (ingressos a realizar).

O sistema não precisa mudar o fechamento para isso. Basta um relatório que mostre:
- **ingressos a realizar**: vendidos e ainda não usados, por data de visita, em quantidade e valor;
- **receita realizada no dia**: ingressos com visita no dia, pelo preço efetivamente pago (o de cada voucher, já com desconto de campanha, e não por preço médio);
- **no-show**: ingressos com visita passada e não usados.

Como cada voucher guarda o valor pago (`net_cents` do item, rateado pelo preço de tabela em `04-INTEGRACAO-ZET.md`), esse relatório sai exato, sem estimativa.

## 4. O que muda no sistema

1. **O fechamento do caixa não usa a catraca para nada que envolva dinheiro.** A etapa "Validações da catraca" sai do cálculo do esperado e vira um bloco informativo e de alertas.
2. **Toda consulta financeira filtra pela data do dinheiro** (pagamento, estorno, crédito). Toda consulta de acesso filtra pela data da visita. O banco guarda as duas datas separadas em cada ingresso (`paid_at`/`business_date` e `visit_date`).
3. **Relatórios com nomes que não confundam**: "Vendas do dia (financeiro)" × "Entradas do dia (operacional)" × "Receita realizada (contábil)".
4. **Os preços nunca ficam fixos no código.** O valor de cada ingresso é o que foi pago por ele.
5. **O relatório do assistente de fechamento** (`10-ASSISTENTE-FECHAMENTO.md`) segue a mesma regra: a IA só fala de dinheiro com base na visão 1.

## 5. Resumo

- **Siga o dinheiro**: o que foi vendido no dia, o que foi estornado, o que foi recebido, para onde foi e quanto há em cada conta.
- **Use a catraca para controlar pessoas**: quem entrou, se tinha ingresso, se o tipo confere, quem não veio.
- **Deixe a competência para o contador**: receita realizada por data de visita, a partir do valor real de cada ingresso.
