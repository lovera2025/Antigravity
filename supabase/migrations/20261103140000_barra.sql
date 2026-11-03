-- 2026-11-03 — Cinco tablas nuevas: la barra. El catálogo de productos, el precio de
-- cada uno en cada fiesta, las cajas de barra, las ventas y sus anulaciones. Van con
-- la v77 de la base local.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 6.2.1 no las conoce, así
-- que esto se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la versión nueva**: si no, cada
-- PC falla al bajar estas tablas en cada ciclo, lo que se venda queda trabado en la
-- cola, y la revisión de la mora no corre (espera una bajada sin fallas).
--
-- `barra_productos`: el catálogo, de todas las fiestas. Dar de baja le pone
-- `activo = 0`; no se borra.
-- `barra_precios`: una fila por producto y fiesta, con id fijo. Sacarlo de la lista
-- de una fiesta le pone `activo = 0`; no se borra. `stock_inicial` nulo: sin control.
-- `barra_cajas`: la abre la cajera en su equipo; cerrarla la actualiza.
-- `barra_ventas`: **una venta nunca se edita ni se borra**. `renglones` es un texto
-- con el JSON de lo vendido, con el nombre y el precio de ese momento.
-- `barra_anulaciones`: una por venta, con id fijo. Solo se agregan filas.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de sync
-- de la app toma cualquier "violates" como un padre que falta y la fila queda trabada
-- para siempre: una venta que no sube. Lo que vale lo controla la app (y un test
-- compara este archivo con lo que manda).
--
-- La plata va en `numeric`, las casillas en `integer` (0 y 1, como en la PC).
--
-- La foto de cada producto (el depósito `barra` de Storage) no va acá: va con el
-- catálogo del jefe, en otro archivo.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. Las tablas ───────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.barra_productos;

create table if not exists public.barra_productos (
  id uuid primary key,
  nombre text not null,
  categoria text,
  activo integer not null default 1,
  orden integer not null default 0,
  imagen_url text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ROLLBACK: drop table if exists public.barra_precios;

create table if not exists public.barra_precios (
  id uuid primary key,
  evento_id uuid not null,
  producto_id uuid not null,
  precio numeric not null,
  activo integer not null default 1,
  orden integer not null default 0,
  stock_inicial integer,
  aviso_stock integer,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ROLLBACK: drop table if exists public.barra_cajas;

create table if not exists public.barra_cajas (
  id uuid primary key,
  evento_id uuid not null,
  operador_id uuid,
  operador_nombre text,
  numero_caja integer not null,
  sede text,
  cambio_inicial numeric not null default 0,
  abierta_at timestamptz not null,
  cerrada_at timestamptz,
  efectivo_contado numeric,
  diferencia numeric,
  nota_cierre text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ROLLBACK: drop table if exists public.barra_ventas;

create table if not exists public.barra_ventas (
  id uuid primary key,
  caja_barra_id uuid not null,
  evento_id uuid not null,
  numero integer not null,
  renglones text not null,
  total numeric not null,
  medio text not null,
  efectivo numeric not null default 0,
  transferencia numeric not null default 0,
  recibe numeric,
  vuelto numeric not null default 0,
  comprobante_visto integer not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ROLLBACK: drop table if exists public.barra_anulaciones;

create table if not exists public.barra_anulaciones (
  id uuid primary key,
  venta_id uuid not null,
  caja_barra_id uuid not null,
  evento_id uuid not null,
  motivo text not null,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Índices comunes, no únicos: un "violates" trabaría la fila en la cola (ver
-- arriba). El número del ticket no se repite porque una caja vive en un solo equipo.
create index if not exists idx_barra_productos_updated
  on public.barra_productos(updated_at desc);

create index if not exists idx_barra_precios_evento
  on public.barra_precios(evento_id);

create index if not exists idx_barra_precios_updated
  on public.barra_precios(updated_at desc);

create index if not exists idx_barra_cajas_evento
  on public.barra_cajas(evento_id);

create index if not exists idx_barra_cajas_updated
  on public.barra_cajas(updated_at desc);

create index if not exists idx_barra_ventas_evento
  on public.barra_ventas(evento_id);

create index if not exists idx_barra_ventas_caja
  on public.barra_ventas(caja_barra_id);

create index if not exists idx_barra_ventas_updated
  on public.barra_ventas(updated_at desc);

create index if not exists idx_barra_anulaciones_evento
  on public.barra_anulaciones(evento_id);

create index if not exists idx_barra_anulaciones_updated
  on public.barra_anulaciones(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `permisos_operador` y `mora_congelada`, cualquier usuario logueado.
-- Un anónimo no ve nada: la página del QR y el tótem no tienen nada que hacer acá.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- un cambio no cruza nunca a la otra PC, porque el pull filtra por `updated_at`
-- y el motor no lo rellena.
--
-- ROLLBACK (lo borran solos los `drop table` de arriba). Si se deshace solo esta
-- sección y las tablas quedan, van estas líneas por cada tabla (barra_productos,
-- barra_precios, barra_cajas, barra_ventas, barra_anulaciones): sin la última, la
-- tabla queda con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "barra_productos_all_authenticated" on public.barra_productos;
--   drop trigger if exists set_updated_at_ins_barra_productos on public.barra_productos;
--   drop trigger if exists set_updated_at_upd_barra_productos on public.barra_productos;
--   alter table public.barra_productos disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['barra_productos', 'barra_precios', 'barra_cajas', 'barra_ventas', 'barra_anulaciones']
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
--     (select count(*) from public.operadores_caja)           as operadores,
--     (select count(*) from public.sesiones_caja)             as sesiones,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: las tablas con RLS prendida, y exactamente un disparador de insert y
-- uno de update. Tiene que devolver cinco filas, con rls = true, trg_insert = 1 y
-- trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('barra_productos', 'barra_precios', 'barra_cajas',
--                       'barra_ventas', 'barra_anulaciones')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver cinco filas). La consulta de arriba no la ve, y con
-- RLS prendida sin policy la app no puede subir nada:
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('barra_productos', 'barra_precios', 'barra_cajas',
--                       'barra_ventas', 'barra_anulaciones');
--
-- Y que no entraron a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('barra_productos', 'barra_precios', 'barra_cajas',
--                       'barra_ventas', 'barra_anulaciones');
