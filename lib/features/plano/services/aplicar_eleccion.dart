import '../../../models/plano_evento.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';

/// El plano que hay que guardar después de "Estilo y armado", a partir del que
/// la nube tiene en ese momento ([fresco]) y no del que se veía en pantalla.
///
/// - Sin plano en la nube ni en esta PC, es uno nuevo, con el id fijo de la
///   fiesta.
/// - Si ya había uno, se le cambia lo elegido y **se conserva todo lo demás**:
///   las mesas fijas y libres, los bloques, los colores y las medidas.
/// - **Con familias ya sentadas el armado no se cambia.** Los números de sus
///   mesas son de ese armado. Puede pasar aunque acá se haya elegido otro: la
///   otra PC armó el plano y sorteó mientras este diálogo estaba abierto.
///   [conservoArmado] lo dice, para avisar.
({PlanoEvento plano, bool conservoArmado}) aplicarEleccionAlPlano({
  required String eventoId,
  required PlanoEvento? fresco,
  required ArmadoSalon armado,
  required EstiloPlano estilo,
  required ModoSorteo modo,
  required bool hayFamiliasConMesa,
  required String? hechoPor,
  required DateTime ahora,
}) {
  if (fresco == null) {
    return (
      plano: PlanoEvento.nuevo(
        eventoId: eventoId,
        armado: armado,
        estilo: estilo,
        modo: modo,
        hechoPor: hechoPor,
        ahora: ahora,
      ),
      conservoArmado: false,
    );
  }
  final conservar = fresco.armadoONull != null && hayFamiliasConMesa;
  return (
    plano: fresco.copyWith(
      armado: conservar ? null : armado,
      estilo: estilo,
      modoSorteo: modo,
      hechoPor: hechoPor,
      ahora: ahora,
    ),
    conservoArmado: conservar,
  );
}
