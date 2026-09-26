# Checklists

## A. Fechamento financeiro diário

**Antes de abrir o wizard**
- [ ] Todos os webhooks Zet do dia processados (fila vazia, nenhum `failed` ou `dead`).
- [ ] Relatório Zet de D−1 importado e conciliado (diferença R$ 0,00 ou exceções com responsável).
- [ ] CSV PagBank do dia importado.
- [ ] Extrato bancário (OFX) importado até o dia.

**Bilheteria (por caixa)**
- [ ] Troco inicial registrado na abertura.
- [ ] Cartões de ingresso iniciais e restantes contados.
- [ ] Dinheiro contado por **duas pessoas**, valor declarado.
- [ ] Total da maquininha (relatório do POS) igual ao total PagBank importado.
- [ ] Diferença esperado × declarado: se ≠ 0, lançamento de quebra ou sobra **com justificativa**.

**Online**
- [ ] Vendas Zet do dia (sistema) = relatório Zet.
- [ ] Estornos do dia conferidos.
- [ ] Repasses Zet recebidos casados com "A receber Zet".

**Foods**
- [ ] Vendas de todas as lojas lançadas.
- [ ] Comissões calculadas pela regra única (sem edição manual do valor).
- [ ] Repasses recebidos alocados (FIFO); excedente em crédito da loja.

**Catraca**
- [ ] Entradas × ingressos válidos do dia; divergência acima de 5% justificada.

**Encerramento**
- [ ] Revisão do resumo (receitas, despesas, saldo por conta).
- [ ] Assinatura de quem fecha.
- [ ] Aprovação por outra pessoa (quem fecha ≠ quem aprova).
- [ ] Dia travado; PDF com hash e QR arquivado.
- [ ] Depósito do dinheiro agendado ou realizado (lançamento Caixa → Banco).

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
- [ ] HMAC obrigatório com comparação em tempo constante.
- [ ] Token secreto na URL; segredo rotacionado desde o incidente.
- [ ] Limite de corpo de 64 KB; WAF e rate limit ativos; lista de IPs da Zet (se disponível).
- [ ] Endpoint faz 1 RPC e responde em menos de 200 ms (p95).
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
