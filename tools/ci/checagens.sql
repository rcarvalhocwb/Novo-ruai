-- Checagens estruturais que reprovam o build (04-repositorio-ci-e-ambientes.md, 4.3).
-- Cada bloco levanta exceção listando o que violou a regra.
\set ON_ERROR_STOP 1

-- 1. Nenhuma policy USING (true) / WITH CHECK (true).
do $$ declare v text; begin
  select string_agg(schemaname||'.'||tablename||':'||policyname, ', ') into v
    from pg_policies where qual = 'true' or with_check = 'true';
  if v is not null then raise exception 'policies com true: %', v; end if;
end $$;

-- 2. RLS ligada em toda tabela dos schemas da aplicação.
do $$ declare v text; begin
  select string_agg(n.nspname||'.'||c.relname, ', ') into v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind = 'r' and not c.relrowsecurity
     and n.nspname in ('api','fin','sales','integ','recon','access','audit');
  if v is not null then raise exception 'tabelas sem RLS: %', v; end if;
end $$;

-- 3. Colunas de dinheiro: *_cents e amount* são bigint; nada de real/double/money/numeric nos schemas financeiros.
do $$ declare v text; begin
  select string_agg(table_schema||'.'||table_name||'.'||column_name||' ('||data_type||')', ', ') into v
    from information_schema.columns
   where table_schema in ('api','fin','sales','integ','recon','access','audit')
     and ( ((column_name like '%\_cents' or column_name like 'amount%') and data_type <> 'bigint')
        or data_type in ('real','double precision','money','numeric') );
  if v is not null then raise exception 'colunas de dinheiro fora de bigint: %', v; end if;
end $$;

-- 4. Toda função SECURITY DEFINER dos schemas da aplicação fixa o search_path.
do $$ declare v text; begin
  select string_agg(n.nspname||'.'||p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.prosecdef and n.nspname in ('api','fin','sales','integ','recon','access','audit')
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  if v is not null then raise exception 'security definer sem search_path: %', v; end if;
end $$;

-- 5. anon não executa nada nos schemas da aplicação; e fin/audit não expõem função a authenticated.
do $$ declare v text; begin
  select string_agg(n.nspname||'.'||p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('api','fin','sales','integ','recon','access','audit')
     and (has_function_privilege('anon', p.oid, 'execute')
          or (n.nspname <> 'api' and has_function_privilege('authenticated', p.oid, 'execute')));
  if v is not null then raise exception 'funções executáveis por anon/authenticated fora da api: %', v; end if;
end $$;

-- 6. Nenhum papel de cliente pode alterar ou apagar tabelas financeiras.
do $$ declare v text; begin
  select string_agg(distinct g.table_schema||'.'||g.table_name||' '||g.privilege_type||' '||g.grantee, ', ') into v
    from information_schema.role_table_grants g
   where g.table_schema in ('fin','sales','integ','recon','access','audit')
     and g.grantee in ('anon','authenticated','public')
     and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
  if v is not null then raise exception 'escrita direta concedida a cliente: %', v; end if;
end $$;

-- 7. FKs dos schemas financeiros nunca em cascata.
do $$ declare v text; begin
  select string_agg(conrelid::regclass::text||'.'||conname, ', ') into v
    from pg_constraint c join pg_namespace n on n.oid = c.connamespace
   where c.contype = 'f' and c.confdeltype = 'c'
     and n.nspname in ('fin','sales','integ','recon','access','audit');
  if v is not null then raise exception 'FK com ON DELETE CASCADE: %', v; end if;
end $$;

select 'checagens ok' as resultado;
