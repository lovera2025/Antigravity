-- 2026-09-26 — Dos tablas nuevas: el plano de cada fiesta y los cambios de mesa.
-- Van con la v73 de la base local.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 5.0.0 no las conoce, así
-- que esto se puede correr cualquier noche antes de publicar sin que las PCs lo
-- noten.
--
-- Es independiente del SQL de la Fase 2
-- (`20260925120000_sillas_retiro_sorteos.sql`): solo apunta a `eventos`. Pero
-- **los dos tienen que estar corridos antes de instalar la versión nueva**; si
-- no, lo que se cargue en estas tablas queda trabado en la cola de subida.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK en `estilo`, `modo_sorteo` ni `tipo`, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta: reencola el
-- evento y la fila queda trabada para siempre. Los valores válidos los controla
-- la app (y un test compara este archivo con lo que la app manda):
--   estilo       gala | arquitecto | neon
--   modo_sorteo  entera | bloques
--   tipo         intercambio | mover | deshacer
--
-- Cómo correrlo (SQL Editor, después de las 20 hs):
--   1. Correr la consulta "ANTES" de la sección 4 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 4 y comparar.

-- ── 1. planos_evento ────────────────────────────────────────────────────────
--
-- Una fila por fiesta (id fijo, `UuidUtils.planoEventoId`). Lleva la copia del
-- armado del salón que eligió la fiesta (JSON en texto, para que vuelva igual),
-- el estilo del plano, cómo se sortea y, en `config` (JSON en texto), las mesas
-- fijas y libres, el orden de las divisiones, los bloques, colores y textos.
--
-- ROLLBACK: drop table if exists public.planos_evento;

create table if not exists public.planos_evento (
  id uuid primary key,
  evento_id uuid not null
    references public.eventos(id) on delete cascade,
  armado text not null,
  armado_json text not null,
  estilo text not null,
  modo_sorteo text not null,
  config text not null default '{}',
  hecho_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint planos_evento_uniq_evento unique (evento_id)
);

create index if not exists idx_planos_evento_updated
  on public.planos_evento(updated_at desc);

-- ── 2. mesas_movimientos ────────────────────────────────────────────────────
--
-- Solo se agregan renglones: cada cambio o movida de familias deja uno, con cómo
-- estaban (`antes`), cómo quedaron (`despues`) y por qué (`motivo`, obligatorio).
-- Deshacer es otro renglón (`deshace_id`), nunca un borrado.
--
-- ROLLBACK: drop table if exists public.mesas_movimientos;

create table if not exists public.mesas_movimientos (
  id uuid primary key,
  evento_id uuid not null
    references public.eventos(id) on delete cascade,
  tipo text not null,
  antes text not null,
  despues text not null,
  motivo text not null,
  deshace_id uuid,
  avisos text,
  hecho_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_mesas_movimientos_evento
  on public.mesas_movimientos(evento_id, created_at);

create index if not exists idx_mesas_movimientos_updated
  on public.mesas_movimientos(updated_at desc);

-- ── 3. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las tablas de la Fase 2, cualquier usuario logueado. Un anónimo
-- no ve nada. (Cuando en diciembre el tótem muestre el plano, lo va a leer por
-- el puente de la PC o por una función; no se abre la tabla a anónimos.)
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- una edición no cruza nunca a la otra PC, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK, por tabla (lo borra solo el `drop table` de arriba). Si se deshace
-- solo esta sección y las tablas quedan, van las cuatro líneas: sin la última,
-- la tabla queda con RLS prendida y sin policy, la app no puede subir nada y la
-- otra PC no se entera.
--   drop policy if exists "<tabla>_all_authenticated" on public.<tabla>;
--   drop trigger if exists set_updated_at_ins_<tabla> on public.<tabla>;
--   drop trigger if exists set_updated_at_upd_<tabla> on public.<tabla>;
--   alter table public.<tabla> disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['planos_evento', 'mesas_movimientos']
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

-- ── 4. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.notas_operativas_contrato) as notas,
--     (select count(*) from public.invitados)                 as invitados,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: las dos tablas con RLS prendida, y exactamente un disparador de
-- insert y uno de update cada una. Tiene que devolver dos filas, las dos con
-- rls = true, trg_insert = 1 y trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('planos_evento', 'mesas_movimientos')
--   group by c.relname, c.relrowsecurity;
--
-- La policy de cada una (tiene que devolver dos filas). La consulta de arriba no
-- la ve, y con RLS prendida sin policy la app no puede subir nada:
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename in ('planos_evento', 'mesas_movimientos');
--
-- Y que ninguna entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('planos_evento', 'mesas_movimientos');
