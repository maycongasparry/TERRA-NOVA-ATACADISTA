-- Etapa 2: execute depois de criar e confirmar seu usuário pelo piloto.
-- Substitua somente o texto EMAIL_DO_ADMIN pelo seu e-mail de login.
begin;

do $$
declare
  v_user uuid;
  v_company uuid;
begin
  select id into v_user from auth.users
    where lower(email) = lower('EMAIL_DO_ADMIN') and email_confirmed_at is not null;
  if v_user is null then
    raise exception 'Usuário confirmado não encontrado. Confira o e-mail e confirme o cadastro antes de executar.';
  end if;
  if exists (select 1 from public.memberships where user_id = v_user) then
    raise exception 'Este usuário já possui vínculo. Não execute a etapa duas vezes.';
  end if;
  insert into public.companies (name) values ('Terra Nova Atacadista') returning id into v_company;
  insert into public.memberships (company_id,user_id,role)
    values (v_company,v_user,'admin');
end $$;

create or replace function public.has_company_role(p_company uuid, p_roles text[] default null)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.company_id = p_company and m.user_id = (select auth.uid())
      and (p_roles is null or m.role = any(p_roles))
  );
$$;
revoke all on function public.has_company_role(uuid,text[]) from public;
grant execute on function public.has_company_role(uuid,text[]) to authenticated;

grant select on public.memberships, public.companies, public.products, public.stock_lots to authenticated;
grant insert on public.products, public.stock_lots to authenticated;

create policy membership_self_read on public.memberships for select to authenticated
  using (user_id = (select auth.uid()));
create policy company_member_read on public.companies for select to authenticated
  using (public.has_company_role(id));
create policy product_member_read on public.products for select to authenticated
  using (public.has_company_role(company_id));
create policy product_admin_insert on public.products for insert to authenticated
  with check (public.has_company_role(company_id,array['admin']));
create policy lot_member_read on public.stock_lots for select to authenticated
  using (public.has_company_role(company_id));
create policy lot_admin_insert on public.stock_lots for insert to authenticated
  with check (public.has_company_role(company_id,array['admin']));

commit;
