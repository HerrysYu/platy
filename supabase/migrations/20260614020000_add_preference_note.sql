-- Free-form dining preferences the user describes in natural language
-- (e.g. "no cilantro, love spicy, light on oil"). Feeds combo + dish advice.
alter table public.profiles
  add column if not exists preference_note text;
