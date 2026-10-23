-- 2026-10-23 — Seis columnas nuevas en `totem_config`: la foto y las frases de
-- la espera del tótem. Van con la 6.2.1.
--
-- En Personalizar, la foto (o el logo) se puede sacar —cuando el fondo ya trae
-- el logo y la pantalla tiene que quedar limpia—, cambiar de forma y agrandar;
-- las frases, agrandar; y las dos juntas, mover a otro lugar de la pantalla.
--
--   mostrar_foto  boolean.  Vacía (las filas de antes) = se muestra.
--   foto_forma    text: circulo | ovalo | cuadrado | arco | corazon | hexagono |
--                 rombo | triangulo | tal_cual. Vacía = círculo.
--   foto_tamano   smallint, de 50 a 300 (% del tamaño de siempre). Vacía = 100.
--   texto_tamano  smallint, de 50 a 200 (% del tamaño de siempre). Vacía = 100.
--   ubicacion_x   smallint, de -100 (izquierda) a 100 (derecha). Vacía = 0, al
--                 medio.
--   ubicacion_y   smallint, de -100 (arriba) a 100 (abajo). Vacía = 0, al medio.
--
-- **Solo agrega columnas vacías a una tabla que ya existe.** No toca ninguna
-- fila ni ninguna otra tabla, ni la base de las PCs. La 6.2.0 no las conoce: no
-- las lee y, como su guardado de Personalizar es un upsert que no las nombra,
-- tampoco las pisa. Se puede correr a cualquier hora.
--
-- **Hay que correrlo antes de instalar la 6.2.1 y de publicar su web.** La
-- 6.2.1 las manda al guardar Personalizar: sin ellas, guardar falla, como pasó
-- con `mostrar_musica`.
--
-- **Sin NOT NULL, sin DEFAULT y sin CHECK, a propósito**, como `mostrar_musica`
-- y las de "Tu fondo": vacía quiere decir "lo de siempre", una fila vieja nunca
-- hace fallar un guardado, y una forma nueva no tiene que esperar otro SQL.
-- Los valores válidos (y los topes) los controla la app.
--
-- Correrlo dos veces es inocuo: todo es `if not exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- Cómo correrlo (SQL Editor):
--   1. Correr la consulta "ANTES" de la sección 2 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 2 y comparar.

-- ── 1. Las columnas ─────────────────────────────────────────────────────────
--
-- ROLLBACK: alter table public.totem_config drop column if exists mostrar_foto;
alter table public.totem_config add column if not exists mostrar_foto boolean;

-- ROLLBACK: alter table public.totem_config drop column if exists foto_forma;
alter table public.totem_config add column if not exists foto_forma text;

-- ROLLBACK: alter table public.totem_config drop column if exists foto_tamano;
alter table public.totem_config add column if not exists foto_tamano smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists texto_tamano;
alter table public.totem_config add column if not exists texto_tamano smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists ubicacion_x;
alter table public.totem_config add column if not exists ubicacion_x smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists ubicacion_y;
alter table public.totem_config add column if not exists ubicacion_y smallint;

-- ── 2. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.notas_operativas_contrato) as notas,
--     (select count(*) from public.invitados)                 as invitados,
--     (select count(*) from public.eventos)                   as eventos,
--     (select count(*) from public.totem_config)              as totem_config;
--
-- DESPUÉS: las seis columnas, vacías en todas las filas. Tiene que devolver
-- seis filas: `mostrar_foto` boolean, `foto_forma` text, y `foto_tamano`,
-- `texto_tamano`, `ubicacion_x` y `ubicacion_y` smallint.
--
--   select column_name, data_type from information_schema.columns
--   where table_schema = 'public' and table_name = 'totem_config'
--     and column_name in ('mostrar_foto', 'foto_forma', 'foto_tamano',
--                         'texto_tamano', 'ubicacion_x', 'ubicacion_y');
--
--   select count(*) filter (where mostrar_foto is not null) as con_mostrar,
--          count(*) filter (where foto_forma is not null)   as con_forma,
--          count(*) filter (where foto_tamano is not null)  as con_tamano,
--          count(*) filter (where texto_tamano is not null) as con_texto,
--          count(*) filter (where ubicacion_x is not null)  as con_x,
--          count(*) filter (where ubicacion_y is not null)  as con_y
--   from public.totem_config;   -- los seis en 0
--
-- Y que `totem_config` sigue fuera de Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and tablename = 'totem_config';
