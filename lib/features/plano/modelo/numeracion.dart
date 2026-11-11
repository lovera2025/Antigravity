/// Dónde termina la numeración de un salón armado a medida (6.5.1).
///
/// Lo pidió el jefe el 10-nov-2026, después del sorteo de una escuela con 101
/// mesas: la 101 le quedó pegada al escenario, y las mesas que se agregan
/// después del sorteo (102, 103…) van al fondo, donde hay lugar. Con la
/// numeración terminando al fondo, las nuevas siguen al lado de la última.
enum FinNumeracion {
  /// La serpentina de siempre: la izquierda desde el escenario hacia el fondo
  /// y la derecha de vuelta, del fondo al escenario. El último número queda
  /// junto al escenario.
  escenario,

  /// Las dos mitades desde el escenario hacia el fondo: primero la izquierda,
  /// después la derecha. El último número queda al fondo, a la derecha.
  fondo;

  /// Lo que se guarda en la `config` del plano, en la clave `numeracion`,
  /// cuando **nadie la eligió**. La serpentina de siempre no se guarda: un
  /// plano sin la clave es ese, y es además "esta fiesta nunca eligió".
  String? get clave => this == fondo ? 'fondo' : null;

  /// Lo que se guarda cuando **alguien la eligió** en Acomodar: también la
  /// serpentina de siempre lleva su clave (`escenario`), junto con el momento
  /// (`numeracion_el`). Así se distingue "nunca eligió" de "eligió junto al
  /// escenario", que es lo que necesita la memoria (`NumeracionRecordada`).
  String get claveElegida => name;

  /// Una clave vacía o que esta versión no conoce es la serpentina de siempre.
  static FinNumeracion deClave(Object? clave) =>
      clave == 'fondo' ? fondo : escenario;

  String get texto => switch (this) {
        escenario => 'Junto al escenario',
        fondo => 'Al fondo',
      };
}
