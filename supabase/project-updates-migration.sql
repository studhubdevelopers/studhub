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
 
/* Автор и его имя подставляются на сервере (как в обсуждениях): нельзя выдать себя за другого,
   и в ленте показывается настоящее имя, а не значение по умолчанию «Автор». */
alter table public.project_updates alter column author_id set default auth.uid();
 
create or replace function public.project_updates_set_author() returns trigger
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if auth.uid() is null then return new; end if;   -- вставка из SQL Editor / сервисным ключом
  new.author_id := auth.uid();
  select name into nm from public.profiles where id = auth.uid();
  new.author_name := coalesce(nm, 'Автор');
  return new;
end $$;
revoke all on function public.project_updates_set_author() from public, anon, authenticated;
drop trigger if exists project_updates_set_author on public.project_updates;
create trigger project_updates_set_author before insert on public.project_updates
  for each row execute function public.project_updates_set_author();
 
-- Новости, опубликованные до этой правки, сохранились с именем «Автор» — подставляем настоящее.
update public.project_updates u set author_name = p.name
  from public.profiles p
  where p.id = u.author_id and u.author_name = 'Автор';
 
/* Права и RLS: читают все вошедшие пользователи, публикует только владелец проекта. */
alter table public.project_updates enable row level security;
revoke all on public.project_updates from anon, authenticated;
grant select on public.project_updates to authenticated;
grant insert (project_id, author_id, title, body) on public.project_updates to authenticated;
 
drop policy if exists project_updates_read on public.project_updates;
create policy project_updates_read on public.project_updates
  for select to authenticated using (true);
 
drop policy if exists project_updates_owner_insert on public.project_updates;
create policy project_updates_owner_insert on public.project_updates
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (select 1 from public.projects p
                where p.id = project_updates.project_id and p.owner_id = auth.uid())
  );
 
-- Просим API Supabase перечитать схему: иначе новая таблица может какое-то время отвечать
-- ошибкой «Could not find the table 'public.project_updates' in the schema cache».
notify pgrst, 'reload schema';
 
-- Проверка результата (видна во вкладке Results).
select 'project_updates готова' as status,
       (select count(*) from public.project_updates) as updates,
       (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'project_updates') as policies;
 
