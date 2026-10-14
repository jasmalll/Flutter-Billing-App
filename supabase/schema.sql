-- Staff Billing Platform: Supabase schema baseline.
-- Run in the Supabase SQL Editor after creating a project.
-- Set auth user app_metadata.org_id to the UUID of the supervisor organization.

create extension if not exists pgcrypto;

create table if not exists public.master_staff (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  phone text not null,
  default_wage numeric not null default 430.0,
  category text not null default 'BOY',
  updated_at timestamptz not null default now(),
  unique (organization_id, phone)
);

create table if not exists public.event_bills (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_date date not null,
  auditorium_name text not null default '',
  bill_payload jsonb not null,
  grand_total numeric not null default 0,
  is_synced boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (organization_id, event_date)
);

create table if not exists public.inventory_counts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique,
  catalog_payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.event_settlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  event_date date not null,
  settlement_payload jsonb not null,
  net_disbursed_total numeric not null default 0,
  updated_at timestamptz not null default now(),
  unique (organization_id, event_date),
  foreign key (organization_id, event_date)
    references public.event_bills (organization_id, event_date) on delete cascade
);

alter table public.master_staff enable row level security;
alter table public.event_bills enable row level security;
alter table public.inventory_counts enable row level security;
alter table public.event_settlements enable row level security;

drop policy if exists "Supervisor organization can manage staff" on public.master_staff;
drop policy if exists "Supervisor organization can manage bills" on public.event_bills;
drop policy if exists "Supervisor organization can manage inventory" on public.inventory_counts;
drop policy if exists "Supervisor organization can manage settlements" on public.event_settlements;

create policy "Supervisor organization can manage staff"
on public.master_staff for all to authenticated
using (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid))
with check (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid));

create policy "Supervisor organization can manage bills"
on public.event_bills for all to authenticated
using (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid))
with check (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid));

create policy "Supervisor organization can manage inventory"
on public.inventory_counts for all to authenticated
using (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid))
with check (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid));

create policy "Supervisor organization can manage settlements"
on public.event_settlements for all to authenticated
using (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid))
with check (organization_id = ((auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid));
