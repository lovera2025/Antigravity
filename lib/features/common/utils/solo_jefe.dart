/// Lo que cambia el salón lo hace solo el jefe: armar y personalizar el plano,
/// sortear, deshacer y restaurar el sorteo, y cambiar o mudar una familia de
/// mesa.
///
/// Es como trabajan (el jefe arma los salones desde la oficina), y además es lo
/// que evita que dos PCs se pisen el plano: la fila de `planos_evento` sube
/// entera, y con una sola PC cambiándola no hay a quién pisar. Ver
/// `docs/ideas/seguro-plano-atrasado.md`.
///
/// Sin modo jefe se sigue viendo todo: el plano, imprimirlo, las planillas, el
/// Historial, las entradas y el reparto de sillas. Lo que no se puede queda a
/// la vista, apagado, con este texto: así el operario sabe que existe y a quién
/// pedírselo. No se pide ningún PIN nuevo.
///
/// Quién está en modo jefe lo dice `esRolJefeProvider`. Las dos pantallas que
/// guardan (`detalle_evento_masivo_screen.dart` y `plano_evento_screen.dart`)
/// lo preguntan además en cada función que escribe, con `_frenaSinModoJefe`:
/// `test/solo_modo_jefe_test.dart` falla si aparece un guardado sin esa llave.
const kSoloEnModoJefe = 'Solo en modo jefe';
