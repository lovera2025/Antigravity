import '../repositories/contratos_repository.dart';

/// Los pagos de cada contrato de [ids], de la base de esta PC, agrupados por
/// su contrato. Quien no tiene ninguno queda con la lista vacía.
///
/// De acá sale qué mesa adicional está "a confirmar" (6.9.2,
/// `AdicionalesDeLaFamilia`): lo leen la puerta y el PLANO. **Si falla, quien
/// lo llama sigue sin los pagos (null)**: sin ellos no se marca ninguna mesa.
Future<Map<String, List<Map<String, dynamic>>>> pagosPorContrato(
  ContratosRepository contratos,
  List<String> ids,
) async {
  final pagos = {for (final id in ids) id: <Map<String, dynamic>>[]};
  for (final p in await contratos.getPagosForContratoIds(ids)) {
    final id = p['contrato_alumno_id'];
    if (id is String) pagos[id]?.add(p);
  }
  return pagos;
}
