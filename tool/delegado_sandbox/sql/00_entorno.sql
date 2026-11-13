-- SOLO DEL SANDBOX. Lo que en Supabase ya existe y acá hay que imitar:
-- los dos roles, auth.role() y las dos tablas del programa que leen las funciones
-- (con las columnas que usan, nada más).

create role anon nologin;
create role authenticated nologin;
grant usage on schema public to anon, authenticated;

create schema auth;
grant usage on schema auth to anon, authenticated;
create function auth.role() returns text
language sql stable
as $$ select current_setting('request.jwt.claim.role', true) $$;

create table public.eventos (
  id     uuid primary key,
  nombre text not null
);

create table public.contratos_alumnos (
  id                    uuid primary key,
  evento_id             uuid not null references public.eventos(id),
  nombre_alumno         text not null,
  curso_division        text,
  nombres_acompanantes  text[],
  cantidad_acompanantes integer,
  musica_elegida        text
);

-- En el programa estas tablas las lee quien tiene usuario; un anónimo, no.
alter table public.eventos enable row level security;
alter table public.contratos_alumnos enable row level security;
revoke all on table public.eventos from anon;
revoke all on table public.contratos_alumnos from anon;
