// El registro de mesas adicionales y sillas (`supabase/lugares_cambios.sql`),
// probado contra el archivo de verdad en un Postgres de prueba en memoria
// (el mismo paquete que el link del delegado). No toca la nube ni la base.
//
//   cd tool/delegado_sandbox && npm install   (una vez)
//   node tool/lugares_cambios_sandbox.mjs
//
// `SQL_DE_LUGARES` (una dirección `file:///…`) lo cambia por una copia, para
// romperlo a propósito sin tocar el archivo de verdad.
import { readFileSync } from 'node:fs';
import { PGlite } from './delegado_sandbox/node_modules/@electric-sql/pglite/dist/index.js';

const SQL = process.env.SQL_DE_LUGARES ?? '../supabase/lugares_cambios.sql';
const leer = (f) => readFileSync(new URL(f, import.meta.url), 'utf8');

const FIESTA = 'aaaaaaaa-0000-4000-8000-000000000001';
const alumno = (n) => `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

// Lo que en Supabase ya existe: la tabla (con las columnas que mira el
// registro y un par más) y auth.jwt().
const ENTORNO = `
  create schema auth;
  create function auth.jwt() returns jsonb language sql stable
    as $$ select nullif(current_setting('request.jwt.claims', true), '')::jsonb $$;
  create table public.contratos_alumnos (
    id                        uuid primary key,
    evento_id                 uuid not null,
    nombre_alumno             text not null,
    telefono                  text,
    numero_mesa               text,
    mesa_extra_cantidad       integer,
    mesa_extra_precio         real,
    sillas_extra_cantidad     integer,
    sillas_extra_precio_total real,
    saldo_deudor              numeric,
    updated_at                timestamptz default now()
  );
`;

async function abrir() {
  const db = new PGlite();
  await db.exec(ENTORNO);
  await db.exec(leer(SQL));
  const sql = async (texto, valores = []) => (await db.query(texto, valores)).rows;
  const filas = () => sql('select * from public.lugares_cambios order by id');
  const alta = (n, o = {}) => sql(
    `insert into public.contratos_alumnos
       (id, evento_id, nombre_alumno, numero_mesa, mesa_extra_cantidad, mesa_extra_precio,
        sillas_extra_cantidad, sillas_extra_precio_total)
     values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8)`,
    [alumno(n), FIESTA, `ALUMNO ${n}`, o.mesa ?? null, o.mesas ?? 0, o.precioMesas ?? 0,
      o.sillas ?? 0, o.precioSillas ?? 0],
  );
  return { db, sql, filas, alta };
}

const pruebas = [];
const prueba = (titulo, fn) => pruebas.push({ titulo, fn });
const cierto = (c, msg) => { if (!c) throw new Error(msg); };
const igual = (dio, esperaba, msg = '') => {
  if (JSON.stringify(dio) !== JSON.stringify(esperaba)) {
    throw new Error(`${msg} esperaba ${JSON.stringify(esperaba)} y dio ${JSON.stringify(dio)}`);
  }
};

prueba('L1 un alumno nuevo sin nada de más no deja fila', async (n) => {
  await n.alta(1);
  igual((await n.filas()).length, 0);
});

prueba('L2 un alumno que se carga ya con mesa adicional o sillas deja su fila, con los "antes" vacíos', async (n) => {
  await n.alta(1, { mesas: 1, precioMesas: 70000, sillas: 2, precioSillas: 16000, mesa: '12, 13' });
  const [f] = await n.filas();
  igual(f.operacion, 'insert');
  igual([f.mesa_extra_cantidad_antes, f.mesa_extra_cantidad_despues], [null, 1]);
  igual([f.sillas_extra_cantidad_antes, f.sillas_extra_cantidad_despues], [null, 2]);
  igual([f.mesa_extra_precio_despues, f.sillas_extra_precio_total_despues], [70000, 16000]);
  igual([f.contrato_alumno_id, f.evento_id, f.nombre_alumno, f.numero_mesa],
    [alumno(1), FIESTA, 'ALUMNO 1', '12, 13']);
  cierto(f.cambiado_at instanceof Date, 'lleva cuándo');
});

prueba('L3 agregar una mesa adicional anota qué había y qué quedó', async (n) => {
  await n.alta(1, { mesa: '12' });
  await n.sql(
    `update public.contratos_alumnos
        set mesa_extra_cantidad = 1, mesa_extra_precio = 70000, numero_mesa = '12, 101'
      where id = $1::uuid`, [alumno(1)]);
  const [f, ...resto] = await n.filas();
  igual(resto.length, 0);
  igual(f.operacion, 'update');
  igual([f.mesa_extra_cantidad_antes, f.mesa_extra_cantidad_despues], [0, 1]);
  igual([f.mesa_extra_precio_antes, f.mesa_extra_precio_despues], [0, 70000]);
  igual([f.sillas_extra_cantidad_antes, f.sillas_extra_cantidad_despues], [0, 0]);
  igual(f.numero_mesa, '12, 101');
  igual(f.otras_columnas_cambiadas, ['numero_mesa']);
});

prueba('L4 agregar y sacar sillas deja una fila cada vez', async (n) => {
  await n.alta(1);
  const poner = (c) => n.sql(
    `update public.contratos_alumnos
        set sillas_extra_cantidad = $2, sillas_extra_precio_total = $3 where id = $1::uuid`,
    [alumno(1), c, 8000 * c]);
  await poner(2);
  await poner(3);
  await poner(1);
  igual((await n.filas()).map((f) => [f.sillas_extra_cantidad_antes, f.sillas_extra_cantidad_despues]),
    [[0, 2], [2, 3], [3, 1]]);
});

prueba('L5 un cambio que no es de lugares (teléfono, saldo, la mesa del sorteo) no anota nada', async (n) => {
  await n.alta(1, { mesas: 1, precioMesas: 70000 });
  const antes = (await n.filas()).length;
  await n.sql(`update public.contratos_alumnos set telefono = '3794000000' where id = $1::uuid`, [alumno(1)]);
  await n.sql(`update public.contratos_alumnos set saldo_deudor = 1000, updated_at = now() where id = $1::uuid`, [alumno(1)]);
  await n.sql(`update public.contratos_alumnos set numero_mesa = '40, 41' where id = $1::uuid`, [alumno(1)]);
  // Reescribir lo mismo (la ficha entera, como Editar alumno) tampoco.
  await n.sql(
    `update public.contratos_alumnos set mesa_extra_cantidad = 1, mesa_extra_precio = 70000,
            sillas_extra_cantidad = 0, sillas_extra_precio_total = 0 where id = $1::uuid`, [alumno(1)]);
  igual((await n.filas()).length, antes);
});

prueba('L6 solo el precio también cuenta: una silla sin precio no es una silla para el programa', async (n) => {
  await n.alta(1, { sillas: 1 });
  await n.sql(`update public.contratos_alumnos set sillas_extra_precio_total = 8000 where id = $1::uuid`, [alumno(1)]);
  const f = (await n.filas()).at(-1);
  igual([f.sillas_extra_precio_total_antes, f.sillas_extra_precio_total_despues], [0, 8000]);
  igual([f.sillas_extra_cantidad_antes, f.sillas_extra_cantidad_despues], [1, 1]);
});

prueba('L7 la subida del programa (insert … on conflict do update) anota como un cambio, una sola vez', async (n) => {
  await n.alta(1, { mesa: '12' });
  await n.sql(
    `insert into public.contratos_alumnos
       (id, evento_id, nombre_alumno, mesa_extra_cantidad, mesa_extra_precio, sillas_extra_cantidad,
        sillas_extra_precio_total)
     values ($1::uuid, $2::uuid, 'ALUMNO 1', 1, 70000, 0, 0)
     on conflict (id) do update set
       mesa_extra_cantidad = excluded.mesa_extra_cantidad,
       mesa_extra_precio = excluded.mesa_extra_precio`, [alumno(1), FIESTA]);
  const todas = await n.filas();
  igual(todas.length, 1);
  igual([todas[0].operacion, todas[0].mesa_extra_cantidad_antes, todas[0].mesa_extra_cantidad_despues],
    ['update', 0, 1]);
});

prueba('L8 anota quién escribió y desde qué programa, si se sabe', async (n) => {
  await n.alta(1);
  await n.sql(`select set_config('request.jwt.claims', '{"email":"jefe@prueba.test"}', false)`);
  await n.sql(`select set_config('request.headers', '{"x-client-info":"supabase-flutter/2.0"}', false)`);
  await n.sql(`update public.contratos_alumnos set sillas_extra_cantidad = 1 where id = $1::uuid`, [alumno(1)]);
  const f = (await n.filas()).at(-1);
  igual([f.usuario, f.cliente], ['jefe@prueba.test', 'supabase-flutter/2.0']);
});

prueba('L9 NUNCA frena: si no puede anotar (la tabla no está), la ficha se guarda igual', async (n) => {
  await n.alta(1);
  await n.sql('drop table public.lugares_cambios');
  await n.sql(
    `update public.contratos_alumnos set mesa_extra_cantidad = 2, mesa_extra_precio = 140000
      where id = $1::uuid`, [alumno(1)]);
  await n.alta(2, { sillas: 2, precioSillas: 16000 });
  const filas = await n.sql('select id, mesa_extra_cantidad, sillas_extra_cantidad from public.contratos_alumnos order by id');
  igual(filas.map((f) => [f.mesa_extra_cantidad, f.sillas_extra_cantidad]), [[2, 0], [0, 2]]);
});

prueba('L10 con los encabezados rotos también guarda y anota', async (n) => {
  await n.alta(1);
  await n.sql(`select set_config('request.headers', 'esto no es json', false)`);
  await n.sql(`update public.contratos_alumnos set sillas_extra_cantidad = 1 where id = $1::uuid`, [alumno(1)]);
  const f = (await n.filas()).at(-1);
  igual([f.sillas_extra_cantidad_despues, f.cliente], [1, null]);
});

prueba('L11 correr el SQL dos veces no rompe ni duplica el trigger', async (n) => {
  await n.db.exec(leer(SQL));
  await n.alta(1);
  await n.sql(`update public.contratos_alumnos set sillas_extra_cantidad = 1 where id = $1::uuid`, [alumno(1)]);
  igual((await n.filas()).length, 1);
  const t = await n.sql(
    `select count(*)::int as n from pg_trigger
      where tgrelid = 'public.contratos_alumnos'::regclass and not tgisinternal`);
  igual(t[0].n, 1);
});

prueba('L12 la tabla queda cerrada: con RLS y sin ninguna política', async (n) => {
  const [t] = await n.sql(`select relrowsecurity from pg_class where oid = 'public.lugares_cambios'::regclass`);
  igual(t.relrowsecurity, true);
  const p = await n.sql(`select count(*)::int as n from pg_policies where tablename = 'lugares_cambios'`);
  igual(p[0].n, 0);
});

let fallaron = 0;
for (const p of pruebas) {
  try {
    await p.fn(await abrir());
    console.log(`ok    ${p.titulo}`);
  } catch (e) {
    fallaron++;
    console.log(`FALLA ${p.titulo}\n      ${e.message}`);
  }
}
console.log(`\n${pruebas.length - fallaron} de ${pruebas.length} en verde`);
process.exit(fallaron ? 1 : 0);
