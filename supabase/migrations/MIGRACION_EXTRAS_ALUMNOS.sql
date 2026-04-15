-- Migración: Agrega campos para mesas extras y sillas a la tabla contratos_alumnos

ALTER TABLE public.contratos_alumnos
ADD COLUMN mesa_extra_precio NUMERIC(10,2) DEFAULT 0,
ADD COLUMN mesa_extra_cuotas INTEGER DEFAULT 1,
ADD COLUMN sillas_extra_cantidad INTEGER DEFAULT 0,
ADD COLUMN sillas_extra_precio_total NUMERIC(10,2) DEFAULT 0;
