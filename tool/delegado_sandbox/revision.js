// La revisión antes de guardar: compara lo que cargaron los delegados con la grilla.
// No escribe nada. Hace de `PlanillaDelegado.comparar` del programa.

export function limpios(lista) {
  return (Array.isArray(lista) ? lista : [])
    .map((n) => String(n ?? '').trim().replace(/\s+/g, ' '))
    .filter((n) => n !== '');
}

/**
 * `cargas`: lo que devuelve `delegado_cargas`. `grilla`: los alumnos como están en el
 * programa ({id, acompanantes, musica}). Un casillero vacío nunca borra nada.
 */
export function comparar(cargas, grilla, { incluirSinEnviar = false } = {}) {
  const porId = new Map(grilla.map((g) => [g.id, g]));
  const cambios = [];
  const revisar = [];
  const sinEnviar = [];
  let iguales = 0;
  for (const c of cargas) {
    const g = porId.get(c.alumno_id);
    if (!c.activo || !g) {
      revisar.push({
        quien: c.alumno || 'Un alumno que ya no está',
        motivo: 'Ya no está activo en la fiesta: no se carga.',
      });
      continue;
    }
    const teniaA = limpios(g.acompanantes);
    const teniaM = String(g.musica ?? '').trim();
    const nuevoA = limpios(c.acompanantes);
    const nuevaM = String(c.musica ?? '').trim();
    const cambiaA = nuevoA.length > 0 && nuevoA.join('|') !== teniaA.join('|');
    const cambiaM = nuevaM !== '' && nuevaM !== teniaM;
    if (!cambiaA && !cambiaM) {
      iguales++;
      continue;
    }
    const cambio = {
      alumno_id: c.alumno_id,
      alumno: c.alumno,
      division: c.division,
      cargo: c.cargo ?? null,
      enviado: c.entregado === true,
      acompanantes: cambiaA ? nuevoA : null,
      musica: cambiaM ? nuevaM : null,
      teniaAcompanantes: cambiaA ? teniaA : [],
      teniaMusica: cambiaM ? teniaM : '',
    };
    cambio.pisa = cambio.teniaAcompanantes.length > 0 || cambio.teniaMusica !== '';
    if (!cambio.enviado) {
      sinEnviar.push(cambio);
      if (!incluirSinEnviar) continue;
    }
    cambios.push(cambio);
  }
  return { cambios, iguales, revisar, sinEnviar };
}

/** Lo que se escribe en la grilla por un cambio: solo lo que cambia. */
export function datosAGuardar(cambio) {
  const d = { alumno_id: cambio.alumno_id };
  if (cambio.acompanantes) d.acompanantes = cambio.acompanantes;
  if (cambio.musica !== null && cambio.musica !== undefined) d.musica = cambio.musica;
  return d;
}
