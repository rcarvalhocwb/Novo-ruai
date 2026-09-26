# 10. Perguntas em aberto

Inclui as que continuam abertas em `08-DUVIDAS.md` (número original entre parênteses). As que o prompt de planejamento já decidiu estão no fim, para registro.

## Dono do evento

| ID | Pergunta | Por que importa | Prazo |
|---|---|---|---|
| **D-01** | Em 2026 (modo "total", sem registro de venda por guichê), a receita em dinheiro de cada guichê é **contado + sangrias − fundo**, e a conferência fica no cartão por guichê (× EDI) e no total dos 9 × catraca. Está de acordo? (`01`, última seção) | Define o wizard do guichê e onde as tolerâncias R17 se aplicam | 30/09 |
| **D-02** | Quantos desenvolvedores, em tempo integral, a partir de quando? | Com 1 desenvolvedor o calendário não fecha (`05`, 5.1) | 30/09 |
| **D-03** | Data da **1ª venda de bilheteria** e das máquinas em 2026 | Define o ensaio geral e se foods vão para 11/11 | 30/09 |
| **D-04** (6) | Preço dos cartões da bilheteria por categoria (inteira, meia, social...) é fixo por evento, ou muda por dia/sessão? Há venda de produtos em todos os caixas? | Tabela `fin.box_office_prices` e a conferência × catraca | 24/10 |
| D-05 (15b) | Quem operava as máquinas da Zet em 2025, e onde? Em 2026 elas serão usadas? Se forem usadas pelos guichês, entram como meio de pagamento "Máquina Zet" no fechamento do guichê (`15`, seção 5) | Evita contar duas vezes | 24/10 |
| D-06 | O acerto de 2025 com a Zet (saldo −R$ 975,00 e os 23 pedidos sem explicação) deve ser registrado no sistema novo como saldo de abertura de um evento "2025"? | `08`, 8.3 | 30/11 |
| D-07 | Quem tem acesso ao registrador do domínio `ruailuminada.com` (para DNSSEC) e à conta Cloudflare? | F-01 | 02/10 |
| D-08 | Canal de alerta: e-mail, Telegram ou os dois? Quem recebe, e em que horário? | A-05, W-04 | 09/10 |
| D-09 | O site institucional em `ruailuminada.com` serve algo por HTTP puro? (HSTS com `includeSubDomains` quebraria) | F-01 | 06/10 |
| D-10 | Prazo de guarda dos arquivos baixados do painel da Zet (têm CPF): proposta de 5 anos após o acerto, a confirmar com o contador | LGPD e prova fiscal | 31/10 |
| D-11 (19, 20, 21) | Data exata do incidente de 2025; se o Cloudflare guarda logs daquele dia; se o sistema antigo ainda está no ar recebendo webhooks | Congelamento (`08`) e reconstrução de 2025 | 30/09 (a 21) |
| D-12 | Plano de contas: validar com o contador (`03`, 3.2) | Relatórios contábeis | 31/10 |

## Zet

| ID | Pergunta | Por que importa | Prazo |
|---|---|---|---|
| **Z-01** (15a, 17d) | Existe **usuário só leitura** para o robô (sem saque, sem nova venda, sem validação)? Pode ser um usuário separado do dono? | Robô agendado (`06`, 6.3) | 10/10 |
| **Z-02** (12) | O link do webhook aceita um token longo no caminho (`/zet/v1/<43 caracteres>`)? Ou um header fixo? | Única prova de origem, já que a Zet não assina | 07/10 |
| Z-03 (14) | Política de reenvio: quantas tentativas, intervalo, o que conta como sucesso? (72 webhooks de 2025 nunca foram reenviados com sucesso) | Dimensionar a rede de segurança do export | 07/10 |
| Z-04 (13) | IPs de origem dos webhooks | Lista de IPs no WAF | 14/10 |
| Z-05 | Evento de **teste** para 2026, com webhook apontando para homologação | W-06; nada de teste em produção | 07/10 |
| Z-06 (15c) | Os 81 pedidos PIX pagos sem data de confirmação: qual a data do pagamento? Isso vai se repetir? | Dia de caixa | 31/10 |
| Z-07 (15c) | Os 23 pedidos que saíram do export sem webhook de estorno: cancelados, estornados ou contestados, e quando? | Acerto de 2025 | 31/10 |
| Z-08 (15c) | Por que 187 vendas online de 2025 não geraram webhook? Existe log de envio? | Confiança no webhook | 31/10 |
| Z-09 (3) | No ES parcial, `eventTicketCodes` traz só os vouchers estornados? O que vem em `totalValue`/`totalTax`? | W-03 (o desenho já trata por voucher, mas o teste precisa de um exemplo real) | 10/10 |
| Z-10 (15, 16, 17c) | Existe API de consulta de pedidos? Relatório da composição de cada saque/repasse? Agenda de repasses (D+quanto)? | Conciliação bancária | 31/10 |
| Z-11 (17b; `14`, 7.3 a 7.5) | Política de cancelamento, prazos de contestação (cartão e PIX MED), quem arca, e por que as contestações PIX têm liberação em 30/06/2026. A Zet pode avisar contestação por webhook? | Valor "em risco" no extrato e data definitiva do dinheiro | 31/10 |
| Z-12 (`14`, 7.2) | Por que o dashboard geral mostra 82.413 ingressos e o do evento 82.433? | Totais de controle do robô | 31/10 |
| Z-13 (`14`, 7.6; `15`, 6.4) | O export de Transações aceita filtro por data e pode incluir cancelados/estornados com a data? Formato (xlsx/csv)? | Robô mais leve | 17/10 |
| Z-14 (`15`, 6.5 e 6.6) | Endpoint ou export com os vouchers de cada pedido (evitar abrir Detalhes um a um)? As vendas da máquina podem gerar webhook e informar o número de série da máquina? | Itens das vendas da máquina | 31/10 |

## PagBank

| ID | Pergunta | Por que importa | Prazo |
|---|---|---|---|
| **P-01** (27) | Liberar o **token da API do Extrato EDI** para o estabelecimento do evento | T-03 automático | 24/10 |
| P-02 | Nome exato do campo do número de série da maquininha no EDI (movimento transacional) | Casar transação → guichê | 24/10 |
| P-03 | Formato do CSV do portal (plano B), com um arquivo real de exemplo | `06`, 6.4 | 31/10 |
| P-04 | Prazos de liquidação por modalidade (débito, crédito, PIX) contratados | "A receber PagBank" | 31/10 |

## Time das catracas (Conexão Topdata)

| ID | Pergunta | Por que importa | Prazo |
|---|---|---|---|
| **CT-01** | Quando acontece o ensaio `HIL-STACK-01` e quando a Fase 2 (motor de decisão) fica pronta? | RS-05; ensaio conjunto C-05 | 09/10 |
| CT-02 | Aceitam o contrato v1 de `16`, seção 4, com as mudanças deste plano: dia operacional calculado na nuvem; `GET /ingressos` vazio em dias normais (a catraca não aceita QR da Zet fora de dia de teste); sem aviso de consumo à Zet; sem venda de balcão em 2026? | C-02, C-03 | 16/10 |
| CT-03 | Perfil do número do cartão (12 ou 14 dígitos, zeros à esquerda) depois da bancada | Categorias e cartões bloqueados | 24/10 |
| CT-04 | As 5 TopFit 4 têm urna e leitor de QR? | Operação da porta | 24/10 |
| CT-05 | Um PC com as 5 catracas no evento, confirmado? Qual internet ele terá? | Latência do painel ao vivo | 24/10 |
| CT-06 | Data para o ensaio conjunto em homologação | C-05 | 16/10 |

## Já decididas (registro)

| Pergunta | Decisão | Fonte |
|---|---|---|
| (15d-a) Quem recebe o webhook da Zet | **Só o sistema novo.** O relé das catracas não é usado; as catracas puxam do contrato v1 | Prompt de planejamento, "Integração com o middleware" |
| (15d-b) A catraca dá baixa na Zet? | **Não.** Nada é alterado na Zet (R27); não existe aviso de consumo | Decisão 5 e escopo 2026 |
| (15d-c) Venda de balcão no PC das catracas | **Não em 2026** (opção C, como hoje); 2027 | `16`, seção 3.3 |
| (11) Assinatura da Zet | A Zet não assina; token na URL | `08` |
