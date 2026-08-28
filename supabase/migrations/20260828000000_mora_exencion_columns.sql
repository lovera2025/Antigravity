-- Campos de mora operativa que vivían solo en el SQLite local.
--
-- Las migraciones v44, v52, v56 y v61 de local_database.dart agregaron estas
-- cuatro columnas al equipo, pero nunca se escribió la contraparte en Supabase.
-- El motor de sync las borraba del payload antes de subir (_cleanForRemote),
-- así que el perdón de mora se guardaba bien en la PC del jefe y no llegaba
-- nunca a la de operarios: subía `mora_tracked_ajuste` —la única de las cinco
-- que sí existía acá— y la exención, que es la que apaga el calendario, se
-- perdía en silencio.
--
-- Aditiva: no toca datos. Los defaults replican el esquema local
-- (REAL DEFAULT 0.0 y INTEGER DEFAULT 1).
--
-- `mora_exencion_reinicia` va smallint y no boolean a propósito:
-- ContratoAlumno.payloadForRemote manda 1/0, y PostgREST rechaza un entero
-- contra una columna booleana.

alter table public.contratos_alumnos
  add column if not exists mora_cobrada_offset    double precision default 0,
  add column if not exists mora_fecha_referencia  date,
  add column if not exists mora_exenta_hasta      date,
  add column if not exists mora_exencion_reinicia smallint default 1;

comment on column public.contratos_alumnos.mora_exenta_hasta is
  'Perdon de mora: fecha hasta la que no corre mora calendario.';
comment on column public.contratos_alumnos.mora_exencion_reinicia is
  '0 = exencion permanente (perdon admin). 1 = reinicia al mes siguiente.';
comment on column public.contratos_alumnos.mora_cobrada_offset is
  'Baseline de mora ya cobrada, para aislar la mora del periodo vigente.';
comment on column public.contratos_alumnos.mora_fecha_referencia is
  'Fecha de referencia para el calculo de mora (congelada en baja temporal).';
