-- 2026-11-05 — Una tabla nueva: las sillas que se suman la noche de la fiesta,
-- en la puerta (6.4.0). Va con la v78 de la base local.
--
-- Desde que empiezan los sorteos las sillas extra se piden solo esa noche, ya
-- sentados. La recepcionista ve si la familia puede agregar, la manda a la caja
-- de la barra (que la cobra como un producto y le da un vale) y anota la silla
-- con el número del vale (decisión del jefe, 5-nov). Acá no hay plata.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 6.3.1 no la conoce, así
-- que se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la 6.4.0**: si no, lo que se
-- anote queda trabado en la cola de subida.
--
-- **Las filas solo se agregan**: quitar una silla le pone `quitada_at`, quién y
-- el motivo, y la fila queda. Nada se borra.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Lo que vale lo controla la app (y un test compara
-- este archivo con lo que manda).
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. sillas_puerta ────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.sillas_puerta;

create table if not exists public.sillas_puerta (
  id uuid primary key,
  evento_id uuid not null,
  contrato_alumno_id uuid not null,
  mesa integer not null,
  cantidad integer not null default 1,
  vale text not null,
  anotado_por text,
  nota text,
  quitada_at timestamptz,
  quitada_por text,
  quitada_motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sillas_puerta_evento
  on public.sillas_puerta(evento_id);

create index if not exists idx_sillas_puerta_contrato
  on public.sillas_puerta(contrato_alumno_id);

create index if not exists idx_sillas_puerta_updated
  on public.sillas_puerta(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `mora_congelada` y `entradas_retiro`, cualquier usuario
-- logueado. Un anónimo no ve nada: los celulares de la puerta no leen esta
-- tabla, reciben la lista por la notebook del salón.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- un cambio no cruza nunca a la otra PC, porque el pull filtra por `updated_at`
-- y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de arriba). Si se deshace solo esta
-- sección y la tabla queda, van las cuatro líneas: sin la última, la tabla queda
-- con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "sillas_puerta_all_authenticated" on public.sillas_puerta;
--   drop trigger if exists set_updated_at_ins_sillas_puerta on public.sillas_puerta;
--   drop trigger if exists set_updated_at_upd_sillas_puerta on public.sillas_puerta;
--   alter table public.sillas_puerta disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['sillas_puerta']
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
--     (select count(*) from public.sillas_reparto)            as repartos,
--     (select count(*) from public.invitados)                 as invitados,
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
--     and c.relname in ('sillas_puerta')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('sillas_puerta');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('sillas_puerta');
