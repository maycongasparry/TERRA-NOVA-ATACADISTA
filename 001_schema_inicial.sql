-- Terra Nova Atacadista: estrutura inicial, sem dados reais.
-- Execute uma vez em um projeto Supabase novo, pelo SQL Editor.
begin;

create extension if not exists pgcrypto;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tax_id text,
  created_at timestamptz not null default now()
);

create table public.memberships (
  company_id uuid not null references public.companies(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('admin','financeiro','vendedor','operacional')),
  created_at timestamptz not null default now(),
  primary key (company_id,user_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null,
  sku text,
  base_unit text not null check (base_unit in ('caixa','unidade','palete')),
  created_at timestamptz not null default now(),
  unique (company_id,sku), unique (company_id,id)
);

create table public.stock_lots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  product_id uuid not null,
  lot_code text,
  invoice_number text,
  expires_on date not null,
  quantity numeric(16,3) not null check (quantity >= 0),
  unit_cost numeric(16,4) not null check (unit_cost >= 0),
  entry_tax_percent numeric(5,2) not null check (entry_tax_percent between 0 and 3),
  created_at timestamptz not null default now(),
  foreign key (company_id,product_id) references public.products(company_id,id),
  unique (company_id,id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  customer_name text not null,
  customer_document text,
  placed_on date not null default current_date,
  freight_terms text not null check (freight_terms in ('FOB','CIF')),
  status text not null default 'rascunho' check (status in ('rascunho','aprovado','cancelado')),
  created_at timestamptz not null default now(),
  unique (company_id,id)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  order_id uuid not null,
  product_id uuid not null,
  quantity numeric(16,3) not null check (quantity > 0),
  unit_price numeric(16,4) not null check (unit_price >= 0),
  minimum_expiry date not null,
  foreign key (company_id,order_id) references public.orders(company_id,id),
  foreign key (company_id,product_id) references public.products(company_id,id),
  unique (company_id,id)
);

create table public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  bank text not null check (bank in ('Banco do Brasil','Bradesco')),
  nickname text not null,
  agency text,
  account_number text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id,id)
);

create table public.receivables (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  order_id uuid not null,
  bank_account_id uuid,
  due_on date not null,
  amount numeric(16,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('Boleto','Pix','Transferência')),
  status text not null default 'pendente' check (status in ('pendente','parcial','pago','cancelado')),
  bank_reference text,
  created_at timestamptz not null default now(),
  foreign key (company_id,order_id) references public.orders(company_id,id),
  foreign key (company_id,bank_account_id) references public.bank_accounts(company_id,id),
  unique (company_id,id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  receivable_id uuid not null,
  amount numeric(16,2) not null check (amount > 0),
  paid_on date not null,
  proof_path text,
  reference text,
  created_at timestamptz not null default now(),
  foreign key (company_id,receivable_id) references public.receivables(company_id,id),
  unique (company_id,id)
);

create table public.bank_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  bank_account_id uuid not null,
  external_id text,
  booked_on date not null,
  amount numeric(16,2) not null check (amount <> 0),
  description text,
  payment_id uuid,
  created_at timestamptz not null default now(),
  foreign key (company_id,bank_account_id) references public.bank_accounts(company_id,id),
  foreign key (company_id,payment_id) references public.payments(company_id,id),
  unique (bank_account_id,external_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  user_id uuid references auth.users(id),
  incurred_on date not null default current_date,
  category text not null,
  description text not null,
  amount numeric(16,2) not null check (amount > 0),
  proof_path text,
  created_at timestamptz not null default now()
);

-- Nenhuma tabela de dados fica acessível pela API até criarmos login e políticas.
alter table public.companies enable row level security;
alter table public.memberships enable row level security;
alter table public.products enable row level security;
alter table public.stock_lots enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.receivables enable row level security;
alter table public.payments enable row level security;
alter table public.bank_entries enable row level security;
alter table public.expenses enable row level security;

revoke all on public.companies, public.memberships, public.products, public.stock_lots,
  public.orders, public.order_items, public.bank_accounts, public.receivables,
  public.payments, public.bank_entries, public.expenses from anon, authenticated;

commit;
