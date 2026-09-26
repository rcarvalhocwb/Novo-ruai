# Análise do backup de webhooks da Zet

Fonte: `webhooks-zet-backup.zip` (27.641 webhooks de `webhook_logs`, fonte `comprenozet`) e `INTEGRACAO-ZET-README.md`, enviados em 26/09/2026.

Os arquivos originais contêm dados pessoais (nome, CPF, e-mail e telefone de cada comprador) e **não foram colocados no repositório**. Aqui estão só números agregados e duas planilhas sem dados pessoais:

| Arquivo | Conteúdo |
|---|---|
| `dados/zet-webhooks-resumo-diario.csv` | Por dia de pagamento (BRT): pedidos, ingressos, bruto, taxa Zet, líquido, estornos e líquido final |
| `dados/zet-webhooks-nao-processados.csv` | Os 208 webhooks que o sistema antigo **nunca conseguiu gravar**, com uuid do pedido, valores e motivo |

## 1. Números gerais

| Item | Valor |
|---|---|
| Período coberto | 22/10/2025 a 04/01/2026 (75 dias de pagamento) |
| Webhooks | 27.641 (27.398 CP, 243 ES) |
| Pedidos pagos distintos (evento 538) | **26.111** |
| Ingressos | **79.495** |
| Bruto (pago pelos clientes) | **R$ 2.274.482,45** |
| Taxa Zet | R$ 206.774,95 |
| Líquido (receita do evento) | **R$ 2.067.707,50** |
| Pedidos estornados | 226 (líquido R$ 17.975,50) |
| **Líquido final** | **R$ 2.049.732,00** |
| Formas de pagamento | PIX 20.760 · Crédito 6.873 · Crédito link 1 · Cortesia 2 |
| Maior dia | 21/12/2025: 924 pedidos, R$ 79.088,00 líquidos |

Esses totais são o que **os webhooks** dizem. Eles só viram verdade financeira depois de conciliados com o relatório da Zet e com o extrato bancário (ver seção 6).

## 2. Os dados da Zet são consistentes; o problema estava no nosso processamento

- **Nenhum valor com mais de 2 casas decimais** no JSON original.
- **Taxa exata**: em 26.109 dos 26.111 pedidos, `totalTax` é exatamente `arredondar(líquido × 10%)`, sem nenhum centavo de diferença. As 2 exceções (`11348743…` e `1bf61e84…`) são justamente os pedidos "corrigidos à mão" em `docs/FINANCIAL-CORRECTIONS-LOG.md` e precisam ser conferidos no painel da Zet.
- **Nenhum desconto** (`discount = 0` em todos) e **nenhum estorno parcial** neste período: os 226 estornos têm os mesmos vouchers e o mesmo valor do pedido original. O desenho continua preparado para os dois casos.
- **Reenvios idênticos**: 1.256 pedidos chegaram 2 vezes (4 chegaram 3 vezes e 1 chegou 5 vezes). **Em nenhum caso os valores mudaram entre um envio e outro.**

Conclusão: **a Zet sempre mandou os mesmos valores**. As divergências de centavos e a "corrupção" vieram do que o sistema antigo fazia com eles (rateio por quantidade, desconto subtraído duas vezes, sobrescritas e correções manuais; ver `02-RELATORIO-DE-PROBLEMAS.md`).

## 3. 199 vendas que o sistema antigo nunca gravou

**208 webhooks nunca foram processados com sucesso**, em nenhuma das entregas: **199 compras** (981 ingressos, **R$ 24.313,00 líquidos**) e 9 estornos.

| Motivo | Webhooks |
|---|---|
| Banco inacessível (`upstream connect error`), picos em 13/12, 18/12 (18h–19h) e 21/12 | 72 |
| `processed = false` sem erro registrado (processamento interrompido) | 56 |
| Pedido sem CPF (`customer_cpf` NOT NULL em `orders`) | 37 |
| CPF com formato diferente do esperado pelo validador | 22 |
| "No active events found" (evento não cadastrado a tempo) | 10 |
| E-mail vazio ou inválido; data de pagamento em formato inesperado | 6 |
| Estorno de pedido que o sistema não tinha | 4 |
| Outros (`FINANCIAL_WRITE_FAILED`) | 1 |

Vendas **pagas** foram recusadas por causa de **CPF ou e-mail**, campos que não têm nada a ver com dinheiro (P-19). E, quando o banco caiu, o webhook falhou e a Zet não reenviou com sucesso.

**Os payloads dessas 199 vendas estão íntegros no backup.** Elas podem ser recuperadas: a lista está em `dados/zet-webhooks-nao-processados.csv`. Antes de lançar, conferir no relatório da Zet se alguma foi importada depois por planilha.

## 4. Segurança: o que o backup mostra

1. **A assinatura não é da Zet, é do nosso próprio Worker.** O `comprenozet-webhook-proxy` (Cloudflare) calcula o HMAC de **qualquer** requisição que recebe e o repassa ao Supabase. Como a URL do Worker é pública, a assinatura prova apenas que a requisição passou pelo Worker, **não que veio da Zet**.
2. **E nem isso funcionou**: 27.368 webhooks ficaram `bypassed`, 272 sem status e **só 1 `valid`**. Ou seja, o segredo do Worker nunca bateu com o do Supabase, e o modo permissivo aceitou tudo.
3. **O IP real da Zet nunca foi registrado.** Todos os 27.636 webhooks vindos do Worker têm `client_ip = 2a06:98c0:3600::103`, que é um endereço do próprio Cloudflare. A função lia `cf-connecting-ip` (o IP do Worker) em vez de `X-Real-IP`. Consequência: o bloqueio por IP (`shouldBlockIP`) nunca protegeu nada, e não dá para montar lista de IPs da Zet a partir destes dados.
4. **Requisições que não vieram da Zet entraram como dados reais:**
   - 3 envios pelo **Postman** em 16/11/2025. O último, com o UUID de exemplo `123e4567…` e R$ 39,60, foi **processado como venda real**.
   - 5 estornos "Admin Manual Refund" em 22/10/2025, injetados pelo mesmo endpoint.
   - 35 webhooks do evento de teste 355 ("Teste rua iluminada") no banco de produção.
5. **O Worker é síncrono**: ele espera o Supabase responder para responder à Zet. Se o banco cai, a Zet recebe erro. É o oposto do "absorve picos" descrito no README.

## 5. O que muda no desenho

- **Chave do tipo de ingresso**: existem 16 grafias diferentes de descrição para as mesmas categorias (ex.: três variações de "Doador de sangue/Portadores de câncer/ID jovem…"), e 1.692 `eventsValues.id` (um por data, sessão e tipo). O de-para deve usar **`eventsValues.id`** (preço por data e sessão), agrupado numa categoria normalizada, e **nunca o texto** da descrição.
- **Preços líquidos observados** (servem para a validação de conteúdo do webhook):

  | Categoria | Líquido por ingresso |
  |---|---|
  | Inteira | R$ 36,00 (20 pedidos a R$ 50,00 e 1 a R$ 72,00: conferir datas especiais) |
  | Solidário + 1 kg de alimento | R$ 25,00 (30 pedidos a R$ 18,00) |
  | Assinante Clube Gazeta | R$ 32,50 |
  | Meia-entrada, Idosos, Crianças 6–12, Professores/Saúde, Doador de sangue/ID Jovem, PCD/Autista e acompanhante | R$ 18,00 |

- **CPF, e-mail e telefone são opcionais** no processamento financeiro. Uma venda paga nunca é recusada por dado cadastral: ela é gravada e o dado faltante vira pendência.
- **Evento não cadastrado não recusa a venda**: o webhook fica no inbox como `failed` até o de-para existir, e é reprocessado sem perda.
- **Nada de testes no endpoint de produção**: testes vão para um endpoint e um banco de homologação; o token secreto impede envios manuais.
- **Registrar o IP certo**: no Worker de borda, gravar `request.headers.get('cf-connecting-ip')` **do lado do Worker** (é o IP da Zet) junto com o corpo, para permitir montar a lista de IPs da Zet.
- **Datas**: `paymentConfirmeDate` é a data do dinheiro (dia operacional do online); `eventsDates.startDate` é a data de visita (catraca). O worker grava as duas.

## 6. Como usar o backup na reconstrução

1. O backup é **fonte F7** (`05-MIGRACAO-E-RECUPERACAO.md`) e, para o período 22/10/2025 a 04/01/2026, é **muito confiável**: payload intacto, valores consistentes, taxa exata.
2. Carregar `payloads-fieis.jsonl` no schema `recovery` e processar com o **novo worker** (idempotente). Isso já produz as vendas e os estornos do período no livro-razão.
3. Conciliar com o relatório da Zet (F2) pedido a pedido. O README cita cobertura de webhook "em torno de 30% em determinados períodos": **o que estiver no relatório e não no backup** foram vendas cujo webhook nunca chegou, e entram pelo relatório.
4. **Antes de 22/10/2025 não há webhooks no backup.** O dia do apagão da AWS (20/10/2025) e anteriores só podem ser reconstruídos pelo relatório da Zet e pelos extratos.
5. Excluir do cálculo: evento 355 (teste), envios pelo Postman e os estornos "Admin Manual Refund" (conferir cada um no painel da Zet).
6. Somar o líquido por data de repasse e comparar com os créditos da Zet no extrato bancário.
