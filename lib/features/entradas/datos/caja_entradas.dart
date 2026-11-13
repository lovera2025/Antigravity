import '../../../core/utils/uuid_utils.dart';
import '../../barra/datos/lectura_de_filas.dart';

/// Una caja de venta de entradas (`entradas_cajas`, v80): la abre quien vende,
/// en su equipo, con el cambio inicial; vende, y la cierra contando el efectivo.
///
/// **No es la caja de cuotas** (`sesiones_caja`) **ni la de la barra**: las tres
/// no se cruzan, y la plata de cada sector no se mezcla.
///
/// **Vive en un solo equipo:** el que la abrió numera sus comprobantes y la
/// cierra. Por eso el número no choca sin internet. Cerrarla la actualiza; **no
/// se borra**.
class CajaEntradas {
  final String id;
  final String eventoId;

  /// Null si la abre el jefe.
  final String? operadorId;

  /// El nombre de quien la abrió, tal como estaba ese día: sale en el
  /// comprobante y en el cierre aunque después le cambien el nombre.
  final String? operadorNombre;
  final double cambioInicial;
  final String abiertaAt;
  final String? cerradaAt;
  final double? efectivoContado;
  final double? diferencia;
  final String? notaCierre;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const CajaEntradas({
    required this.id,
    required this.eventoId,
    this.operadorId,
    this.operadorNombre,
    this.cambioInicial = 0,
    required this.abiertaAt,
    this.cerradaAt,
    this.efectivoContado,
    this.diferencia,
    this.notaCierre,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get abierta => cerradaAt == null;

  /// Una caja recién abierta. El cambio puede ser 0, no negativo.
  factory CajaEntradas.abrir({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    double cambioInicial = 0,
    required DateTime ahora,
  }) {
    if (cambioInicial.isNaN || cambioInicial < 0) {
      throw ArgumentError.value(
          cambioInicial, 'cambioInicial', 'no puede ser negativo');
    }
    final iso = isoDe(ahora);
    return CajaEntradas(
      id: UuidUtils.generate(),
      eventoId: eventoId,
      operadorId: comoTextoONull(operadorId),
      operadorNombre: comoTextoONull(operadorNombre),
      cambioInicial: cambioInicial,
      abiertaAt: iso,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  CajaEntradas _con({
    String? cerradaAt,
    double? efectivoContado,
    double? diferencia,
    String? notaCierre,
    bool cambiaNota = false,
    String? hechoPor,
    String? deviceId,
    bool cambiaSello = false,
    String? updatedAt,
  }) =>
      CajaEntradas(
        id: id,
        eventoId: eventoId,
        operadorId: operadorId,
        operadorNombre: operadorNombre,
        cambioInicial: cambioInicial,
        abiertaAt: abiertaAt,
        cerradaAt: cerradaAt ?? this.cerradaAt,
        efectivoContado: efectivoContado ?? this.efectivoContado,
        diferencia: diferencia ?? this.diferencia,
        notaCierre: cambiaNota ? notaCierre : this.notaCierre,
        hechoPor: cambiaSello ? hechoPor : this.hechoPor,
        deviceId: cambiaSello ? deviceId : this.deviceId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// La misma caja, cerrada con lo que contó quien vende y la diferencia contra
  /// lo que tendría que haber. **No se corrige nada**: lo contado queda como se
  /// contó.
  CajaEntradas cerrada({
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required DateTime ahora,
  }) {
    if (efectivoContado.isNaN || efectivoContado < 0) {
      throw ArgumentError.value(
          efectivoContado, 'efectivoContado', 'no puede ser negativo');
    }
    if (diferencia.isNaN) {
      throw ArgumentError.value(
          diferencia, 'diferencia', 'tiene que ser un número');
    }
    return _con(
      cerradaAt: isoDe(ahora),
      efectivoContado: efectivoContado,
      diferencia: diferencia,
      notaCierre: comoTextoONull(nota),
      cambiaNota: true,
    );
  }

  /// La misma caja con otra nota de cierre: lo único que se puede agregar
  /// después de cerrar.
  CajaEntradas conNota(String? nota) =>
      _con(notaCierre: comoTextoONull(nota), cambiaNota: true);

  /// Con quién la tocó por última vez, desde qué equipo y cuándo: lo pone el
  /// repositorio.
  CajaEntradas sellada({
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) =>
      _con(
        hechoPor: hechoPor,
        deviceId: deviceId,
        cambiaSello: true,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'operador_id': operadorId,
        'operador_nombre': operadorNombre,
        'cambio_inicial': cambioInicial,
        'abierta_at': abiertaAt,
        'cerrada_at': cerradaAt,
        'efectivo_contado': efectivoContado,
        'diferencia': diferencia,
        'nota_cierre': notaCierre,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory CajaEntradas.fromMap(Map<String, dynamic> m) => CajaEntradas(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        operadorId: comoTextoONull(m['operador_id']),
        operadorNombre: comoTextoONull(m['operador_nombre']),
        cambioInicial: comoDouble(m['cambio_inicial']),
        abiertaAt: comoTexto(m['abierta_at']),
        cerradaAt: comoTextoONull(m['cerrada_at']),
        efectivoContado: comoDoubleONull(m['efectivo_contado']),
        diferencia: comoDoubleONull(m['diferencia']),
        notaCierre: comoTextoONull(m['nota_cierre']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
