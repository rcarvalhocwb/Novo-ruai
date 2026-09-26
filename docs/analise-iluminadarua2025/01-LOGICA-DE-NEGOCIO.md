# Lógica de negócio a preservar

Tudo o que está aqui foi extraído do código e da documentação do `iluminadarua2025`. Onde o código e a documentação se contradizem, o ponto está marcado como **[DÚVIDA]** e repetido em `08-DUVIDAS.md`.

## 1. Glossário

| Termo | Significado no sistema |
|-------|------------------------|
| **Evento** | A temporada (ex.: "Rua Iluminada 2025"), com várias datas e sessões. |
| **Sessão / show time** | Data e horário de visitação vendável. |
| **Tipo de ingresso** | Inteira, Meia, Social/Gazeta, Cortesia. |
| **Zet / CompreNoZet** | Plataforma de venda online. Envia webhooks `CP` (compra paga) e `ES` (estorno). |
| **Bruto (`totalValue`)** | Valor pago pelo cliente na Zet = preço do ingresso + taxa Zet. |
| **Taxa (`totalTax`)** | Taxa de conveniência: **acréscimo de 10% sobre o preço**, paga pelo cliente e **retida pela Zet**. Não é receita nem despesa do evento. |
| **Líquido** | `bruto − taxa` = preço do ingresso: **a receita do evento** e o que a Zet repassa. |
| **Repasse online** | Transferência da Zet para a conta do evento (`online_transfers`: esperado × recebido). |
| **Bilheteria** | Venda física: dinheiro, cartão/PIX na maquininha PagBank e cartões físicos de ingresso por caixa. |
| **Bilheteria / caixa** | Um dos **9 caixas** físicos. Cada um abre o dia com um **fundo de troco** e o devolve no fechamento, junto com a venda do dia. |
| **Fundo de troco** | Dinheiro do evento entregue a cada caixa para começar o dia. **O valor pode variar por operador.** Não é receita: sai da tesouraria e volta para ela no fechamento. |
| **Conta bancária** | Contas do evento, **cadastradas e alteradas durante o evento**. É possível transferir (sangria) de uma conta para outra. |
| **Falta de repasse** | Quando a loja paga menos que a comissão do dia. A diferença **continua devida**: gera alerta e deve ser paga no próximo caixa ou quitada à parte. |
| **Tesouraria / cofre** | Onde fica o dinheiro do evento entre o fechamento dos caixas e a sangria. |
| **Sangria** | Depois do fechamento, retirada do dinheiro da tesouraria para **depósito numa conta bancária** ou para **pagamento de despesas do evento**. |
| **Assinantes do fechamento** | As **duas pessoas designadas** para assinar o relatório de fechamento. São escolhidas durante o evento e podem ser trocadas a qualquer momento. |
| **Food / loja** | Operação de alimentação parceira. Informa vendas do dia; o evento tem direito a um **percentual de comissão** sobre elas. |
| **Repasse de food** | Pagamento da comissão pela loja ao evento, distribuído entre os dias pendentes em ordem FIFO. |
| **Sangria / despesa / ajuste** | Movimentos de caixa de uma loja (`store_cash_movements`). |
| **Fechamento diário** | Conferência do dia (online + bilheteria + comissões + troco + catraca), com assinatura e aprovação. |
| **Caixa geral** | Soma dos fechamentos diários menos os repasses já feitos à administração. |
| **Repasse à administração** | Transferência do saldo do evento para a administração, mantendo um caixa mínimo (padrão R$ 1.000). |
| **Catraca / RFID** | Controle de acesso. Serve para conferir ingressos vendidos × entradas. |

## 2. Fluxos financeiros

```mermaid
flowchart LR
  subgraph Online
    Z[Zet] -- webhook CP/ES --> V[Venda online<br/>bruto, taxa, líquido]
    Z -- repasse bancário --> B[(Conta bancária)]
  end
  subgraph Bilheteria
    T[(Tesouraria)] -- fundo de troco --> C1[Caixa 1..9]
    C1 -- fundo + venda em dinheiro --> T
    T -- sangria --> B2[Banco ou despesas]
    C1 -- cartão/PIX --> PB[PagBank] -- liquidação D+x --> B
  end
  subgraph Foods
    L[Loja] -- vendas do dia --> CM[Comissão devida<br/>= vendas × %]
    L -- repasse FIFO --> B
  end
  V --> FD[Fechamento diário]
  T --> FD
  PB --> FD
  CM --> FD
  FD --> CG[Caixa geral] -- repasse --> ADM[Administração]
```

### 2.1 Venda online (Zet)
1. A Zet envia `action = CP` com `order.uuid`, `totalValue`, `totalTax`, `discount`, `paymentType`, `paymentSituation = PAGO`, `paymentConfirmeDate` e a lista `eventTicketCodes` (1 por ingresso, com `voucher` e `eventsValues.description` = tipo).
2. O sistema grava a venda **com os valores exatos recebidos**. Regra: **nunca recalcular a taxa**.
3. `paymentType = CORTESIA` indica ingresso cortesia (valor zero).
4. `action = ES` ou `paymentSituation ∈ {ESTORNADO, ESTORNO}` indica estorno do **pedido inteiro**: a venda vira ESTORNADO e os ingressos são cancelados.
5. Cada voucher vira um ingresso validável na catraca.
6. O repasse da Zet cai na conta bancária e é conciliado contra a soma dos líquidos do período (`online_transfers.expected_amount` × `received_amount`).

**Regra da taxa (confirmada):** a taxa é um **acréscimo de 10% sobre o preço do ingresso** (o líquido), cobrado do cliente e retido pela Zet.

| | Valor |
|---|---|
| Preço do ingresso (líquido, receita do evento) | R$ 30,00 |
| Taxa Zet (10% sobre o líquido) | R$ 3,00 |
| `totalValue` no payload (bruto, pago pelo cliente) | R$ 33,00 |

Consequências:
- A **receita do evento é o líquido**. A taxa é da Zet e não entra como receita nem como despesa do evento.
- Validação (sem reescrever nada): `taxa ≈ arredondar(líquido × 10%)`. Como a Zet pode arredondar por ingresso, aceita-se uma diferença de até 1 centavo por ingresso; acima disso, abre-se exceção para conferir com a Zet.
- Visto sobre o bruto, a taxa dá 9,09% (`3/33`). O documento `FINANCIAL-CALCULATIONS.md` calculava "10% do bruto" e por isso achava que a Zet cobrava a mais. **Essa regra estava errada**; a de `COMPRENOZET-TAX-CALCULATION.md` estava certa.

**Estorno online (confirmado):** o evento devolve **só o preço do ingresso**; a taxa da Zet não é estornada pelo evento. Pode ser total ou parcial.

**Desconto (confirmado):** só existe em **campanhas**. O `totalValue` que a Zet envia **já vem com o desconto aplicado**, e a taxa é calculada sobre o valor com desconto. O campo `discount` é só informativo, para o relatório de campanhas. O webhook antigo gravava `orders.total_amount = totalValue − discount`, ou seja, **subtraía o desconto duas vezes** (P-13).

**Início das vendas online (confirmado):** 15/10/2025.

**Preço por sessão (confirmado):** existem sessões especiais com preço próprio (ex.: sessões de teste com brindes e horário especial). O preço de tabela é guardado por data, sessão e tipo de ingresso.

**Erro de taxa da Zet (confirmado):** a Zet já cobrou taxa errada na meia-entrada e corrigiu depois que o sistema apontou. A validação automática da taxa continua obrigatória.

**Estorno parcial (confirmado):** a Zet pode estornar só alguns ingressos de um pedido. O estorno é tratado ingresso a ingresso.

**Dia operacional do online (confirmado):** vai de 00:00 a 23:59:59 no horário de Brasília (`America/Sao_Paulo`), pela data de pagamento.

### 2.2 Bilheteria física (9 caixas)
1. **Abertura**: cada um dos 9 caixas recebe da tesouraria o seu **fundo de troco**, cujo valor **pode variar por operador**; a sessão do caixa registra quem é o operador e quanto recebeu e a **quantidade inicial de cartões de ingresso** (inteira, meia e social).
2. **Venda**: dinheiro, cartão ou PIX (maquininha PagBank). Produtos vendidos no caixa entram na bilheteria, mas não no ticket médio.
3. **Estorno na bilheteria**: sempre **total** (a venda inteira é devolvida ao cliente, pelo mesmo meio de pagamento).
4. **Fechamento do caixa**: informam-se os cartões restantes (vendidos = iniciais − restantes), o **dinheiro contado**, o total da maquininha e o total de PIX. O caixa **devolve o fundo de troco junto com a venda do dia**.
   - **Nada fica de um dia para o outro (confirmado)**: o fundo de troco vai junto na sangria. No dia seguinte, o valor do fundo é retirado de novo (da conta bancária) e entregue aos caixas. A tesouraria começa e termina o dia **zerada**.
   - Dinheiro esperado = fundo de troco + vendas em dinheiro − estornos em dinheiro.
   - Diferença entre contado e esperado = quebra (falta) ou sobra, sempre registrada com justificativa.
5. **Dia operacional da bilheteria (confirmado)**: termina **quando o caixa é fechado** para aquele dia, e não à meia-noite. Uma venda às 00:20 num caixa ainda aberto pertence ao dia daquele caixa.
6. Cartão e PIX têm taxa PagBank por modalidade (`pagbank_fee_config`: PIX 0,40%, débito 1,28%, crédito 3,08%). Hoje o sistema **estima** a taxa por média ponderada (2,27%) ou por um padrão de 2,5%. No novo sistema, a taxa **real** tem que vir do CSV ou extrato do PagBank.

### 2.3 Foods (lojas parceiras)
1. **Percentual por loja (confirmado)**: cada loja tem o seu percentual de comissão, parametrizado individualmente. Se o percentual mudar, a mudança vale a partir de uma data e não altera dias anteriores.
2. A loja informa as vendas do dia e o sistema calcula `comissão do dia = vendas × percentual da loja`, arredondada a centavos uma única vez.
3. **Pagamento diário (confirmado)**: a **loja paga a comissão ao evento todos os dias**. O repasse é receita do evento.
4. O repasse é **distribuído FIFO** entre os dias pendentes (o mais antigo primeiro). Cada dia fica `pendente`, `parcial` ou `pago`. Se a loja pagar a mais, o excedente vira crédito da loja.
5. **Pagou menos (confirmado)**: a diferença **não é desconto nem perda**. É **falta de repasse**: continua devida, gera **alerta** e deve ser paga no próximo caixa ou quitada à parte. O alerta mostra o valor em aberto e há quantos dias.
6. Só um admin, com motivo registrado, pode dar baixa numa falta de repasse (perdão da dívida). Isso vira um lançamento próprio, e não uma edição do valor da comissão.
7. A loja tem movimentos próprios (sangria, despesa, ajustes) e fechamento próprio (vendas do dia e acumuladas, saídas, dinheiro esperado × declarado, diferença). Diferença de dinheiro na loja é **falta em caixa** da loja.
8. Os foods **não entram** no saldo financeiro da bilheteria nem no ticket médio. Aparecem só como informação no relatório.

O manual antigo (passo 3.6) fala em "pagar comissões de lojas" como despesa e em "ajustar o valor recebido" como desconto acordado. **As duas coisas estão erradas**: a loja paga o evento, e o valor a menor é falta de repasse, não desconto.

### 2.4 Fechamento diário
1. **Importar**: repasses online recebidos na data e transações PagBank liquidadas na data.
2. **Caixas da bilheteria**: os 9 caixas fechados, cada um com o fundo de troco devolvido, dinheiro contado e diferença justificada.
3. **Movimentações manuais**: receitas e despesas com forma de pagamento.
4. **Catraca**: contagem inicial e final × ingressos vendidos (tolerância de 5 a 10; mais de 20 é alerta de fraude).
5. **Comissões**: registrar o valor **recebido de cada loja**. Se for menor que a comissão devida, a diferença fica como **falta de repasse**, com alerta para o próximo caixa.
6. **Revisão**: receitas − despesas = saldo; saldo físico deve ser igual ao saldo calculado.
7. **Assinaturas (confirmado)**: o relatório é assinado pelas **duas pessoas designadas** para o fechamento. A designação é feita durante o evento e pode ser trocada a qualquer momento; vale quem estiver designado **no momento da assinatura**. Sai um PDF com as duas assinaturas e QR de verificação.
8. **Sangria (confirmado)**: depois do fechamento, o dinheiro da tesouraria é retirado para **depósito em conta bancária** ou para **pagamento de despesas do evento** (com comprovante).
9. Depois de fechado, **não pode ser editado**; só um admin reabre. Essa regra está no manual, mas **não é garantida pelo banco** no sistema antigo.

**Fórmulas atuais** (`src/services/closureCalculationService.ts`):
- Dinheiro final = entradas − troco utilizado.
- Cartão líquido = bruto − taxa.
- Saldo financeiro = dinheiro + cartão líquido + online (**sem foods**).
- Total de vendas (relatório) = dinheiro + cartão líquido + produtos + online + foods.
- Ticket médio = (dinheiro + cartão + online) / total de ingressos (**sem foods e sem produtos**).
- Divergência vendidos × validados: alerta acima de 5%, crítico acima de 10%.

### 2.5 Caixa geral, contas bancárias e repasse à administração
- Receita total = Σ fechamentos. Saldo = receita − despesa. Saldo acumulado = saldo − Σ repasses à administração.
- Sugestão de repasse = saldo acumulado − **caixa mínimo**, que é **configurado por evento** (confirmado).
- **Contas bancárias (confirmado)**: são cadastradas e alteradas durante o evento. É possível fazer sangria/transferência de uma conta para outra. Uma conta nunca é apagada, só desativada, para não perder o histórico.

## 3. Regras que DEVEM ser mantidas

| # | Regra |
|---|-------|
| R1 | Valores de venda online são os **exatos recebidos da Zet**. A taxa nunca é recalculada. A **receita do evento é o líquido** (`totalValue − totalTax`); a taxa é da Zet. |
| R2 | Idempotência por `order.uuid`: um pedido corresponde a uma venda. |
| R3 | Estorno online: pode ser **parcial** (por ingresso); o evento devolve **só o preço do ingresso** (o líquido); a taxa da Zet não é estornada. Estorno na bilheteria: sempre **total**. |
| R4 | Cortesia = venda com valor zero, contada como ingresso e fora da receita. |
| R5 | Comissão de food = `vendas × %` **da própria loja** (percentual individual, com vigência), **arredondada a centavos uma única vez**. |
| R6 | A **loja paga a comissão ao evento, diariamente**. O repasse é distribuído **FIFO** entre os dias pendentes. |
| R6a | Pagamento a menor = **falta de repasse**: continua devida, gera alerta e deve ser paga no próximo caixa. Baixa só por admin, com motivo. |
| R7 | Foods ficam fora do saldo da bilheteria e do ticket médio. |
| R8 | Produtos ficam dentro da bilheteria e fora do ticket médio. |
| R9 | Fechamento diário exige conferência física e a assinatura das **duas pessoas designadas** no momento da assinatura (designação alterável a qualquer momento). |
| R10 | Fechamento aprovado é imutável; só um admin reabre, com motivo registrado. |
| R11 | Repasse à administração preserva um **caixa mínimo configurado por evento**. |
| R11a | Contas bancárias podem ser cadastradas e alteradas durante o evento (nunca apagadas); transferência entre contas é permitida e registrada. |
| R12 | Dia operacional: **online** = 00:00–23:59:59 em America/Sao_Paulo; **bilheteria** = até o fechamento do caixa daquele dia. |
| R14 | Cada um dos 9 caixas abre com um **fundo de troco** (valor pode variar por operador) e o devolve no fechamento junto com a venda. O fundo não é receita. **Nenhum valor fica de um dia para o outro**: o fundo vai na sangria e é retirado de novo no dia seguinte; a tesouraria termina o dia zerada. |
| R15 | Após o fechamento, a **sangria** leva o dinheiro para conta bancária ou para pagamento de despesas do evento, sempre com registro. |
| R16 | Descontos só existem em **campanhas** e reduzem a receita do ingresso. O `totalValue` da Zet já vem com o desconto; `discount` é só informativo. |
| R17 | Tolerâncias do fechamento por guichê: até R$ 1,00 justificativa opcional; R$ 1,01 a R$ 50,00 obrigatória; acima de R$ 50,00 destaque para os assinantes. **Editáveis por evento.** |
| R18 | Cada guichê tem a sua maquininha PagBank (a maioria Smart); no fechamento do guichê não fica dinheiro na gaveta. Pode haver **sangria parcial durante o dia**, registrada na hora, com quem entregou e quem recebeu. |
| R19 | **O fechamento segue o dinheiro**: vendas pela data do pagamento, estornos pela data do estorno, recebimentos pela data do crédito. A catraca controla **pessoas** (entrada sem ingresso, tipo, comparecimento) e **nunca** vira valor no caixa. Receita por data de visita é só relatório contábil. Ver `11-VENDA-X-ENTRADA.md`. |
| R20 | Ingressos online são validados pela **equipe da Zet no app dela**, em fila separada; não passam pela catraca (exceto em dias de teste). A entrada online vem do **borderô da Zet**, importado todo dia. |
| R21 | O fechamento do dia mostra, separados: vendas do dia (bilheteria e online), estornos do dia, entradas do dia (bilheteria e online; online dividido em compradas hoje e antes), ticket médio de cada canal e previsão de público por data de visita. |
| R22 | Ingresso online vendido e não estornado é receita do evento, tenha sido utilizado ou não. O acerto com a Zet é: vendas − estornos − repasses recebidos. |
| R23 | **Ticket médio** = valor pago pelos ingressos de quem **entrou** no dia ÷ pessoas que entraram (geral, bilheteria e online; com e sem cortesia). A venda média do dia é um indicador comercial separado. |
| R24 | Um **robô** acessa diariamente o painel administrativo da Zet e traz vendas, estornos, borderô e relatórios para conciliar com os webhooks. Ver `13-ROBO-PAINEL-ZET.md`. |
| R25 | **Contestações** (chargeback no cartão e devolução PIX/MED) só aparecem no **extrato da Zet**, não no webhook. Debitam o valor **líquido** da venda, na data em que aparecem, e podem deixar o saldo com a Zet negativo (caso real: −R$ 975,00 em 13 vendas). Ver `14-MAPEAMENTO-PAINEL-ZET.md`. |
| R26 | A Zet também vende em **máquinas próprias** (`PIX_MAQUINA`, `CREDITO_MAQUINA`; `FISICO` no extrato), com a mesma taxa de 10%, **sem webhook**. No evento 2025 foram **1.161 pedidos, R$ 60.952,50 líquidos**. O **robô** importa essas vendas do export de Transações para o sistema, pelo mesmo caminho do webhook (`source = 'zet_export'`, canal `zet_maquina`). Ver `15-IMPORTACAO-EXPORT-ZET.md`. |
| R27 | **Validação de ingressos: a Zet é a fonte, o nosso sistema acompanha, e o painel da Zet nunca é alterado.** O robô lê a Lista de ingressos da Zet. Voucher validado na Zet e não no nosso sistema → o nosso sistema é ajustado (`used_at` = data de uso da Zet, `used_source = 'zet_painel'`). Voucher validado no nosso sistema e não na Zet (ex.: catraca em dia de teste) → exceção para análise, sem mexer na Zet. O robô **nunca** clica em Validar, Nova venda ou Solicitar saque, nem altera nada no painel. |
| R13 | Divergência de catraca: alerta acima de 5%, crítico acima de 10%; mais de 20 entradas de diferença é suspeita de fraude. |

## 4. Modelo de dados atual (resumo)

```mermaid
erDiagram
  events ||--o{ event_sessions : tem
  events ||--o{ zet_sales_master : "vendas online"
  events ||--o{ daily_closures_v2 : "fechamentos (JSON)"
  events ||--o{ boxoffice_cashier_sessions : caixas
  events ||--o{ store_daily_sales : "vendas foods"
  stores ||--o{ store_daily_sales : ""
  stores ||--o{ food_repayments : repasses
  stores ||--o{ store_cash_movements : movimentos
  daily_closures ||--o{ closure_approvals : ""
  daily_closures ||--o{ closure_signatures : ""
  orders ||--o{ order_items : ""
  orders ||--o{ tickets : ""
  bank_transactions ||--o{ commission_bank_matches : ""
```

Tabelas legadas que coexistem com dados sobrepostos: `orders`, `online_sales`, `online_sales_transactions` (DEPRECATED), `transacoes` (DEPRECATED), `imported_sales`, `zet_sales_master`, `daily_closures` e `daily_closures_v2`. **Existem pelo menos 5 representações da mesma venda online.**
