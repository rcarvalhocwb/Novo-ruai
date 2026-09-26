# 8. Plano de virada

## 8.1 Linha do tempo

| Quando | Passo | Responsável | Verificação |
|---|---|---|---|
| **Já (antes de 01/10)** | Congelar evidências do sistema antigo: `pg_dump` completo guardado em 2 lugares fora do Supabase com `sha256`; download de todo o bucket R2 antigo; export dos logs das edge functions e do Cloudflare do período do apagão (`05-MIGRACAO`, seção 0) | Dono do evento + dev B | Arquivos e hashes registrados num documento fora do repositório |
| Já | Fechar o que apaga dados no sistema antigo: desligar `r2-backup`, `reset-*`, `cleanup-*`, `fix-*`, `reprocess-*`, `middleware-*` abertas; trocar `USING (true)`; rotacionar `service_role` e chaves do R2 antigas (`00-RESUMO`, "ações urgentes") | Dono + dev B | Chamadas com a chave `anon` → 401/403 |
| 09/10 | Borda nova em produção (`ingest.`), testada em hml | Dev B | `07`, 7.3 |
| 13/10 | Zet: evento de teste aponta para `ingest-hml`; webhook de teste processado | Zet + dono | Linha no inbox de hml |
| **14/10** | Zet: o evento 2026 recebe o link novo `https://ingest.ruailuminada.com/zet/v1/<token-novo>` (o dono cola o link no painel; o token vem do cofre, nunca por mensagem) | Dono | Primeiro CP real em produção |
| 14/10 | **Congelamento do sistema antigo**: webhook antigo desligado (o Worker `comprenozet-webhook-proxy` e a rota em `api.ruailuminada.com` removidos), edge functions desativadas, projeto Supabase antigo em **somente leitura** (papéis de escrita revogados), app antigo tirado do ar ou com aviso | Dev B + dono | Requisição ao endereço antigo → 404; nenhuma escrita no banco antigo depois de 14/10 |
| 15/10 | Abertura das vendas online | — | Painel mostra vendas; export da Zet confere no dia seguinte |
| até 31/10 | `api.ruailuminada.com` passa a apontar para o sistema novo (depois de removida a rota antiga) | Dev B | `curl` |
| até 07/11 | Carga do cadastro da bilheteria, foods e assinantes (8.2) | Dono + gestor | Revisão em tela, com dupla conferência |
| 12 e 13/11 | Ensaio geral | Todos | `07`, 7.6 |
| 1ª venda de bilheteria | Operação no sistema novo | — | Primeiro dia fechado com duas assinaturas |

**Por que o sistema antigo não recebe webhooks de 2026 em paralelo:** a Zet aceita um link por evento, e o sistema antigo é o que apagava e sobrescrevia dados. A conferência do novo não precisa do antigo: ela é feita contra o export da Zet (R-01), que é a fonte da própria Zet.

## 8.2 Carga do cadastro (sem dado pessoal no repositório)

| Cadastro | Fonte | Como entra | Conferência |
|---|---|---|---|
| Evento 2026 e `zet_event_map` | Painel da Zet (`event.id`) | Tela de admin | Primeiro webhook casa com o evento |
| Tipos de ingresso online (`zet_ticket_type_map` por `eventsValues.id`, preço líquido, categoria normalizada) | Webhook de teste ou Detalhes de um pedido; lista de sessões e preços da Zet | Importação por planilha **sem dado pessoal** + revisão | Validação de conteúdo do webhook passa; tipo desconhecido vira `failed`, não venda perdida |
| Preços da bilheteria por categoria, com vigência | Dono do evento (D-04) | Tela T-01 | Aparecem na `configuracao` das catracas |
| 9 guichês e maquininhas (número de série → guichê, com vigência) | Dono / PagBank | Tela T-01 | Primeiro EDI casa com os guichês |
| Contas bancárias do evento | Dono | Tela T-01 (dados bancários só no banco, nunca no repositório) | Primeiro OFX casa |
| Lojas e percentuais com vigência | Dono | Tela A-01 | Comissão do primeiro dia |
| Usuários, papéis e os dois assinantes designados | Dono | Convite pelo Auth; MFA configurado por cada um | Login com MFA de cada admin e aprovador |
| Caixa mínimo, tolerâncias, limites de catraca | Dono (valores de `10` como padrão) | Tela T-01 | `audit.log` |
| PCs das catracas (um segredo por PC) | Time das catracas | Admin gera o segredo e mostra **uma vez**; o time guarda no cofre do Windows | `401` com segredo antigo |

## 8.3 O que acontece com os dados de 2025

| Dado | Destino em 2026 | Quando |
|---|---|---|
| Banco antigo (dump) e bucket R2 antigo | **Evidência congelada**, cifrada, fora do Supabase, com `sha256` registrado. Nada é migrado como verdade | Já |
| Backup de 27.641 webhooks e export `data.xlsx` | Guardados cifrados fora do repositório (têm dados pessoais). Usados **como teste** (W-05, R-01) em ambiente local | Out/2026 |
| Contestações de 2025 (−R$ 975,00, saldo negativo com a Zet) | Registradas como **saldo inicial** da conta-corrente Zet do evento 2025 no sistema novo, por lançamento de abertura com evidência, se o dono quiser o acerto de 2025 dentro do sistema (D-06) | Quando decidido |
| Reconstrução completa de 2025 (fontes F1 a F12, selos provado/estimado/irrecuperável) | **Adiada para depois da temporada** (fev–mar/2027), num evento "2025" separado no mesmo banco, com o schema `recovery` | 2027 |
| Tabelas duplicadas de venda online, `daily_closures*` | Não migram. Só consulta na reconstrução | — |

Motivo de adiar a reconstrução: ela não muda a operação de 2026, e cada dia gasto nela antes de 15/10 sai do caminho crítico. Os 208 webhooks nunca gravados (R$ 24.313,00) e o saldo com a Zet de 2025 continuam documentados em `09` e `14` para cobrança.

## 8.4 Critério para declarar a virada concluída

1. Uma semana de vendas online com `recon.v_zet_export_diff` sem divergência aberta há mais de 24 h.
2. Primeiro dia de bilheteria fechado, assinado e com Tesouraria zerada.
3. Checklist `07`, parte B, 100% verde.
4. Sistema antigo sem nenhuma escrita desde 14/10.
