-- 2026-09-25 — Tres tablas nuevas: reparto de sillas extra, retiro de entradas
-- y registro de sorteos. Van con la v72 de la base local.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. La 5.0.0 no las conoce, así
-- que esto se puede correr cualquier noche antes de publicar sin que las PCs lo
-- noten.
--
-- Son tablas aparte y no columnas de `contratos_alumnos` a propósito: esa es la
-- fila de la plata, y la app la reescribe entera en varios caminos (Editar alumno,
-- las dos bajadas). Un dato nuevo ahí se pisa en silencio.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- Cómo correrlo (SQL Editor, después de las 20 hs):
--   1. Correr la consulta "ANTES" de la sección 5 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 5 y comparar.

-- ── 1. sillas_reparto ───────────────────────────────────────────────────────
--
-- Una fila por alumno (id fijo, `UuidUtils.sillasRepartoId`). Cuántas sillas
-- extra van a la mesa principal, y para qué cuenta se eligió.
--
-- ROLLBACK: drop table if exists public.sillas_reparto;

create table if not exists public.sillas_reparto (
  id uuid primary key,
  contrato_alumno_id uuid not null
    references public.contratos_alumnos(id) on delete cascade,
  sillas_principal integer not null check (sillas_principal >= 0),
  sillas_extra integer not null check (sillas_extra >= 0),
  mesas integer not null check (mesas >= 0),
  hecho_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sillas_reparto_uniq_contrato unique (contrato_alumno_id)
);

create index if not exists idx_sillas_reparto_updated
  on public.sillas_reparto(updated_at desc);

-- ── 2. entradas_retiro ──────────────────────────────────────────────────────
--
-- Una fila por alumno (id fijo, `UuidUtils.entradasRetiroId`): un egresado no
-- puede tener dos retiros. Anular no borra: cambia el estado y anota quién y por
-- qué. `tramos` son los números del talonario: "1043-1058,1101-1108".
--
-- ROLLBACK: drop table if exists public.entradas_retiro;

create table if not exists public.entradas_retiro (
  id uuid primary key,
  contrato_alumno_id uuid not null
    references public.contratos_alumnos(id) on delete cascade,
  estado text not null check (estado in ('entregado', 'anulado')),
  vip integer not null default 0 check (vip >= 0),
  generales integer not null default 0 check (generales >= 0),
  tramos text,
  menores_10 integer not null default 0 check (menores_10 >= 0),
  parentesco text,
  retiro_nombre text,
  otra_persona_motivo text,
  autorizacion_firmada boolean not null default false,
  escribio_en_planilla boolean not null default false,
  entregado_por text,
  entregado_at timestamptz,
  anulado_por text,
  anulado_at timestamptz,
  anulado_motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entradas_retiro_uniq_contrato unique (contrato_alumno_id)
);

create index if not exists idx_entradas_retiro_updated
  on public.entradas_retiro(updated_at desc);

-- ── 3. sorteos_mesas ────────────────────────────────────────────────────────
--
-- Solo se agregan renglones: cada sorteo, deshacer o restaurar deja uno, con
-- quién, cuándo y cómo quedaron las mesas. `resultado` es texto JSON y no
-- `jsonb`, para que vuelva a la app igual que como salió.
--
-- ROLLBACK: drop table if exists public.sorteos_mesas;

create table if not exists public.sorteos_mesas (
  id uuid primary key,
  evento_id uuid not null references public.eventos(id) on delete cascade,
  tipo text not null check (tipo in ('sorteo', 'deshacer', 'restaurar')),
  resultado text not null,
  alumnos integer not null default 0,
  hecho_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sorteos_mesas_evento
  on public.sorteos_mesas(evento_id, created_at);

create index if not exists idx_sorteos_mesas_updated
  on public.sorteos_mesas(updated_at desc);

-- ── 4. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que `notas_operativas_contrato`, cualquier usuario logueado. Un
-- anónimo no ve nada: la web pública no las necesita.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin
-- ellos una edición no cruza nunca a la otra PC, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK, por tabla (lo borra solo el `drop table` de arriba):
--   drop policy if exists "<tabla>_all_authenticated" on public.<tabla>;
--   drop trigger if exists set_updated_at_ins_<tabla> on public.<tabla>;
--   drop trigger if exists set_updated_at_upd_<tabla> on public.<tabla>;

do $$
declare
  t text;
begin
  foreach t in array array['sillas_reparto', 'entradas_retiro', 'sorteos_mesas']
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

-- ── 5. Verificación ─────────────────────────────────────────────────────────
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
-- DESPUÉS: las tres tablas con RLS prendida, y exactamente un disparador de
-- insert y uno de update cada una. Tiene que devolver tres filas, todas con
-- rls = true, trg_insert = 1 y trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname in ('sillas_reparto', 'entradas_retiro', 'sorteos_mesas')
--   group by c.relname, c.relrowsecurity;
--
-- Y que ninguna entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename in ('sillas_reparto', 'entradas_retiro', 'sorteos_mesas');
