import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// Una caja de barra (`barra_cajas`, v77): la abre la cajera en su equipo con el
/// cambio inicial, vende, y la cierra contando el efectivo. **No es la caja de cuotas**
/// (`sesiones_caja`): las dos no se cruzan.
///
/// **Vive en un solo equipo:** el que la abrió numera sus tickets y la cierra. Por eso
/// el número del ticket no choca sin internet. Cerrarla la actualiza; **no se borra**.
class CajaBarra {
  final String id;
  final String eventoId;
  final String? operadorId;

  /// El nombre de quien la abrió, tal como estaba ese día: sale en el ticket y en el
  /// cierre aunque después le cambien el nombre al operador.
  final String? operadorNombre;

  /// El número que eligió la cajera (Caja 1 a 6): sale en el ticket.
  final int numeroCaja;

  /// Dónde está la caja en la fiesta, si hace falta decirlo. Texto libre.
  final String? sede;
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

  const CajaBarra({
    required this.id,
    required this.eventoId,
    this.operadorId,
    this.operadorNombre,
    required this.numeroCaja,
    this.sede,
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

  /// Una caja recién abierta. El número va de 1 en adelante y el cambio no puede ser
  /// negativo.
  factory CajaBarra.abrir({
    required String eventoId,
    String? operadorId,
    String? operadorNombre,
    required int numeroCaja,
    String? sede,
    double cambioInicial = 0,
    required DateTime ahora,
  }) {
    if (numeroCaja < 1) {
      throw ArgumentError.value(numeroCaja, 'numeroCaja', 'va de 1 en adelante');
    }
    if (cambioInicial.isNaN || cambioInicial < 0) {
      throw ArgumentError.value(cambioInicial, 'cambioInicial', 'no puede ser negativo');
    }
    final iso = isoDe(ahora);
    return CajaBarra(
      id: UuidUtils.generate(),
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: comoTextoONull(operadorNombre),
      numeroCaja: numeroCaja,
      sede: comoTextoONull(sede),
      cambioInicial: cambioInicial,
      abiertaAt: iso,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// La misma caja, cerrada con lo que contó la cajera y la diferencia contra lo que
  /// tendría que haber. No se corrige nada: lo contado queda como se contó.
  CajaBarra cerrada({
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required DateTime ahora,
  }) {
    if (efectivoContado.isNaN || efectivoContado < 0) {
      throw ArgumentError.value(efectivoContado, 'efectivoContado', 'no puede ser negativo');
    }
    if (diferencia.isNaN) {
      throw ArgumentError.value(diferencia, 'diferencia', 'tiene que ser un número');
    }
    return CajaBarra(
      id: id,
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: operadorNombre,
      numeroCaja: numeroCaja,
      sede: sede,
      cambioInicial: cambioInicial,
      abiertaAt: abiertaAt,
      cerradaAt: isoDe(ahora),
      efectivoContado: efectivoContado,
      diferencia: diferencia,
      notaCierre: comoTextoONull(nota),
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// La misma caja con el cambio con que arrancó: abrirla no lo pregunta, se pone
  /// después si hay. No puede ser negativo.
  CajaBarra conCambio(double cambio) {
    if (cambio.isNaN || cambio < 0) {
      throw ArgumentError.value(cambio, 'cambio', 'no puede ser negativo');
    }
    return CajaBarra(
      id: id,
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: operadorNombre,
      numeroCaja: numeroCaja,
      sede: sede,
      cambioInicial: cambio,
      abiertaAt: abiertaAt,
      cerradaAt: cerradaAt,
      efectivoContado: efectivoContado,
      diferencia: diferencia,
      notaCierre: notaCierre,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Con quién la tocó por última vez, desde qué equipo y cuándo: lo pone el
  /// repositorio.
  CajaBarra sellada({
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) =>
      CajaBarra(
        id: id,
        eventoId: eventoId,
        operadorId: operadorId,
        operadorNombre: operadorNombre,
        numeroCaja: numeroCaja,
        sede: sede,
        cambioInicial: cambioInicial,
        abiertaAt: abiertaAt,
        cerradaAt: cerradaAt,
        efectivoContado: efectivoContado,
        diferencia: diferencia,
        notaCierre: notaCierre,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'operador_id': operadorId,
        'operador_nombre': operadorNombre,
        'numero_caja': numeroCaja,
        'sede': sede,
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

  factory CajaBarra.fromMap(Map<String, dynamic> m) => CajaBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        operadorId: comoTextoONull(m['operador_id']),
        operadorNombre: comoTextoONull(m['operador_nombre']),
        numeroCaja: comoInt(m['numero_caja']),
        sede: comoTextoONull(m['sede']),
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
