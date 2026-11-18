// Roturas a propósito del SQL del link (la segunda parte, 6.9.2): cambia UNA regla
// en una COPIA del archivo, corre `pruebas.mjs` contra esa copia y dice qué pruebas
// fallaron. Sirve para saber que cada regla tiene una prueba que de verdad la vigila.
//
//   node roturas.mjs            todas
//   node roturas.mjs N3 N6      solo esos casos
//
// El archivo de la migración no se toca nunca (se compara su huella al final).
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const ARCHIVO = new URL('../../supabase/migrations/20261118120000_link_delegado_reabrir.sql', import.meta.url);
const huella = () => createHash('sha256').update(readFileSync(ARCHIVO)).digest('hex');
const original = readFileSync(ARCHIVO, 'utf8').replace(/\r\n/g, '\n');
const antes = huella();

/** `n`: cuál de las apariciones se cambia (1 = la primera). Sin `n`, tiene que haber una sola. */
const CASOS = [
  { id: 'R01', regla: 'Guardar después de enviar deja ese alumno sin enviar',
    busca: "        traido_at    = null,\n        enviado_at   = null;", pone: "        traido_at    = null;" },
  { id: 'R02', regla: 'Corregir lo ya aceptado lo vuelve a "para traer"',
    busca: "        traido_at    = null,\n        enviado_at   = null;", pone: "        enviado_at   = null;" },
  { id: 'R03', regla: 'El mismo nombre entra desde otro celular aunque el cupo esté lleno',
    busca: 'if v_aparatos > 0 then', pone: 'if false then' },
  { id: 'R04', regla: 'El cupo cuenta personas, no celulares',
    busca: 'select count(distinct public.delegado_llave(c.nombre)) into v_personas', pone: 'select count(*) into v_personas' },
  { id: 'R05', regla: 'Quien fue sacado no entra con su nombre desde otro celular',
    busca: "    if v_sacada then\n      return jsonb_build_object('ok', false, 'motivo', 'sacado');\n    end if;\n", pone: '' },
  { id: 'R06', regla: 'Enviar marca solo lo de esa persona',
    busca: "  where g.evento_id = v_link.evento_id and g.enviado_at is null\n    and g.celular_id in (\n      select c.id from public.celulares_delegado c\n      where c.evento_id = v_link.evento_id and public.delegado_llave(c.nombre) = v_llave);",
    pone: '  where g.evento_id = v_link.evento_id and g.enviado_at is null;' },
  { id: 'R07', regla: 'Una fecha futura prende el link cerrado a mano',
    busca: 'apagado  = case when v_vence > v_ahora then false else apagado end', pone: 'apagado  = apagado' },
  { id: 'R08', regla: 'Cada guardado queda en el historial',
    busca: "  insert into public.cambios_delegado\n    (evento_id, alumno_id, celular_id, quien, que, acompanantes, musica, created_at)\n  values (v_link.evento_id, p_alumno, v_cel.id, v_cel.nombre, 'guardo', v_nombres, v_musica, v_ahora);\n", pone: '' },
  { id: 'R09', regla: 'Vaciar queda en el historial',
    busca: "      insert into public.cambios_delegado (evento_id, alumno_id, celular_id, quien, que, created_at)\n      values (v_link.evento_id, p_alumno, v_cel.id, v_cel.nombre, 'vacio', v_ahora);\n", pone: '' },
  { id: 'R10', regla: 'El aviso de "envió" cuenta solo lo enviado (un guardado suelto no avisa)',
    busca: 'where g.evento_id = p_evento and g.traido_at is null and g.enviado_at is not null', pone: 'where g.evento_id = p_evento and g.traido_at is null' },
  { id: 'R42', regla: 'El aviso se va cuando se trae lo enviado',
    busca: 'where g.evento_id = p_evento and g.traido_at is null and g.enviado_at is not null', pone: 'where g.evento_id = p_evento and g.enviado_at is not null' },
  { id: 'R43', regla: 'El aviso mira cada carga, no la hora del último traer (envían mientras el jefe revisa)',
    busca: "    where g.evento_id = p_evento and g.traido_at is null and g.enviado_at is not null\n",
    pone: "    where g.evento_id = p_evento and g.traido_at is null and g.enviado_at is not null\n      and g.enviado_at > coalesce(v_link.traido_at, '-infinity'::timestamptz)\n" },
  { id: 'R11', regla: 'Al vencer avisa también por lo corregido después de enviar',
    busca: 'where g.evento_id = p_evento and g.traido_at is null and g.enviado_at is null', pone: 'where g.evento_id = p_evento and g.traido_at is null and c.entregado_at is null' },
  { id: 'R12', regla: 'Sacar a un delegado vale para todos sus celulares',
    busca: "  elsif p_accion = 'sacar_dejando' then\n    update public.celulares_delegado c set sacado_at = v_ahora\n    where c.evento_id = p_evento and c.sacado_at is null\n      and public.delegado_llave(c.nombre) = v_persona;",
    pone: "  elsif p_accion = 'sacar_dejando' then\n    update public.celulares_delegado c set sacado_at = v_ahora\n    where c.evento_id = p_evento and c.sacado_at is null\n      and c.id = p_valor::uuid;" },
  { id: 'R13', regla: 'Volver a dejar entrar a quien se había sacado',
    busca: 'update public.celulares_delegado c set sacado_at = null', pone: 'update public.celulares_delegado c set sacado_at = c.sacado_at' },
  { id: 'R14', regla: 'El estado "aceptado" de un alumno',
    busca: "when g.traido_at is not null  then 'aceptado'", pone: "when g.traido_at is not null  then 'enviado'" },
  { id: 'R15', regla: 'Vencido no entra', busca: 'if v_ahora >= v_link.vence_at then', n: 1, pone: 'if false then' },
  { id: 'R16', regla: 'Vencido no guarda', busca: 'if v_ahora >= v_link.vence_at then', n: 2, pone: 'if false then' },
  { id: 'R17', regla: 'Vencido no envía', busca: 'if v_ahora >= v_link.vence_at then', n: 3, pone: 'if false then' },
  { id: 'R18', regla: 'Hasta 2 acompañantes', busca: 'if jsonb_array_length(v_nombres) > 2 then', pone: 'if jsonb_array_length(v_nombres) > 3 then' },
  { id: 'R19', regla: 'Música de hasta 300 letras', busca: 'if char_length(v_musica) > 300 then', pone: 'if char_length(v_musica) > 301 then' },
  { id: 'R20', regla: 'La lista de alumnos con su estado, solo con usuario',
    busca: "if auth.role() is distinct from 'authenticated' then", n: 4, pone: 'if false then' },
  { id: 'R21', regla: 'El historial, solo con usuario',
    busca: "if auth.role() is distinct from 'authenticated' then", n: 5, pone: 'if false then' },
  { id: 'R22', regla: 'El historial, cerrado para quien no tiene usuario (la tabla)',
    busca: 'revoke all on table public.cambios_delegado from anon, authenticated;', pone: 'grant all on table public.cambios_delegado to anon, authenticated;' },
  { id: 'R23', regla: 'Enviar dos veces sin nada nuevo no cambia nada', busca: 'if v_nuevas = 0 then', pone: 'if false then' },
  { id: 'R24', regla: 'Enviar sin haber guardado nada no envía', busca: 'if v_suyas = 0 then', pone: 'if false then' },
  { id: 'R25', regla: 'Sacar borrando queda en el historial',
    busca: "'Junior Eventos', 'borrado', g.acompanantes", pone: "'Junior Eventos', 'guardo', g.acompanantes" },
  { id: 'R26', regla: 'Aceptar queda en el historial',
    busca: "'Junior Eventos', 'aceptado', g.acompanantes", pone: "'Junior Eventos', 'guardo', g.acompanantes" },
  { id: 'R27', regla: 'Lo cargado antes entra al historial al pasar a la segunda parte',
    busca: "       'guardo', g.acompanantes, g.musica, g.updated_at\n  from public.cargas_delegado g\n  left join public.celulares_delegado c on c.id = g.celular_id\n where not exists (",
    pone: "       'guardo', g.acompanantes, g.musica, g.updated_at\n  from public.cargas_delegado g\n  left join public.celulares_delegado c on c.id = g.celular_id\n where false and not exists (" },
  { id: 'R28', regla: 'Lo enviado con la regla anterior sigue enviado',
    busca: "   and c.entregado_at is not null\n   and g.enviado_at is null;", pone: "   and false;" },
  { id: 'R29', regla: 'Al traer, "enviado" es de cada carga y no del celular',
    busca: "'entregado',    g.enviado_at is not null,", pone: "'entregado',    c.entregado_at is not null," },
  { id: 'R30', regla: 'Sin sesión, la entrada no da ningún alumno (solo quiénes entraron)',
    busca: "      'ok', false, 'motivo', 'entrar',", pone: "      'ok', false, 'motivo', 'entrar', 'alumnos', (select jsonb_agg(t.nombre) from public.delegado_tablero(v_link.evento_id) t)," },
  { id: 'R31', regla: 'Quien fue sacado no figura para tocar su nombre en la entrada',
    busca: 'where c.evento_id = v_link.evento_id and c.sacado_at is null\n      group by', pone: 'where c.evento_id = v_link.evento_id\n      group by' },
  { id: 'R32', regla: 'Lo que cargó otro se ve como de otro ("de")',
    busca: "when t.persona = v_yo     then 'mio'", pone: "when true                 then 'mio'" },
  { id: 'R33', regla: 'Reenviar avisa de nuevo (el envío queda con la hora nueva)',
    busca: "  update public.celulares_delegado c set entregado_at = v_ahora\n  where c.evento_id = v_link.evento_id and public.delegado_llave(c.nombre) = v_llave;\n", pone: '' },
  { id: 'R34', regla: 'Aceptar marca como traído solo lo que se trajo',
    busca: "        update public.cargas_delegado g set traido_at = v_ahora\n        where g.evento_id = p_evento\n          and g.alumno_id in (select e::uuid from jsonb_array_elements_text(p_valor::jsonb) e);",
    pone: "        update public.cargas_delegado g set traido_at = v_ahora\n        where g.evento_id = p_evento;" },
  { id: 'R35', regla: 'La lista de alumnos con su estado: un anónimo no la puede llamar (el permiso)',
    busca: 'revoke all on function public.delegado_alumnos_estado(uuid) from public, anon;\n', pone: '' },
  { id: 'R36', regla: 'El historial: un anónimo no lo puede llamar (el permiso)',
    busca: 'revoke all on function public.delegado_historial(uuid)      from public, anon;\n', pone: '' },
  { id: 'R37', regla: 'Cómo está el link, solo con usuario (la llave de adentro)',
    busca: "if auth.role() is distinct from 'authenticated' then", n: 1, pone: 'if false then' },
  { id: 'R38', regla: 'Lo que cambia el jefe, solo con usuario (la llave de adentro)',
    busca: "if auth.role() is distinct from 'authenticated' then", n: 2, pone: 'if false then' },
  { id: 'R39', regla: 'Lo cargado para traer, solo con usuario (la llave de adentro)',
    busca: "if auth.role() is distinct from 'authenticated' then", n: 3, pone: 'if false then' },
  { id: 'R40', regla: 'El tablero de adentro: nadie de afuera',
    busca: 'revoke all on function public.delegado_tablero(uuid)            from public, anon, authenticated;\n', pone: '' },
  { id: 'R41', regla: 'Los datos de los alumnos de adentro: nadie de afuera',
    busca: 'revoke all on function public.delegado_alumnos_datos(uuid)      from public, anon, authenticated;\n', pone: '' },
];

const cambiar =(texto, { busca, pone, n }) => {
  const partes = texto.split(busca);
  const veces = partes.length - 1;
  if (veces === 0) return null;
  if (!n && veces !== 1) return null;
  const k = n ?? 1;
  if (k > veces) return null;
  return partes.slice(0, k).join(busca) + pone + partes.slice(k).join(busca);
};

const pedidos = process.argv.slice(2);
const carpeta = mkdtempSync(join(tmpdir(), 'roturas-link-'));
const aqui = fileURLToPath(new URL('.', import.meta.url));
let sinVigia = 0;
for (const caso of CASOS) {
  if (pedidos.length && !pedidos.includes(caso.id)) continue;
  const roto = cambiar(original, caso);
  if (roto === null) {
    console.log(`[${caso.id}] NO SE APLICÓ (no encontró el texto, o está más de una vez): ${caso.regla}`);
    sinVigia++;
    continue;
  }
  const copia = join(carpeta, `${caso.id}.sql`);
  writeFileSync(copia, roto);
  const r = spawnSync(process.execPath, ['pruebas.mjs'], {
    cwd: aqui, encoding: 'utf8', env: { ...process.env, SQL_DEL_LINK_2: pathToFileURL(copia).href },
  });
  const salida = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const todas = [...salida.matchAll(/^NO PASA (\S+)/gm)].map((m) => m[1]);
  // M1 (las muestras) cambia con casi cualquier cosa: no cuenta como la vigía de
  // una regla. Cada regla tiene que tener su prueba.
  const fallan = todas.filter((id) => id !== 'M1');
  const cuenta = /(\d+) de (\d+) pasan/.exec(salida);
  if (todas.length && !fallan.length) {
    sinVigia++;
    console.log(`[${caso.id}] ATENCIÓN: solo lo notan las muestras (M1), ninguna prueba propia · ${caso.regla}`);
  } else if (fallan.length) {
    console.log(`[${caso.id}] FALLA, como tiene que ser → ${fallan.join(', ')} · ${caso.regla}`);
  } else if (!cuenta) {
    console.log(`[${caso.id}] el SQL roto ni carga (cuenta como vigilado, pero mirar) · ${caso.regla}\n${salida.slice(-300)}`);
  } else {
    sinVigia++;
    console.log(`[${caso.id}] ATENCIÓN: todo sigue pasando con la regla rota · ${caso.regla}`);
  }
}
console.log(`\nSin vigía: ${sinVigia}. El archivo de verdad ${huella() === antes ? 'quedó IGUAL' : 'CAMBIÓ: revisar'}.`);
process.exit(sinVigia ? 1 : 0);
