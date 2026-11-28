-- 2026-11-28 — Una tabla nueva: cómo nombra el locutor a cada egresado y a sus
-- acompañantes (el locutor, "Cómo lo nombran"). Va con la v85 de la base local.
--
-- La recepcionista cambia, la noche de la fiesta, solo cómo nombrar al egresado y a sus
-- acompañantes ("Juani 'el Tano' Pérez" en vez de "PÉREZ, JUAN IGNACIO"). **La ficha de
-- la oficina no cambia**: esto va aparte, una fila por alumno con id fijo.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus índices,
-- su RLS y sus disparadores de `updated_at`. Una versión anterior no la conoce, así que
-- se puede correr a cualquier hora antes de instalar. **Tiene que estar corrido antes de
-- instalar la versión con la v85**: si no, lo que se nombre queda trabado en la cola, y
-- en las PCs nuevas la bajada de esta tabla falla (y con eso no corre la revisión de la
-- mora al arrancar: la corre solo sin tablas que fallen).
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito** (el motor de sync
-- toma cualquier "violates" como un padre que falta y la fila queda trabada).
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. como_lo_nombran ──────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.como_lo_nombran;

create table if not exists public.como_lo_nombran (
  id uuid primary key,
  evento_id uuid not null,
  contrato_alumno_id uuid not null,
  alumno text,
  alumno_cargado text,
  acompanantes text not null default '[]',
  cambiado_por text,
  cambiado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_como_lo_nombran_evento
  on public.como_lo_nombran(evento_id);

create index if not exists idx_como_lo_nombran_contrato
  on public.como_lo_nombran(contrato_alumno_id);

create index if not exists idx_como_lo_nombran_updated
  on public.como_lo_nombran(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `sillas_puerta`, cualquier usuario
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
--   drop policy if exists "como_lo_nombran_all_authenticated" on public.como_lo_nombran;
--   drop trigger if exists set_updated_at_ins_como_lo_nombran on public.como_lo_nombran;
--   drop trigger if exists set_updated_at_upd_como_lo_nombran on public.como_lo_nombran;
--   alter table public.como_lo_nombran disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['como_lo_nombran']
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
--     and c.relname in ('como_lo_nombran')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('como_lo_nombran');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('como_lo_nombran');
