-- ============================================================================
-- Fotos de la mora: cómo está la mora de cada alumno en un momento dado, para
-- comparar antes y después de una actualización y ver a quién se le revivió
-- una mora cobrada o perdonada, o se le descongeló una congelada.
--
-- Pedido del usuario el 2-nov-2026: "siempre que lanzamos una actualización es
-- como que algunas moras que ya se cobró o perdonó reviven, y encima ahora los
-- congelados". Hasta hoy no había con qué comparar.
--
-- La app no conoce esta tabla: no se sincroniza, no tiene políticas, y solo se
-- lee y escribe desde el SQL Editor (o desde el MCP, con el rol de servicio).
-- Es solo-agregar: nunca se borra una foto.
--
-- Cómo se usa, en cada actualización:
--   1. ANTES de correr los SQL de la versión y de instalar: sacar una foto
--      (sección 2) con el motivo "antes de X.Y.Z".
--   2. Instalar las tres PCs (lo ideal, el mismo día) y abrir cada una: la
--      revisión de la mora corre al arrancar.
--   3. Sacar otra foto, "después de X.Y.Z", y correr la comparación (sección 3).
--      Lo que lista es lo que hay que revisar, alumno por alumno.
--   4. Si algo revivió, la sección 4 vuelve a ese alumno a lo que decía la
--      foto de antes, con la app cerrada en las tres PCs.
--
-- ROLLBACK de la sección 1 (saca la tabla con todas las fotos):
--   drop table if exists public.mora_fotos;
-- ============================================================================

-- ── 1. La tabla (una sola vez) ──────────────────────────────────────────────

create table if not exists public.mora_fotos (
  id                     bigserial primary key,
  foto_id                uuid        not null,  -- la misma para todas las filas de una foto
  tomada_at              timestamptz not null default now(),
  motivo                 text        not null,  -- "antes de 6.2.1", "después de 6.2.1"
  contrato_alumno_id     uuid        not null,
  evento_id              uuid,
  nombre_alumno          text,
  saldo_deudor           numeric,
  mora_pendiente_tracked double precision,
  mora_tracked_ajuste    double precision,
  mora_cobrada_offset    double precision,
  mora_fecha_referencia  date,
  mora_exenta_hasta      date,
  mora_exencion_reinicia smallint,
  pausas                 text,                  -- mora_congelada.pausas; null si no está congelado
  contrato_updated_at    timestamptz            -- cuándo se tocó la ficha por última vez
);

create index if not exists mora_fotos_foto_idx   on public.mora_fotos (foto_id);
create index if not exists mora_fotos_alumno_idx on public.mora_fotos (contrato_alumno_id, tomada_at);

-- Sin políticas a propósito: con RLS prendido y ninguna política, ni anon ni
-- authenticated la ven. Solo el rol de servicio (SQL Editor, MCP).
alter table public.mora_fotos enable row level security;

-- ── 2. Sacar una foto (cambiar el motivo cada vez) ─────────────────────────

with f as (
  select gen_random_uuid() as id, 'antes de 6.2.1' as motivo
)
insert into public.mora_fotos (
  foto_id, motivo, contrato_alumno_id, evento_id, nombre_alumno, saldo_deudor,
  mora_pendiente_tracked, mora_tracked_ajuste, mora_cobrada_offset,
  mora_fecha_referencia, mora_exenta_hasta, mora_exencion_reinicia, pausas,
  contrato_updated_at
)
select
  f.id, f.motivo, c.id, c.evento_id, c.nombre_alumno, c.saldo_deudor,
  c.mora_pendiente_tracked, c.mora_tracked_ajuste, c.mora_cobrada_offset,
  c.mora_fecha_referencia, c.mora_exenta_hasta, c.mora_exencion_reinicia,
  m.pausas, c.updated_at
from f
cross join public.contratos_alumnos c
left join lateral (
  select pausas
  from public.mora_congelada mc
  where mc.contrato_alumno_id = c.id
  order by mc.updated_at desc
  limit 1
) m on true;

-- Las fotos que hay:
select foto_id, min(tomada_at) at time zone 'America/Argentina/Buenos_Aires' as tomada,
       min(motivo) as motivo, count(*) as alumnos
from public.mora_fotos
group by foto_id
order by tomada desc;

-- ── 3. Comparar las dos últimas fotos ──────────────────────────────────────
-- Lista solo lo sospechoso: mora pendiente que SUBIÓ, eximición que se fue o
-- se acortó, perdón (ajuste) que cambió, "ya usado" que BAJÓ, congelada que
-- cambió o se fue, y la fecha de referencia que cambió. Un cobro normal no
-- aparece (sube el "ya usado" y corre la eximición hacia adelante).
-- Para comparar otras dos fotos, reemplazar los dos `foto_id` de abajo.

with ultimas as (
  select foto_id, min(tomada_at) as tomada
  from public.mora_fotos
  group by foto_id
  order by tomada desc
  limit 2
),
antes as (
  select * from public.mora_fotos
  where foto_id = (select foto_id from ultimas order by tomada asc  limit 1)
),
despues as (
  select * from public.mora_fotos
  where foto_id = (select foto_id from ultimas order by tomada desc limit 1)
),
cambios as (
  select
    coalesce(a.nombre_alumno, d.nombre_alumno)         as alumno,
    coalesce(a.contrato_alumno_id, d.contrato_alumno_id) as contrato_alumno_id,
    case
      when a.contrato_alumno_id is null then 'alumno nuevo (no estaba en la foto de antes)'
      when d.contrato_alumno_id is null then 'alumno que ya no está'
      else nullif(concat_ws(' · ',
        case when coalesce(d.mora_pendiente_tracked, 0) > coalesce(a.mora_pendiente_tracked, 0) + 0.005
             then format('mora pendiente SUBIÓ %s → %s', a.mora_pendiente_tracked, d.mora_pendiente_tracked) end,
        case when a.mora_exenta_hasta is not null
              and (d.mora_exenta_hasta is null or d.mora_exenta_hasta < a.mora_exenta_hasta)
             then format('eximición %s → %s', a.mora_exenta_hasta, coalesce(d.mora_exenta_hasta::text, 'NINGUNA')) end,
        case when coalesce(a.mora_tracked_ajuste, 0) is distinct from coalesce(d.mora_tracked_ajuste, 0)
             then format('perdón (ajuste) %s → %s', a.mora_tracked_ajuste, d.mora_tracked_ajuste) end,
        case when coalesce(d.mora_cobrada_offset, 0) < coalesce(a.mora_cobrada_offset, 0) - 0.005
             then format('ya usado BAJÓ %s → %s', a.mora_cobrada_offset, d.mora_cobrada_offset) end,
        case when a.pausas is not null and d.pausas is distinct from a.pausas
             then format('congelada %s → %s', a.pausas, coalesce(d.pausas, 'SIN CONGELAR')) end,
        case when a.mora_fecha_referencia is distinct from d.mora_fecha_referencia
             then format('fecha de referencia %s → %s', a.mora_fecha_referencia, d.mora_fecha_referencia) end
      ), '')
    end as que_cambio,
    d.contrato_updated_at at time zone 'America/Argentina/Buenos_Aires' as ficha_tocada
  from antes a
  full join despues d on d.contrato_alumno_id = a.contrato_alumno_id
)
select alumno, que_cambio, ficha_tocada, contrato_alumno_id
from cambios
where que_cambio is not null
order by alumno;

-- ── 4. Volver a UN alumno a lo que decía una foto ──────────────────────────
-- Con la app CERRADA en las tres PCs (si no, una PC vuelve a subir lo suyo).
-- Lo congelado (mora_congelada) no se toca acá: se revisa a mano.
-- ROLLBACK: la foto siguiente, o sacar una foto antes de correr esto.
--
-- update public.contratos_alumnos c set
--   mora_pendiente_tracked = f.mora_pendiente_tracked,
--   mora_tracked_ajuste    = f.mora_tracked_ajuste,
--   mora_cobrada_offset    = f.mora_cobrada_offset,
--   mora_fecha_referencia  = f.mora_fecha_referencia,
--   mora_exenta_hasta      = f.mora_exenta_hasta,
--   mora_exencion_reinicia = f.mora_exencion_reinicia
-- from public.mora_fotos f
-- where f.foto_id = '<foto_id de antes>'
--   and f.contrato_alumno_id = c.id
--   and c.id = '<contrato_alumno_id>';

-- ── Verificación ───────────────────────────────────────────────────────────
-- Antes y después de sacar una foto, los alumnos tienen que ser los mismos:
-- select count(*) from public.contratos_alumnos;
-- select count(*) from public.mora_fotos where foto_id = '<foto_id>';
