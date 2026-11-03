import 'package:image/image.dart' as img;

import '../../../core/utils/ar_time.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/numero_de_ticket.dart';
import '../cuentas/pesos.dart';
import '../cuentas/vales_de_barra.dart';
import '../datos/barra_repositorio.dart';
import 'ticket_esc_pos.dart';

/// Qué dice cada papel de la barra, renglón por renglón, sin saber cómo se imprime: la
/// misma lista va a la impresora (`TicketEscPos`) y al PDF del ticket.
abstract final class ModeloTicket {
  /// "04/12/2026 - 23:41", en hora de Argentina, la del equipo no importa.
  static String fechaYHora(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final ar = ArTime.toAr(dt);
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(ar.day)}/${dos(ar.month)}/${ar.year} - ${dos(ar.hour)}:${dos(ar.minute)}';
  }

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  /// "Vie 04/12/2026 - 23:41": con el día, para que un vale de otra noche se note.
  static String diaFechaYHora(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${_dias[ArTime.toAr(dt).weekday - 1]} ${fechaYHora(iso)}';
  }

  static String _caja(CajaBarra caja) {
    final nombre = caja.operadorNombre;
    return nombre == null ? 'Caja ${caja.numeroCaja}' : 'Caja ${caja.numeroCaja} - $nombre';
  }

  /// Un texto centrado partido por palabras: un nombre de fiesta largo no se corta
  /// en el medio de una palabra.
  static List<LineaTicket> _centrado(String texto, {bool negrita = false}) => [
        for (final r in partirPorPalabras(texto, letrasPorRenglon))
          TextoTicket(r, negrita: negrita),
      ];

  static List<LineaTicket> _encabezado({
    required String fiesta,
    required CajaBarra caja,
    required String momento,
    img.Image? logo,
    String? titulo,
  }) =>
      [
        if (logo != null) LogoTicket(logo),
        const TituloTicket('JUNIOR EVENTOS'),
        TextoTicket(titulo ?? 'BARRA', negrita: true),
        ..._centrado(fiesta),
        TextoTicket(momento),
        ..._centrado(_caja(caja)),
      ];

  /// El ticket de una venta. Con [anulacion], dice que está anulada arriba y abajo, y
  /// no da las gracias.
  static List<LineaTicket> deVenta(
    VentaBarra venta, {
    required CajaBarra caja,
    required String fiesta,
    AnulacionBarra? anulacion,
    img.Image? logo,
  }) {
    final anulada = anulacion != null;
    final hayEfectivo = centavos(venta.efectivo) > 0;
    final hayTransferencia = centavos(venta.transferencia) > 0;
    return [
      ..._encabezado(
        fiesta: fiesta,
        caja: caja,
        momento: fechaYHora(venta.createdAt),
        logo: logo,
      ),
      if (anulada) const TextoTicket('*** ANULADA ***', negrita: true),
      const SeparadorTicket(),
      for (final r in venta.renglones)
        RenglonTicket('${r.cantidad} x ${r.nombre}', pesos(r.subtotal)),
      const SeparadorTicket(),
      RenglonTicket('TOTAL', pesos(venta.total), negrita: true),
      if (hayEfectivo || !hayTransferencia)
        RenglonTicket('Efectivo', pesos(venta.efectivo)),
      if (hayTransferencia) RenglonTicket('Transferencia', pesos(venta.transferencia)),
      if (venta.recibe != null && hayEfectivo) ...[
        RenglonTicket('Recibe', pesos(venta.recibe!)),
        RenglonTicket('Vuelto', pesos(venta.vuelto)),
      ],
      const SeparadorTicket(),
      TextoTicket(
        NumeroDeTicket.texto(numeroCaja: caja.numeroCaja, numero: venta.numero),
        negrita: true,
      ),
      QrTicket(NumeroDeTicket.qr(venta.id)),
      if (anulada) ...[
        const TextoTicket('*** ANULADA ***', negrita: true),
        ..._centrado('Motivo: ${anulacion.motivo}'),
        ..._centrado('${fechaYHora(anulacion.createdAt)}'
            '${anulacion.hechoPor == null ? '' : ' - ${anulacion.hechoPor}'}'),
      ] else
        const TextoTicket('¡Gracias, salud!'),
    ];
  }

  /// Un vale: lo que el barman entrega y se queda. Sin logo, sin precios y sin QR, y con
  /// todo lo que hace falta para reclamarlo: la fiesta, el día y la hora, la caja con su
  /// cajera y el número de la venta. Lo que se entrega va en letras dobles. Una
  /// [copia] lo dice en grande arriba y abajo, con quién, cuándo y por qué.
  static List<LineaTicket> deVale(
    Vale vale, {
    required VentaBarra venta,
    required CajaBarra caja,
    required String fiesta,
    CopiaDeVale? copia,
  }) {
    // "Caja 2 · Marta · N° 0017-3": la cajera en el medio, y el orden del vale en la
    // venta si no es el único.
    final numero = [
      'Caja ${caja.numeroCaja}',
      if (caja.operadorNombre != null) caja.operadorNombre!,
      'N° ${venta.numero.toString().padLeft(4, '0')}${vale.numero == null ? '' : '-${vale.numero}'}',
    ].join(' · ');
    return [
      if (copia != null) const GrandeTicket('*** COPIA ***'),
      ..._centrado(fiesta.toUpperCase(), negrita: true),
      TextoTicket(diaFechaYHora(venta.createdAt)),
      ..._centrado(numero),
      if (vale.porSeparado) ...[
        GrandeTicket('VALE POR ${vale.bebidas.single.cantidad}'),
        GrandeTicket(vale.bebidas.single.nombre.toUpperCase()),
      ] else
        for (final b in vale.bebidas) GrandeTicket('${b.cantidad} ${b.nombre.toUpperCase()}'),
      if (copia != null) ...[
        ..._centrado('Copia ${copia.numero}'
            '${copia.hechoPor == null ? '' : ' - ${copia.hechoPor}'}'),
        TextoTicket(fechaYHora(copia.createdAt)),
        ..._centrado('Motivo: ${copia.motivo}'),
        const TextoTicket('Se entrega solo con el jefe'),
        const GrandeTicket('*** COPIA ***'),
      ] else ...[
        const TextoTicket('Vale solo hoy · una sola vez'),
        const TextoTicket('El barman se queda el vale'),
      ],
    ];
  }

  /// El papel del cierre de una caja: lo vendido, el efectivo esperado, lo contado y la
  /// diferencia **como se anotó al cerrar**. Una caja abierta sale sin lo contado.
  static List<LineaTicket> deCierre(
    CajaBarra caja,
    CierreDeBarra cuentas, {
    required String fiesta,
    img.Image? logo,
  }) {
    final cerrada = !caja.abierta;
    return [
      ..._encabezado(
        fiesta: fiesta,
        caja: caja,
        momento: 'Abrió ${fechaYHora(caja.abiertaAt)}',
        logo: logo,
        titulo: 'CIERRE DE CAJA - BARRA',
      ),
      if (cerrada) TextoTicket('Cerró ${fechaYHora(caja.cerradaAt!)}'),
      if (!cerrada) const TextoTicket('*** CAJA ABIERTA ***', negrita: true),
      const SeparadorTicket(),
      RenglonTicket('Ventas', '${cuentas.ventas}'),
      if (cuentas.mixtos > 0) RenglonTicket('De ellas, mixtas', '${cuentas.mixtos}'),
      RenglonTicket('Efectivo', pesos(cuentas.efectivo)),
      RenglonTicket('Transferencia', pesos(cuentas.transferencia)),
      RenglonTicket('TOTAL VENDIDO', pesos(cuentas.total), negrita: true),
      if (cuentas.anuladas > 0) ...[
        RenglonTicket('Anuladas (no cuentan)', '${cuentas.anuladas}'),
        RenglonTicket(
          'Lo anulado',
          pesos(cuentas.efectivoAnulado + cuentas.transferenciaAnulada),
        ),
      ],
      const SeparadorTicket(),
      RenglonTicket('Cambio inicial', pesos(cuentas.cambioInicial)),
      RenglonTicket('Efectivo esperado', pesos(cuentas.efectivoEsperado), negrita: true),
      if (cerrada && caja.efectivoContado != null) ...[
        RenglonTicket('Efectivo contado', pesos(caja.efectivoContado!), negrita: true),
        ..._centrado(diferenciaEnPalabras(caja.diferencia ?? 0), negrita: true),
      ],
      if (caja.notaCierre != null) ...[
        const SeparadorTicket(),
        for (final r in partirPorPalabras('Nota: ${caja.notaCierre}', letrasPorRenglon))
          TextoTicket(r, centrado: false),
      ],
    ];
  }
}
