import 'dart:convert';

import '../../../core/utils/uuid_utils.dart';
import '../../barra/datos/lectura_de_filas.dart';
import '../../barra/datos/venta_barra.dart' show MedioBarra;

/// Qué es un renglón de una venta de entradas.
enum TipoRenglonEntradas {
  /// Entradas a precio de lista, con el descuento a mano si lo hay.
  suelta,

  /// Las de la mesa adicional y las sillas extra de esa familia: pagan el
  /// lugar, y su entrada se compra con el descuento de la fiesta (el 50 %).
  lugar,

  /// Un tipo que esta versión no conoce (lo escribió una más nueva). Se cuenta
  /// por su precio y su cantidad, que siempre están.
  otro;

  static TipoRenglonEntradas deTexto(Object? v) =>
      TipoRenglonEntradas.values.firstWhere(
        (t) => t != TipoRenglonEntradas.otro && t.name == v,
        orElse: () => TipoRenglonEntradas.otro,
      );
}

/// Un renglón del comprobante, **con el nombre y el precio de ese momento**: si
/// el jefe cambia el precio, la venta vieja sigue diciendo lo que se cobró.
class RenglonEntradas {
  /// Como vino escrito: `suelta`, `lugar`, o lo que haya puesto una versión
  /// más nueva (se conserva para no perderlo).
  final String tipoClave;
  final String nombre;

  /// El precio de lista de cada una, antes del descuento.
  final double precioLista;

  /// El porcentaje descontado: el de los lugares en un `lugar`, el que se puso
  /// a mano en una `suelta`.
  final double descuentoPct;

  /// Lo que se cobró por cada una.
  final double precio;
  final int cantidad;

  const RenglonEntradas({
    required this.tipoClave,
    required this.nombre,
    required this.precioLista,
    this.descuentoPct = 0,
    required this.precio,
    required this.cantidad,
  });

  TipoRenglonEntradas get tipo => TipoRenglonEntradas.deTexto(tipoClave);

  double get subtotal => precio * cantidad;

  /// Lo que se dejó de cobrar en este renglón contra el precio de lista.
  double get descontado => (precioLista - precio) * cantidad;

  /// El precio de cada una con [pct] de descuento sobre [lista], en pesos
  /// enteros. Es la única cuenta del descuento: la usan la pantalla y la venta.
  static double precioCon(double lista, double pct) =>
      (lista * (100 - pct) / 100).roundToDouble();

  /// Un renglón de entradas sueltas, con el descuento a mano [descuentoPct].
  factory RenglonEntradas.suelta({
    required String nombre,
    required double precioLista,
    double descuentoPct = 0,
    required int cantidad,
  }) =>
      RenglonEntradas(
        tipoClave: TipoRenglonEntradas.suelta.name,
        nombre: nombre,
        precioLista: precioLista,
        descuentoPct: descuentoPct,
        precio: precioCon(precioLista, descuentoPct),
        cantidad: cantidad,
      );

  /// Un renglón de las entradas de los lugares adicionales de una familia.
  factory RenglonEntradas.lugar({
    required String nombre,
    required double precioLista,
    required double descuentoPct,
    required int cantidad,
  }) =>
      RenglonEntradas(
        tipoClave: TipoRenglonEntradas.lugar.name,
        nombre: nombre,
        precioLista: precioLista,
        descuentoPct: descuentoPct,
        precio: precioCon(precioLista, descuentoPct),
        cantidad: cantidad,
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipoClave,
        'nombre': nombre,
        'precio_lista': precioLista,
        'descuento_pct': descuentoPct,
        'precio': precio,
        'cantidad': cantidad,
      };

  factory RenglonEntradas.fromJson(Map<String, dynamic> m) => RenglonEntradas(
        tipoClave: comoTexto(m['tipo']),
        nombre: comoTexto(m['nombre']),
        // Un renglón sin precio de lista (no debería) vale lo que se cobró.
        precioLista: comoDoubleONull(m['precio_lista']) ?? comoDouble(m['precio']),
        descuentoPct: comoDouble(m['descuento_pct']),
        precio: comoDouble(m['precio']),
        cantidad: comoInt(m['cantidad']),
      );

  @override
  bool operator ==(Object other) =>
      other is RenglonEntradas &&
      other.tipoClave == tipoClave &&
      other.nombre == nombre &&
      other.precioLista == precioLista &&
      other.descuentoPct == descuentoPct &&
      other.precio == precio &&
      other.cantidad == cantidad;

  @override
  int get hashCode =>
      Object.hash(tipoClave, nombre, precioLista, descuentoPct, precio, cantidad);
}

/// Una venta de entradas (`entradas_ventas`, v80). **Nunca se edita ni se
/// borra:** anularla es otra fila (`entradas_anulaciones`), que hace el jefe.
///
/// **No es un pago de cuota**: no toca `pagos_contrato_alumno`, ni
/// `sesiones_caja`, ni `contratos_alumnos`. El saldo, la mora y el cierre de
/// COBROS no la conocen (`test/venta_entradas_no_toca_test.dart`).
class VentaEntradas {
  final String id;
  final String cajaEntradasId;
  final String eventoId;

  /// Correlativo dentro de su caja: "N° 0017".
  final int numero;

  /// La familia, si compra una familia de la fiesta. Null: alguien de afuera.
  final String? contratoAlumnoId;

  /// Nombre y apellido de quien compra y retira. Obligatorio.
  final String compradorNombre;
  final String? compradorDni;
  final List<RenglonEntradas> renglones;

  /// Las entradas de toda la venta: la suma de los renglones.
  final int cantidad;

  /// Lo que valen, ya con los descuentos. El recargo va aparte.
  final double total;

  /// La plata descontada **a mano** en esta venta (no la de los lugares).
  final double descuento;
  final MedioBarra medio;

  /// Lo cobrado en efectivo y por transferencia: suman el [total] más el
  /// [recargo].
  final double efectivo;
  final double transferencia;
  final double? recibe;
  final double vuelto;
  final double recargo;
  final double? recargoPct;

  /// Los números del talonario, como `TramoTalonario.aTexto`
  /// ("1043-1058,1101-1108"). Null: no se anotaron.
  final String? numeros;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const VentaEntradas({
    required this.id,
    required this.cajaEntradasId,
    required this.eventoId,
    required this.numero,
    this.contratoAlumnoId,
    required this.compradorNombre,
    this.compradorDni,
    required this.renglones,
    required this.cantidad,
    required this.total,
    this.descuento = 0,
    required this.medio,
    this.efectivo = 0,
    this.transferencia = 0,
    this.recibe,
    this.vuelto = 0,
    this.recargo = 0,
    this.recargoPct,
    this.numeros,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Lo que pagó, con el recargo.
  double get cobrado => total + recargo;

  /// Cuántas de sus entradas son de un tipo.
  int cuantas(TipoRenglonEntradas tipo) => renglones
      .where((r) => r.tipo == tipo)
      .fold(0, (s, r) => s + r.cantidad);

  /// Una venta nueva, con su número. **Tiene que cerrar**, y si no, tira
  /// `ArgumentError` y la venta no se arma (como `VentaBarra.nueva`):
  ///
  /// - con renglones, cada uno con cantidad de 1 en adelante y su precio igual
  ///   al de lista con su descuento;
  /// - con nombre y apellido de quien compra;
  /// - un renglón `lugar` solo con una familia de la fiesta;
  /// - un descuento de 0 a 100;
  /// - el efectivo más la transferencia dan el total más el recargo.
  factory VentaEntradas.nueva({
    required String cajaEntradasId,
    required String eventoId,
    required int numero,
    String? contratoAlumnoId,
    required String compradorNombre,
    String? compradorDni,
    required List<RenglonEntradas> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    String? numeros,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    int centavos(double v) => (v * 100).round();
    Never no(String por) => throw ArgumentError('la venta no cierra: $por');

    if (numero < 1) no('el número va de 1 en adelante');
    final comprador = compradorNombre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (comprador.isEmpty) no('falta el nombre y apellido de quien compra');
    final familia = comoTextoONull(contratoAlumnoId);
    if (renglones.isEmpty) no('no tiene renglones');
    for (final r in renglones) {
      if (r.cantidad < 1) no('${r.nombre} tiene cantidad ${r.cantidad}');
      if (r.precioLista.isNaN || r.precioLista < 0) {
        no('${r.nombre} tiene precio de lista ${r.precioLista}');
      }
      if (r.descuentoPct.isNaN || r.descuentoPct < 0 || r.descuentoPct > 100) {
        no('${r.nombre} tiene un descuento de ${r.descuentoPct} %');
      }
      if (centavos(r.precio) !=
          centavos(RenglonEntradas.precioCon(r.precioLista, r.descuentoPct))) {
        no('${r.nombre}: el precio ${r.precio} no es el de lista '
            '${r.precioLista} con ${r.descuentoPct} %');
      }
      if (r.tipo == TipoRenglonEntradas.lugar && familia == null) {
        no('las entradas de los lugares adicionales son de una familia de la fiesta');
      }
      if (r.tipo == TipoRenglonEntradas.otro) {
        no('el renglón "${r.tipoClave}" no se conoce');
      }
    }
    final total = renglones.fold<double>(0, (s, r) => s + r.subtotal);
    final descuento = renglones
        .where((r) => r.tipo == TipoRenglonEntradas.suelta)
        .fold<double>(0, (s, r) => s + r.descontado);
    if (efectivo.isNaN || efectivo < 0) no('efectivo negativo');
    if (transferencia.isNaN || transferencia < 0) no('transferencia negativa');
    if (recargo.isNaN || recargo < 0) no('recargo negativo');
    if (centavos(recargo) > 0 && centavos(transferencia) == 0) {
      no('el recargo va solo con algo por transferencia');
    }
    if (centavos(recargo) > centavos(transferencia)) {
      no('el recargo $recargo es más que la transferencia $transferencia');
    }
    if (centavos(efectivo) + centavos(transferencia) !=
        centavos(total) + centavos(recargo)) {
      no('efectivo $efectivo + transferencia $transferencia no da el total '
          '$total más el recargo $recargo');
    }
    switch (medio) {
      case MedioBarra.efectivo:
        if (centavos(transferencia) != 0) no('en efectivo no va transferencia');
      case MedioBarra.transferencia:
        if (centavos(efectivo) != 0) no('por transferencia no va efectivo');
      case MedioBarra.mixto:
        if (centavos(efectivo) == 0 || centavos(transferencia) == 0) {
          no('un mixto lleva las dos partes');
        }
      case MedioBarra.otro:
        no('el medio de pago no se conoce');
    }
    double vuelto = 0;
    if (recibe != null) {
      if (recibe.isNaN || centavos(recibe) < centavos(efectivo)) {
        no('recibe $recibe es menos que el efectivo $efectivo');
      }
      vuelto = (centavos(recibe) - centavos(efectivo)) / 100;
    }
    final iso = isoDe(ahora);
    return VentaEntradas(
      id: UuidUtils.generate(),
      cajaEntradasId: cajaEntradasId,
      eventoId: eventoId,
      numero: numero,
      contratoAlumnoId: familia,
      compradorNombre: comprador,
      compradorDni: comoTextoONull(compradorDni),
      renglones: List.unmodifiable(renglones),
      cantidad: renglones.fold(0, (s, r) => s + r.cantidad),
      total: centavos(total) / 100,
      descuento: centavos(descuento) / 100,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      vuelto: vuelto,
      recargo: centavos(recargo) / 100,
      recargoPct: centavos(recargo) > 0 ? recargoPct : null,
      numeros: comoTextoONull(numeros),
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'caja_entradas_id': cajaEntradasId,
        'evento_id': eventoId,
        'numero': numero,
        'contrato_alumno_id': contratoAlumnoId,
        'comprador_nombre': compradorNombre,
        'comprador_dni': compradorDni,
        'renglones': jsonEncode([for (final r in renglones) r.toJson()]),
        'cantidad': cantidad,
        'total': total,
        'descuento': descuento,
        'medio': medio.name,
        'efectivo': efectivo,
        'transferencia': transferencia,
        'recibe': recibe,
        'vuelto': vuelto,
        'recargo': recargo,
        'recargo_pct': recargoPct,
        'numeros': numeros,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Unos renglones ilegibles dejan la venta sin renglones, no frenan la
  /// lista: el total, la cantidad y los montos siguen estando.
  static List<RenglonEntradas> _renglonesDe(Object? v) {
    try {
      final lista = v is String ? jsonDecode(v) : v;
      if (lista is! List) return const [];
      return [
        for (final r in lista)
          if (r is Map) RenglonEntradas.fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (_) {
      return const [];
    }
  }

  factory VentaEntradas.fromMap(Map<String, dynamic> m) => VentaEntradas(
        id: comoTexto(m['id']),
        cajaEntradasId: comoTexto(m['caja_entradas_id']),
        eventoId: comoTexto(m['evento_id']),
        numero: comoInt(m['numero']),
        contratoAlumnoId: comoTextoONull(m['contrato_alumno_id']),
        compradorNombre: comoTexto(m['comprador_nombre']),
        compradorDni: comoTextoONull(m['comprador_dni']),
        renglones: _renglonesDe(m['renglones']),
        cantidad: comoInt(m['cantidad']),
        total: comoDouble(m['total']),
        descuento: comoDouble(m['descuento']),
        medio: MedioBarra.deTexto(m['medio']),
        efectivo: comoDouble(m['efectivo']),
        transferencia: comoDouble(m['transferencia']),
        recibe: comoDoubleONull(m['recibe']),
        vuelto: comoDouble(m['vuelto']),
        recargo: comoDouble(m['recargo']),
        recargoPct: comoDoubleONull(m['recargo_pct']),
        numeros: comoTextoONull(m['numeros']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
