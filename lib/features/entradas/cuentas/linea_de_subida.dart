/// Lo que espera subir a la nube desde este equipo, para la línea de arriba de
/// VENDER: las ventas, **las entregas sin cargo** (familias con una parte, o la
/// fila de la entrega, sin subir) y el resto de la caja (abrirla o cerrarla, una
/// anulación). Pedido del usuario (20-nov-2026, "si sube, que suba de verdad"):
/// la línea decía "Todo subido" con una entrega hecha sin internet todavía en la
/// cola, porque contaba solo las ventas.
class PendientesDeEntradas {
  final int ventas;
  final int entregas;
  final int otros;

  const PendientesDeEntradas({this.ventas = 0, this.entregas = 0, this.otros = 0});

  static const nada = PendientesDeEntradas();

  int get total => ventas + entregas + otros;
  bool get vacio => total <= 0;

  /// "1 venta", "2 ventas y 1 entrega", "2 ventas, 1 entrega y 1 cambio". Vacío: "".
  String get enPalabras {
    final partes = [
      if (ventas > 0) ventas == 1 ? '1 venta' : '$ventas ventas',
      if (entregas > 0) entregas == 1 ? '1 entrega' : '$entregas entregas',
      if (otros > 0) otros == 1 ? '1 cambio' : '$otros cambios',
    ];
    if (partes.length <= 1) return partes.join();
    return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
  }

  @override
  bool operator ==(Object other) =>
      other is PendientesDeEntradas &&
      other.ventas == ventas &&
      other.entregas == entregas &&
      other.otros == otros;

  @override
  int get hashCode => Object.hash(ventas, entregas, otros);
}

/// Lo que dice la línea de arriba de VENDER sobre lo que espera subir a la nube:
/// "Todo subido" o cuánto falta (lo mismo que dice la barra, pedido del 7-nov
/// "para quedarnos tranquilos"). [atencion]: hay algo sin subir.
///
/// **Sin internet se vende y se entrega igual**: todo queda en el equipo y sube
/// solo. "Todo subido" solo cuando no queda **nada** de este equipo en la cola:
/// ni ventas, ni entregas, ni la caja.
({String texto, bool atencion}) lineaDeSubidaDeEntradas({
  required bool hayInternet,
  required PendientesDeEntradas pendientes,
}) {
  final cuanto = pendientes.enPalabras;
  if (hayInternet) {
    return pendientes.vacio
        ? (texto: 'Todo subido', atencion: false)
        : (texto: '$cuanto subiendo', atencion: true);
  }
  return pendientes.vacio
      ? (texto: 'Sin internet · nada por subir', atencion: false)
      : (texto: 'Sin internet · $cuanto por subir', atencion: true);
}
