create or replace function public.match_dish_info(
  query_embedding extensions.vector(3072),
  match_count int default 5
)
returns table (
  id uuid,
  name text,
  category text,
  description text,
  image_url text,
  similarity double precision
)
language sql
stable
as $$
  select
    dish_info.id,
    dish_info.name,
    dish_info.category,
    dish_info.description,
    dish_info.image_url,
    1 - (dish_info.embedding OPERATOR(extensions.<=>) query_embedding) as similarity
  from public.dish_info
  order by dish_info.embedding OPERATOR(extensions.<=>) query_embedding
  limit greatest(1, least(match_count, 10));
$$;

grant execute on function public.match_dish_info(extensions.vector, int) to anon, authenticated, service_role;
