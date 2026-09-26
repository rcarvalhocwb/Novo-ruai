# Checklists

## A. Fechamento financeiro diário

**Antes de abrir o wizard**
- [ ] Todos os webhooks Zet do dia processados (fila vazia, nenhum `failed` ou `dead`).
- [ ] Relatório Zet de D−1 importado e conciliado (diferença R$ 0,00 ou exceções com responsável).
- [ ] Vendas das maquininhas do dia anterior importadas pela API EDI do PagBank (D+1) e conferidas por guichê.
- [ ] Extrato bancário (OFX) importado até o dia.

**Bilheteria (cada um dos 9 caixas)**
- [ ] Fundo de troco entregue e registrado na abertura, com o operador e o valor dele (Tesouraria → Caixa N).
- [ ] Cartões de ingresso iniciais e restantes contados.
- [ ] Dinheiro contado por **duas pessoas**, valor declarado; fundo de troco devolvido junto com a venda.
- [ ] Estornos do caixa (sempre totais) registrados com o meio de pagamento.
- [ ] Sangrias parciais do dia registradas na hora (quem entregou, quem recebeu, valor).
- [ ] Total da maquininha (relatório do POS) igual ao total PagBank importado.
- [ ] Diferença esperado × declarado: se ≠ 0, lançamento de quebra ou sobra **com justificativa**.

**Online**
- [ ] Borderô da Zet do dia importado (validações por voucher ou por tipo).
- [ ] Vendas Zet do dia (sistema) = relatório Zet.
- [ ] Estornos do dia conferidos.
- [ ] Repasses Zet recebidos casados com "A receber Zet".

**Foods**
- [ ] Vendas de todas as lojas lançadas.
- [ ] Comissões calculadas com o percentual vigente de cada loja (sem edição manual do valor).
- [ ] Repasse de cada loja registrado pelo valor **efetivamente recebido**; alocado FIFO; excedente em crédito da loja.
- [ ] Lojas com **falta de repasse** (pagaram menos) listadas com valor e dias em aberto, para cobrança no próximo caixa.

**Catraca (controle de pessoas; não entra no valor do caixa)**
- [ ] Nenhuma entrada sem ingresso válido para a data (cartão RFID vendido no dia ou voucher com visita no dia).
- [ ] Bilheteria: entradas por tipo × cartões vendidos por tipo; divergência acima de 5% justificada.
- [ ] Online (pelo borderô): entradas do dia, divididas em compradas hoje × antes; ingressos com visita hoje não utilizados listados.

**Encerramento**
- [ ] Sincronização com a Zet feita (botão no wizard) e bloco "Zet no dia" revisado; online marcado como parcial até a meia-noite. Se a Zet estiver fora, registrar e seguir.
- [ ] Revisão do resumo (receitas, despesas, saldo por conta).
- [ ] Os 9 caixas fechados.
- [ ] Assinatura das **duas pessoas designadas** (vigentes no momento da assinatura) sobre o mesmo conteúdo.
- [ ] Dia travado; PDF com hash e QR arquivado.
- [ ] Sangria registrada (venda + fundos de troco): Tesouraria → conta bancária escolhida (depósito) ou Tesouraria → Despesa (com comprovante). Transferências entre contas também registradas.
- [ ] Tesouraria **zerada** no fim do dia (nada fica de um dia para o outro).

## B. Segurança para produção

**Acesso e autorização**
- [ ] Nenhuma policy `USING (true)` sem `TO service_role` (`select * from pg_policies where qual = 'true' or with_check = 'true'`).
- [ ] RLS habilitado em **todas** as tabelas do schema exposto; padrão *deny*.
- [ ] Só o schema `api` exposto no PostgREST.
- [ ] Toda edge function verifica o papel do usuário (não basta `verify_jwt`).
- [ ] Nenhuma função devolve segredo ao cliente.
- [ ] Usuário da aplicação sem `DELETE`/`TRUNCATE`/`DROP` em `fin`, `integ`, `recon`, `audit`.
- [ ] FKs financeiras `ON DELETE RESTRICT`; cadastros com `archived_at`.
- [ ] MFA obrigatório para `admin` e `aprovador`.
- [ ] Separação de funções: quem lança não aprova; quem aprova não reabre.

**Integração Zet**
- [ ] Token secreto no endereço do webhook (a Zet não assina), comparado em tempo constante; trocado desde o incidente.
- [ ] Entrada do webhook na borda (Cloudflare Worker + fila), **sem depender do banco** para responder.
- [ ] Limite de corpo de 64 KB; WAF e rate limit ativos; lista de IPs da Zet (se disponível).
- [ ] Endpoint responde em menos de 100 ms (p95) mesmo com o banco fora do ar (teste de queda).
- [ ] Validação de conteúdo: líquido do pedido = preços de tabela dos vouchers − desconto de campanha; divergência vira exceção.
- [ ] Worker idempotente com máquina de estados e fila morta com alerta.

**Dados e recuperação**
- [ ] PITR ativo (RPO ≤ 5 min).
- [ ] `pg_dump` diário completo em bucket externo com *object lock*; a chave de escrita não apaga.
- [ ] Restauração testada no último mês (data e responsável registrados).
- [ ] `webhook_inbox`, `journal_entries`, `postings` e `audit.log` append-only (teste automatizado).
- [ ] Migrations só alteram schema (revisão obrigatória; proibido `DELETE FROM` em migration).

**Operação**
- [ ] CORS restrito ao domínio do app.
- [ ] Segredos no Vault ou nas variáveis do projeto, nunca no repositório (varrer com `gitleaks`).
- [ ] Alertas: fila parada, assinaturas inválidas acima de 1%, exceção de conciliação aberta há mais de 24 h, pico de requisições.
- [ ] Logs com `correlation_id`, retidos por 90 dias ou mais.
- [ ] Dados pessoais (CPF, telefone) mascarados em relatórios e logs (LGPD).
- [ ] Runbook de incidente: quem desliga o quê, como girar os segredos, como restaurar.
