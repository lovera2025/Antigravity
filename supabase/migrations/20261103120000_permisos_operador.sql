-- 2026-11-03 — Dos tablas nuevas: los permisos de los operadores (Cobros, Entradas,
-- Barra) y el registro de quién dio o sacó cada uno. Van con la v76 de la base local.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 6.2.1 no las conoce, así
-- que esto se puede correr a cualquier hora antes de instalar sin que las PCs lo
-- noten. **Tiene que estar corrido antes de instalar la versión nueva**: si no, lo
-- que se cambie en OPERADORES queda trabado en la cola de subida.
--
-- `permisos_operador`: una fila por operador, con id fijo. **Un operador sin fila es
-- de Cobros solo**: así siguen los de hoy, con su mismo PIN. Sacar un permiso la
-- actualiza; no se borra nunca. No va en `operadores_caja` porque esa fila se
-- reescribe entera al editar y al bajar.
--
-- `permisos_operador_cambios`: solo se agregan renglones.
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

-- ── 1. Las tablas ───────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.permisos_operador;

create table if not exists public.permisos_operador (
  id uuid primary key,
  operador_id uuid not null,
  cobros integer not null default 0,
  entradas integer not null default 0,
  barra integer not null default 0,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ROLLBACK: drop table if exists public.permisos_operador_cambios;

create table if not exists public.permisos_operador_cambios (
  id uuid primary key,
  operador_id uuid not null,
  permiso text not null,
  dado integer not null,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Índices comunes, no únicos: un "violates" trabaría la fila en la cola (ver
-- arriba). No hace falta: el id sale del operador, así que hay una fila por operador.
create index if not exists idx_permisos_operador_operador
  on public.permisos_operador(operador_id);

create index if not exists idx_permisos_operador_updated
  on public.permisos_operador(updated_at desc);

create index if not exists idx_permisos_operador_cambios_operador
  on public.permisos_operador_cambios(operador_id);

create index if not exists idx_permisos_operador_cambios_updated
  on public.permisos_operador_cambios(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `predios` y `mora_congelada`, cualquier usuario logueado. Un
-- anónimo no ve nada.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- un cambio no cruza nunca a la otra PC, porque el pull filtra por `updated_at`
-- y el motor no lo rellena.
--
-- ROLLBACK (lo borran solos los `drop table` de arriba). Si se deshace solo esta
-- sección y las tablas quedan, van estas líneas: sin la última de cada una, la tabla
-- queda con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "permisos_operador_all_authenticated" on public.permisos_operador;
--   drop trigger if exists set_updated_at_ins_permisos_operador on public.permisos_operador;
--   drop trigger if exists set_updated_at_upd_permisos_operador on public.permisos_operador;
--   alter table public.permisos_operador disable row level security;
--   drop policy if exists "permisos_operador_cambios_all_authenticated" on public.permisos_operador_cambios;
--   drop trigger if exists set_updated_at_ins_permisos_operador_cambios on public.permisos_operador_cambios;
--   drop trigger if exists set_updated_at_upd_permisos_operador_cambios on public.permisos_operador_cambios;
--   alter table public.permisos_operador_cambios disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['permisos_operador', 'permisos_operador_cambios']
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
--     and c.relname in ('permisos_operador', 'permisos_operador_cambios')
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver dos filas). La consulta de arriba no la ve, y con
-- RLS prendida sin policy la app no puede subir nada:
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('permisos_operador', 'permisos_operador_cambios');
--
-- Y que no entraron a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('permisos_operador', 'permisos_operador_cambios');
