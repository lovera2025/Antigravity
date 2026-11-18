// Las muestras: lo que contesta el SQL de verdad en una historia fija, guardado en
// `test/datos/nube_del_delegado.json`. El programa las lee en
// `test/nube_del_delegado_se_lee_test.dart`: así una clave que el SQL cambie y el
// programa no (o al revés) se nota sin abrir un navegador.
//
//   node muestras.mjs      las vuelve a sacar y las guarda
//
// `pruebas.mjs` (M1) falla si el archivo guardado ya no es lo que contesta el SQL.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { abrir, FIESTA_A, alumnoA } from './db.mjs';

export const ARCHIVO_DE_MUESTRAS = new URL('../../test/datos/nube_del_delegado.json', import.meta.url);

const AHORA = '2026-11-12 15:00:00-03';
const MAS_TARDE = '2026-11-12 16:00:00-03';
const VENCIDO = '2026-11-20 10:00:00-03';

/** Corre la historia en [nube] (con reloj de prueba) y devuelve las respuestas. */
export async function armarMuestras(nube) {
  await nube.reiniciar();
  await nube.reloj(AHORA);
  const jefe = (fn, args = {}) => nube.rpc('jefe', fn, args);
  const anon = (fn, args = {}) => nube.rpc('anon', fn, args);
  const link = () => jefe('delegado_link', { p_evento: FIESTA_A });
  const cambiar = (accion, valor = null) =>
    jefe('delegado_link_cambiar', { p_evento: FIESTA_A, p_accion: accion, p_valor: valor });
  const m = {};

  m.link_sin = await link();
  m.crear = await jefe('delegado_link_crear', {
    p_evento: FIESTA_A, p_fiesta: 'Escuela Normal · Promo 2026', p_vence_local: '2026-11-19 20:00', p_cupo: 2,
  });
  const clave = m.crear.clave;
  const lista = (sesion) => anon('delegado_lista', { p_clave: clave, p_sesion: sesion });
  const entrar = (nombre) => anon('delegado_entrar', { p_clave: clave, p_nombre: nombre });
  const guardar = (sesion, n, acomp, musica) => anon('delegado_guardar', {
    p_clave: clave, p_sesion: sesion, p_alumno: alumnoA(n), p_acompanantes: acomp, p_musica: musica,
  });
  const entregar = (sesion) => anon('delegado_entregar', { p_clave: clave, p_sesion: sesion });

  m.lista_link_malo = await anon('delegado_lista', { p_clave: 'no-existe', p_sesion: null });
  m.lista_sin_nadie = await lista(null);
  m.entrar_nombre = await entrar('Laura');
  m.entrar_ok = await entrar('Laura Gómez');
  const laura = m.entrar_ok.sesion;
  const pedro = (await entrar('Pedro Sosa')).sesion;
  m.entrar_lleno = await entrar('Ana Ríos');
  m.lista_para_entrar = await lista(null);

  m.guardar_ok = await guardar(laura, 2, ['ÁLVAREZ, EVA'], 'Tema de Laura');
  m.guardar_vacio = await guardar(laura, 4, [], '');
  m.guardar_tope = await guardar(laura, 4, ['A, B', 'C, D', 'E, F'], '');
  m.guardar_largo = await guardar(laura, 4, [], 'ñ'.repeat(301));
  await guardar(laura, 4, [], 'Para aceptar');
  m.entregar_nada = await entregar(pedro);
  m.entregar_ok = await entregar(laura);
  m.entregar_ya = await entregar(laura);
  m.pendientes = await jefe('delegado_pendientes');
  // El jefe acepta uno de los dos enviados.
  await cambiar('traido', JSON.stringify([alumnoA(4)]));

  await nube.reloj(MAS_TARDE);
  await guardar(pedro, 5, ['DE PRUEBA, ANA'], 'De Pedro');
  await guardar(laura, 6, [], 'Sin enviar de Laura');
  await guardar(laura, 7, [], 'Se saca');
  m.guardar_libre = await guardar(laura, 7, [], '');
  // Pedro corrige lo que ya estaba en el programa (ACOSTA tenía todo).
  await guardar(pedro, 1, [], 'Corregido por Pedro');

  m.lista_adentro = await lista(laura);
  m.link_abierto = await link();
  m.cargas = await jefe('delegado_cargas', { p_evento: FIESTA_A });
  m.alumnos_estado = await jefe('delegado_alumnos_estado', { p_evento: FIESTA_A });
  m.historial = await jefe('delegado_historial', { p_evento: FIESTA_A });

  const celulares = m.link_abierto.celulares.map((c) => c.id);
  const idPedro = m.link_abierto.delegados.find((d) => d.nombre === 'PEDRO SOSA').id;
  m.sacar = await cambiar('sacar_dejando', idPedro);
  m.entrar_sacado = await entrar('pedro sosa');
  m.lista_sacado = await lista(pedro);
  m.link_con_sacado = await link();

  await cambiar('apagar');
  m.lista_apagado = await lista(laura);
  m.link_apagado = await link();
  await cambiar('prender');

  await nube.reloj(VENCIDO);
  m.lista_vencido = await lista(laura);
  m.link_vencido = await link();
  m.guardar_vencido = await guardar(laura, 8, [], 'Tarde');
  m.cambiar_mal = await cambiar('inventada');

  // Lo que sale al azar (la clave, las sesiones, los ids de los celulares) se
  // cambia por nombres fijos: si no, el archivo cambiaría en cada corrida.
  let texto = JSON.stringify(m, null, 1);
  const fijo = (valor, nombre) => { texto = texto.split(valor).join(nombre); };
  fijo(clave, 'CLAVE');
  fijo(laura, 'SESION-LAURA');
  fijo(pedro, 'SESION-PEDRO');
  celulares.forEach((id, i) => fijo(id, `celular-${i + 1}`));
  return `${texto}\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const nube = await abrir({ relojDePrueba: true });
  writeFileSync(ARCHIVO_DE_MUESTRAS, await armarMuestras(nube));
  console.log(`Muestras guardadas en ${fileURLToPath(ARCHIVO_DE_MUESTRAS)}`);
  process.exit(0);
}
