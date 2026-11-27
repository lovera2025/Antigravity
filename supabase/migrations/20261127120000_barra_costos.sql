-- 2026-11-26 — Dos tablas nuevas: el precio de lista de la barra y las recetas de los
-- tragos. Van con la v84 de la base local (plan del 26-nov, audio 77 del jefe, y sus
-- mensajes de esa noche por WhatsApp).
--
-- Pedido del jefe: al cargar el stock pone lo que le cobra el proveedor por unidad
-- (el "precio de lista"); vende a su precio; y ve, **solo él** (pestaña GANANCIA,
-- en modo jefe), lo que se vendió, lo que le debe al proveedor y lo que ganó,
-- juntando las noches que rinde de una vez.
--
-- - `barra_costos`: el precio de lista de un producto en una fiesta. Una fila por
--   fiesta y producto, con id fijo: si el jefe lo cambia desde dos equipos,
--   escriben la misma (gana la última). `precio_lista` nulo: falta cargarlo; en 0:
--   no se le paga a nadie (la silla). `contenido_cc`: cuántos cc trae la botella
--   (750, 2250) si se sirve en tragos por cc; nulo si no. No se borra. **Solo del
--   jefe**: la tablet no la baja y no viaja por la red del salón.
-- - `barra_recetas`: lo que lleva un trago en una fiesta ("el Fernet con coca lleva
--   200 cc de fernet y 500 de coca"; "el vodka, 500 cc de vodka y un Speed"). Una
--   fila por fiesta, trago e ingrediente, con id fijo. `unidad`: 'cc' (no se cuenta
--   en la barra: sirve para calcular botellas) o 'unidad' (baja del stock, como el
--   Speed). Sacar un ingrediente le pone `activo` en false: no se borra. **No lleva
--   plata**: la baja la tablet (el Speed del vodka baja su stock).
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. Las versiones anteriores no
-- conocen esta tabla, así que se puede correr a cualquier hora antes de instalar.
-- **Tiene que estar corrido antes de instalar la versión que lo usa**: si no, cada
-- precio de lista queda trabado en la cola de subida.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito**: el motor de
-- sync toma cualquier "violates" como un padre que falta y la fila queda trabada
-- para siempre. Lo que vale lo controla la app.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. La tabla ─────────────────────────────────────────────────────────────
--
-- ROLLBACK:
--   drop table if exists public.barra_costos;
--   drop table if exists public.barra_recetas;

create table if not exists public.barra_costos (
  id uuid primary key,
  evento_id uuid not null,
  producto_id uuid not null,
  precio_lista numeric,
  contenido_cc integer,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_costos_evento
  on public.barra_costos(evento_id);

create index if not exists idx_barra_costos_updated
  on public.barra_costos(updated_at desc);

create table if not exists public.barra_recetas (
  id uuid primary key,
  evento_id uuid not null,
  producto_id uuid not null,
  ingrediente_id uuid not null,
  cantidad integer not null default 0,
  unidad text not null default 'cc',
  activo boolean not null default true,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_barra_recetas_evento
  on public.barra_recetas(evento_id);

create index if not exists idx_barra_recetas_updated
  on public.barra_recetas(updated_at desc);

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
--   drop policy if exists "barra_costos_all_authenticated" on public.barra_costos;
--   drop trigger if exists set_updated_at_ins_barra_costos on public.barra_costos;
--   drop trigger if exists set_updated_at_upd_barra_costos on public.barra_costos;
--   alter table public.barra_costos disable row level security;
--   (y lo mismo con barra_recetas)

do $$
declare
  t text;
begin
  foreach t in array array['barra_costos', 'barra_recetas'] loop
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
-- uno de update cada una. Tiene que devolver dos filas, con rls = true, trg_insert = 1
-- y trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('barra_costos', 'barra_recetas')
--   group by c.relname, c.relrowsecurity;
--
-- Las policies (tiene que devolver dos filas):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public' and tablename in ('barra_costos', 'barra_recetas');
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and tablename in ('barra_costos', 'barra_recetas');
