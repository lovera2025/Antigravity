import '../../../core/utils/uuid_utils.dart';
import '../../barra/datos/lectura_de_filas.dart';

/// El precio de la entrada de una fiesta (`entradas_config`, v80): lo pone el
/// jefe en ENTRADAS → PRECIOS. Una fila por fiesta, con id fijo
/// ([UuidUtils.entradasConfigId]); cambiarla la actualiza.
///
/// **Sin [valorEntrada] la fiesta no se puede vender**, y la pantalla lo dice.
/// Todo lo que el jefe todavía no decidió vive acá como un dato, no como
/// código: la anticipada, el porcentaje de los lugares adicionales, el recargo
/// y si el vendedor puede descontar.
class ConfigEntradas {
  final String id;
  final String eventoId;

  /// El "$X". Null: todavía no se puso.
  final double? valorEntrada;

  /// El precio de la anticipada. Null: no hay anticipada.
  final double? precioAnticipada;

  /// El último día de la anticipada, `AAAA-MM-DD`, en hora de Argentina.
  final String? anticipadaHasta;

  /// El porcentaje **de descuento** de las entradas de la mesa adicional y las
  /// sillas extra (regla del 4-nov: "al 50 % de su valor"). Viene en 50.
  final double descuentoLugaresPct;

  /// El recargo por pagar por transferencia. Viene en 0: sin recargo.
  final double recargoPct;

  /// Si el vendedor puede poner descuentos a mano. Si no, solo en modo jefe.
  final bool descuentoAMano;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const ConfigEntradas({
    required this.id,
    required this.eventoId,
    this.valorEntrada,
    this.precioAnticipada,
    this.anticipadaHasta,
    this.descuentoLugaresPct = kDescuentoDeLosLugares,
    this.recargoPct = 0,
    this.descuentoAMano = false,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// El descuento de los lugares adicionales mientras el jefe no lo cambie.
  static const kDescuentoDeLosLugares = 50.0;

  /// La de una fiesta a la que todavía no se le puso nada.
  factory ConfigEntradas.vacia(String eventoId, {required DateTime ahora}) {
    final iso = isoDe(ahora);
    return ConfigEntradas(
      id: UuidUtils.entradasConfigId(eventoId),
      eventoId: eventoId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Si ya se puede vender.
  bool get tienePrecio => (valorEntrada ?? 0) > 0;

  /// Si tiene una anticipada completa: precio y hasta qué día. Una sin fecha
  /// no rige nunca.
  bool get tieneAnticipada =>
      (precioAnticipada ?? 0) > 0 && diaValido(anticipadaHasta);

  /// `AAAA-MM-DD`, y que sea un día que existe.
  static bool diaValido(String? dia) {
    if (dia == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dia)) {
      return false;
    }
    final d = DateTime.tryParse(dia);
    return d != null && _dia(d) == dia;
  }

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// El día de [momento] como se guarda: `AAAA-MM-DD`.
  static String diaDe(DateTime momento) => _dia(momento);

  /// La misma config con lo que el jefe puso en PRECIOS. **Tira `ArgumentError`
  /// si algo no cierra**: es la segunda llave de **las reglas de siempre** (los
  /// precios en pesos enteros, la anticipada con su precio y su día o ninguna de
  /// las dos, los porcentajes entre 0 y 100).
  ///
  /// Las reglas nuevas de PRECIOS (6.9.3: elegir Anticipada o General, la
  /// General siempre, un día que no pasó, los porcentajes con número) las frena
  /// `EleccionDePrecios` (`loQueFalta` y `enColumnas`, que llama a esta): esta
  /// no sabe qué día es ni qué se eligió (decisión de la fase A del 20-nov,
  /// aceptada).
  ConfigEntradas conPrecios({
    required double? valorEntrada,
    required double? precioAnticipada,
    required String? anticipadaHasta,
    required double descuentoLugaresPct,
    required double recargoPct,
    required bool descuentoAMano,
  }) {
    Never no(String por) => throw ArgumentError('los precios no cierran: $por');
    bool pesosEnteros(double v) => !v.isNaN && v >= 0 && v == v.roundToDouble();

    if (valorEntrada != null && !pesosEnteros(valorEntrada)) {
      no('el valor de la entrada va en pesos enteros');
    }
    final anticipada = (precioAnticipada ?? 0) > 0 ? precioAnticipada : null;
    final hasta = anticipadaHasta?.trim();
    final hayDia = hasta != null && hasta.isNotEmpty;
    if (anticipada != null && !pesosEnteros(anticipada)) {
      no('la anticipada va en pesos enteros');
    }
    if ((anticipada != null) != hayDia) {
      no('la anticipada lleva su precio y hasta qué día, las dos cosas o ninguna');
    }
    if (hayDia && !diaValido(hasta)) no('el día de la anticipada no existe');
    if (anticipada != null && (valorEntrada ?? 0) <= 0) {
      no('la anticipada necesita el valor de la entrada');
    }
    if (descuentoLugaresPct.isNaN ||
        descuentoLugaresPct < 0 ||
        descuentoLugaresPct > 100) {
      no('el porcentaje de los lugares va de 0 a 100');
    }
    if (recargoPct.isNaN || recargoPct < 0 || recargoPct > 100) {
      no('el recargo va de 0 a 100');
    }
    return ConfigEntradas(
      id: id,
      eventoId: eventoId,
      valorEntrada: (valorEntrada ?? 0) > 0 ? valorEntrada : null,
      precioAnticipada: anticipada,
      anticipadaHasta: anticipada == null ? null : hasta,
      descuentoLugaresPct: descuentoLugaresPct,
      recargoPct: recargoPct,
      descuentoAMano: descuentoAMano,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Si [otra] dice lo mismo: guardar sin cambiar nada no escribe.
  bool mismosPreciosQue(ConfigEntradas otra) =>
      otra.eventoId == eventoId &&
      otra.valorEntrada == valorEntrada &&
      otra.precioAnticipada == precioAnticipada &&
      otra.anticipadaHasta == anticipadaHasta &&
      otra.descuentoLugaresPct == descuentoLugaresPct &&
      otra.recargoPct == recargoPct &&
      otra.descuentoAMano == descuentoAMano;

  /// Con quién la tocó por última vez, desde qué equipo y cuándo: lo pone el
  /// repositorio. [createdAt] es cuándo nació la fila que ya había.
  ConfigEntradas sellada({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      ConfigEntradas(
        id: id,
        eventoId: eventoId,
        valorEntrada: valorEntrada,
        precioAnticipada: precioAnticipada,
        anticipadaHasta: anticipadaHasta,
        descuentoLugaresPct: descuentoLugaresPct,
        recargoPct: recargoPct,
        descuentoAMano: descuentoAMano,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'valor_entrada': valorEntrada,
        'precio_anticipada': precioAnticipada,
        'anticipada_hasta': anticipadaHasta,
        'descuento_lugares_pct': descuentoLugaresPct,
        'recargo_pct': recargoPct,
        'descuento_a_mano': descuentoAMano ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ConfigEntradas.fromMap(Map<String, dynamic> m) => ConfigEntradas(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        valorEntrada: comoDoubleONull(m['valor_entrada']),
        precioAnticipada: comoDoubleONull(m['precio_anticipada']),
        anticipadaHasta: comoTextoONull(m['anticipada_hasta']),
        // Una fila sin la columna (no debería) se lee con lo de siempre.
        descuentoLugaresPct: comoDoubleONull(m['descuento_lugares_pct']) ??
            kDescuentoDeLosLugares,
        recargoPct: comoDouble(m['recargo_pct']),
        descuentoAMano: comoBool(m['descuento_a_mano']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
