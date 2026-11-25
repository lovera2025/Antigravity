-- 2026-11-25 — Dos tablas nuevas: el repositor y el stock por barra. Van con la v83
-- de la base local (`docs/SPEC_repositor_y_stock_por_barra_2026-11-25.md`).
--
-- Pedido del usuario del 25-nov: el jefe carga el stock general y reparte con cuánto
-- arranca cada barra; el depósito es el límite; el repositor repone, pasa de una barra
-- a otra explicando por qué, anota faltantes con motivo, cuenta lo que hay y avisa
-- "voy en camino"; sin stock no se vende.
--
-- - `barra_stock_barras`: con cuánto arranca cada producto en cada barra y desde
--   cuánto se avisa. Una fila por fiesta, producto y barra, con id fijo: si el jefe la
--   cambia desde dos equipos, escriben la misma (gana la última). Sacarla es
--   `activo = 0`: no se borra.
-- - `barra_stock_movimientos`: lo que hace el repositor. **Solo se agregan filas.**
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. Las versiones anteriores no
-- conocen estas tablas, así que se puede correr a cualquier hora antes de instalar
-- sin que las PCs ni las tablets lo noten. **Tiene que estar corrido antes de
-- instalar la versión que lo usa**: si no, cada reposición queda trabada en la cola
-- de subida.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de sync
-- de la app toma cualquier "violates" como un padre que falta y la fila queda trabada
-- para siempre. Lo que vale lo controla la app (y `test/sync_tablas_v83_test.dart`
-- compara este archivo con lo que manda). `tipo` es un texto: entrada, reposicion,
-- traspaso, faltante, conteo, en_camino o en_camino_no; un valor que una versión no
-- conoce lo ignora.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. Las tablas ───────────────────────────────────────────────────────────
--
-- ROLLBACK:
--   drop table if exists public.barra_stock_barras;
--   drop table if exists public.barra_stock_movimientos;

create table if not exists public.barra_stock_barras (
  id uuid primary key,
  evento_id uuid not null,
  producto_id uuid not null,
  barra text not null,
  arranque integer not null default 0,
  aviso integer,
  activo integer not null default 1,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_stock_barras_evento
  on public.barra_stock_barras(evento_id);

create index if not exists idx_barra_stock_barras_updated
  on public.barra_stock_barras(updated_at desc);

create table if not exists public.barra_stock_movimientos (
  id uuid primary key,
  evento_id uuid not null,
  producto_id uuid not null,
  tipo text not null,
  cantidad integer not null default 0,
  desde text,
  hacia text,
  contadas integer,
  ajuste integer not null default 0,
  motivo text,
  nota text,
  conocido text,
  avisos_previos integer,
  responde_a uuid,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_stock_movimientos_evento
  on public.barra_stock_movimientos(evento_id);

create index if not exists idx_barra_stock_movimientos_updated
  on public.barra_stock_movimientos(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las demás de la barra, cualquier usuario logueado.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- una fila nueva no cruza nunca al otro equipo, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK (lo borran solos los `drop table` de arriba). Si se deshace solo esta
-- sección y las tablas quedan, van las cuatro líneas por tabla: sin la última, la
-- tabla queda con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "barra_stock_barras_all_authenticated" on public.barra_stock_barras;
--   drop trigger if exists set_updated_at_ins_barra_stock_barras on public.barra_stock_barras;
--   drop trigger if exists set_updated_at_upd_barra_stock_barras on public.barra_stock_barras;
--   alter table public.barra_stock_barras disable row level security;
--   (lo mismo con barra_stock_movimientos)

do $$
declare
  t text;
begin
  foreach t in array array['barra_stock_barras', 'barra_stock_movimientos']
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
--     (select count(*) from public.barra_cajas)               as cajas_barra,
--     (select count(*) from public.barra_ventas)              as ventas_barra,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: las dos tablas con RLS prendida, y exactamente un disparador de insert y
-- uno de update. Tiene que devolver dos filas, con rls = true, trg_insert = 1 y
-- trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('barra_stock_barras', 'barra_stock_movimientos')
--   group by c.relname, c.relrowsecurity;
--
-- Las policies (tiene que devolver dos filas):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('barra_stock_barras', 'barra_stock_movimientos');
--
-- Y que no entraron a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('barra_stock_barras', 'barra_stock_movimientos');
