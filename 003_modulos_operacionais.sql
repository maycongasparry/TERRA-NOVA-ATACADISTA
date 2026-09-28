-- Execute uma vez após 001 e 002. Instala as abas conectadas ao Supabase.
begin;

create table public.representatives (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null,
  phone text,
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id,id)
);
create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null,
  starts_on date not null,
  ends_on date not null,
  target_amount numeric(16,2) not null default 0 check (target_amount >= 0),
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on),
  unique (company_id,id)
);
create table public.partners (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  kind text not null check (kind in ('cliente','fornecedor','transportadora')),
  name text not null,
  document text,
  phone text,
  email text,
  city text,
  state_code text,
  created_at timestamptz not null default now(),
  unique (company_id,id)
);
alter table public.orders add column representative_id uuid;
alter table public.orders add column campaign_id uuid;
alter table public.orders add column customer_id uuid;
alter table public.orders add column client_request_id uuid;
alter table public.orders add constraint order_request_unique unique (company_id,client_request_id);
alter table public.orders add constraint order_representative_fk foreign key (company_id,representative_id) references public.representatives(company_id,id);
alter table public.orders add constraint order_campaign_fk foreign key (company_id,campaign_id) references public.campaigns(company_id,id);
alter table public.orders add constraint order_customer_fk foreign key (company_id,customer_id) references public.partners(company_id,id);
alter table public.payments add column client_request_id uuid;
alter table public.payments add constraint payment_request_unique unique (company_id,client_request_id);

create table public.order_allocations (
  company_id uuid not null,
  order_item_id uuid not null,
  lot_id uuid not null,
  quantity numeric(16,3) not null check (quantity > 0),
  primary key (order_item_id,lot_id),
  foreign key (company_id,order_item_id) references public.order_items(company_id,id),
  foreign key (company_id,lot_id) references public.stock_lots(company_id,id)
);

alter table public.representatives enable row level security;
alter table public.campaigns enable row level security;
alter table public.partners enable row level security;
alter table public.order_allocations enable row level security;
revoke all on public.representatives, public.campaigns, public.partners, public.order_allocations from anon, authenticated;
grant select on public.representatives, public.campaigns, public.partners, public.order_allocations,
  public.orders, public.order_items, public.receivables, public.payments,
  public.bank_accounts, public.bank_entries, public.expenses to authenticated;
grant insert on public.representatives, public.campaigns, public.partners, public.bank_accounts,
  public.bank_entries, public.expenses to authenticated;
grant update (sku) on public.products to authenticated;
create policy product_admin_sku_update on public.products for update to authenticated
  using (public.has_company_role(company_id,array['admin']))
  with check (public.has_company_role(company_id,array['admin']));

create policy rep_read on public.representatives for select to authenticated using (public.has_company_role(company_id));
create policy rep_write on public.representatives for insert to authenticated with check (public.has_company_role(company_id,array['admin']));
create policy campaign_read on public.campaigns for select to authenticated using (public.has_company_role(company_id));
create policy campaign_write on public.campaigns for insert to authenticated with check (public.has_company_role(company_id,array['admin']));
create policy partners_read on public.partners for select to authenticated using (public.has_company_role(company_id));
create policy partners_write on public.partners for insert to authenticated with check (public.has_company_role(company_id,array['admin','vendedor','operacional']));
create policy allocations_read on public.order_allocations for select to authenticated using (public.has_company_role(company_id));
create policy orders_read on public.orders for select to authenticated using (public.has_company_role(company_id));
create policy items_read on public.order_items for select to authenticated using (public.has_company_role(company_id));
create policy receivables_read on public.receivables for select to authenticated using (public.has_company_role(company_id));
create policy payments_read on public.payments for select to authenticated using (public.has_company_role(company_id));
create policy accounts_read on public.bank_accounts for select to authenticated using (public.has_company_role(company_id));
create policy accounts_write on public.bank_accounts for insert to authenticated with check (public.has_company_role(company_id,array['admin','financeiro']));
create policy entries_read on public.bank_entries for select to authenticated using (public.has_company_role(company_id));
create policy entries_write on public.bank_entries for insert to authenticated with check (public.has_company_role(company_id,array['admin','financeiro']) and payment_id is null);
create policy expenses_read on public.expenses for select to authenticated using (public.has_company_role(company_id));
create policy expenses_write on public.expenses for insert to authenticated
  with check (public.has_company_role(company_id,array['admin','financeiro','operacional']) and user_id = (select auth.uid()));

-- Uma venda, um item e uma cobrança. A operação inteira é atômica: se faltar
-- estoque válido, nenhum pedido, baixa de lote ou cobrança será gravado.
create function public.register_sale(
  p_company uuid, p_customer text, p_product uuid, p_quantity numeric,
  p_unit_price numeric, p_min_expiry date, p_due date,
  p_payment_method text, p_freight_terms text,
  p_representative uuid default null, p_campaign uuid default null,
  p_customer_id uuid default null, p_request uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_order uuid; v_item uuid; v_remaining numeric(16,3); v_take numeric(16,3);
  v_lot record;
begin
  if not public.has_company_role(p_company,array['admin','vendedor']) then raise exception 'Sem permissão para registrar venda'; end if;
  if p_request is null then raise exception 'Identificador do pedido ausente'; end if;
  select id into v_order from public.orders where company_id=p_company and client_request_id=p_request;
  if v_order is not null then return v_order; end if;
  if nullif(btrim(p_customer),'') is null or p_quantity is null or p_quantity <= 0
    or p_quantity <> round(p_quantity,3) or p_unit_price is null or p_unit_price < 0
    or p_min_expiry is null or p_due is null or p_payment_method not in ('Boleto','Pix','Transferência')
    or p_freight_terms not in ('FOB','CIF') or round(p_quantity*p_unit_price,2) <= 0 then
    raise exception 'Confira cliente, quantidade, valor, validade, vencimento e condições';
  end if;
  if not exists (select 1 from public.products where company_id=p_company and id=p_product) then raise exception 'Produto não encontrado'; end if;
  if p_representative is not null and not exists
    (select 1 from public.representatives where company_id=p_company and id=p_representative and active) then raise exception 'Representante não encontrado'; end if;
  if p_campaign is not null and not exists
    (select 1 from public.campaigns where company_id=p_company and id=p_campaign) then raise exception 'Campanha não encontrada'; end if;
  if p_customer_id is not null and not exists
    (select 1 from public.partners where company_id=p_company and id=p_customer_id and kind='cliente' and name=btrim(p_customer)) then raise exception 'Cliente cadastrado não encontrado'; end if;

  insert into public.orders(company_id,customer_name,placed_on,freight_terms,status,representative_id,campaign_id,customer_id,client_request_id)
    values(p_company,btrim(p_customer),(now() at time zone 'America/Sao_Paulo')::date,p_freight_terms,'aprovado',p_representative,p_campaign,p_customer_id,p_request) returning id into v_order;
  insert into public.order_items(company_id,order_id,product_id,quantity,unit_price,minimum_expiry)
    values(p_company,v_order,p_product,p_quantity,p_unit_price,p_min_expiry) returning id into v_item;
  v_remaining := p_quantity;
  for v_lot in select id,quantity from public.stock_lots
    where company_id=p_company and product_id=p_product and expires_on >= greatest(p_min_expiry,(now() at time zone 'America/Sao_Paulo')::date)
      and quantity > 0 order by expires_on,id for update
  loop
    v_take := least(v_remaining,v_lot.quantity);
    update public.stock_lots set quantity=quantity-v_take where id=v_lot.id;
    insert into public.order_allocations(company_id,order_item_id,lot_id,quantity)
      values(p_company,v_item,v_lot.id,v_take);
    v_remaining := v_remaining-v_take;
    exit when v_remaining=0;
  end loop;
  if v_remaining>0 then raise exception 'Estoque insuficiente com a validade exigida'; end if;
  insert into public.receivables(company_id,order_id,due_on,amount,payment_method)
    values(p_company,v_order,p_due,round(p_quantity*p_unit_price,2),p_payment_method);
  return v_order;
end $$;
revoke all on function public.register_sale(uuid,text,uuid,numeric,numeric,date,date,text,text,uuid,uuid,uuid,uuid) from public;
grant execute on function public.register_sale(uuid,text,uuid,numeric,numeric,date,date,text,text,uuid,uuid,uuid,uuid) to authenticated;

-- Pagamento pode ser registrado sem extrato/conciliacao bancaria.
create function public.record_payment(p_company uuid,p_receivable uuid,p_amount numeric,p_paid_on date,p_reference text default null,p_request uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_due numeric(16,2); v_paid numeric(16,2); v_payment uuid;
begin
  if not public.has_company_role(p_company,array['admin','financeiro']) then raise exception 'Sem permissão para registrar pagamento'; end if;
  if p_request is null then raise exception 'Identificador do pagamento ausente'; end if;
  select id into v_payment from public.payments where company_id=p_company and client_request_id=p_request;
  if v_payment is not null then return v_payment; end if;
  select amount into v_due from public.receivables
    where company_id=p_company and id=p_receivable and status <> 'cancelado' for update;
  if v_due is null then raise exception 'Cobrança não encontrada'; end if;
  select coalesce(sum(amount),0) into v_paid from public.payments where company_id=p_company and receivable_id=p_receivable;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount,2)
    or p_paid_on is null or v_paid+p_amount>v_due then raise exception 'Valor do pagamento inválido ou superior ao saldo'; end if;
  insert into public.payments(company_id,receivable_id,amount,paid_on,reference,client_request_id)
    values(p_company,p_receivable,p_amount,p_paid_on,nullif(btrim(p_reference),''),p_request) returning id into v_payment;
  update public.receivables set status=case when v_paid+p_amount=v_due then 'pago' else 'parcial' end where id=p_receivable;
  return v_payment;
end $$;
revoke all on function public.record_payment(uuid,uuid,numeric,date,text,uuid) from public;
grant execute on function public.record_payment(uuid,uuid,numeric,date,text,uuid) to authenticated;

create function public.reconcile_entry(p_company uuid,p_entry uuid,p_payment uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_entry_amount numeric(16,2); v_payment_amount numeric(16,2);
begin
  if not public.has_company_role(p_company,array['admin','financeiro']) then raise exception 'Sem permissão para conciliar'; end if;
  select amount into v_entry_amount from public.bank_entries
    where company_id=p_company and id=p_entry and payment_id is null for update;
  select amount into v_payment_amount from public.payments
    where company_id=p_company and id=p_payment;
  if v_entry_amount is null or v_payment_amount is null or v_entry_amount<>v_payment_amount then
    raise exception 'Selecione um lançamento não conciliado e um pagamento do mesmo valor';
  end if;
  if exists(select 1 from public.bank_entries where company_id=p_company and payment_id=p_payment) then
    raise exception 'Pagamento já conciliado';
  end if;
  update public.bank_entries set payment_id=p_payment where id=p_entry;
end $$;
revoke all on function public.reconcile_entry(uuid,uuid,uuid) from public;
grant execute on function public.reconcile_entry(uuid,uuid,uuid) to authenticated;

commit;
