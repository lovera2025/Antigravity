-- 2026-10-23 — Once columnas nuevas en `totem_config`: la apariencia "Tu fondo"
-- (una imagen propia de fondo, con su animación, sus efectos y sus colores).
--
-- **Solo agrega columnas vacías a una tabla que ya existe.** No toca ninguna
-- fila ni ninguna otra tabla, ni el bucket `totem` ni sus permisos: el fondo se
-- sube al mismo bucket, en `<evento>/fondo.<ext>`, y la política "Escritura
-- totem bucket con permiso" (`for all` sobre el bucket entero) ya lo cubre.
-- Las versiones de antes no las conocen: no las leen, y como su guardado de
-- Personalizar es un upsert que no las nombra, tampoco las pisan. Se puede
-- correr a cualquier hora.
--
-- **Hay que correrlo antes de instalar la versión nueva y antes de publicar la
-- web.** Las dos mandan estas columnas al guardar Personalizar (`toJson()` las
-- manda todas): sin ellas, guardar falla, como pasó con `mostrar_musica`.
--
--   fondo_url                 text. La imagen del fondo, con `?v=`. Vacía = sin
--                             fondo (y "Tu fondo" no se puede elegir).
--   fondo_automatico          boolean. Si la receta sale de la imagen. Vacía =
--                             automático.
--   fondo_animacion           text: quieta | acercarse | recorrer | flotar |
--                             respirar | ondular. Vacía = acercarse.
--   fondo_efectos             text: los efectos separados por comas (destellos,
--                             polvo, bokeh, titileo, barrido, marco, glitch,
--                             bruma). '' = sin efectos; vacía = polvo de luz.
--   fondo_intensidad          smallint, de 0 a 100: cuánto se mueve la imagen.
--                             Vacía = 40.
--   fondo_intensidad_efectos  smallint, de 0 a 100. Vacía = 50.
--   fondo_oscurecer           smallint, de 0 a 80. Vacía = 30.
--   fondo_paleta              text: '#RRGGBB,#RRGGBB,#RRGGBB' (brillo, saludo,
--                             tarjeta). Vacía = sale del color del evento.
--   fondo_foco                text: 'x,y', de 0 a 1 (hacia dónde va la
--                             animación). Vacía = el centro.
--   fondo_letras              text: clasica | suave | fiesta | moderna. Vacía =
--                             clasica.
--   fondo_luz                 smallint, de 0 a 100: qué tan clara es la imagen.
--                             Vacía = oscura.
--
-- **Sin NOT NULL, sin DEFAULT y sin CHECK, a propósito**, como `mostrar_musica`
-- y `estilo`: vacía quiere decir "lo de siempre" y lo resuelve la app (una fila
-- vieja nunca hace fallar un guardado), y una animación o un efecto nuevos no
-- tienen que esperar otro SQL. (`totem_config` no pasa por la cola de subida,
-- así que tampoco la traba un "violates".)
--
-- Correrlo dos veces es inocuo: todo es `if not exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- Cómo correrlo (SQL Editor):
--   1. Correr la consulta "ANTES" de la sección 2 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 2 y comparar.

-- ── 1. Las columnas ─────────────────────────────────────────────────────────

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_url;
alter table public.totem_config add column if not exists fondo_url text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_automatico;
alter table public.totem_config add column if not exists fondo_automatico boolean;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_animacion;
alter table public.totem_config add column if not exists fondo_animacion text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_efectos;
alter table public.totem_config add column if not exists fondo_efectos text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_intensidad;
alter table public.totem_config add column if not exists fondo_intensidad smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_intensidad_efectos;
alter table public.totem_config add column if not exists fondo_intensidad_efectos smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_oscurecer;
alter table public.totem_config add column if not exists fondo_oscurecer smallint;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_paleta;
alter table public.totem_config add column if not exists fondo_paleta text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_foco;
alter table public.totem_config add column if not exists fondo_foco text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_letras;
alter table public.totem_config add column if not exists fondo_letras text;

-- ROLLBACK: alter table public.totem_config drop column if exists fondo_luz;
alter table public.totem_config add column if not exists fondo_luz smallint;

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
-- DESPUÉS: las once columnas (once filas: seis `text`, un `boolean` y cuatro
-- `smallint`), vacías en todas las filas:
--
--   select column_name, data_type from information_schema.columns
--   where table_schema = 'public' and table_name = 'totem_config'
--     and column_name like 'fondo\_%' order by column_name;
--
--   select count(*) filter (where fondo_url is not null)        as con_fondo,
--          count(*) filter (where fondo_animacion is not null) as con_animacion,
--          count(*) filter (where fondo_paleta is not null)     as con_paleta
--   from public.totem_config;   -- los tres en 0
--
-- Y que `totem_config` sigue fuera de Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and tablename = 'totem_config';
