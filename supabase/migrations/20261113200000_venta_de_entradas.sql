-- 2026-11-13 — Cinco tablas nuevas: la venta de entradas. Van con la v80 de la
-- base local (`docs/SPEC_venta_de_entradas_2026-11-13.md`).
--
-- Una caja de entradas por fiesta, aparte de la de cuotas y de la de la barra:
-- el jefe pone el precio (`entradas_config`), quien vende abre su caja
-- (`entradas_cajas`) y anota cada venta (`entradas_ventas`); anular es otra fila
-- (`entradas_anulaciones`) y "Pago verificado", otra (`entradas_verificaciones`).
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. Una venta de entradas no
-- es un pago de cuota: nada de esto escribe en `contratos_alumnos`,
-- `pagos_contrato_alumno` ni `sesiones_caja`. Las versiones anteriores no
-- conocen estas tablas, así que se puede correr a cualquier hora antes de
-- instalar sin que las PCs ni las tablets lo noten. **Tiene que estar corrido
-- antes de instalar la versión que las usa**: si no, cada PC falla al bajar en
-- cada pasada y lo vendido queda trabado en la cola de subida.
--
-- **Nada se borra.** Una venta nunca se edita: anularla es otra fila. Una caja se
-- cierra. El precio y "Pago verificado" son una fila por fiesta o por venta, con
-- id fijo, que se actualiza.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Lo que vale lo controla la app (y un test compara
-- este archivo con lo que manda). La plata va en `numeric` y las casillas en
-- `integer` (0 y 1), como en la barra.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 7 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 7 y comparar.

-- ── 1. entradas_config: el precio de la fiesta ──────────────────────────────
--
-- Una fila por fiesta, con id fijo. Sin `valor_entrada`, esa fiesta no se vende.
--
-- ROLLBACK: drop table if exists public.entradas_config;

create table if not exists public.entradas_config (
  id uuid primary key,
  evento_id uuid not null,
  valor_entrada numeric,
  precio_anticipada numeric,
  anticipada_hasta text,
  descuento_lugares_pct numeric not null default 50,
  recargo_pct numeric not null default 0,
  descuento_a_mano integer not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_config_evento
  on public.entradas_config(evento_id);

create index if not exists idx_entradas_config_updated
  on public.entradas_config(updated_at desc);

-- ── 2. entradas_cajas: la caja de quien vende ───────────────────────────────
--
-- La abre quien vende, en su equipo, y vive en ese equipo. Cerrarla la actualiza.
--
-- ROLLBACK: drop table if exists public.entradas_cajas;

create table if not exists public.entradas_cajas (
  id uuid primary key,
  evento_id uuid not null,
  operador_id uuid,
  operador_nombre text,
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

create index if not exists idx_entradas_cajas_evento
  on public.entradas_cajas(evento_id);

create index if not exists idx_entradas_cajas_updated
  on public.entradas_cajas(updated_at desc);

-- ── 3. entradas_ventas: cada venta ──────────────────────────────────────────
--
-- Nunca se edita ni se borra. `renglones` es un JSON en texto, con el nombre y
-- el precio de ese momento. `contrato_alumno_id` vacío: alguien de afuera.
--
-- ROLLBACK: drop table if exists public.entradas_ventas;

create table if not exists public.entradas_ventas (
  id uuid primary key,
  caja_entradas_id uuid not null,
  evento_id uuid not null,
  numero integer not null,
  contrato_alumno_id uuid,
  comprador_nombre text not null,
  comprador_dni text,
  renglones text not null,
  cantidad integer not null,
  total numeric not null,
  descuento numeric not null default 0,
  medio text not null,
  efectivo numeric not null default 0,
  transferencia numeric not null default 0,
  recibe numeric,
  vuelto numeric not null default 0,
  recargo numeric not null default 0,
  recargo_pct numeric,
  numeros text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_ventas_evento
  on public.entradas_ventas(evento_id);

create index if not exists idx_entradas_ventas_caja
  on public.entradas_ventas(caja_entradas_id);

create index if not exists idx_entradas_ventas_alumno
  on public.entradas_ventas(contrato_alumno_id);

create index if not exists idx_entradas_ventas_updated
  on public.entradas_ventas(updated_at desc);

-- ── 4. entradas_anulaciones ─────────────────────────────────────────────────
--
-- Una por venta, con id fijo. Solo se agregan. `devueltas`: 1 si devolvieron las
-- entradas y las pulseras.
--
-- ROLLBACK: drop table if exists public.entradas_anulaciones;

create table if not exists public.entradas_anulaciones (
  id uuid primary key,
  venta_id uuid not null,
  caja_entradas_id uuid not null,
  evento_id uuid not null,
  motivo text not null,
  devueltas integer not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_anulaciones_evento
  on public.entradas_anulaciones(evento_id);

create index if not exists idx_entradas_anulaciones_caja
  on public.entradas_anulaciones(caja_entradas_id);

create index if not exists idx_entradas_anulaciones_updated
  on public.entradas_anulaciones(updated_at desc);

-- ── 5. entradas_verificaciones: "Pago verificado" ───────────────────────────
--
-- Una por venta, con id fijo. Tildar y destildar la actualiza. Va aparte para no
-- editar la venta.
--
-- ROLLBACK: drop table if exists public.entradas_verificaciones;

create table if not exists public.entradas_verificaciones (
  id uuid primary key,
  venta_id uuid not null,
  evento_id uuid not null,
  verificado integer not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_verificaciones_evento
  on public.entradas_verificaciones(evento_id);

create index if not exists idx_entradas_verificaciones_updated
  on public.entradas_verificaciones(updated_at desc);

-- ── 6. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las de la barra, cualquier usuario logueado. Un anónimo no ve
-- nada.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- una fila nueva no cruza nunca al otro equipo, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de cada tabla). Si se deshace solo
-- esta sección y las tablas quedan, por cada una van las cuatro líneas: sin la
-- última, la tabla queda con RLS prendida y sin policy, y la app no puede subir
-- nada.
--   drop policy if exists "<tabla>_all_authenticated" on public.<tabla>;
--   drop trigger if exists set_updated_at_ins_<tabla> on public.<tabla>;
--   drop trigger if exists set_updated_at_upd_<tabla> on public.<tabla>;
--   alter table public.<tabla> disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'entradas_config',
    'entradas_cajas',
    'entradas_ventas',
    'entradas_anulaciones',
    'entradas_verificaciones'
  ]
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

-- ── 7. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.sesiones_caja)             as sesiones,
--     (select count(*) from public.entradas_retiro)           as retiros,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: las cinco tablas con RLS prendida, y exactamente un disparador de
-- insert y uno de update cada una. Tiene que devolver cinco filas, todas con
-- rls = true, trg_insert = 1 y trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('entradas_config', 'entradas_cajas', 'entradas_ventas',
--                       'entradas_anulaciones', 'entradas_verificaciones')
--   group by c.relname, c.relrowsecurity
--   order by c.relname;
--
-- Las policies (tiene que devolver cinco filas):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename like 'entradas\_%' escape '\'
--     and tablename <> 'entradas_retiro'
--   order by tablename;
--
-- Y que ninguna entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('entradas_config', 'entradas_cajas', 'entradas_ventas',
--                       'entradas_anulaciones', 'entradas_verificaciones');
