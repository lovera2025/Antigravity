-- SOLO DEL SANDBOX. Datos inventados. Correrlo de nuevo deja todo como al principio.
delete from public.cargas_delegado;
delete from public.celulares_delegado;
delete from public.links_delegado;
delete from public.contratos_alumnos;
delete from public.eventos;

insert into public.eventos (id, nombre) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'Escuela Normal · Promo 2026'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'Colegio San José · Promo 2026');

-- Fiesta A: 12 activos en 3 divisiones, 2 de baja temporal y uno sin nombre.
insert into public.contratos_alumnos
  (id, evento_id, nombre_alumno, curso_division, nombres_acompanantes, cantidad_acompanantes, musica_elegida) values
  ('a0000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'ACOSTA, LUCÍA',      '6° A', array['ACOSTA, JORGE','RÍOS, MARTA'], 2, 'Vivir mi vida · Marc Anthony'),
  ('a0000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'ÁLVAREZ, BRUNO',     '6° A', null, 0, null),
  ('a0000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'BENÍTEZ, MATEO',     '6° A', array['BENÍTEZ, CARLA'], 1, null),
  ('a0000000-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001', 'CABRERA, SOFÍA',     '6° A', null, 0, ''),
  ('a0000000-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000001', 'DÍAZ, TOMÁS',        '6° B', array[]::text[], 0, null),
  ('a0000000-0000-4000-8000-000000000006', 'aaaaaaaa-0000-4000-8000-000000000001', 'ESCOBAR, VALENTINA', '6° B', null, 0, null),
  ('a0000000-0000-4000-8000-000000000007', 'aaaaaaaa-0000-4000-8000-000000000001', 'FERNÁNDEZ, JOAQUÍN', '6° B', null, 0, null),
  ('a0000000-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-000000000001', 'GÓMEZ, SOFÍA',       '6° B', null, 0, null),
  ('a0000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-000000000001', 'IBARRA, CAMILA',     '6° C', null, 0, null),
  ('a0000000-0000-4000-8000-000000000010', 'aaaaaaaa-0000-4000-8000-000000000001', 'LEDESMA, SANTINO',   '6° C', null, 0, null),
  ('a0000000-0000-4000-8000-000000000011', 'aaaaaaaa-0000-4000-8000-000000000001', 'MEZA, MARTINA',      '6° C', null, 0, null),
  ('a0000000-0000-4000-8000-000000000012', 'aaaaaaaa-0000-4000-8000-000000000001', 'OJEDA, THIAGO',      '6° C', null, 0, null),
  ('a0000000-0000-4000-8000-000000000013', 'aaaaaaaa-0000-4000-8000-000000000001', '[BAJA] ROMERO, MILAGROS', '6° A', null, 0, null),
  ('a0000000-0000-4000-8000-000000000014', 'aaaaaaaa-0000-4000-8000-000000000001', '[BAJA] SOSA, DYLAN',      '6° C', null, 0, null),
  ('a0000000-0000-4000-8000-000000000015', 'aaaaaaaa-0000-4000-8000-000000000001', '   ',                     '6° C', null, 0, null);

-- Fiesta B: 5 alumnos.
insert into public.contratos_alumnos
  (id, evento_id, nombre_alumno, curso_division, nombres_acompanantes, cantidad_acompanantes, musica_elegida) values
  ('b0000000-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001', 'AGUIRRE, NICOLÁS',  '5° U', null, 0, null),
  ('b0000000-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000001', 'BLANCO, JULIETA',   '5° U', null, 0, null),
  ('b0000000-0000-4000-8000-000000000003', 'bbbbbbbb-0000-4000-8000-000000000001', 'CORREA, LAUTARO',   '5° U', null, 0, null),
  ('b0000000-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001', 'DUARTE, ABRIL',     '5° U', null, 0, null),
  ('b0000000-0000-4000-8000-000000000005', 'bbbbbbbb-0000-4000-8000-000000000001', 'ESPINOZA, BAUTISTA','5° U', null, 0, null);
