-- 2026-11-07 — Una tabla nueva: los vales que salieron de cada venta de la barra
-- (6.4.0, etapa 5). Va con la v78 de la base local, junto con `sillas_puerta`.
--
-- Cada papel de vale que **salió** es una fila: el original, y cada copia que se
-- reimprimió (con quién, cuándo y el motivo). Sirve para que una copia saque el
-- mismo vale que salió, y para que la cajera reimprima una sola vez. La venta no
-- se toca: nunca se edita.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 6.3.1 no la conoce, así
-- que se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la 6.4.0**: si no, cada vale
-- que salga queda trabado en la cola de subida.
--
-- **Las filas solo se agregan.** Nada se borra ni se edita.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Lo que vale lo controla la app (y un test compara
-- este archivo con lo que manda). Las casillas van en `integer` (0 y 1, como en la
-- PC); `bebidas` es un texto con el JSON de lo que dice el vale.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. barra_vales ──────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.barra_vales;

create table if not exists public.barra_vales (
  id uuid primary key,
  venta_id uuid not null,
  caja_barra_id uuid not null,
  evento_id uuid not null,
  numero_vale integer,
  bebidas text not null,
  por_separado integer not null default 0,
  copia_numero integer not null default 0,
  motivo text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_vales_evento
  on public.barra_vales(evento_id);

create index if not exists idx_barra_vales_venta
  on public.barra_vales(venta_id);

create index if not exists idx_barra_vales_updated
  on public.barra_vales(updated_at desc);

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
--   drop policy if exists "barra_vales_all_authenticated" on public.barra_vales;
--   drop trigger if exists set_updated_at_ins_barra_vales on public.barra_vales;
--   drop trigger if exists set_updated_at_upd_barra_vales on public.barra_vales;
--   alter table public.barra_vales disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['barra_vales']
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
--     and c.relname in ('barra_vales')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('barra_vales');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('barra_vales');
