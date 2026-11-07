import 'dart:convert';

import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';
import 'venta_barra.dart';

/// Una bebida de un vale: cuántas y cuál, con el nombre de la venta.
class BebidaDelVale {
  final int cantidad;
  final String nombre;

  const BebidaDelVale(this.cantidad, this.nombre);

  Map<String, dynamic> toJson() => {'cantidad': cantidad, 'nombre': nombre};

  factory BebidaDelVale.fromJson(Map<String, dynamic> m) =>
      BebidaDelVale(comoInt(m['cantidad']), comoTexto(m['nombre']));

  @override
  bool operator ==(Object other) =>
      other is BebidaDelVale && other.cantidad == cantidad && other.nombre == nombre;

  @override
  int get hashCode => Object.hash(cantidad, nombre);

  @override
  String toString() => '$cantidad $nombre';
}

/// Un papel de vale que **salió** de una venta de la barra (`barra_vales`, v78): el
/// original, o una copia. Se anota cuando el papel sale, nunca antes: un vale que no
/// salió no tiene fila.
///
/// Sirve para dos cosas: que una copia saque **el mismo vale** que salió (con sus
/// bebidas, cantidades y número), y que la cajera reimprima una sola vez. **La venta
/// no se toca** (nunca se edita), y **solo se agregan filas.**
class ValeBarra {
  final String id;
  final String ventaId;
  final String cajaBarraId;
  final String eventoId;

  /// El orden del vale en la venta ("N° 0017-3"). Null: era el único de la venta.
  final int? numeroVale;
  final List<BebidaDelVale> bebidas;

  /// Por separado sale "VALE POR 3 / CERVEZA"; todo junto, una bebida por renglón.
  final bool porSeparado;

  /// 0 el original; 1, 2… cada copia.
  final int copiaNumero;

  /// Por qué se reimprimió. Solo las copias, y siempre.
  final String? motivo;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const ValeBarra({
    required this.id,
    required this.ventaId,
    required this.cajaBarraId,
    required this.eventoId,
    this.numeroVale,
    required this.bebidas,
    required this.porSeparado,
    this.copiaNumero = 0,
    this.motivo,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get esCopia => copiaNumero > 0;

  /// El papel que salió de [venta]. Si no cierra es un error del programa: sin
  /// bebidas, una cantidad en cero, o una copia sin motivo.
  factory ValeBarra.salio({
    required VentaBarra venta,
    required List<BebidaDelVale> bebidas,
    required bool porSeparado,
    int? numeroVale,
    int copiaNumero = 0,
    String? motivo,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    Never no(String por) => throw ArgumentError('el vale no cierra: $por');
    if (bebidas.isEmpty) no('no tiene bebidas');
    for (final b in bebidas) {
      if (b.cantidad < 1) no('${b.nombre} tiene cantidad ${b.cantidad}');
    }
    if (numeroVale != null && numeroVale < 1) no('el número va de 1 en adelante');
    if (copiaNumero < 0) no('la copia va de 0 en adelante');
    final m = motivo?.trim();
    if (copiaNumero > 0 && (m == null || m.isEmpty)) no('una copia lleva motivo');
    final iso = isoDe(ahora);
    return ValeBarra(
      id: UuidUtils.generate(),
      ventaId: venta.id,
      cajaBarraId: venta.cajaBarraId,
      eventoId: venta.eventoId,
      numeroVale: numeroVale,
      bebidas: List.unmodifiable(bebidas),
      porSeparado: porSeparado,
      copiaNumero: copiaNumero,
      motivo: copiaNumero > 0 ? m : null,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'venta_id': ventaId,
        'caja_barra_id': cajaBarraId,
        'evento_id': eventoId,
        'numero_vale': numeroVale,
        'bebidas': jsonEncode([for (final b in bebidas) b.toJson()]),
        'por_separado': porSeparado ? 1 : 0,
        'copia_numero': copiaNumero,
        'motivo': motivo,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Unas bebidas ilegibles dejan el vale sin bebidas, no frenan la lista.
  static List<BebidaDelVale> _bebidasDe(Object? v) {
    try {
      final lista = v is String ? jsonDecode(v) : v;
      if (lista is! List) return const [];
      return [
        for (final b in lista)
          if (b is Map) BebidaDelVale.fromJson(Map<String, dynamic>.from(b)),
      ];
    } catch (_) {
      return const [];
    }
  }

  factory ValeBarra.fromMap(Map<String, dynamic> m) => ValeBarra(
        id: comoTexto(m['id']),
        ventaId: comoTexto(m['venta_id']),
        cajaBarraId: comoTexto(m['caja_barra_id']),
        eventoId: comoTexto(m['evento_id']),
        numeroVale: comoIntONull(m['numero_vale']),
        bebidas: _bebidasDe(m['bebidas']),
        porSeparado: comoBool(m['por_separado']),
        copiaNumero: comoInt(m['copia_numero']),
        motivo: comoTextoONull(m['motivo']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
