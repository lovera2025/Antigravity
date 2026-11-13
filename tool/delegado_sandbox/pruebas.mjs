// Las pruebas de reglas: contra el SQL de verdad, en el Postgres de prueba.
// Cada una empieza con los datos como al principio y el reloj en la misma hora.
import { writeFileSync, readFileSync } from 'node:fs';
import { abrir, FIESTA_A, FIESTA_B, alumnoA, alumnoB, SQL_DE_LA_NUBE } from './db.mjs';
import { comparar, datosAGuardar } from './revision.js';

const nube = await abrir({ relojDePrueba: true });
const AHORA = '2026-11-12 15:00:00-03';
const LIMITE = '2026-11-19 20:00'; // hora de Argentina = 23:00 UTC
const FIESTA = 'Escuela Normal · Promo 2026';

const pruebas = [];
const prueba = (id, titulo, fn) => pruebas.push({ id, titulo, fn });
const cierto = (c, msg) => { if (!c) throw new Error(msg); };
// Las claves de un JSON de la nube vienen ordenadas: se compara sin mirar el orden.
const canon = (v) => JSON.stringify(v, (_, x) => (x && typeof x === 'object' && !Array.isArray(x)
  ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, x[k]])) : x));
const igual = (dio, esperaba, msg = '') => {
  if (canon(dio) !== canon(esperaba)) {
    throw new Error(`${msg} esperaba ${JSON.stringify(esperaba)} y dio ${JSON.stringify(dio)}`);
  }
};
const falla = async (promesa, msg) => {
  let fallo = null;
  try { await promesa; } catch (e) { fallo = e; }
  cierto(fallo !== null, msg);
  return fallo;
};

const crear = async (o = {}) => {
  const r = await nube.rpc('jefe', 'delegado_link_crear', {
    p_evento: o.evento ?? FIESTA_A, p_fiesta: o.fiesta ?? FIESTA, p_vence_local: o.vence ?? LIMITE, p_cupo: o.cupo ?? 3,
  });
  cierto(r.ok, `No se pudo crear el link: ${JSON.stringify(r)}`);
  return r.clave;
};
const entrarCrudo = (clave, nombre) => nube.rpc('anon', 'delegado_entrar', { p_clave: clave, p_nombre: nombre });
const entrar = async (clave, nombre) => {
  const r = await entrarCrudo(clave, nombre);
  cierto(r.ok, `No pudo entrar ${nombre}: ${JSON.stringify(r)}`);
  return r.sesion;
};
const lista = (clave, sesion) => nube.rpc('anon', 'delegado_lista', { p_clave: clave, p_sesion: sesion ?? null });
const guardar = (clave, sesion, alumno, acomp, musica) => nube.rpc('anon', 'delegado_guardar', {
  p_clave: clave, p_sesion: sesion, p_alumno: alumno, p_acompanantes: acomp, p_musica: musica,
});
const entregar = (clave, sesion) => nube.rpc('anon', 'delegado_entregar', { p_clave: clave, p_sesion: sesion });
const link = (evento = FIESTA_A) => nube.rpc('jefe', 'delegado_link', { p_evento: evento });
const cambiar = (accion, valor = null) => nube.rpc('jefe', 'delegado_link_cambiar', {
  p_evento: FIESTA_A, p_accion: accion, p_valor: valor,
});
const cargas = () => nube.rpc('jefe', 'delegado_cargas', { p_evento: FIESTA_A });
const pendientes = () => nube.rpc('jefe', 'delegado_pendientes', {});
const celular = async (nombre) => (await link()).celulares.find((c) => c.nombre === nombre.toUpperCase()).id;
const deLista = (l, n) => l.alumnos.find((a) => a.id === alumnoA(n));
const foto = async () => JSON.stringify(await nube.sql('select * from public.contratos_alumnos order by id'));

const ORDEN = [
  'ACOSTA, LUCÍA', 'ÁLVAREZ, BRUNO', 'BENÍTEZ, MATEO', 'CABRERA, SOFÍA',
  'DÍAZ, TOMÁS', 'ESCOBAR, VALENTINA', 'FERNÁNDEZ, JOAQUÍN', 'GÓMEZ, SOFÍA',
  'IBARRA, CAMILA', 'LEDESMA, SANTINO', 'MEZA, MARTINA', 'OJEDA, THIAGO',
];

// ── A. Qué alumnos muestra el link ──────────────────────────────────────────

prueba('A1', 'La lista de la fiesta A: exactamente los 12 activos, una vez cada uno', async () => {
  const clave = await crear();
  const l = await lista(clave, await entrar(clave, 'Laura Gómez'));
  cierto(l.ok, JSON.stringify(l));
  igual(l.alumnos.length, 12, 'cantidad:');
  igual(new Set(l.alumnos.map((a) => a.id)).size, 12, 'repetidos:');
  igual(l.alumnos.map((a) => a.id).sort(), Array.from({ length: 12 }, (_, i) => alumnoA(i + 1)).sort(), 'quiénes:');
  igual(l.total, 12, 'total:');
});

prueba('A2', 'Los 2 de baja temporal (y el sin nombre) no aparecen', async () => {
  const clave = await crear();
  const l = await lista(clave, await entrar(clave, 'Laura Gómez'));
  for (const n of [13, 14, 15]) cierto(!deLista(l, n), `apareció el ${n}`);
  cierto(!l.alumnos.some((a) => a.nombre.includes('BAJA')), 'apareció un [BAJA]');
});

prueba('A3', 'Ninguno de la fiesta B', async () => {
  const clave = await crear();
  const l = await lista(clave, await entrar(clave, 'Laura Gómez'));
  cierto(!l.alumnos.some((a) => a.id.startsWith('b0000000')), 'apareció uno de la fiesta B');
});

prueba('A4', 'Orden: por división y, adentro, por apellido, sin que los acentos lo cambien', async () => {
  const clave = await crear();
  const l = await lista(clave, await entrar(clave, 'Laura Gómez'));
  igual(l.alumnos.map((a) => a.nombre), ORDEN, 'orden:');
  igual(l.alumnos.map((a) => a.division), [...Array(4).fill('6° A'), ...Array(4).fill('6° B'), ...Array(4).fill('6° C')], 'divisiones:');
});

prueba('A6', 'Guardar con el link de A a un alumno de B: lo rechaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoB(1), ['X, Y'], 'tema'), { ok: false, motivo: 'alumno' });
  igual((await nube.sql('select count(*)::int as n from public.cargas_delegado'))[0].n, 0, 'cargas:');
});

prueba('A7', 'Guardar a un alumno de baja: lo rechaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(13), ['X, Y'], 'tema'), { ok: false, motivo: 'alumno' });
});

prueba('A8', 'Un alumno pasa a baja después de cargado: sale de la lista y al traer queda aparte, sin entrar a la grilla', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(5), ['DÍAZ, ANA'], 'Tema uno'), { ok: true });
  await entregar(clave, s);
  await nube.sql(`update public.contratos_alumnos set nombre_alumno = '[BAJA] ' || nombre_alumno where id = $1::uuid`, [alumnoA(5)]);
  const l = await lista(clave, s);
  cierto(!deLista(l, 5), 'sigue en la lista');
  const c = await cargas();
  igual(c.length, 1, 'cargas:');
  igual(c[0].activo, false, 'activo:');
  const r = comparar(c, await nube.grilla(FIESTA_A));
  igual(r.cambios.length, 0, 'cambios:');
  igual(r.revisar.length, 1, 'revisar:');
});

prueba('A9', 'Se agrega un alumno a la fiesta con el link ya creado: aparece', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.sql(`insert into public.contratos_alumnos (id, evento_id, nombre_alumno, curso_division)
                  values ('a0000000-0000-4000-8000-000000000099', $1::uuid, 'ZÁRATE, NUEVO', '6° C')`, [FIESTA_A]);
  const l = await lista(clave, s);
  igual(l.alumnos.length, 13, 'cantidad:');
  igual(l.alumnos.at(-1).nombre, 'ZÁRATE, NUEVO', 'último:');
});

prueba('A10', 'Un link inventado o mal copiado: no muestra nada', async () => {
  const clave = await crear();
  igual(await lista('no-existe', null), { ok: false, motivo: 'link' });
  igual(await lista(clave.slice(0, -1), null), { ok: false, motivo: 'link' });
  igual(await lista(null, null), { ok: false, motivo: 'link' });
  igual(await entrarCrudo('no-existe', 'Laura Gómez'), { ok: false, motivo: 'link' });
  igual(await guardar('no-existe', 'x', alumnoA(2), ['A, B'], 't'), { ok: false, motivo: 'link' });
  igual(await entregar('no-existe', 'x'), { ok: false, motivo: 'link' });
});

prueba('A10b', 'Con el link bien pero sin haber entrado: dice la fiesta y ningún alumno', async () => {
  const clave = await crear();
  const l = await lista(clave, null);
  igual(l.ok, false); igual(l.motivo, 'entrar');
  igual(l.fiesta, 'Escuela Normal · Promo 2026', 'fiesta:');
  cierto(!('alumnos' in l), 'devolvió alumnos sin sesión');
  const otra = await lista(clave, 'sesion-inventada');
  igual(otra.motivo, 'entrar'); cierto(!('alumnos' in otra), 'devolvió alumnos con una sesión inventada');
});

prueba('A11', 'Alumno que ya tiene acompañantes y música en el programa: cerrado, y guardarle algo se rechaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  const a = deLista(await lista(clave, s), 1);
  igual(a.de, 'programa', 'de:');
  igual([a.prog_acomp, a.prog_musica], [true, true], 'programa:');
  igual([a.acompanantes, a.musica], [null, null], 'no muestra lo cargado:');
  igual(await guardar(clave, s, alumnoA(1), ['OTRO, NOMBRE'], 'otra'), { ok: false, motivo: 'ya_cargado' });
  igual(await guardar(clave, s, alumnoA(1), [], 'otra'), { ok: false, motivo: 'ya_cargado' });
});

prueba('A12', 'Alumno con solo acompañantes en el programa: se completa la música y nada más', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  const a = deLista(await lista(clave, s), 3);
  igual([a.de, a.prog_acomp, a.prog_musica], ['libre', true, false], 'estado:');
  igual(await guardar(clave, s, alumnoA(3), ['OTRO, NOMBRE'], 'Tema'), { ok: false, motivo: 'ya_cargado', campo: 'acompanantes' });
  igual(await guardar(clave, s, alumnoA(3), [], 'Tema de Mateo'), { ok: true });
  const c = await cargas();
  igual([c[0].acompanantes, c[0].musica], [[], 'Tema de Mateo'], 'lo cargado:');
});

prueba('A13', 'En el programa se borra lo cargado de un alumno: en el link vuelve a quedar libre', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.sql(`update public.contratos_alumnos set nombres_acompanantes = null, cantidad_acompanantes = 0, musica_elegida = null where id = $1::uuid`, [alumnoA(1)]);
  igual(deLista(await lista(clave, s), 1).de, 'libre', 'de:');
  igual(await guardar(clave, s, alumnoA(1), ['ACOSTA, JORGE'], 'Tema'), { ok: true });
});

prueba('A14', 'El contador cuenta los ya cargados en el programa y los que cargan los delegados', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  let l = await lista(clave, s);
  igual([l.total, l.cargados, l.faltan, l.mios], [12, 1, 11, 0], 'al principio:');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  await guardar(clave, s, alumnoA(5), [], 'Tema');
  l = await lista(clave, s);
  igual([l.total, l.cargados, l.faltan, l.mios], [12, 3, 9, 2], 'después:');
  const k = await link();
  igual([k.total, k.en_programa, k.cargados, k.faltan], [12, 1, 2, 9], 'en el panel:');
});

prueba('A15', 'El link lleva el nombre de la fiesta que le manda el programa, y sin nombre no se crea', async () => {
  const con = (f) => nube.rpc('jefe', 'delegado_link_crear', { p_evento: FIESTA_A, p_fiesta: f, p_vence_local: LIMITE, p_cupo: 1 });
  for (const malo of ['', '   ', null, 'x'.repeat(121)]) igual(await con(malo), { ok: false, motivo: 'fiesta' }, `"${String(malo).slice(0, 8)}":`);
  const r = await con('  Normal   Mariano  Iloza ');
  cierto(r.ok, JSON.stringify(r));
  igual((await lista(r.clave, null)).fiesta, 'Normal Mariano Iloza', 'en la entrada:');
  const s = await entrar(r.clave, 'Laura Gómez');
  await guardar(r.clave, s, alumnoA(2), [], 'Tema');
  await entregar(r.clave, s);
  cierto((await pendientes())[0].texto.startsWith('Acompañantes y música para traer: Normal Mariano Iloza · '), 'el aviso no dice la fiesta');
});

// ── B. La fecha y la hora límite ────────────────────────────────────────────

prueba('B1', 'Crear con "19/11 a las 20:00": queda como las 20:00 de Argentina (23:00 UTC), exacto', async () => {
  const r = await nube.rpc('jefe', 'delegado_link_crear', { p_evento: FIESTA_A, p_fiesta: FIESTA, p_vence_local: '2026-11-19 20:00', p_cupo: 1 });
  igual(r.vence_texto, 'jueves 19/11 a las 20:00', 'texto:');
  const f = await nube.sql(`select to_char(vence_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') as utc from public.links_delegado`);
  igual(f[0].utc, '2026-11-19 23:00:00', 'UTC:');
  igual((await link()).vence_local, '2026-11-19 20:00', 'vuelta:');
});

prueba('B2', 'Un segundo antes del límite: guarda', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.reloj('2026-11-19 22:59:59+00');
  igual(await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema'), { ok: true });
});

prueba('B3', 'En el límite en punto y un segundo después: no guarda', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.reloj('2026-11-19 23:00:00+00');
  igual(await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema'), { ok: false, motivo: 'vencido' });
  await nube.reloj('2026-11-19 23:00:01+00');
  igual(await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema'), { ok: false, motivo: 'vencido' });
  igual((await nube.sql('select count(*)::int as n from public.cargas_delegado'))[0].n, 0, 'cargas:');
  igual(await entrarCrudo(clave, 'Pedro Sosa'), { ok: false, motivo: 'vencido' });
});

prueba('B4', 'Enviar después del límite: no envía', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  await nube.reloj('2026-11-19 23:00:00+00');
  igual(await entregar(clave, s), { ok: false, motivo: 'vencido' });
  igual((await link()).celulares[0].entregado, false, 'entregado:');
});

prueba('B5', 'Con otro huso horario del lado de quien pregunta: el límite se dice igual', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.sql(`set timezone = 'Asia/Tokyo'`);
  try {
    igual((await lista(clave, s)).vence_texto, 'jueves 19/11 a las 20:00', 'Tokio:');
    await nube.reloj('2026-11-19 22:59:59+00');
    igual(await guardar(clave, s, alumnoA(2), [], 'Tema'), { ok: true }, 'un segundo antes:');
    await nube.reloj('2026-11-19 23:00:00+00');
    igual((await guardar(clave, s, alumnoA(4), [], 'Tema')).motivo, 'vencido', 'en punto:');
  } finally {
    await nube.sql(`set timezone = 'UTC'`);
  }
});

prueba('B6', 'Crear con una fecha ya pasada, o que no es una fecha: no lo deja', async () => {
  const con = (v) => nube.rpc('jefe', 'delegado_link_crear', { p_evento: FIESTA_A, p_fiesta: FIESTA, p_vence_local: v, p_cupo: 1 });
  igual(await con('2026-11-12 14:59'), { ok: false, motivo: 'pasada' });
  igual(await con('2026-11-12 15:00'), { ok: false, motivo: 'pasada' });
  igual(await con('19/11 20:00'), { ok: false, motivo: 'fecha' });
  igual(await con('2026-13-40 99:99'), { ok: false, motivo: 'fecha' });
  igual(await con(null), { ok: false, motivo: 'fecha' });
  igual(await link(), { ok: false, motivo: 'sin_link' });
});

prueba('B7', 'Alargar el límite con el link vencido: vuelve a guardar, con el mismo link', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await nube.reloj('2026-11-19 23:30:00+00');
  igual((await guardar(clave, s, alumnoA(2), [], 'Tema')).motivo, 'vencido');
  igual(await cambiar('vence', '2026-11-21 12:00'), { ok: true });
  igual(await guardar(clave, s, alumnoA(2), [], 'Tema'), { ok: true });
  const k = await link();
  igual([k.clave, k.vence_texto, k.estado], [clave, 'sábado 21/11 a las 12:00', 'abierto'], 'link:');
});

prueba('B8', 'Acortar el límite a una hora ya pasada: se cierra en el momento', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(2), [], 'Tema'), { ok: true });
  igual(await cambiar('vence', '2026-11-12 14:00'), { ok: true });
  igual((await guardar(clave, s, alumnoA(4), [], 'Tema')).motivo, 'vencido');
  igual((await link()).estado, 'vencido', 'estado:');
});

prueba('B9', 'Vencido con un delegado sin enviar: el panel dice quién y cuánto, y lo cargado sigue', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  await nube.reloj('2026-11-12 15:10:00-03');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'Tema');
  await entregar(clave, laura);
  await guardar(clave, pedro, alumnoA(5), [], 'Tema');
  await guardar(clave, pedro, alumnoA(6), [], 'Tema');
  await nube.reloj('2026-11-19 23:00:00+00');
  const k = await link();
  igual(k.estado, 'vencido', 'estado:');
  igual(k.celulares.map((c) => [c.nombre, c.entregado, c.cargados]), [['LAURA GÓMEZ', true, 1], ['PEDRO SOSA', false, 2]], 'celulares:');
  cierto(k.aviso.includes('venció sin enviar: PEDRO SOSA (cargó 2)'), `aviso: ${k.aviso}`);
  igual((await cargas()).length, 3, 'lo cargado sigue:');
  const l = await lista(clave, pedro);
  cierto(l.ok && l.vencido === true, 'el que estaba adentro sigue viendo, vencido');
});

prueba('B9b', 'Vencido, con lo de uno ya traído y lo de otro sin enviar: avisa por el que falta, hasta que lo traés', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'De Laura');
  await entregar(clave, laura);
  await guardar(clave, pedro, alumnoA(5), [], 'De Pedro');
  await nube.reloj('2026-11-12 16:00:00-03');
  igual(await cambiar('traido', JSON.stringify([alumnoA(2)])), { ok: true });
  igual(await pendientes(), [], 'recién traído, sin vencer:');
  await nube.reloj('2026-11-19 23:00:00+00');
  const p = await pendientes();
  igual(p.length, 1, 'al vencer:');
  cierto(p[0].texto.includes('venció sin enviar: PEDRO SOSA (cargó 1)') && !p[0].texto.includes('LAURA'), p[0].texto);
  igual(await cambiar('traido', JSON.stringify([alumnoA(5)])), { ok: true });
  igual(await pendientes(), [], 'traído lo de Pedro:');
  igual(await cambiar('traido', 'no es una lista'), { ok: false, motivo: 'alumnos' }, 'una lista mal armada:');
});

// ── C. Guardar, Enviar y su aviso ───────────────────────────────────────────

prueba('C1', 'Lo que falta, para el aviso de Enviar: el número justo', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  for (const n of [2, 3, 4, 5, 6, 7, 8, 9]) await guardar(clave, s, alumnoA(n), [], 'Tema');
  igual((await lista(clave, s)).faltan, 3, 'faltan:');
});

prueba('C2', 'Con todo completo no falta nadie', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  for (let n = 2; n <= 12; n++) await guardar(clave, s, alumnoA(n), [], 'Tema');
  igual((await lista(clave, s)).faltan, 0, 'faltan:');
});

prueba('C5', 'Enviar: queda enviado', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), [], 'Tema');
  igual((await lista(clave, s)).yo, { nombre: 'LAURA GÓMEZ', entregado: false }, 'antes:');
  igual(await entregar(clave, s), { ok: true });
  igual((await lista(clave, s)).yo, { nombre: 'LAURA GÓMEZ', entregado: true }, 'después:');
});

prueba('C5b', 'Enviar sin haber guardado ningún alumno: no envía', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await entregar(clave, s), { ok: false, motivo: 'nada' });
});

prueba('C7', 'Guardar lo suyo después de enviar: lo rechaza y no cambia nada', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  await entregar(clave, s);
  igual(await guardar(clave, s, alumnoA(2), ['OTRA, COSA'], 'Otro'), { ok: false, motivo: 'entregado' });
  igual(await guardar(clave, s, alumnoA(4), [], 'Otro'), { ok: false, motivo: 'entregado' });
  igual(await guardar(clave, s, alumnoA(2), [], ''), { ok: false, motivo: 'entregado' });
  const c = await cargas();
  igual([c.length, c[0].acompanantes, c[0].musica], [1, ['ÁLVAREZ, EVA'], 'Tema'], 'quedó:');
});

prueba('C8', 'Confirmar dos veces: una sola entrega', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), [], 'Tema');
  igual(await entregar(clave, s), { ok: true });
  const antes = (await nube.sql('select entregado_at::text as t from public.celulares_delegado'))[0].t;
  await nube.reloj('2026-11-12 16:00:00-03');
  igual(await entregar(clave, s), { ok: true, ya: true });
  const [a, b] = await Promise.all([entregar(clave, s), entregar(clave, s)]);
  igual([a, b], [{ ok: true, ya: true }, { ok: true, ya: true }], 'a la vez:');
  igual((await nube.sql('select entregado_at::text as t from public.celulares_delegado'))[0].t, antes, 'la hora de la entrega no cambió:');
});

prueba('C9', 'Otro delegado sigue después de que el primero envió: puede, y solo alumnos libres', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'Tema');
  await entregar(clave, laura);
  igual(await guardar(clave, pedro, alumnoA(5), [], 'Tema'), { ok: true });
  igual(await guardar(clave, pedro, alumnoA(2), [], 'Pisar'), { ok: false, motivo: 'otro', cargo: 'LAURA GÓMEZ' });
  igual(await entregar(clave, pedro), { ok: true });
});

prueba('C10', 'Reabrirle el envío: vuelve a editar lo suyo, y la grilla no cambió', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  const grillaAntes = await foto();
  await guardar(clave, s, alumnoA(2), [], 'Tema');
  await entregar(clave, s);
  const id = (await link()).celulares[0].id;
  igual(await cambiar('reabrir', id), { ok: true });
  igual((await lista(clave, s)).yo.entregado, false, 'entregado:');
  igual(await guardar(clave, s, alumnoA(2), [], 'Tema corregido'), { ok: true });
  igual(await foto(), grillaAntes, 'la grilla:');
});

prueba('C11', 'Guardar un alumno: queda guardado, no envía y no hay aviso', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema'), { ok: true });
  const a = deLista(await lista(clave, s), 2);
  igual([a.de, a.acompanantes, a.musica], ['mio', ['ÁLVAREZ, EVA'], 'Tema'], 'guardado:');
  const k = await link();
  igual([k.celulares[0].entregado, k.aviso], [false, null], 'sin enviar ni aviso:');
  igual(await pendientes(), [], 'pendientes:');
});

prueba('C12', 'Guardar, cerrar y volver con la misma sesión: lo guardado sigue', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA', 'ÁLVAREZ, LUIS'], 'Tema');
  const a = deLista(await lista(clave, s), 2);
  igual([a.de, a.acompanantes, a.musica], ['mio', ['ÁLVAREZ, EVA', 'ÁLVAREZ, LUIS'], 'Tema'], 'al volver:');
  igual(await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema dos'), { ok: true }, 'se puede cambiar:');
  igual(deLista(await lista(clave, s), 2).musica, 'Tema dos', 'cambiado:');
});

// ── D. Varios celulares, sin pisarse ────────────────────────────────────────

prueba('D1', 'Entrar pide nombre y apellido de verdad', async () => {
  const clave = await crear();
  for (const malo of ['', '   ', 'A', 'Laura', '12345 678', 'x'.repeat(61) + ' y']) {
    igual(await entrarCrudo(clave, malo), { ok: false, motivo: 'nombre' }, `"${malo.slice(0, 12)}":`);
  }
  const r = await entrarCrudo(clave, '  laura   gómez ');
  cierto(r.ok && r.sesion.length >= 60, 'no entró con un nombre bueno');
  igual((await link()).celulares[0].nombre, 'LAURA GÓMEZ', 'como quedó anotado:');
});

prueba('D2', 'Volver con la misma sesión: sigue adentro, con lo suyo', async () => {
  const clave = await crear({ cupo: 1 });
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), [], 'Tema');
  const l = await lista(clave, s);
  cierto(l.ok, 'no siguió adentro');
  igual([l.yo.nombre, l.mios], ['LAURA GÓMEZ', 1], 'lo suyo:');
  igual((await link()).celulares.length, 1, 'no ocupó otro lugar:');
});

prueba('D3', 'El segundo celular ve lo del primero cerrado, con el nombre y sin el contenido', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema secreto');
  const a = deLista(await lista(clave, pedro), 2);
  igual([a.de, a.cargo, a.acompanantes, a.musica], ['otro', 'LAURA GÓMEZ', null, null], 'lo que ve Pedro:');
});

prueba('D4', 'El segundo guarda un alumno del primero: lo rechaza y lo del primero queda intacto', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema de Laura');
  igual(await guardar(clave, pedro, alumnoA(2), ['PISAR, PISAR'], 'Pisado'), { ok: false, motivo: 'otro', cargo: 'LAURA GÓMEZ' });
  igual(await guardar(clave, pedro, alumnoA(2), [], ''), { ok: false, motivo: 'otro', cargo: 'LAURA GÓMEZ' }, 'vaciarlo tampoco:');
  const a = deLista(await lista(clave, laura), 2);
  igual([a.de, a.acompanantes, a.musica], ['mio', ['ÁLVAREZ, EVA'], 'Tema de Laura'], 'lo de Laura:');
});

prueba('D5', 'Dos celulares guardan el mismo alumno libre a la vez: queda el de uno solo', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  for (let vuelta = 0; vuelta < 20; vuelta++) {
    const n = 2 + (vuelta % 10);
    if (n === 3) continue;
    await nube.sql('delete from public.cargas_delegado');
    const pares = vuelta % 2 === 0
      ? [guardar(clave, laura, alumnoA(n), [], 'De Laura'), guardar(clave, pedro, alumnoA(n), [], 'De Pedro')]
      : [guardar(clave, pedro, alumnoA(n), [], 'De Pedro'), guardar(clave, laura, alumnoA(n), [], 'De Laura')];
    const r = await Promise.all(pares);
    igual(r.filter((x) => x.ok).length, 1, `vuelta ${vuelta}, cuántos ganaron:`);
    igual(r.filter((x) => x.motivo === 'otro').length, 1, `vuelta ${vuelta}, a cuántos les avisó:`);
    igual((await cargas()).length, 1, `vuelta ${vuelta}, renglones:`);
  }
});

prueba('D6', 'El primero vacía un alumno suyo: queda libre y otro lo puede cargar', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  igual(await guardar(clave, laura, alumnoA(2), [], '   '), { ok: true, libre: true });
  igual(deLista(await lista(clave, pedro), 2).de, 'libre', 'para Pedro:');
  igual(await guardar(clave, pedro, alumnoA(2), [], 'De Pedro'), { ok: true });
  igual(await guardar(clave, laura, alumnoA(4), [], ''), { ok: false, motivo: 'vacio' }, 'guardar vacío uno libre:');
});

prueba('D7', 'Link para 2 delegados: el tercero no entra', async () => {
  const clave = await crear({ cupo: 2 });
  await entrar(clave, 'Laura Gómez');
  await entrar(clave, 'Pedro Sosa');
  igual(await entrarCrudo(clave, 'Tercero Colado'), { ok: false, motivo: 'lleno' });
  const l = await lista(clave, null);
  igual([l.motivo, l.lleno], ['entrar', true], 'la pantalla de entrada lo sabe:');
  igual((await link()).celulares.length, 2, 'celulares:');
  for (const cupo of [0, 6, null]) {
    igual(await nube.rpc('jefe', 'delegado_link_crear', { p_evento: FIESTA_B, p_fiesta: 'San José', p_vence_local: LIMITE, p_cupo: cupo }), { ok: false, motivo: 'cupo' }, `cupo ${cupo}:`);
  }
});

prueba('D8', 'Sacar un celular dejando lo que cargó: no entra más y sus alumnos quedan libres para corregir', async () => {
  const clave = await crear({ cupo: 2 });
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema de Laura');
  const id = await celular('Laura Gómez');
  igual(await cambiar('sacar_dejando', id), { ok: true });
  igual((await lista(clave, laura)).motivo, 'sacado', 'Laura al abrir:');
  igual(await guardar(clave, laura, alumnoA(4), [], 'x'), { ok: false, motivo: 'sacado' }, 'Laura al guardar:');
  igual(await entregar(clave, laura), { ok: false, motivo: 'sacado' }, 'Laura al enviar:');
  const a = deLista(await lista(clave, pedro), 2);
  igual([a.de, a.acompanantes, a.musica], ['suelto', ['ÁLVAREZ, EVA'], 'Tema de Laura'], 'lo que ve Pedro:');
  igual(await guardar(clave, pedro, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema corregido'), { ok: true });
  igual(deLista(await lista(clave, pedro), 2).de, 'mio', 'pasó a Pedro:');
  cierto((await entrarCrudo(clave, 'Nueva Delegada')).ok, 'el lugar no quedó libre');
});

prueba('D9', 'Sacar un celular borrando lo que cargó: no entra más y sus alumnos quedan vacíos', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'Tema de Laura');
  await guardar(clave, pedro, alumnoA(5), [], 'Tema de Pedro');
  const id = await celular('Laura Gómez');
  igual(await cambiar('sacar_borrando', id), { ok: true });
  igual((await lista(clave, laura)).motivo, 'sacado', 'Laura:');
  igual(deLista(await lista(clave, pedro), 2).de, 'libre', 'su alumno:');
  igual((await cargas()).map((c) => c.cargo), ['PEDRO SOSA'], 'queda solo lo de Pedro:');
  igual(await cambiar('sacar_borrando', 'cualquier-cosa'), { ok: false, motivo: 'celular' }, 'un celular que no existe:');
});

prueba('D10', 'Link apagado: nadie entra ni guarda, y no dice ningún alumno', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await cambiar('apagar'), { ok: true });
  const l = await lista(clave, s);
  igual([l.ok, l.motivo], [false, 'apagado']); cierto(!('alumnos' in l), 'devolvió alumnos');
  igual(await entrarCrudo(clave, 'Pedro Sosa'), { ok: false, motivo: 'apagado' });
  igual(await guardar(clave, s, alumnoA(2), [], 'Tema'), { ok: false, motivo: 'apagado' });
  igual(await entregar(clave, s), { ok: false, motivo: 'apagado' });
  igual((await link()).estado, 'apagado', 'estado:');
  igual(await cambiar('prender'), { ok: true });
  igual(await guardar(clave, s, alumnoA(2), [], 'Tema'), { ok: true }, 'prendido de nuevo:');
});

prueba('D11', 'Leer o escribir las tablas sin usuario: no puede', async () => {
  await crear();
  for (const t of ['links_delegado', 'celulares_delegado', 'cargas_delegado', 'contratos_alumnos', 'eventos']) {
    const e = await falla(nube.sql(`select * from public.${t}`, [], 'anon'), `un anónimo leyó ${t}`);
    cierto(/permission denied/.test(e.message), `${t}: ${e.message}`);
  }
  for (const t of ['links_delegado', 'celulares_delegado', 'cargas_delegado']) {
    await falla(nube.sql(`delete from public.${t}`, [], 'anon'), `un anónimo borró ${t}`);
    await falla(nube.sql(`update public.${t} set evento_id = evento_id`, [], 'anon'), `un anónimo cambió ${t}`);
    const e = await falla(nube.sql(`select * from public.${t}`, [], 'jefe'), `alguien con usuario leyó ${t} directo`);
    cierto(/permission denied/.test(e.message), `${t} con usuario: ${e.message}`);
  }
});

prueba('D12', 'Usar lo del jefe, o lo de adentro, sin usuario: lo rechaza', async () => {
  const clave = await crear();
  const delJefe = [
    ['delegado_link', { p_evento: FIESTA_A }],
    ['delegado_link_crear', { p_evento: FIESTA_B, p_fiesta: 'San José', p_vence_local: LIMITE, p_cupo: 1 }],
    ['delegado_link_cambiar', { p_evento: FIESTA_A, p_accion: 'apagar', p_valor: null }],
    ['delegado_cargas', { p_evento: FIESTA_A }],
    ['delegado_pendientes', {}],
    ['delegado_alumnos', { p_evento: FIESTA_A }],
    ['delegado_aviso', { p_evento: FIESTA_A }],
  ];
  for (const [fn, args] of delJefe) {
    const e = await falla(nube.rpc('anon', fn, args), `un anónimo usó ${fn}`);
    cierto(/permission denied/.test(e.message), `${fn}: ${e.message}`);
  }
  igual((await link()).estado, 'abierto', 'el link sigue prendido:');
  igual(await link(FIESTA_B), { ok: false, motivo: 'sin_link' }, 'no se creó nada en B:');
  cierto(clave.length >= 60, 'la clave es corta');
});

prueba('D13', 'Cargar 3 acompañantes: lo rechaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(2), ['UNO, A', 'DOS, B', 'TRES, C'], 'Tema'), { ok: false, motivo: 'tope' });
  igual(await guardar(clave, s, alumnoA(2), ['UNO, A', '   ', 'DOS, B'], 'Tema'), { ok: true }, 'dos y uno vacío:');
  igual(deLista(await lista(clave, s), 2).acompanantes, ['UNO, A', 'DOS, B'], 'quedaron:');
  igual(await guardar(clave, s, alumnoA(4), 'UNO, A', 'Tema'), { ok: false, motivo: 'formato' }, 'no es una lista:');
  igual(await guardar(clave, s, alumnoA(4), [1, { a: 1 }], 'Tema'), { ok: false, motivo: 'formato' }, 'no son nombres:');
});

prueba('D14', 'Un nombre de acompañante larguísimo: lo rechaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(2), ['A'.repeat(81)], ''), { ok: false, motivo: 'largo', campo: 'acompanantes' });
  igual(await guardar(clave, s, alumnoA(2), ['A'.repeat(80)], ''), { ok: true }, '80 justas:');
});

prueba('D15', 'Música detallada, con acentos, símbolos y un link: llega igual, letra por letra, en un solo renglón', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  const musica = 'Entrada: "Vivir mi vida" – Marc Anthony (versión en vivo, 2013). Desde el minuto 0:45 hasta 2:10 — ¡sin la intro! https://youtu.be/YXnjy5YlDwk?t=45 & después «Ñandú» #2 @ 100%';
  // Escrita con renglones y espacios de más, queda en uno solo.
  const escrita = musica.replace('2013). ', '2013).\n  ').replace('intro! ', 'intro!\r\n');
  igual(await guardar(clave, s, alumnoA(2), ["D'ANGELO, MARÍA JOSÉ", 'ÑÁÑEZ, GÜNTHER'], escrita), { ok: true });
  const a = deLista(await lista(clave, s), 2);
  igual(a.musica, musica, 'en la página:');
  igual(a.acompanantes, ["D'ANGELO, MARÍA JOSÉ", 'ÑÁÑEZ, GÜNTHER'], 'acompañantes:');
  await entregar(clave, s);
  const c = await cargas();
  igual(c[0].musica, musica, 'al traer:');
  const r = comparar(c, await nube.grilla(FIESTA_A));
  igual(r.cambios[0].musica, musica, 'en la revisión:');
  await nube.guardarEnLaGrilla(FIESTA_A, r.cambios.map(datosAGuardar));
  const g = (await nube.grilla(FIESTA_A)).find((x) => x.id === alumnoA(2));
  igual([g.musica, g.acompanantes], [musica, ["D'ANGELO, MARÍA JOSÉ", 'ÑÁÑEZ, GÜNTHER']], 'en la grilla:');
});

prueba('D16', 'Música de 300 letras justas entra; de 301, no', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  igual(await guardar(clave, s, alumnoA(2), [], 'ñ'.repeat(300)), { ok: true }, '300:');
  igual(deLista(await lista(clave, s), 2).musica.length, 300, 'guardadas:');
  igual(await guardar(clave, s, alumnoA(2), [], 'ñ'.repeat(301)), { ok: false, motivo: 'largo', campo: 'musica' }, '301:');
  igual(deLista(await lista(clave, s), 2).musica.length, 300, 'sigue la de 300:');
});

// ── E. Lo que te llega a vos ────────────────────────────────────────────────

prueba('E1', 'Un delegado envía: el aviso dice qué fiesta, quién, cuántos y cuántos faltan', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), [], 'Tema');
  await guardar(clave, s, alumnoA(4), [], 'Tema');
  await entregar(clave, s);
  const p = await pendientes();
  igual(p.length, 1, 'avisos:');
  igual(p[0].evento_id, FIESTA_A, 'de qué fiesta:');
  igual(p[0].texto, 'Acompañantes y música para traer: Escuela Normal · Promo 2026 · envió LAURA GÓMEZ (2) · faltan 9 alumnos', 'texto:');
});

prueba('E7', 'Guardan borradores sin enviar: no hay aviso, solo sube el contador', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  for (const n of [2, 4]) await guardar(clave, laura, alumnoA(n), [], 'Tema');
  for (const n of [5, 6, 7]) await guardar(clave, pedro, alumnoA(n), [], 'Tema');
  igual(await pendientes(), [], 'avisos:');
  const k = await link();
  igual([k.aviso, k.cargados], [null, 5], 'en la fiesta:');
});

prueba('E8', 'Envían tres delegados de la misma fiesta: un solo aviso, con los tres', async () => {
  const clave = await crear();
  const nombres = ['Laura Gómez', 'Pedro Sosa', 'Ana Ríos'];
  let n = 2;
  for (const nombre of nombres) {
    const s = await entrar(clave, nombre);
    await guardar(clave, s, alumnoA(n === 3 ? 4 : n), [], 'Tema');
    n += 3;
    await nube.reloj(`2026-11-12 15:0${n}:00-03`);
    await entregar(clave, s);
  }
  const p = await pendientes();
  igual(p.length, 1, 'avisos:');
  for (const nombre of nombres) cierto(p[0].texto.includes(nombre.toUpperCase()), `falta ${nombre}: ${p[0].texto}`);
});

prueba('E9', 'Traés: el aviso se va y no vuelve hasta que haya un envío nuevo', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'Tema');
  await entregar(clave, laura);
  igual((await pendientes()).length, 1, 'antes de traer:');
  await nube.reloj('2026-11-12 16:00:00-03');
  igual(await cambiar('traido'), { ok: true });
  igual(await pendientes(), [], 'después de traer:');
  await nube.reloj('2026-11-12 17:00:00-03');
  await guardar(clave, pedro, alumnoA(5), [], 'Tema');
  igual(await pendientes(), [], 'otro guarda sin enviar:');
  igual(await cambiar('reabrir', await celular('Laura Gómez')), { ok: true });
  await guardar(clave, laura, alumnoA(4), [], 'Tema');
  igual(await pendientes(), [], 'reabierta, sin enviar todavía:');
  await entregar(clave, laura);
  igual((await pendientes()).length, 1, 'envío nuevo:');
});

prueba('E2', 'Traer: la revisión dice qué se carga, quién lo cargó y, si tenía algo, qué se reemplaza', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema nuevo');
  await guardar(clave, s, alumnoA(4), [], 'Tema de Sofía');
  await entregar(clave, s);
  // Después de que cargó, en el programa alguien le puso otra música a Bruno.
  await nube.sql(`update public.contratos_alumnos set musica_elegida = 'Tema viejo' where id = $1::uuid`, [alumnoA(2)]);
  const r = comparar(await cargas(), await nube.grilla(FIESTA_A));
  igual(r.cambios.length, 2, 'cambios:');
  const bruno = r.cambios.find((c) => c.alumno_id === alumnoA(2));
  igual([bruno.alumno, bruno.cargo, bruno.acompanantes, bruno.musica, bruno.teniaMusica, bruno.pisa],
    ['ÁLVAREZ, BRUNO', 'LAURA GÓMEZ', ['ÁLVAREZ, EVA'], 'Tema nuevo', 'Tema viejo', true], 'Bruno:');
  const sofia = r.cambios.find((c) => c.alumno_id === alumnoA(4));
  igual([sofia.acompanantes, sofia.musica, sofia.pisa], [null, 'Tema de Sofía', false], 'Sofía:');
});

prueba('E3', 'Traer con un delegado que no envió: lo suyo va aparte y elegís si lo incluís', async () => {
  const clave = await crear();
  const laura = await entrar(clave, 'Laura Gómez');
  const pedro = await entrar(clave, 'Pedro Sosa');
  await guardar(clave, laura, alumnoA(2), [], 'De Laura');
  await entregar(clave, laura);
  await guardar(clave, pedro, alumnoA(5), [], 'De Pedro');
  const c = await cargas();
  igual(c.map((x) => [x.cargo, x.entregado]), [['LAURA GÓMEZ', true], ['PEDRO SOSA', false]], 'cargas:');
  const sin = comparar(c, await nube.grilla(FIESTA_A));
  igual([sin.cambios.length, sin.sinEnviar.length], [1, 1], 'sin incluir:');
  const con = comparar(c, await nube.grilla(FIESTA_A), { incluirSinEnviar: true });
  igual([con.cambios.length, con.sinEnviar.length], [2, 1], 'incluyendo:');
});

prueba('E4', 'Mirar la revisión y no guardar: la grilla queda igual', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  const antes = await foto();
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  await entregar(clave, s);
  comparar(await cargas(), await nube.grilla(FIESTA_A));
  await link(); await pendientes();
  igual(await foto(), antes, 'la grilla:');
});

prueba('E5', 'Guardar: a la grilla entra solo lo revisado, y un casillero vacío no borra nada', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(3), [], 'Tema de Mateo');      // ya tenía acompañantes
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], '');     // sin música
  await entregar(clave, s);
  const r = comparar(await cargas(), await nube.grilla(FIESTA_A));
  igual(await nube.guardarEnLaGrilla(FIESTA_A, r.cambios.map(datosAGuardar)), 2, 'guardados:');
  const g = await nube.grilla(FIESTA_A);
  const de = (n) => g.find((x) => x.id === alumnoA(n));
  igual([de(3).acompanantes, de(3).musica], [['BENÍTEZ, CARLA'], 'Tema de Mateo'], 'Mateo conserva su acompañante:');
  igual([de(2).acompanantes, de(2).musica], [['ÁLVAREZ, EVA'], ''], 'Bruno:');
  igual([de(1).acompanantes, de(1).musica], [['ACOSTA, JORGE', 'RÍOS, MARTA'], 'Vivir mi vida · Marc Anthony'], 'Lucía no se tocó:');
  igual(de(6).musica, '', 'los no cargados siguen vacíos:');
  await falla(nube.guardarEnLaGrilla(FIESTA_A, [{ alumno_id: alumnoA(2), nombre_alumno: 'OTRO' }]), 'dejó escribir otra columna');
  igual(comparar(await cargas(), await nube.grilla(FIESTA_A)).cambios.length, 0, 'traer de nuevo no trae nada:');
});

prueba('E6', 'Un delegado cambia algo después de reabrirle: la grilla no cambia hasta que traés', async () => {
  const clave = await crear();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), [], 'Primera');
  await entregar(clave, s);
  const r = comparar(await cargas(), await nube.grilla(FIESTA_A));
  await nube.guardarEnLaGrilla(FIESTA_A, r.cambios.map(datosAGuardar));
  await cambiar('traido');
  const despuesDeTraer = await foto();
  await cambiar('reabrir', (await link()).celulares[0].id);
  // Bruno ya tiene música en el programa: desde el link no se la puede cambiar.
  igual(await guardar(clave, s, alumnoA(2), [], 'Segunda'), { ok: false, motivo: 'ya_cargado', campo: 'musica' }, 'lo ya traído:');
  igual(await guardar(clave, s, alumnoA(4), [], 'De Sofía'), { ok: true }, 'otro alumno:');
  igual(await foto(), despuesDeTraer, 'la grilla:');
});

prueba('G1', 'El SQL de la nube no escribe nunca en los alumnos ni en las fiestas', async () => {
  const sqlNube = readFileSync(new URL(SQL_DE_LA_NUBE, import.meta.url), 'utf8');
  for (const tabla of ['contratos_alumnos', 'eventos']) {
    cierto(!new RegExp(`(insert\\s+into|update|delete\\s+from|alter\\s+table|drop\\s+table)\\s+(public\\.)?${tabla}\\b`, 'i').test(sqlNube), `el SQL escribe en ${tabla}`);
  }
  const clave = await crear();
  const antes = await foto();
  const s = await entrar(clave, 'Laura Gómez');
  await guardar(clave, s, alumnoA(2), ['ÁLVAREZ, EVA'], 'Tema');
  await entregar(clave, s);
  const id = (await link()).celulares[0].id;
  for (const [accion, valor] of [['reabrir', id], ['cupo', '2'], ['vence', '2026-11-20 10:00'], ['apagar'], ['prender'], ['traido'], ['sacar_dejando', id]]) {
    igual(await cambiar(accion, valor ?? null), { ok: true }, `${accion}:`);
  }
  igual(await cambiar('inventada'), { ok: false, motivo: 'accion' });
  igual(await foto(), antes, 'los alumnos:');
});

// ── Correr ──────────────────────────────────────────────────────────────────

const resultados = [];
for (const p of pruebas) {
  await nube.reiniciar();
  await nube.reloj(AHORA);
  try {
    await p.fn();
    resultados.push({ ...p, pasa: true });
  } catch (e) {
    resultados.push({ ...p, pasa: false, error: e.message });
  }
}
const mal = resultados.filter((r) => !r.pasa);
for (const r of resultados) {
  console.log(`${r.pasa ? 'PASA   ' : 'NO PASA'} ${r.id.padEnd(4)} ${r.titulo}${r.pasa ? '' : `\n          → ${r.error}`}`);
}
console.log(`\n${resultados.length - mal.length} de ${resultados.length} pasan.`);
writeFileSync(new URL('./RESULTADO_reglas.md', import.meta.url), [
  '# Pruebas de reglas contra el SQL',
  '',
  `${resultados.length - mal.length} de ${resultados.length} pasan.`,
  '',
  '| # | Prueba | Resultado |',
  '|---|---|---|',
  ...resultados.map((r) => `| ${r.id} | ${r.titulo} | ${r.pasa ? 'Pasa' : `**No pasa**: ${r.error.replace(/\|/g, '/')}`} |`),
  '',
].join('\n'));
process.exit(mal.length ? 1 : 0);
