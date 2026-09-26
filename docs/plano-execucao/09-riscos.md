# 9. Riscos

Probabilidade (P) e impacto (I): **A** alto · **M** médio · **B** baixo.

| ID | Risco | P | I | Mitigação | Gatilho para agir |
|---|---|---|---|---|---|
| RS-01 | Time menor que 2 desenvolvedores em tempo integral | M | A | Cortes na ordem de `06`, 6.1; bilheteria em papel com as mesmas regras até o sistema ficar pronto | Até 30/09 sem o 2º desenvolvedor |
| RS-02 | Webhook atrasa além de 13/10 | B | A | Borda (1,5 pd) em produção em 09/10; export como rede de segurança (`06`, 6.2) | W-01 não pronto em 08/10 |
| RS-03 | Zet não cadastra o link novo a tempo, ou não aceita token no caminho (Z-02) | M | M | Export diário por upload cobre 100% dos pedidos pagos; perde-se só o tempo real. Se o token no caminho não for aceito, token em header fixo, se a Zet oferecer | Sem resposta da Zet até 07/10 |
| RS-04 | Zet não libera usuário só leitura | A | M | Robô só no botão, acompanhado; ou upload manual (`06`, 6.3) | Sem resposta até 17/10 |
| RS-05 | Lado das catracas não fica pronto (ensaio `HIL-STACK-01` e Fase 2 do Conexão Topdata ainda não feitos) | A | M | Conferência bilheteria × catraca fica pendente; importação por arquivo; o dinheiro não depende dela (`06`, 6.5) | Ensaio de bancada não feito até 16/10 |
| RS-06 | PagBank não libera o token EDI | M | M | CSV do portal no mesmo importador (`06`, 6.4) | Sem token até 24/10 |
| RS-07 | Data de abertura da bilheteria antes de 14/11 | M | A | Antecipar foods e PDF (já proposto para 11/11); cortar A-07; se abrir antes de 07/11, os primeiros dias fecham em papel e são lançados depois | Data confirmada (D-03) |
| RS-08 | Mudança de layout ou de formato do export da Zet no meio da temporada | M | M | Validação de cabeçalho e de soma antes de importar; falha e alerta, nunca importação pela metade; upload manual enquanto corrige | Execução do robô `falhou` por formato |
| RS-09 | Reenvio em massa da Zet (novo apagão de algum provedor) | B | B (era A em 2025) | Borda + fila + consumidor com concorrência limitada; carga testada a 200 req/s com banco fora | — |
| RS-10 | Webhook forjado por quem descobrir a URL | B | A | Token de 43 caracteres, comparação em tempo constante, WAF, IP real registrado para lista futura, validação de conteúdo pelos preços, conciliação diária com o export ("venda só no sistema" vira exceção) | Pico de 404 no `ingest`; venda sem par no export |
| RS-11 | Vazamento de segredo (token, senha do painel da Zet) | M | A | Só em cofre/variáveis; `gitleaks` no CI; rotação documentada; nada por chat ou planilha | Qualquer segredo visto fora do cofre |
| RS-12 | Dado pessoal entrar no repositório ou em logs | M | A | Varredura `pii` no CI; export original cifrado no R2; staging sem CPF/e-mail/celular; logs com `correlation_id` | Achado da varredura |
| RS-13 | Diferença de centavos por regra implementada fora de `money`/SQL | B | A | Lint proíbe `parseFloat`/`toFixed`/`Math.round`; teste de coluna `bigint`; somas só no banco; ensaio geral exige R$ 0,00 | Qualquer diferença no ensaio |
| RS-14 | Semântica do fechamento da bilheteria em 2026 (sem esperado por guichê, `01`) não ser a que a equipe espera | M | M | Validar com o dono em 30/09 (D-01); mostrar o exemplo do `01` no treinamento | Resposta de D-01 |
| RS-15 | Custo do Supabase maior que o previsto (PITR, compute) | B | B | Tabela de `02`, 2.5; desligar PITR só depois do acerto final | Fatura acima de US$ 250 |
| RS-16 | Retenção da fila da Cloudflare (4 dias padrão) estourar com banco fora por muito tempo | B | M | Retenção configurada no máximo; corpo já está no R2; reconciliação R2 × inbox | Banco fora > 24 h |
| RS-17 | Equipe do evento sem treino no sistema novo | M | A | Ensaio geral com operadores e assinantes reais; roteiro de 1 página por papel | — |
| RS-18 | 81 pedidos PIX sem data de confirmação (padrão de 2025) se repetirem em 2026 | M | B | Exceção "sem dia de caixa"; entra no dia da descoberta como ajuste, com nota; pergunta Z-06 | Primeira ocorrência |
| RS-19 | Voucher usado duas vezes (app da Zet + QR na catraca) se a catraca aceitar QR da Zet em dia normal | B | M | Em 2026 a catraca **não** aceita QR da Zet em dia normal (só em dia de teste); o robô aponta duplicidade no dia seguinte | Configuração da catraca |
| RS-20 | Acesso ao registrador do domínio indisponível (DNSSEC, DS) | M | B | DNSSEC pode entrar depois da abertura sem afetar o resto | Até 06/10 sem acesso |
