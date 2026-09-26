#!/usr/bin/env bash
# 50 CPs do mesmo pedido (corpos diferentes) processados em 8 conexões paralelas → 1 venda e 1 lançamento.
# Roda num banco já migrado (DB). Tudo o que cria fica num evento próprio de teste.
set -euo pipefail
DB="${DB:-ruai_test}"
q() { psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }

q "insert into fin.events(id,name,starts_on,ends_on) values ('99999999-9999-9999-9999-999999999999','Concorrência','2026-10-15','2027-01-10') on conflict do nothing;
   select fin.create_chart_of_accounts('99999999-9999-9999-9999-999999999999');
   insert into integ.zet_event_map values (990,'zet','99999999-9999-9999-9999-999999999999') on conflict do nothing;
   insert into integ.zet_ticket_type_map values (99001,990,'Inteira','inteira',3600) on conflict do nothing;" >/dev/null

for i in $(seq 1 50); do
  body="{\"action\":\"CP\",\"n\":$i,\"data\":{\"order\":{\"uuid\":\"99999999-0000-0000-0000-000000000099\",\"paymentType\":\"PIX\",\"paymentConfirmeDate\":\"2026-10-16T15:00:00Z\",\"totalValue\":39.6,\"totalTax\":3.6,\"discount\":0},\"eventTicketCodes\":[{\"voucher\":\"V-CONC\",\"eventsValues\":{\"id\":99001}}],\"event\":{\"id\":990}}}"
  q "select integ.receive_webhook('zet', encode(convert_to('$body','UTF8'),'base64'), encode(sha256(convert_to('$body','UTF8')),'hex'), '{}', null, now())" >/dev/null
done

for w in $(seq 1 8); do q "select integ.process_pending(50)" >/dev/null & done
wait

vendas=$(q "select count(*) from sales.zet_orders where order_uuid='99999999-0000-0000-0000-000000000099'")
lanc=$(q "select count(*) from fin.journal_entries where idempotency_key='zet:CP:99999999-0000-0000-0000-000000000099'")
saldo=$(q "select balance_cents from fin.v_account_balances where event_id='99999999-9999-9999-9999-999999999999' and code='1.2.01'")
pend=$(q "select count(*) from integ.webhook_inbox i where status <> 'processed' and convert_from(raw_body,'UTF8') like '%99999999-0000-0000-0000-000000000099%'")
echo "vendas=$vendas lançamentos=$lanc saldo=$saldo pendentes=$pend"
[ "$vendas" = 1 ] && [ "$lanc" = 1 ] && [ "$saldo" = 3600 ] && [ "$pend" = 0 ] && echo "concorrência ok"
