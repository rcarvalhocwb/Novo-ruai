# Assistente de fechamento da bilheteria (chat com IA)

## 1. O que existe hoje e o que o código faz de fato

A descrição do assistente (wizard `BoxOfficeClosureWizard` + chat com a edge function `cash-closure-assistant`) é boa como ideia. O código, porém, não faz o que a descrição diz em vários pontos:

| Descrição | O que o código faz | Onde |
|---|---|---|
| "Esperado = Troco + Receitas − Despesas/Sangrias" | `esperado = troco + entradas − turnstileTotalValue − despesas`. **Subtrai o valor da catraca** do dinheiro esperado. Isso não tem sentido contábil: a catraca conta entradas de pessoas, não tira dinheiro do caixa. | `src/hooks/useBoxOfficeClosureAI.ts:70-73` |
| Conferência do dinheiro físico | "Entradas" soma **todos** os movimentos de receita, inclusive cartão e PIX, e compara com a **contagem de cédulas**. Cartão e PIX nunca estão na gaveta. | `useBoxOfficeClosureAI.ts:61-73` |
| "Caixa conciliado se \|diferença\| < R$ 1,00" | Soma em float e esconde até R$ 0,99 por fechamento. Com 9 caixas, até R$ 8,91 por dia somem sem registro. | `useBoxOfficeClosureAI.ts:75` |
| Comparação com a média dos últimos 7 dias | O histórico é enviado como `null` no wizard principal; a comparação histórica não está implementada. | `src/components/admin/CashClosureWizard.tsx:162,735` |
| Validação da catraca por caixa | A catraca registra **todas** as entradas do dia (online + bilheteria). Não dá para atribuir giros de catraca a um guichê específico. | Regra de negócio |
| "Falta no caixa: taxa de cartão não deduzida" | A taxa do PagBank é descontada na liquidação da maquininha e nunca afeta o dinheiro da gaveta. Essa hipótese confunde o operador. | Prompt/mensagens |
| Troco comparado com média de 7 dias | O fundo de troco **varia por operador** (confirmado). O valor certo é o que a tesouraria entregou na abertura, e é exato, não uma média. | Regra de negócio |

**Problemas de segurança e custo** da função `cash-closure-assistant`:
- Não verifica o papel do usuário (está entre as funções de S-04). Qualquer um com a chave pública do app pode chamá-la e **gastar créditos da API de IA**.
- Aceita do navegador mensagens com `role: 'system'` (`index.ts:5,184`). Qualquer usuário pode reescrever as instruções da IA (injeção de prompt).
- O contexto (valores, histórico) é montado **no navegador** e enviado pronto. A IA confia em números que o cliente pode alterar.
- `temperature: 0.7`: respostas variáveis para uma tarefa que precisa ser exata.

## 2. Princípio do novo desenho

**A IA orienta; o banco calcula e decide.**

- Todo número (esperado, diferença, totais por meio de pagamento, ingressos vendidos) é calculado **no banco**, a partir do livro-razão e dos registros da sessão do caixa. É determinístico e testável.
- A IA recebe esses números **prontos**, montados no servidor, e só explica, orienta, levanta hipóteses e sugere o que conferir. Ela **nunca grava** nada nem altera valores.
- O veredito (conciliado, falta, sobra) vem da regra do sistema, **não da IA**.
- Sem IA disponível (queda do provedor, custo), o fechamento funciona igual; o chat é um complemento.

## 3. Fechamento por guichê (1 a 9)

Cada guichê fecha **separadamente**, na sessão do seu operador. O fechamento do dia só acontece com os 9 fechados.

### Etapa 1: abertura (conferência do fundo)
- O fundo entregue pela tesouraria já está registrado na abertura da sessão (valor por operador). O operador **confirma** o que recebeu.
- Divergência entre o registrado e o recebido: **bloqueia** a sessão até ser resolvida (é erro de entrega, não de venda).

### Etapa 2: vendas por meio de pagamento
- **Dinheiro**: vendas em dinheiro − estornos em dinheiro (todos registrados na sessão).
- **Cartão e PIX**: total do relatório da maquininha do guichê (identificada pelo número de série) comparado com o total importado do PagBank daquele terminal. É uma conferência **separada** da gaveta.

### Etapa 3: ingressos (depende do modo de controle do evento)

Hoje **não existe controle de quantos ingressos cada guichê vendeu**. Por isso o sistema tem dois modos, escolhidos na configuração do evento (`box_office_ticket_control`). A conferência dos ingressos muda conforme o modo; a conferência do **dinheiro** de cada guichê (etapas 4 e 5) é igual nos dois.

**Modo "total da bilheteria" (padrão, é o que existe hoje)**
- Cada guichê fecha só o **dinheiro** (gaveta) e a **maquininha**. Não há contagem de ingressos por guichê.
- Os ingressos são conferidos **uma vez, no fechamento do dia**, para os 9 guichês juntos:
  - **receita da bilheteria** = Σ dos 9 guichês (dinheiro + cartão + PIX − estornos);
  - **receita esperada pela catraca** = Σ (**usos consumidos** na catraca no dia, pela categoria **fotografada na passagem** × preço do tipo). Cortesia conta R$ 0,00. **Não se contam cartões distintos**: o cartão da bilheteria é um recipiente, revendido várias vezes no mesmo dia (ciclo de uns 20 minutos), então um cartão pode ser três entradas pagas. A tentativa repetida no mesmo cartão já é barrada pela urna e pelo intervalo de reuso, e só a passagem consumida entra na conta (ver `16-INTEGRACAO-CATRACAS.md`);
  - as duas têm de bater. A diferença aparece em valor e em %.
- O que explica uma diferença: cartão vendido que ainda não passou na catraca (diferença positiva, normal e pequena), tipo errado (meia vendida como inteira), venda sem registro de pagamento, ou cortesia não registrada.
- Limites (configuráveis): até 5% alerta; acima de 10% crítico. É uma **conferência**: nunca altera o valor do caixa, que é sempre o contado e o registrado na maquininha.

**Modo "por guichê" (opcional, se o evento implantar o controle)**
- Cada guichê recebe um lote de cartões por tipo na abertura (quantidade, ou faixa de números dos cartões RFID) e devolve os restantes no fechamento.
- Cartões vendidos por tipo = iniciais − restantes. **Receita esperada pelos ingressos** = Σ (vendidos × preço do tipo) + produtos, e ela tem de ser igual a **dinheiro + cartão + PIX** daquele guichê. Assim se descobre **em qual guichê** está a diferença.
- A conferência total com a catraca (modo anterior) **continua** existindo, agora também por tipo: cartões vendidos nos 9 guichês × entradas na catraca.
- Se os cartões forem ligados ao guichê na venda (leitura do RFID no guichê, ou app na maquininha Smart), o controle por guichê vem automático, sem contagem manual.

### Sangria parcial (durante o dia, registrada na hora)
Quando o guichê acumula dinheiro, pode haver retirada antes do fechamento. Ela é registrada **no momento da retirada**:
- valor contado, quem entregou (operador) e quem recebeu (tesouraria), com confirmação das duas pessoas no sistema;
- gera o lançamento Caixa do guichê → Tesouraria na hora, então o "dinheiro esperado na gaveta" já desconta a retirada automaticamente;
- opcionalmente, recibo impresso ou foto do envelope lacrado.

Sangria que não foi registrada aparece como falta no fechamento. É exatamente a hipótese que o assistente sugere primeiro nesse caso.

### Etapa 4: contagem física
- Contagem por cédula e moeda (a soma é calculada pelo sistema) e foto da contagem e do relatório da maquininha, guardadas com hash e vinculadas à sessão.

### Etapa 5: veredito do guichê
- **Dinheiro esperado na gaveta** = fundo de troco + vendas em dinheiro − estornos em dinheiro − sangrias parciais do dia (se houver).
- **Diferença** = contado − esperado, **em centavos**.
- A diferença, qualquer que seja, **vira lançamento** (quebra ou sobra) no livro-razão. Nenhum valor some.

### Catraca (no fechamento do dia, não por guichê)
- Receita total dos 9 guichês × receita esperada pelas entradas RFID da bilheteria (etapa 3, nos dois modos).
- Entradas da catraca no dia × ingressos válidos para o dia (online com visita no dia + bilheteria). Alerta acima de 5%, crítico acima de 10% (regra atual mantida).

### Fechamento do dia: dados da Zet
Antes das assinaturas, o wizard oferece o botão **Sincronizar com a Zet**. Ele roda o robô e acrescenta ao relatório o bloco "Zet no dia": vendas online, vendas na máquina da Zet, estornos, contestações, entradas online e divergências. O online fica marcado como parcial até a meia-noite, e o fechamento **não trava** se a Zet estiver fora do ar. Ver `13-ROBO-PAINEL-ZET.md`, seção 5a.

## 4. Regra de tolerância (aprovada)

A tolerância não serve para "esconder" diferença; ela só define **o quanto de justificativa e aprovação** cada diferença exige. Os valores abaixo foram aprovados como padrão e ficam **editáveis numa tela de configurações do evento** (tabela `fin.event_settings`, alterações registradas na auditoria):

| Diferença do guichê | O que acontece |
|---|---|
| R$ 0,00 | Conciliado ✅ |
| até R$ 1,00 (padrão) | Lançada como quebra/sobra; justificativa opcional (ex.: arredondamento de troco) |
| de R$ 1,01 a R$ 50,00 (padrão) | Lançada; **justificativa obrigatória** do operador |
| acima de R$ 50,00 (padrão) | Lançada; justificativa obrigatória **e** aparece em destaque para as duas pessoas que assinam o fechamento do dia, que precisam comentar antes de assinar |
| Diferença recorrente do mesmo operador (ex.: 3 dias seguidos) | Alerta de padrão para a gestão |

## 5. O que o assistente de IA faz em cada etapa

| Etapa | Orientação | Dados que recebe (montados no servidor) |
|---|---|---|
| 1 | Confirmar o fundo recebido | Fundo registrado na abertura |
| 2 | Conferir relatório da maquininha × PagBank | Totais por meio de pagamento do guichê |
| 3 | Explicar diferenças entre ingressos vendidos e receita | Cartões iniciais e restantes, preços, receita esperada × recebida |
| 4 | Guiar a contagem por cédula | Soma calculada pelo sistema |
| 5 | Levantar hipóteses para a diferença (sangria não lançada, estorno em dinheiro não registrado, troco dado errado, cortesia cobrada, erro de contagem) | Esperado, contado, diferença e histórico do **mesmo guichê e operador** (calculado no banco, por dia operacional) |

Regras da integração com a IA:
- A função só aceita usuário autenticado com papel de operador ou gestor, e **só** para a sessão de caixa dele.
- O navegador envia apenas `session_id` e a pergunta. O servidor monta o contexto a partir do banco. Mensagens com papel `system` vindas do cliente são descartadas.
- Limite de uso por usuário e por dia (controle de custo); temperatura baixa.
- Toda conversa fica registrada junto da sessão do caixa (auditoria), sem dados pessoais de clientes.
- A IA não tem ferramentas de escrita. Se sugerir um lançamento, o operador faz pelo formulário, que passa pelas regras normais.

## 6. Tabelas e funções (complemento ao `03-ARQUITETURA-ALVO.md`)

```sql
-- modo de controle dos ingressos da bilheteria
alter table fin.event_settings
  add column box_office_ticket_control text not null default 'total'
    check (box_office_ticket_control in ('total','por_guiche')),
  add column box_office_alert_bps    int not null default 500,    -- 5%: alerta
  add column box_office_critical_bps int not null default 1000;   -- 10%: crítico

-- contagem de cartões de ingresso por categoria na sessão do caixa (só no modo 'por_guiche')
create table fin.cashier_ticket_counts (
  session_id        uuid not null references fin.cashier_sessions(id) on delete restrict,
  category          text not null,             -- inteira, meia, social, ...
  unit_price_cents  bigint not null check (unit_price_cents >= 0),
  initial_qty       int not null check (initial_qty >= 0),
  remaining_qty     int check (remaining_qty >= 0 and remaining_qty <= initial_qty),
  primary key (session_id, category)
);

-- tolerâncias por evento
alter table fin.event_settings
  add column cash_diff_optional_cents  bigint not null default 100,   -- até R$ 1,00: justificativa opcional
  add column cash_diff_highlight_cents bigint not null default 5000;  -- acima de R$ 50,00: destaque para os assinantes

-- conferência do guichê, toda calculada no banco
create or replace function fin.cashier_check(p_session uuid)
returns table (
  expected_cash_cents   bigint,   -- saldo da conta do caixa no livro-razão (fundo + dinheiro − estornos − sangrias)
  counted_cash_cents    bigint,
  cash_diff_cents       bigint,
  tickets_revenue_cents bigint,   -- Σ vendidos × preço
  level                 text      -- conciliado | opcional | justificar | destacar
)
language sql stable as $$
  with s as (
    select cs.*, a.id as account_id
      from fin.cashier_sessions cs
      join fin.accounts a on a.event_id = cs.event_id
                         and a.counterparty = 'cashier:' || cs.cashier_number
     where cs.id = p_session
  ), bal as (
    select coalesce(sum(case p.side when 'D' then p.amount_cents else -p.amount_cents end), 0) as cents
      from s
      join fin.postings p on p.account_id = s.account_id
      join fin.journal_entries e on e.id = p.entry_id
     where e.source_type = 'cashier_session' and e.source_id = p_session::text
       and e.kind <> 'cashier_close'            -- a entrega à tesouraria não entra no esperado
  ), tk as (
    select coalesce(sum((initial_qty - coalesce(remaining_qty, initial_qty)) * unit_price_cents), 0) as cents
      from fin.cashier_ticket_counts where session_id = p_session
  ), cfg as (
    select coalesce(es.cash_diff_optional_cents, 100) as opt, coalesce(es.cash_diff_highlight_cents, 5000) as hi
      from s left join fin.event_settings es on es.event_id = s.event_id
  )
  select bal.cents,
         s.counted_cash_cents,
         s.counted_cash_cents - bal.cents,
         tk.cents,
         case
           when s.counted_cash_cents is null then 'pendente'
           when s.counted_cash_cents = bal.cents then 'conciliado'
           when abs(s.counted_cash_cents - bal.cents) <= cfg.opt then 'opcional'
           when abs(s.counted_cash_cents - bal.cents) <= cfg.hi then 'justificar'
           else 'destacar'
         end
    from s, bal, tk, cfg
$$;
```

No modo `por_guiche`, a receita dos ingressos (`tickets_revenue_cents`) é comparada com dinheiro + cartão + PIX do guichê na tela da etapa 3. No modo `total`, ela vem zerada e a conferência dos ingressos é feita pela função abaixo, para a bilheteria inteira.

```sql
-- conferência da bilheteria inteira com a catraca (modo 'total'; no modo 'por_guiche' também roda)
-- receita_guiches: Σ das sessões do dia (dinheiro + cartão + PIX − estornos), vinda do livro-razão
-- esperado_catraca: usos consumidos da bilheteria no dia, pela categoria fotografada na passagem × preço do tipo
-- (o cartão é revendido várias vezes no dia: contar cartões distintos subconta)
create or replace function fin.box_office_check(p_event uuid, p_day date)
returns table (
  category             text,
  entries              int,
  unit_price_cents     bigint,
  expected_cents       bigint,
  revenue_total_cents  bigint,   -- repetido em todas as linhas: receita dos 9 guichês
  diff_total_cents     bigint,   -- receita − Σ esperado (positivo: vendido que não entrou)
  diff_bps             int,
  level                text      -- ok | alerta | critico
)
language sql stable as $$
  with entr as (
    select a.category, count(*)::int as entries, pr.unit_price_cents
      from access.ticket_use_attempts a            -- espelho do que a borda das catracas sobe
      join fin.box_office_prices pr on pr.event_id = p_event and pr.category = a.category
                                   and p_day <@ pr.valid_during
     where a.event_id = p_event and a.provider = 'bilheteria' and a.outcome = 'consumido'
       and a.business_date = p_day
     group by a.category, pr.unit_price_cents
  ), rev as (
    select coalesce(sum(case p.side when 'D' then p.amount_cents else -p.amount_cents end), 0) as cents
      from fin.postings p
      join fin.journal_entries e on e.id = p.entry_id
      join fin.accounts a on a.id = p.account_id
     where a.event_id = p_event and a.code in ('4.1.02','4.9.02')      -- receita e estornos da bilheteria
       and e.business_date = p_day
  ), tot as (select sum(entries * unit_price_cents) as exp from entr),
  cfg as (select box_office_alert_bps as a, box_office_critical_bps as c from fin.event_settings where event_id = p_event)
  select entr.category, entr.entries, entr.unit_price_cents, entr.entries * entr.unit_price_cents,
         -rev.cents, -rev.cents - tot.exp,
         case when tot.exp = 0 then null else (abs(-rev.cents - tot.exp) * 10000 / tot.exp)::int end,
         case when tot.exp = 0 then 'ok'
              when abs(-rev.cents - tot.exp) * 10000 > cfg.c * tot.exp then 'critico'
              when abs(-rev.cents - tot.exp) * 10000 > cfg.a * tot.exp then 'alerta'
              else 'ok' end
    from entr, rev, tot, cfg
$$;
```
(A receita é crédito, por isso o sinal invertido. `access.ticket_use_attempts` é o espelho das tentativas que o sistema das catracas (Conexão Topdata) sobe para a nuvem; ver `16-INTEGRACAO-CATRACAS.md`.)

## 7. Integração com as maquininhas PagBank (uma por guichê)

Cada guichê tem a sua maquininha. O sistema antigo usava a API de transações do PagSeguro (`ws.pagseguro.uol.com.br/v4/transactions`, em `fetch-pagseguro-sales`), que é voltada a pagamentos online, e dependia de importação de CSV.

**Recomendação: API do Extrato EDI do PagBank** (`https://edi.api.pagbank.com.br/movement/v3.00/{transactional|financial}/{AAAA-MM-DD}`), documentada em developer.pagbank.com.br:
- Traz cada transação da conta em JSON, com valor bruto, taxa, líquido, meio de pagamento, data prevista de pagamento e identificação da maquininha (confirmar o nome exato do campo do número de série no manual EDI).
- Acesso por usuário (número do estabelecimento) e **token EDI**, que é solicitado ao PagBank.
- **Os dados saem em D+1**, não em tempo real.

Como isso se encaixa no fechamento:

| Momento | Fonte | O que confere |
|---|---|---|
| No fechamento do guichê (mesmo dia) | Relatório impresso ou do app da maquininha, digitado ou fotografado pelo operador | Total de cartão e PIX do guichê |
| No dia seguinte, automático | API EDI, por número de série da maquininha → guichê | Cada transação, com a **taxa real** (MDR). O que não bater com o que o operador declarou vira exceção |
| Na liquidação (D+x) | API EDI financeira + extrato bancário | "A receber PagBank" zera quando o dinheiro cai na conta |

Cadastro: tabela de maquininhas (`número de série → guichê`, com vigência, porque uma maquininha pode trocar de guichê).

**Tempo real nas maquininhas Smart (a maioria do parque, confirmado)**: as maquininhas PagBank Smart (Android) aceitam um aplicativo próprio via SDK de integração do PagBank. Com ele, a **venda do ingresso e o pagamento acontecem no mesmo terminal**: o sistema registra cada venda, com o tipo de ingresso e o meio de pagamento, na hora. Isso elimina a digitação e a conferência de cartão no fechamento.

Estratégia recomendada, já que nem todas são Smart:
1. **Primeiro, API EDI para todas** as maquininhas (Smart ou não): uma única forma de conferência, com a taxa real, em D+1. Resolve a conciliação de cartão já na primeira versão.
2. **Depois, aplicativo nas Smart**: os guichês com Smart passam a registrar venda + pagamento em tempo real. A API EDI continua rodando por baixo como conferência (o que o app registrou tem de bater com o que o PagBank liquidou).
3. **Guichês sem Smart** seguem com o fluxo manual + EDI. Se possível, trocar essas maquininhas por Smart com o tempo, para padronizar os 9 guichês.

## 8. Conciliação com a catraca (controle de pessoas, não de dinheiro)

A ideia de usar a catraca para conferir as vendas está certa: **toda entrada tem de corresponder a um ingresso pago** (ou a uma cortesia registrada). Mas multiplicar o número de acessos por um valor médio dá uma conta fraca, porque:
- a catraca não sabe o preço: há inteira, meia (R$ 18), solidário (R$ 25), Gazeta e cortesias no mesmo giro;
- quem comprou online pode entrar em outro dia (data da venda × data da visita);
- há reentradas, giros negados e passagens de staff.

**Forma melhor: conciliar por ingresso e por quantidade, e só então por valor.** O sistema já tem o que precisa:
- **Bilheteria**: o cartão RFID entregue ao cliente tem tipo (MEIA, INTEIRA...), e cada passagem registra o cartão (`access_events.card_id`). Então se sabe **quantas entradas de cada tipo** vieram da bilheteria no dia.
- **Online**: o voucher da Zet é validado na catraca (QR), e o próprio payload da Zet traz `used` e `dateTimeUsed`. Então se sabe **quais vouchers** entraram no dia.

| Nível | Conferência | Resultado esperado |
|---|---|---|
| 1. Por ingresso | Cada passagem autorizada corresponde a um cartão RFID vendido naquele dia ou a um voucher válido para aquela data | Passagem sem ingresso = alerta (possível fraude ou cartão não devolvido) |
| 2. Por tipo (bilheteria, só no modo por guichê) | Entradas por tipo × cartões vendidos por tipo nos 9 guichês | Iguais, descontadas as reentradas |
| 3. Por valor (**só bilheteria, total dos 9 guichês**; é a conferência principal no modo total) | Σ (usos consumidos da bilheteria, pela categoria fotografada na passagem × preço do tipo) × receita dos 9 guichês (dinheiro + cartão + PIX − estornos) | Igual; a diferença aponta cartão vendido que não entrou, tipo errado (meia vendida como inteira) ou venda sem registro. Nunca é por guichê, a não ser no modo por guichê |
| 4. Online por data de visita | Vouchers usados no dia × vouchers com visita no dia | Não comparecimento é normal; entrada sem voucher válido, não |

**Importante (ver `11-VENDA-X-ENTRADA.md`)**: a catraca é um controle **de pessoas**, não de dinheiro. O nível 3 vale **só para a bilheteria**, porque ali a compra e a entrada acontecem no mesmo dia; e mesmo assim é uma conferência que gera alerta, **nunca** um valor que entra ou sai do caixa. No online, 39% dos ingressos são usados em outro dia, então entradas online **nunca** são convertidas em valor no fechamento.

Alertas mantidos: divergência de quantidade acima de 5% = alerta; acima de 10% = crítico.
