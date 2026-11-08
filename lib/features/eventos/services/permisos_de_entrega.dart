/// Qué puede hacer quien está entregando entradas, según dónde está y quién es.
///
/// **En la oficina** (la fiesta → ENTRADAS) se cobra y se edita al alumno con las
/// pantallas de siempre. **En el mostrador de Entradas** (el operador que entra con
/// su PIN solo a entregar) no: si la familia debe, se le dice que pase por caja, y
/// si el operador también tiene Cobros, PASAR A CAJA lo lleva sin volver a poner el
/// PIN. **Anular una entrega es solo del jefe**, en los dos lugares (decidido el
/// 30-oct: "el jefe solo puede anular, con las entradas también").
class PermisosDeEntrega {
  /// IR A COBRAR abre el cobro de siempre (solo en la oficina).
  final bool cobrarAca;

  /// PASAR A CAJA: el mostrador, con el permiso de Cobros.
  final bool pasarACaja;

  /// EDITAR ALUMNO y "Cambiar acompañantes" (solo en la oficina).
  final bool editar;

  /// ANULAR ENTREGA (solo el jefe).
  final bool anular;

  const PermisosDeEntrega({
    required this.cobrarAca,
    required this.pasarACaja,
    required this.editar,
    required this.anular,
  });

  /// La entrega desde la pantalla de la fiesta.
  const PermisosDeEntrega.oficina({required bool esJefe})
      : cobrarAca = true,
        pasarACaja = false,
        editar = true,
        anular = esJefe;

  /// La entrega desde el mostrador de Entradas.
  const PermisosDeEntrega.mostrador({required bool tieneCobros})
      : cobrarAca = false,
        pasarACaja = tieneCobros,
        editar = false,
        anular = false;

  factory PermisosDeEntrega.de({
    required bool enElMostrador,
    required bool tieneCobros,
    required bool esJefe,
  }) =>
      enElMostrador
          ? PermisosDeEntrega.mostrador(tieneCobros: tieneCobros)
          : PermisosDeEntrega.oficina(esJefe: esJefe);
}
