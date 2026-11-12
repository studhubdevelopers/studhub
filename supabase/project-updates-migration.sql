-- Лента обновлений проектов StudHub
-- Выполнить один раз в Supabase -> SQL Editor.
create table if not exists public.project_updates (
  id bigint generated always as identity primary key,
  project_id text not null references public.projects(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'Автор',
  title text not null check (char_length(title) between 3 and 100),
  body text not null check (char_length(body) between 5 and 3000),
  created_at timestamptz not null default now()
);
create index if not exists project_updates_project_created_idx
  on public.project_updates(project_id, created_at desc);
alter table public.project_updates enable row level security;
revoke all on public.project_updates from anon, authenticated;
grant select, insert on public.project_updates to authenticated;
grant usage, select on sequence public.project_updates_id_seq to authenticated;
drop policy if exists project_updates_read on public.project_updates;
create policy project_updates_read on public.project_updates
  for select to authenticated using (true);
drop policy if exists project_updates_owner_insert on public.project_updates;
create policy project_updates_owner_insert on public.project_updates
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (select 1 from public.projects p
                where p.id = project_id and p.owner_id = auth.uid())
  );
