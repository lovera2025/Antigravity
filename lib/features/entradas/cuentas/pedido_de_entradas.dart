import 'dart:math';

import '../../../models/entradas_retiro.dart';
import '../../barra/cuentas/cobro_barra.dart';
import '../../barra/cuentas/pesos.dart';
import '../datos/entradas_repositorio.dart';
import 'lugares_de_la_familia.dart';
import 'numeros_de_entradas.dart';
import 'precio_de_entradas.dart';

/// Lo que se está por vender en VENDER, **sin pantalla**: a quién, cuántas de
/// sus lugares adicionales y cuántas sueltas, el descuento a mano, quién compra
/// y los números del talonario. Dice los renglones, el total y, si todavía no
/// se puede confirmar, **por qué**, con las palabras que lee quien vende.
///
/// No cambia nunca: cada cambio da un pedido nuevo (como `CobroBarra`).
///
/// Los precios salen de [PrecioDeEntradas]; cuántas le quedan a la familia, de
/// [LugaresDeLaFamilia]; los números, de [NumerosDeEntradas]. Acá no se repite
/// ninguna de esas cuentas.
class PedidoDeEntradas {
  /// El precio de la fiesta. Null: el jefe todavía no puso nada.
  final ConfigEntradas? config;

  /// El momento de la venta en el reloj de Argentina
  /// (`PrecioDeEntradas.hoyEnArgentina`): decide si rige la anticipada.
  final DateTime hoyAr;

  /// Si quien vende está en modo jefe: puede descontar siempre.
  final bool esJefe;

  /// La familia de la fiesta que compra. Null: alguien de afuera.
  final String? familiaId;

  /// Las de los lugares adicionales de esa familia.
  final LugaresDeLaFamilia lugares;

  /// Cuántas de sus lugares adicionales lleva (nunca más de las que le quedan).
  final int deLugar;

  /// Cuántas sueltas lleva, al precio de hoy.
  final int sueltas;

  /// El descuento a mano sobre las sueltas, de 0 a 100. Viene en 0.
  final double descuentoPct;

  /// Nombre y apellido de quien compra y retira.
  final String comprador;
  final String dni;

  /// Los números del talonario. Vacío: no se anotaron (son opcionales).
  final List<TramoTalonario> tramos;

  /// Los números que ya tienen dueño (`NumerosDeEntradas.ocupados`).
  final Map<String, List<TramoTalonario>> ocupados;

  const PedidoDeEntradas._({
    required this.config,
    required this.hoyAr,
    required this.esJefe,
    required this.familiaId,
    required this.lugares,
    required this.deLugar,
    required this.sueltas,
    required this.descuentoPct,
    required this.comprador,
    required this.dni,
    required this.tramos,
    required this.ocupados,
  });

  /// Un pedido vacío, para alguien de afuera.
  factory PedidoDeEntradas.nuevo({
    required ConfigEntradas? config,
    required DateTime hoyAr,
    bool esJefe = false,
    Map<String, List<TramoTalonario>> ocupados = const {},
  }) =>
      PedidoDeEntradas._(
        config: config,
        hoyAr: hoyAr,
        esJefe: esJefe,
        familiaId: null,
        lugares: LugaresDeLaFamilia.ninguno,
        deLugar: 0,
        sueltas: 0,
        descuentoPct: 0,
        comprador: '',
        dni: '',
        tramos: const [],
        ocupados: ocupados,
      );

  /// Cómo se llama cada renglón en el comprobante.
  static const nombreSuelta = 'Entrada';
  static const nombreAnticipada = 'Entrada anticipada';

  /// "Entrada de lugar adicional (50 %)": lo que paga del valor de la entrada.
  static String nombreDeLugar(double descuentoPct) {
    final paga = 100 - descuentoPct;
    final texto = paga == paga.roundToDouble()
        ? paga.round().toString()
        : paga.toStringAsFixed(1).replaceAll('.', ',');
    return 'Entrada de lugar adicional ($texto %)';
  }

  PedidoDeEntradas _con({
    String? familiaId,
    bool sinFamilia = false,
    LugaresDeLaFamilia? lugares,
    int? deLugar,
    int? sueltas,
    double? descuentoPct,
    String? comprador,
    String? dni,
    List<TramoTalonario>? tramos,
    Map<String, List<TramoTalonario>>? ocupados,
  }) =>
      PedidoDeEntradas._(
        config: config,
        hoyAr: hoyAr,
        esJefe: esJefe,
        familiaId: sinFamilia ? null : (familiaId ?? this.familiaId),
        lugares: lugares ?? this.lugares,
        deLugar: deLugar ?? this.deLugar,
        sueltas: sueltas ?? this.sueltas,
        descuentoPct: descuentoPct ?? this.descuentoPct,
        comprador: comprador ?? this.comprador,
        dni: dni ?? this.dni,
        tramos: tramos ?? this.tramos,
        ocupados: ocupados ?? this.ocupados,
      );

  /// Compra una familia de la fiesta. **Viene con todas las de sus lugares
  /// adicionales que le quedan**; quien vende baja la cantidad si lleva menos.
  PedidoDeEntradas paraLaFamilia(String id, LugaresDeLaFamilia lugares) =>
      _con(familiaId: id, lugares: lugares, deLugar: lugares.quedan);

  /// Compra alguien de afuera: sin entradas de lugares adicionales.
  PedidoDeEntradas paraAlguienDeAfuera() =>
      _con(sinFamilia: true, lugares: LugaresDeLaFamilia.ninguno, deLugar: 0);

  /// **No se le venden más de las que le quedan**: lo de más queda en el tope.
  PedidoDeEntradas conDeLugar(int n) =>
      _con(deLugar: familiaId == null ? 0 : n.clamp(0, lugares.quedan));

  PedidoDeEntradas conSueltas(int n) => _con(sueltas: max(0, n));

  /// Lo negativo queda en 0; más de 100, en 100.
  PedidoDeEntradas conDescuento(double pct) =>
      _con(descuentoPct: pct.isNaN ? 0 : pct.clamp(0, 100).toDouble());

  PedidoDeEntradas conComprador(String nombre) => _con(comprador: nombre);
  PedidoDeEntradas conDni(String dni) => _con(dni: dni);
  PedidoDeEntradas conTramos(List<TramoTalonario> tramos) =>
      _con(tramos: List.unmodifiable(tramos));
  PedidoDeEntradas conOcupados(Map<String, List<TramoTalonario>> ocupados) =>
      _con(ocupados: ocupados);

  /// Si la fiesta tiene precio. Sin precio no se vende.
  bool get tienePrecio => config?.tienePrecio ?? false;

  bool get rigeLaAnticipada => PrecioDeEntradas.rigeLaAnticipada(config, hoyAr);

  /// Lo que vale hoy cada suelta, antes del descuento a mano. Null sin precio.
  double? get precioDeHoy => PrecioDeEntradas.deHoy(config, hoyAr);

  /// Lo que vale cada una de sus lugares adicionales. Null sin precio.
  double? get precioDeLugar => PrecioDeEntradas.deLugar(config);

  /// **El descuento a mano, solo con permiso:** en modo jefe, o si el jefe
  /// tildó "El vendedor puede poner descuentos" en PRECIOS.
  bool get puedeDescontar => esJefe || (config?.descuentoAMano ?? false);

  /// El descuento que de verdad va: sin permiso, ninguno.
  double get descuentoQueVa => puedeDescontar ? descuentoPct : 0;

  /// Las de sus lugares adicionales que de verdad van: con familia, y con el
  /// tope de las que le quedan.
  int get deLugarQueVan =>
      familiaId == null ? 0 : deLugar.clamp(0, lugares.quedan);

  /// Los renglones de la venta, con el nombre y el precio de este momento.
  /// Vacío sin precio o sin entradas.
  List<RenglonEntradas> get renglones {
    final c = config;
    final deHoy = precioDeHoy;
    if (c == null || deHoy == null) return const [];
    return [
      if (deLugarQueVan > 0)
        RenglonEntradas.lugar(
          nombre: nombreDeLugar(c.descuentoLugaresPct),
          precioLista: c.valorEntrada!,
          descuentoPct: c.descuentoLugaresPct,
          cantidad: deLugarQueVan,
        ),
      if (sueltas > 0)
        RenglonEntradas.suelta(
          nombre: rigeLaAnticipada ? nombreAnticipada : nombreSuelta,
          precioLista: deHoy,
          descuentoPct: descuentoQueVa,
          cantidad: sueltas,
        ),
    ];
  }

  /// Las entradas de toda la venta.
  int get cantidad => renglones.fold(0, (s, r) => s + r.cantidad);

  /// Lo que valen, ya con los descuentos. El recargo lo pone el cobro.
  double get total =>
      deCentavos(renglones.fold(0, (s, r) => s + centavos(r.subtotal)));

  /// La plata que se deja de cobrar por el descuento a mano.
  double get descontado => deCentavos(renglones
      .where((r) => r.tipo == TipoRenglonEntradas.suelta)
      .fold(0, (s, r) => s + centavos(r.descontado)));

  /// Con un descuento del 100 % la venta vale 0: se guarda igual (queda
  /// anotada, con el descuento), sin pasar por el cobro.
  bool get esSinCargo => cantidad > 0 && centavos(total) == 0;

  /// El recargo por transferencia de la fiesta. En 0: sin recargo.
  double get recargoPct => config?.recargoPct ?? 0;
  bool get recargoPrendido => recargoPct > 0;

  /// El cobro de este pedido por [medio], con el recargo de la fiesta.
  CobroBarra cobroPor(MedioBarra medio) => CobroBarra.de(
        total,
        medio: medio,
        recargo: recargoPrendido,
        recargoPct: recargoPct,
      );

  /// El error de los números del talonario, o null.
  String? get errorDeLosNumeros => NumerosDeEntradas.error(
        tramos: tramos,
        cantidad: cantidad,
        ocupados: ocupados,
      );

  /// Por qué no se puede confirmar todavía, de arriba hacia abajo en la
  /// pantalla. Null: se puede.
  String? get falta {
    if (!tienePrecio) {
      return 'El jefe todavía no puso el precio de la entrada de esta fiesta';
    }
    final palabras =
        comprador.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
    if (palabras < 2) return 'Escribí nombre y apellido de quien compra';
    if (cantidad < 1) return 'Elegí cuántas entradas lleva';
    return errorDeLosNumeros;
  }

  bool get puedeConfirmar => falta == null;

  /// La venta de este pedido cobrada con [cobro], con su [numero]. **Tira
  /// `ArgumentError` si no se puede confirmar o si no cierra**
  /// (`VentaEntradas.nueva`): nada a medias llega a guardarse.
  ///
  /// Del cobro se toma lo mismo que la barra: el efectivo, lo transferido **con
  /// el recargo adentro**, lo que entregó y el recargo aparte.
  VentaEntradas venta({
    required CajaEntradas caja,
    required int numero,
    required CobroBarra cobro,
    required DateTime ahora,
    String? hechoPor,
    String? deviceId,
  }) {
    final porQue = falta;
    if (porQue != null) {
      throw ArgumentError('la venta no se puede confirmar: $porQue');
    }
    if (config!.eventoId != caja.eventoId) {
      throw ArgumentError('la caja es de otra fiesta');
    }
    if (centavos(cobro.total) != centavos(total)) {
      throw ArgumentError(
          'el cobro es por ${cobro.total} y la venta vale $total');
    }
    return VentaEntradas.nueva(
      cajaEntradasId: caja.id,
      eventoId: caja.eventoId,
      numero: numero,
      contratoAlumnoId: familiaId,
      compradorNombre: comprador,
      compradorDni: dni,
      renglones: renglones,
      medio: cobro.medio,
      efectivo: cobro.efectivo,
      transferencia: cobro.transfiere,
      recibe: cobro.recibeQueCuenta,
      recargo: cobro.recargo,
      recargoPct: cobro.recargoPctQueQueda,
      numeros: tramos.isEmpty ? null : TramoTalonario.aTexto(tramos),
      hechoPor: hechoPor,
      deviceId: deviceId,
      ahora: ahora,
    );
  }

  /// Guarda la venta en [caja]. El número lo da el repositorio, en la misma
  /// transacción.
  ///
  /// **Lo que se guarda es lo que arma [venta]**: se arma primero (y tira si
  /// algo no cierra) y al repositorio va eso mismo, campo por campo. Así la
  /// pantalla no tiene una segunda cuenta.
  Future<VentaEntradas> guardarEn(
    EntradasDeLaCaja repositorio, {
    required CajaEntradas caja,
    required CobroBarra cobro,
    required String quien,
  }) {
    final v = venta(caja: caja, numero: 1, cobro: cobro, ahora: hoyAr);
    return repositorio.vender(
      caja: caja,
      contratoAlumnoId: v.contratoAlumnoId,
      compradorNombre: v.compradorNombre,
      compradorDni: v.compradorDni,
      renglones: v.renglones,
      medio: v.medio,
      efectivo: v.efectivo,
      transferencia: v.transferencia,
      recibe: v.recibe,
      recargo: v.recargo,
      recargoPct: v.recargoPct,
      numeros: v.numeros,
      quien: quien,
    );
  }
}
