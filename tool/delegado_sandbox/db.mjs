// La nube de mentira: un Postgres de prueba en memoria, con el SQL de verdad.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const leer = (f) => readFileSync(new URL(f, import.meta.url), 'utf8');

export const FIESTA_A = 'aaaaaaaa-0000-4000-8000-000000000001';
export const FIESTA_B = 'bbbbbbbb-0000-4000-8000-000000000001';
export const alumnoA = (n) => `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
export const alumnoB = (n) => `b0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** El SQL que va a la nube: los mismos archivos de las migraciones, en orden. */
export const SQL_DE_LA_NUBE = '../../supabase/migrations/20261113120000_link_delegado.sql';
/** La segunda parte (6.9.2): todos corrigen todo, Enviar no cierra, el historial. */
// `SQL_DEL_LINK_2` (una dirección `file:///…`) lo cambia por una copia: así las
// roturas a propósito (`roturas.mjs`) nunca tocan el archivo de verdad.
export const SQL_DE_LA_NUBE_2 = process.env.SQL_DEL_LINK_2
  ?? '../../supabase/migrations/20261118120000_link_delegado_reabrir.sql';
export const SQL_DE_LA_NUBE_TODO = [SQL_DE_LA_NUBE, SQL_DE_LA_NUBE_2];

const TIPOS = { p_evento: 'uuid', p_alumno: 'uuid', p_acompanantes: 'jsonb', p_cupo: 'integer' };

export async function abrir({ relojDePrueba = false, soloLaPrimera = false } = {}) {
  const db = new PGlite();
  await db.exec(leer('sql/00_entorno.sql'));
  // `soloLaPrimera`: la nube como quedó con la 6.8.0, para probar que correr la
  // segunda parte encima no pierde nada.
  await db.exec(leer(SQL_DE_LA_NUBE));
  if (!soloLaPrimera) await db.exec(leer(SQL_DE_LA_NUBE_2));
  if (relojDePrueba) await db.exec(leer('sql/02_reloj_de_prueba.sql'));
  await db.exec(leer('sql/01_datos.sql'));

  // Una sola conexión: todo va en fila, de a uno.
  let cola = Promise.resolve();
  const enFila = (f) => {
    const p = cola.then(f, f);
    cola = p.catch(() => {});
    return p;
  };

  /** Llama a una función como lo haría la web: `rol` es 'anon' o 'jefe'. */
  const rpc = (rol, fn, args = {}) => {
    if (!/^delegado_[a-z_]+$/.test(fn)) return Promise.reject(new Error('Función desconocida'));
    const claves = Object.keys(args);
    for (const k of claves) {
      if (!/^p_[a-z_]+$/.test(k)) return Promise.reject(new Error('Parámetro desconocido'));
    }
    const partes = claves.map((k, i) => `${k} => $${i + 1}::${TIPOS[k] ?? 'text'}`);
    const valores = claves.map((k) => {
      const v = args[k];
      if (v === null || v === undefined) return null;
      return TIPOS[k] === 'jsonb' ? JSON.stringify(v) : String(v);
    });
    const pgRol = rol === 'jefe' ? 'authenticated' : 'anon';
    return enFila(async () => {
      await db.exec(`set role ${pgRol}; select set_config('request.jwt.claim.role', '${pgRol}', false);`);
      try {
        const r = await db.query(`select public.${fn}(${partes.join(', ')}) as r`, valores);
        return r.rows[0].r;
      } finally {
        await db.exec(`reset role; select set_config('request.jwt.claim.role', '', false);`);
      }
    });
  };

  /** SQL suelto. Sin `rol` corre como dueño (para preparar una prueba). */
  const sql = (texto, valores = [], rol = null) =>
    enFila(async () => {
      if (rol) await db.exec(`set role ${rol === 'jefe' ? 'authenticated' : 'anon'}`);
      try {
        return (await db.query(texto, valores)).rows;
      } finally {
        if (rol) await db.exec('reset role');
      }
    });

  const reiniciar = () => enFila(async () => {
    await db.exec(leer('sql/01_datos.sql'));
    await db.exec(`select set_config('prueba.ahora', '', false)`);
  });

  /** Pone el reloj de la nube. Solo con `relojDePrueba`. */
  const reloj = (momento) =>
    enFila(() => db.query(`select set_config('prueba.ahora', $1, false)`, [momento ?? '']));

  // ── Lo que hace de programa (no es parte del SQL de la nube) ──────────────

  /** La grilla: los alumnos de una fiesta como están en el programa. */
  const grilla = async (evento) => {
    const filas = await sql(
      `select id, nombre_alumno, curso_division, nombres_acompanantes, musica_elegida
         from public.contratos_alumnos where evento_id = $1::uuid
        order by curso_division, nombre_alumno`,
      [evento],
    );
    return filas.map((f) => ({
      id: f.id,
      nombre: f.nombre_alumno,
      division: f.curso_division,
      acompanantes: f.nombres_acompanantes ?? [],
      musica: f.musica_elegida ?? '',
    }));
  };

  /**
   * Guarda en la grilla, como `cargarAcompanantesYMusica` del programa: del alumno
   * solo se escriben los acompañantes, cuántos son y la música, y solo lo que vino.
   */
  const guardarEnLaGrilla = async (evento, datos) => {
    for (const d of datos) {
      const extra = Object.keys(d).filter((k) => !['alumno_id', 'acompanantes', 'musica'].includes(k));
      if (extra.length) throw new Error(`Solo acompañantes y música: sobra ${extra.join(', ')}`);
    }
    for (const d of datos) {
      if (Array.isArray(d.acompanantes)) {
        await sql(
          `update public.contratos_alumnos
              set nombres_acompanantes = $3::text[], cantidad_acompanantes = $4::integer
            where id = $1::uuid and evento_id = $2::uuid`,
          [d.alumno_id, evento, d.acompanantes, d.acompanantes.length],
        );
      }
      if (typeof d.musica === 'string') {
        await sql(
          `update public.contratos_alumnos set musica_elegida = $3
            where id = $1::uuid and evento_id = $2::uuid`,
          [d.alumno_id, evento, d.musica],
        );
      }
    }
    return datos.length;
  };

  /** Corre la segunda parte del SQL encima (para probar la pasada de una a otra). */
  const correrLaSegunda = () => enFila(async () => {
    await db.exec(leer(SQL_DE_LA_NUBE_2));
    if (relojDePrueba) await db.exec(leer('sql/02_reloj_de_prueba.sql'));
  });

  return { rpc, sql, reiniciar, reloj, grilla, guardarEnLaGrilla, correrLaSegunda };
}
