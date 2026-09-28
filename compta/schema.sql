-- Factures : espace partagé en lecture pour le comptable / l'associé.
-- À exécuter une fois dans Supabase : SQL Editor → New query → coller → Run.
-- Le téléphone reste la référence : il publie une copie ; les invités consultent et commentent.

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null,
  role text not null default 'viewer',
  created_at timestamptz not null default now(),
  primary key (company_id, email)
);

create table if not exists public.datasets (
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (company_id, name)
);

create table if not exists public.comments (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  target text not null default '',
  target_label text not null default '',
  author text not null default auth.email(),
  body text not null,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);

-- Accès : propriétaire ou invité (par e-mail)
create or replace function public.is_owner(c uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from companies where id = c and owner = auth.uid())
$$;

create or replace function public.is_member(c uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select public.is_owner(c)
      or exists (select 1 from members where company_id = c and lower(email) = lower(auth.email()))
$$;

alter table public.companies enable row level security;
alter table public.members enable row level security;
alter table public.datasets enable row level security;
alter table public.comments enable row level security;

drop policy if exists companies_read on public.companies;
create policy companies_read on public.companies for select using (owner = auth.uid() or public.is_member(id));
drop policy if exists companies_insert on public.companies;
create policy companies_insert on public.companies for insert with check (owner = auth.uid());
drop policy if exists companies_owner on public.companies;
create policy companies_owner on public.companies for update using (owner = auth.uid());
drop policy if exists companies_delete on public.companies;
create policy companies_delete on public.companies for delete using (owner = auth.uid());

drop policy if exists members_read on public.members;
create policy members_read on public.members for select using (public.is_member(company_id));
drop policy if exists members_write on public.members;
create policy members_write on public.members for insert with check (public.is_owner(company_id));
drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete using (public.is_owner(company_id));

drop policy if exists datasets_read on public.datasets;
create policy datasets_read on public.datasets for select using (public.is_member(company_id));
drop policy if exists datasets_insert on public.datasets;
create policy datasets_insert on public.datasets for insert with check (public.is_owner(company_id));
drop policy if exists datasets_update on public.datasets;
create policy datasets_update on public.datasets for update using (public.is_owner(company_id));

drop policy if exists comments_read on public.comments;
create policy comments_read on public.comments for select using (public.is_member(company_id));
drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments for insert
  with check (public.is_member(company_id) and lower(author) = lower(auth.email()));
drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments for update using (public.is_owner(company_id));

-- Fichiers (justificatifs, PDF de vente, documents) : bucket privé, un dossier par société
insert into storage.buckets (id, name, public) values ('pieces', 'pieces', false)
on conflict (id) do nothing;

drop policy if exists pieces_read on storage.objects;
create policy pieces_read on storage.objects for select
  using (bucket_id = 'pieces' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists pieces_insert on storage.objects;
create policy pieces_insert on storage.objects for insert
  with check (bucket_id = 'pieces' and public.is_owner(((storage.foldername(name))[1])::uuid));
drop policy if exists pieces_update on storage.objects;
create policy pieces_update on storage.objects for update
  using (bucket_id = 'pieces' and public.is_owner(((storage.foldername(name))[1])::uuid));
drop policy if exists pieces_delete on storage.objects;
create policy pieces_delete on storage.objects for delete
  using (bucket_id = 'pieces' and public.is_owner(((storage.foldername(name))[1])::uuid));
