-- Execute uma vez após 003. Habilita pedidos com vários itens, sem alterar pedidos existentes.
begin;

create function public.register_order(
  p_company uuid, p_customer_id uuid, p_items jsonb, p_due date,
  p_payment_method text, p_freight_terms text, p_request uuid,
  p_representative uuid default null, p_campaign uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_order uuid; v_customer text; v_item_id uuid; v_line jsonb; v_product uuid;
  v_qty numeric; v_price numeric; v_expiry date; v_remaining numeric(16,3);
  v_take numeric(16,3); v_total numeric(16,2):=0; v_lot record;
begin
  if not public.has_company_role(p_company,array['admin','vendedor']) then raise exception 'Sem permissão para registrar venda'; end if;
  if p_request is null then raise exception 'Identificador do pedido ausente'; end if;
  select id into v_order from public.orders where company_id=p_company and client_request_id=p_request;
  if v_order is not null then return v_order; end if;
  select name into v_customer from public.partners where id=p_customer_id and company_id=p_company and kind='cliente';
  if v_customer is null then raise exception 'Selecione um cliente cadastrado'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100
    or p_due is null or p_payment_method is null or p_payment_method not in ('Boleto','Pix','Transferência')
    or p_freight_terms is null or p_freight_terms not in ('FOB','CIF') then
    raise exception 'Confira itens, pagamento, frete e vencimento';
  end if;
  if p_representative is not null and not exists
    (select 1 from public.representatives where company_id=p_company and id=p_representative and active) then raise exception 'Representante não encontrado'; end if;
  if p_campaign is not null and not exists
    (select 1 from public.campaigns where company_id=p_company and id=p_campaign) then raise exception 'Campanha não encontrada'; end if;

  insert into public.orders(company_id,customer_id,customer_name,placed_on,freight_terms,status,
    representative_id,campaign_id,client_request_id)
    values(p_company,p_customer_id,v_customer,(now() at time zone 'America/Sao_Paulo')::date,
      p_freight_terms,'aprovado',p_representative,p_campaign,p_request) returning id into v_order;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    begin
      v_product := (v_line->>'product_id')::uuid;
      v_qty := (v_line->>'quantity')::numeric;
      v_price := (v_line->>'unit_price')::numeric;
      v_expiry := (v_line->>'min_expiry')::date;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Dados de um item inválidos';
    end;
    if v_product is null or v_qty is null or v_qty<=0 or v_qty<>round(v_qty,3)
      or v_price is null or v_price<0 or v_expiry is null or round(v_qty*v_price,2)<=0
      or not exists(select 1 from public.products where company_id=p_company and id=v_product) then
      raise exception 'Confira produto, quantidade, preço e validade de cada item';
    end if;
    v_total := v_total + round(v_qty*v_price,2);
    insert into public.order_items(company_id,order_id,product_id,quantity,unit_price,minimum_expiry)
      values(p_company,v_order,v_product,v_qty,v_price,v_expiry) returning id into v_item_id;
    v_remaining := v_qty;
    for v_lot in select id,quantity from public.stock_lots
      where company_id=p_company and product_id=v_product
        and expires_on>=greatest(v_expiry,(now() at time zone 'America/Sao_Paulo')::date)
        and quantity>0 order by expires_on,id for update
    loop
      v_take := least(v_remaining,v_lot.quantity);
      update public.stock_lots set quantity=quantity-v_take where id=v_lot.id;
      insert into public.order_allocations(company_id,order_item_id,lot_id,quantity)
        values(p_company,v_item_id,v_lot.id,v_take);
      v_remaining := v_remaining-v_take;
      exit when v_remaining=0;
    end loop;
    if v_remaining>0 then raise exception 'Estoque insuficiente com a validade exigida'; end if;
  end loop;
  insert into public.receivables(company_id,order_id,due_on,amount,payment_method)
    values(p_company,v_order,p_due,v_total,p_payment_method);
  return v_order;
end $$;
revoke all on function public.register_order(uuid,uuid,jsonb,date,text,text,uuid,uuid,uuid) from public;
grant execute on function public.register_order(uuid,uuid,jsonb,date,text,text,uuid,uuid,uuid) to authenticated;

commit;
