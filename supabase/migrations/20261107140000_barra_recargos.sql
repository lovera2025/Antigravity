-- 2026-11-07 — Una tabla nueva: el recargo por transferencia de cada fiesta
-- (6.4.0, etapa 7 de la barra). Va con la v78 de la base local, junto con
-- `sillas_puerta` y `barra_vales`.
--
-- Lo pone el jefe en BARRA → PRECIOS. Cada cobro de cada caja arranca con este
-- porcentaje, y la cajera lo puede cambiar en ese cobro (decidido el 3-nov). Una
-- fila por fiesta, con id fijo: si el jefe lo cambia desde la PC y desde la web,
-- escriben la misma fila. Cambiarlo la actualiza; **no se borra**.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, su
-- índice, su RLS y sus disparadores de `updated_at`. La 6.3.3 no la conoce, así
-- que se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la 6.4.0**: si no, el recargo
-- que guarde el jefe queda trabado en la cola de subida, y una tablet no queda
-- "Lista para trabajar sin internet" (lo baja al prepararse).
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Lo que vale (de 0 a 100) lo controla la app, y un
-- test compara este archivo con lo que manda.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. barra_recargos ───────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.barra_recargos;

create table if not exists public.barra_recargos (
  id uuid primary key,
  evento_id uuid not null,
  recargo_pct numeric not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_recargos_evento
  on public.barra_recargos(evento_id);

create index if not exists idx_barra_recargos_updated
  on public.barra_recargos(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las demás de la barra, cualquier usuario logueado.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- una fila nueva no cruza nunca a la otra PC, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de arriba). Si se deshace solo esta
-- sección y la tabla queda, van las cuatro líneas: sin la última, la tabla queda
-- con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "barra_recargos_all_authenticated" on public.barra_recargos;
--   drop trigger if exists set_updated_at_ins_barra_recargos on public.barra_recargos;
--   drop trigger if exists set_updated_at_upd_barra_recargos on public.barra_recargos;
--   alter table public.barra_recargos disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['barra_recargos']
  loop
    execute format('alter table public.%I enable row level security', t);

    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = t
        and policyname = t || '_all_authenticated'
    ) then
      execute format(
        'create policy %I on public.%I for all '
        'using (auth.role() = ''authenticated'') '
        'with check (auth.role() = ''authenticated'')',
        t || '_all_authenticated', t);
    end if;

    execute format(
      'drop trigger if exists set_updated_at_ins_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_ins_%1$I before insert on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);

    execute format(
      'drop trigger if exists set_updated_at_upd_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_upd_%1$I before update on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);
  end loop;
end $$;

-- ── 3. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.barra_precios)             as precios_barra,
--     (select count(*) from public.barra_ventas)              as ventas_barra,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: la tabla con RLS prendida, y exactamente un disparador de insert y
-- uno de update. Tiene que devolver una fila, con rls = true, trg_insert = 1 y
-- trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('barra_recargos')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('barra_recargos');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('barra_recargos');
