# Plano de execução: sistema novo da Rua Iluminada (temporada 2026)

Feito a partir de `docs/analise-iluminadarua2025/` (fonte da verdade, regras R1 a R28) e do repositório `conexao-topdata`, em resposta a `17-PROMPT-PLANEJAMENTO-EXECUCAO.md`. Data: 26/09/2026.

| # | Arquivo | Conteúdo |
|---|---|---|
| 1 | [`01-resumo-de-entendimento.md`](01-resumo-de-entendimento.md) | O que o sistema faz, para quem, o que muda em relação a 2025, e o efeito de R28 no fechamento do guichê |
| 2 | [`02-arquitetura-de-producao.md`](02-arquitetura-de-producao.md) | Diagrama, subdomínios, TLS/HSTS/DNSSEC/CAA, cada componente (onde roda, como escala, como falha), credenciais e custo mensal |
| 3 | [`03-decisao-de-banco.md`](03-decisao-de-banco.md) | Supabase Pro em `sa-east-1` confirmado; compute Small; PITR 7 dias; sem réplica; dump externo no B2 |
| 4 | [`04-repositorio-ci-e-ambientes.md`](04-repositorio-ci-e-ambientes.md) | Monorepo, ferramentas, jobs do CI, ambientes e nomes dos segredos |
| 5 | [`05-backlog-por-entrega.md`](05-backlog-por-entrega.md) | 6 entregas + ensaio geral, com aceite testável, dependências, estimativa e quem precisa agir; conta de capacidade |
| 6 | [`06-caminho-critico-e-plano-b.md`](06-caminho-critico-e-plano-b.md) | Caminho crítico, o que se protege e o que se corta; planos B (webhook, usuário da Zet, EDI, catracas) |
| 7 | [`07-plano-de-testes.md`](07-plano-de-testes.md) | Unidade, pgTAP, carga com banco desligado, contrato com as catracas, robô contra o export de 2025, ensaio de um dia com R$ 0,00 |
| 8 | [`08-plano-de-virada.md`](08-plano-de-virada.md) | Congelamento do sistema antigo, troca do link na Zet, carga do cadastro, destino dos dados de 2025 |
| 9 | [`09-riscos.md`](09-riscos.md) | 20 riscos com probabilidade, impacto, mitigação e gatilho |
| 10 | [`10-perguntas-em-aberto.md`](10-perguntas-em-aberto.md) | Perguntas por destinatário (dono, Zet, PagBank, catracas), com prazo |
| 11 | [`11-estado-atual-da-infra.md`](11-estado-atual-da-infra.md) | Levantamento só leitura do Supabase e da Cloudflare atuais; o banco antigo não é alterado |

## Em uma página

- **As datas são viáveis com 2 desenvolvedores em tempo integral a partir de 28/09** (59,5 pessoa-dia de backlog para 66 de capacidade). Com 1 desenvolvedor, não são: o online continua protegido, e a bilheteria fecha em papel até ~30/11.
- **O que não pode atrasar é a borda do webhook, não o processador.** Ela vira um marco próprio, em produção em **09/10**. Com a borda no ar, nada se perde, mesmo que o processamento atrase.
- **O importador do export da Zet vem antes do robô** (20/10). O export fecha no centavo com o painel e é a rede de segurança de tudo o que é online. O robô só automatiza o download.
- **A conexão com as catracas não está no caminho crítico do dinheiro.** O maior risco dela está do lado do PC (ensaio de bancada ainda não feito).
- **Custo:** ~US$ 190 a 200 por mês na temporada e ~US$ 70 a 75 fora dela. O maior item é o PITR.

## Decisões que dependem do dono do evento (até 30/09)

1. **D-01:** aceitar que, em 2026, a receita em dinheiro do guichê é *contado + sangrias − fundo*, com a conferência feita no cartão (× PagBank) e no total dos 9 guichês × catraca.
2. **D-02:** tamanho do time (2 desenvolvedores em tempo integral).
3. **D-03:** data da 1ª venda de bilheteria (define o ensaio geral e se foods vão para 11/11).
4. **D-07:** acesso à conta Cloudflare e ao registrador do domínio.
5. Pedir à Zet, **já**: usuário só leitura (Z-01), token no caminho do link (Z-02) e evento de teste (Z-05). Pedir ao PagBank o token EDI (P-01).
