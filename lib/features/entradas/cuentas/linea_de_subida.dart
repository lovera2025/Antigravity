/// Lo que dice la línea de arriba de VENDER sobre lo que espera subir a la nube:
/// "Todo subido" o cuánto falta (lo mismo que dice la barra, pedido del 7-nov
/// "para quedarnos tranquilos"). [atencion]: hay algo sin subir.
///
/// **Sin internet se vende igual**: todo queda en el equipo y sube solo.
({String texto, bool atencion}) lineaDeSubidaDeEntradas({
  required bool hayInternet,
  required int sinSubir,
}) {
  final ventas = sinSubir == 1 ? '1 venta' : '$sinSubir ventas';
  if (hayInternet) {
    return sinSubir <= 0
        ? (texto: 'Todo subido', atencion: false)
        : (texto: '$ventas subiendo', atencion: true);
  }
  return sinSubir <= 0
      ? (texto: 'Sin internet · nada por subir', atencion: false)
      : (texto: 'Sin internet · $ventas por subir', atencion: true);
}
