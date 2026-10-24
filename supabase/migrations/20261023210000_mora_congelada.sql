-- 2026-10-23 — Una tabla nueva: la mora congelada (6.2.1). Va con la v75 de la
-- base local.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, su
-- índice, su RLS y sus disparadores de `updated_at`. La 6.2.0 no la conoce, así
-- que esto se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la 6.2.1**: si no, lo que se
-- congele queda trabado en la cola de subida.
--
-- Una fila por alumno (id fijo, el mismo en todas las PCs): `pausas` es la lista
-- de tramos en que la mora de una cuota (o de todas) no corrió, en JSON en texto.
-- **Descongelar no borra la fila**: la guarda con otras pausas.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK y sin clave foránea, a propósito.** El motor de sync de la app toma
-- cualquier "violates" como un padre que falta y la fila queda trabada para
-- siempre. Lo que vale lo controla la app (y un test compara este archivo con lo
-- que manda).
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. mora_congelada ───────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.mora_congelada;

create table if not exists public.mora_congelada (
  id uuid primary key,
  contrato_alumno_id uuid not null,
  evento_id uuid,
  pausas text not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Índice común, no único: un "violates" trabaría la fila en la cola (ver
-- arriba). No hace falta: el id sale del alumno, así que hay una fila por alumno.
create index if not exists idx_mora_congelada_contrato
  on public.mora_congelada(contrato_alumno_id);

create index if not exists idx_mora_congelada_updated
  on public.mora_congelada(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `predios` y `entradas_retiro`, cualquier usuario logueado. Un
-- anónimo no ve nada.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- un cambio no cruza nunca a la otra PC, porque el pull filtra por `updated_at`
-- y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de arriba). Si se deshace solo esta
-- sección y la tabla queda, van las cuatro líneas: sin la última, la tabla queda
-- con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "mora_congelada_all_authenticated" on public.mora_congelada;
--   drop trigger if exists set_updated_at_ins_mora_congelada on public.mora_congelada;
--   drop trigger if exists set_updated_at_upd_mora_congelada on public.mora_congelada;
--   alter table public.mora_congelada disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['mora_congelada']
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
--     (select count(*) from public.entradas_retiro)           as entradas,
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
--     and c.relname in ('mora_congelada')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila). La consulta de arriba no la ve, y con
-- RLS prendida sin policy la app no puede subir nada:
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('mora_congelada');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('mora_congelada');
