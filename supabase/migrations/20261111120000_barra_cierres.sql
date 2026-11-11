-- 2026-11-11 — Una tabla nueva: el cierre de una caja de barra con el OK de la
-- encargada. Va con la v79 de la base local.
--
-- Pedido del usuario del 11-nov: la caja se cierra cuando la encargada acepta.
-- La cajera cuenta a ciegas y su tablet anota el **pedido** (con lo contado); el
-- aparato de la encargada anota la **respuesta** (ok, o que cuente de nuevo); y
-- con el ok la tablet de la cajera cierra la caja. Cada paso es una fila.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. `barra_cajas` queda como
-- está: la caja la sigue cerrando su propio equipo. La 6.5.1 no conoce esta
-- tabla, así que se puede correr a cualquier hora antes de instalar sin que las
-- PCs ni las tablets lo noten. **Tiene que estar corrido antes de instalar la
-- versión que lo usa**: si no, cada pedido de cierre queda trabado en la cola de
-- subida.
--
-- **Las filas solo se agregan.** Nada se borra ni se edita.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Lo que vale lo controla la app (y un test compara
-- este archivo con lo que manda). `tipo` es un texto: pedido, ok, recontar,
-- cancelado o sin_ok; un valor que una versión no conoce lo ignora.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. barra_cierres ────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.barra_cierres;

create table if not exists public.barra_cierres (
  id uuid primary key,
  caja_barra_id uuid not null,
  evento_id uuid not null,
  tipo text not null,
  pedido_id uuid,
  efectivo_contado numeric,
  nota text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_cierres_evento
  on public.barra_cierres(evento_id);

create index if not exists idx_barra_cierres_caja
  on public.barra_cierres(caja_barra_id);

create index if not exists idx_barra_cierres_updated
  on public.barra_cierres(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las demás de la barra, cualquier usuario logueado.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- una fila nueva no cruza nunca al otro equipo, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de arriba). Si se deshace solo esta
-- sección y la tabla queda, van las cuatro líneas: sin la última, la tabla queda
-- con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "barra_cierres_all_authenticated" on public.barra_cierres;
--   drop trigger if exists set_updated_at_ins_barra_cierres on public.barra_cierres;
--   drop trigger if exists set_updated_at_upd_barra_cierres on public.barra_cierres;
--   alter table public.barra_cierres disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['barra_cierres']
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
--     (select count(*) from public.barra_cajas)               as cajas_barra,
--     (select count(*) from public.barra_ventas)              as ventas_barra,
--     (select count(*) from public.barra_anulaciones)         as anulaciones_barra,
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
--     and c.relname in ('barra_cierres')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('barra_cierres');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('barra_cierres');
