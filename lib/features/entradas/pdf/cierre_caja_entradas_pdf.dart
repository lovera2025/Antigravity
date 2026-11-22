import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../barra/cuentas/pesos.dart';
import '../../common/utils/currency_extensions.dart' show numeroALetras;
import '../cuentas/cierre_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import 'comprobante_entradas_pdf.dart';
import 'recibo_de_entradas_pdf.dart';

/// Lo que lleva el papel del cierre de una caja de entradas.
class DatosDelCierreDeEntradas {
  /// La caja como quedó guardada al cerrar (lo contado sale de acá: no se
  /// vuelve a calcular).
  final CajaEntradas caja;
  final CierreDeEntradas cuentas;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  const DatosDelCierreDeEntradas({
    required this.caja,
    required this.cuentas,
    required this.fiesta,
    this.fechaFiesta,
  });
}

/// El papel del cierre de una caja de entradas (sección 9.1 del spec del
/// 13-nov), **con la forma del recibo de las cuotas, tal cual** (22-nov-2026,
/// [ReciboDeEntradasPdf]): "RECIBO DE CAJA", media hoja A4. Es el recibo de lo
/// que entrega quien cerró la caja: "Recibí de" quien vendió, "La suma de
/// pesos" el efectivo que contó (con el cambio), y en el concepto lo cobrado
/// por transferencia y lo vendido.
///
/// **No dice la diferencia** (pedido del usuario, 22-nov-2026: "que no diga
/// 'Justo, sin diferencia'"): ni lo que tenía que haber, ni si sobra o falta.
/// El jefe la ve en la pantalla (Cierre de caja → ENTRADAS). Lo anulado
/// después del cierre sí va, en rojo: el cierre no se corrige.
///
/// No hace ninguna cuenta propia: lo vendido sale de [CierreDeEntradas] y lo
/// contado, de la caja como se guardó al cerrar.
class CierreCajaEntradasPdf {
  CierreCajaEntradasPdf._();

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  /// "Entradas vendidas: 26 (14 sueltas y 12 de lugares adicionales)".
  static String vendidas(CierreDeEntradas c) =>
      'Entradas vendidas: ${c.entradas} (${c.sueltas} sueltas y ${c.deLugar} de '
      'lugares adicionales${c.otras > 0 ? ', ${c.otras} otras' : ''})';

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDelCierreDeEntradas d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) =>
      ReciboDeEntradasPdf.armar(contenido(d), fuentes: fuentes, logo: logo);

  /// Lo que dice el papel, con la forma del recibo de las cuotas.
  static ContenidoDelRecibo contenido(DatosDelCierreDeEntradas d) {
    final caja = d.caja;
    final c = d.cuentas;
    final quien = (caja.operadorNombre ?? '').trim().isEmpty
        ? 'Jefe'
        : caja.operadorNombre!.trim();
    final contado = caja.efectivoContado;
    final cerrada = caja.cerradaAt;
    final abierta = ComprobanteEntradasPdf.cuando(caja.abiertaAt);
    final fiesta = [
      d.fiesta.trim().toUpperCase(),
      if (d.fechaFiesta != null) 'fiesta ${_dia(d.fechaFiesta!)}',
    ].where((s) => s.isNotEmpty).join(' · ');
    final ventas = [
      'Ventas: ${c.ventas}',
      if (c.mixtos > 0) c.mixtos == 1 ? '1 mixta' : '${c.mixtos} mixtas',
      if (c.anuladas > 0)
        '${c.anuladas == 1 ? '1 anulada' : '${c.anuladas} anuladas'} (no cuentan)',
    ].join(' · ');

    return ContenidoDelRecibo(
      titulo: 'RECIBO DE CAJA',
      bajoElTitulo: 'Entradas · $quien',
      fecha: cerrada == null ? abierta : ComprobanteEntradasPdf.cuando(cerrada),
      debajoDeLaFecha: 'Abierta: $abierta'
          '${cerrada == null ? ' · sigue abierta' : ' · Cerrada: ${ComprobanteEntradasPdf.cuando(cerrada)}'}',
      recibiDe: quien,
      sumaEnLetras: contado == null
          ? '— (la caja sigue abierta: el efectivo todavía no se entregó)'
          : numeroALetras(contado),
      concepto: 'Caja de entradas · $fiesta',
      renglones: [
        if (contado != null)
          RenglonDelRecibo(
            'Efectivo contado (con ${pesos(c.cambioInicial)} de cambio)',
            monto: pesos(contado),
          ),
        RenglonDelRecibo(
          'Transferencias (con los recargos)',
          monto: pesos(c.transferencia),
          nota: c.recargos > 0
              ? 'De eso, ${pesos(c.recargos)} de recargos por transferencia'
              : null,
        ),
        RenglonDelRecibo(vendidas(c), monto: pesos(c.vendido)),
        if (c.descuentos > 0)
          RenglonDelRecibo(
            'Descuentos a mano (${c.conDescuento == 1 ? '1 venta' : '${c.conDescuento} ventas'})',
            monto: pesos(c.descuentos),
          ),
      ],
      notas: [ventas],
      total: contado == null ? '—' : pesos(contado),
      enElTotal: [
        'Total cobrado en la caja: ${pesos(c.total)} '
            '(efectivo ${pesos(c.efectivo)} + transferencia ${pesos(c.transferencia)})',
      ],
      pie: [
        if ((caja.notaCierre ?? '').trim().isNotEmpty) 'Nota: ${caja.notaCierre!.trim()}',
      ],
      enRojo: [
        if (c.hayAnuladoDespues)
          'Anulado después del cierre: ${pesos(c.anuladoDespues)} '
              '(el cierre no se corrige)',
      ],
    );
  }

  /// Cómo se llama el archivo.
  static String nombreDelArchivo(DatosDelCierreDeEntradas d) {
    String limpio(String s) => s
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final quien = limpio(d.caja.operadorNombre ?? 'Jefe');
    return 'Cierre_entradas_${limpio(d.fiesta)}_$quien.pdf';
  }
}
