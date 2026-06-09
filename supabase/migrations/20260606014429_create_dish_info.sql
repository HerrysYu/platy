create extension if not exists vector with schema extensions;

create table if not exists public.dish_info (
  id uuid primary key,
  name text not null,
  category text not null,
  description text not null,
  image_url text,
  embedding extensions.vector(3072) not null
);

alter table public.dish_info enable row level security;

drop policy if exists dish_info_select_all on public.dish_info;
create policy dish_info_select_all
  on public.dish_info for select
  using (true);

grant select on public.dish_info to anon, authenticated;
