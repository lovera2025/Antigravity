import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/evento.dart';
import '../../common/services/pdf_service.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../cuentas/cuenta_del_proveedor.dart';
import '../cuentas/pesos.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../estilos/disenio_barra.dart';
import '../providers/barra_del_jefe_provider.dart';
import 'barra_jefe_providers.dart';

/// **GANANCIA** (audio 77 del jefe; maqueta aprobada el 27-nov-2026, forma A): lo que se le
/// debe al proveedor, lo que se vendió y lo que se ganó, de las fiestas que rinde juntas.
/// **Solo el jefe** (`ReglasDeLaBarra.veElCostoYLaGanancia`). La cuenta es una sola,
/// [CuentaDelProveedor]; esta pantalla no hace otra al lado.
///
/// Siempre las mismas palabras: "Precio de lista" (lo que cobra el proveedor) y "Le debo
/// al proveedor".

/// Las fiestas que se rinden juntas, por defecto: la elegida y las de los 3 días que
/// siguen (vie a lun: "pide bebida para vie-sáb-dom-lun y rinde el martes").
List<Evento> fiestasDeLaTanda(Evento desde, Iterable<Evento> todas) {
  final dia = DateTime(desde.fechaEvento.year, desde.fechaEvento.month, desde.fechaEvento.day);
  final hasta = dia.add(const Duration(days: 4));
  return [
    for (final e in todas)
      if (!e.fechaEvento.isBefore(dia) && e.fechaEvento.isBefore(hasta)) e,
  ]..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
}

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _diaCorto(DateTime f) => '${_dias[f.weekday - 1]} ${f.day}/${f.month}';

/// "Vie 4/12 al lun 7/12 · 4 fiestas", o "Vie 4/12 · 1 fiesta".
String periodoDe(List<Evento> fiestas) {
  if (fiestas.isEmpty) return 'Ninguna fiesta elegida';
  final orden = [...fiestas]..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
  final desde = _diaCorto(orden.first.fechaEvento);
  final hasta = _diaCorto(orden.last.fechaEvento);
  final dias = desde == hasta ? desde : '$desde al $hasta';
  final cuantas = orden.length == 1 ? '1 fiesta' : '${orden.length} fiestas';
  return '${dias[0].toUpperCase()}${dias.substring(1)} · $cuantas';
}

/// La cuenta de las fiestas [ids] (separadas por coma, en orden). Lee lo de cada fiesta
/// de la barra de este equipo (en la web, de la nube).
final gananciaDelJefeProvider = FutureProvider.family<CuentaDelProveedor, String>((ref, ids) async {
  ref.watch(operationalSyncRevisionProvider);
  // Solo el jefe, también en la web (ahí la barra es la nube y no tiene la segunda llave).
  // A quien no le toca le llega la cuenta de ninguna fiesta, sin leer nada. No tira un
  // error: Riverpod reintenta solo al provider que falla y la pantalla quedaría cargando.
  if (!ReglasDeLaBarra.veElCostoYLaGanancia(ref.watch(rolEnLaBarraProvider))) {
    return CuentaDelProveedor.de(const [], nombres: const {});
  }
  final barra = ref.read(barraDelJefeProvider);
  final datos = await ref.watch(fiestasDelJefeProvider.future);
  final eventos = {for (final e in datos.todas) e.id: e};
  final productos = await barra.productos(conBajas: true);
  final fiestas = <FiestaParaLaGanancia>[];
  for (final id in ids.split(',').where((x) => x.isNotEmpty)) {
    final e = eventos[id];
    if (e == null) continue;
    final costos = await barra.costos(id);
    fiestas.add(FiestaParaLaGanancia(
      eventoId: id,
      nombre: EventoPresentacion.tituloPrincipal(e),
      fecha: e.fechaEvento,
      cajas: await barra.cajas(id),
      ventas: await barra.ventas(id),
      anulaciones: await barra.anulaciones(id),
      precios: await barra.precios(id),
      // El stock por barra (28-nov-2026): el reparto del jefe y lo que anotó el repositor.
      // Con eso "lo perdido" son los faltantes (rotas, congeladas…), que se le pagan igual
      // al proveedor. Sin reparto, lo perdido es 0 y "quedaron" sale del stock del jefe.
      repartos: await barra.repartos(id),
      movimientos: await barra.movimientosDeStock(id),
      listas: {for (final c in costos) c.productoId: c.precioLista},
      contenidos: {for (final c in costos) c.productoId: c.contenidoCc},
      recetas: await barra.recetas(id),
    ));
  }
  return CuentaDelProveedor.de(fiestas, nombres: {for (final p in productos) p.id: p.nombre});
});

/// Imprimir GANANCIA en A4 (con botón; nada sale solo). Los tests lo reemplazan.
typedef ImprimirGanancia = Future<void> Function(
  CuentaDelProveedor cuenta, {
  required String periodo,
  required bool conProductos,
  BuildContext? context,
});

final imprimirGananciaProvider = Provider<ImprimirGanancia>((ref) {
  return (cuenta, {required periodo, required conProductos, context}) async {
    final bytes = await GananciaPdf.armar(
      cuenta,
      periodo: periodo,
      conProductos: conProductos,
      fuentes: await PdfService.fuentesOutfit(),
    );
    if (context != null && !context.mounted) return;
    await PdfService.entregarPdf(bytes, 'Ganancia - $periodo', context: context);
  };
});

String _plata(int centavos) => pesos(deCentavos(centavos));

/// "10,67" botellas, "183".
String cuantasDe(UsoDelProveedor u) {
  if (u.cc > 0 && (u.contenidoCc ?? 0) > 0) {
    final b = u.usadas;
    final texto = b == b.roundToDouble() ? b.toInt().toString() : b.toStringAsFixed(2).replaceAll('.', ',');
    return '$texto ${b == 1 ? 'botella' : 'botellas'}';
  }
  return '${u.unidades}';
}

String _miles(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// De dónde sale: "180 vendidas + 3 perdidas", "60 vendidas + 25 en los tragos",
/// "8.000 cc en los tragos".
String porqueDe(UsoDelProveedor u) => [
      if (u.sueltas > 0) '${u.sueltas} ${u.sueltas == 1 ? 'vendida' : 'vendidas'}',
      if (u.perdidas > 0) '${u.perdidas} ${u.perdidas == 1 ? 'perdida' : 'perdidas'}',
      if (u.enTragos > 0) '${u.enTragos} en los tragos',
      if (u.cc > 0) '${_miles(u.cc)} cc en los tragos',
    ].join(' + ');

/// Lo que va en la tabla del proveedor: lo que se usó, salvo lo que no se le compra a
/// nadie (precio de lista 0, como la silla: es toda ganancia).
bool deLoQueSePaga(UsoDelProveedor u) => u.seUso && u.lista != 0;

/// "$ 1.500", "falta" o "varía" (cambió entre las fiestas del período).
String listaDe(UsoDelProveedor u) => u.lista != null ? _plata(u.lista!) : (u.faltaLaLista ? 'falta' : 'varía');

class GananciaDelJefeVista extends ConsumerStatefulWidget {
  final Evento fiesta;
  final List<Evento> todas;

  /// IR A PRECIOS, cuando a algo le falta el precio de lista.
  final VoidCallback? onIrAPrecios;

  const GananciaDelJefeVista({super.key, required this.fiesta, required this.todas, this.onIrAPrecios});

  @override
  ConsumerState<GananciaDelJefeVista> createState() => _GananciaDelJefeVistaState();
}

class _GananciaDelJefeVistaState extends ConsumerState<GananciaDelJefeVista> {
  late List<Evento> _elegidas = fiestasDeLaTanda(widget.fiesta, widget.todas);
  bool _porProducto = false;
  bool _porFiesta = false;

  String get _clave => ([for (final e in _elegidas) e.id]..sort()).join(',');

  Future<void> _cambiar() async {
    final elegidas = await showDialog<List<Evento>>(
      context: context,
      builder: (_) => _ElegirFiestas(todas: widget.todas, elegidas: _elegidas),
    );
    if (elegidas != null && mounted) setState(() => _elegidas = elegidas);
  }

  @override
  Widget build(BuildContext context) {
    final periodo = periodoDe(_elegidas);
    final cuenta = ref.watch(gananciaDelJefeProvider(_clave));
    final angosto = MediaQuery.sizeOf(context).width < 640;
    return cuenta.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('No se pudo armar la ganancia.')),
      data: (c) {
        final usos = [for (final u in c.paraElProveedor) if (deLoQueSePaga(u)) u];
        final faltan = c.faltaLaLista;
        return ListView(
          key: const Key('jefe_ganancia'),
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(periodo, key: const Key('jefe_ganancia_periodo'), style: const TextStyle(color: Color(0xFFC9C4BA))),
                TextButton(key: const Key('jefe_ganancia_cambiar'), onPressed: _cambiar, child: const Text('CAMBIAR')),
              ],
            ),
            const SizedBox(height: 8),
            if (faltan.isNotEmpty)
              _Aviso(
                texto: faltan.length == 1
                    ? 'A ${faltan.single.nombre} le falta el precio de lista: no entra en Le debo y la ganancia no se sabe.'
                    : 'A ${faltan.length} productos les falta el precio de lista: no entran en Le debo y la ganancia '
                        'no se sabe.',
                onIrAPrecios: widget.onIrAPrecios,
              ),
            _Arriba(cuenta: c, angosto: angosto),
            const SizedBox(height: 18),
            const Text('LO QUE LE DEBO AL PROVEEDOR, COSA POR COSA',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .6)),
            const SizedBox(height: 6),
            if (usos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Todavía no se vendió nada en estas fiestas.', key: Key('jefe_ganancia_vacia')),
              )
            else ...[
              if (!angosto) const _Fila(celdas: ['QUÉ', 'CUÁNTAS', 'PRECIO DE LISTA', 'LE DEBO'], encabezado: true),
              for (final u in usos)
                _Fila(
                  key: Key('jefe_ganancia_uso_${u.productoId}'),
                  celdas: [u.nombre, cuantasDe(u), listaDe(u), _plata(u.leDebo)],
                  debajo: porqueDe(u),
                  angosto: angosto,
                ),
              _Fila(
                celdas: ['Le debo al proveedor', '', '', _plata(c.leDebo)],
                total: true,
                angosto: angosto,
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('jefe_ganancia_por_producto'),
                onPressed: () => setState(() => _porProducto = !_porProducto),
                icon: Icon(_porProducto ? Icons.expand_more : Icons.chevron_right),
                label: Text(_porProducto
                    ? 'OCULTAR LA GANANCIA DE CADA PRODUCTO'
                    : 'VER LA GANANCIA DE CADA PRODUCTO'),
              ),
            ),
            if (_porProducto) ...[
              const SizedBox(height: 4),
              if (!angosto) const _Fila(celdas: ['PRODUCTO', 'SE VENDIÓ', 'GANÉ'], encabezado: true),
              for (final p in c.productos)
                if (p.vendidas > 0)
                  _Fila(
                    key: Key('jefe_ganancia_producto_${p.productoId}'),
                    celdas: [p.nombre, _plata(p.seVendio), p.ganancia == null ? 'falta la lista' : _plata(p.ganancia!)],
                    debajo: '${p.vendidas} ${p.vendidas == 1 ? 'vendida' : 'vendidas'}',
                    angosto: angosto,
                  ),
            ],
            if (_porFiesta && c.fiestas.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('POR FIESTA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .6)),
              const SizedBox(height: 6),
              if (!angosto) const _Fila(celdas: ['FIESTA', 'SE VENDIÓ', 'LE DEBO', 'GANANCIA'], encabezado: true),
              for (final f in c.fiestas)
                _Fila(
                  key: Key('jefe_ganancia_fiesta_${f.eventoId}'),
                  celdas: [
                    f.nombre,
                    _plata(f.productos.fold(0, (s, p) => s + p.seVendio)),
                    _plata(f.productos.fold(0, (s, p) => s + p.leDebo)),
                    _plata(f.productos.fold(0, (s, p) => s + (p.ganancia ?? 0))),
                  ],
                  angosto: angosto,
                ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('jefe_ganancia_ver_por_fiesta'),
                  onPressed: () => setState(() => _porFiesta = !_porFiesta),
                  child: Text(_porFiesta ? 'OCULTAR POR FIESTA' : 'VER POR FIESTA'),
                ),
                FilledButton.icon(
                  key: const Key('jefe_ganancia_imprimir'),
                  onPressed: () => ref.read(imprimirGananciaProvider)(
                    c,
                    periodo: periodo,
                    conProductos: _porProducto,
                    context: context,
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('IMPRIMIR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Las botellas de los tragos son una cuenta con la receta: "más o menos". Lo demás es lo que se vendió de '
              'verdad, más lo que se anotó como perdido y lo que se entregó con una venta anulada sin el vale.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A)),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

/// Arriba de todo: LE DEBO AL PROVEEDOR, grande; al lado, la cuenta una sola vez.
class _Arriba extends StatelessWidget {
  final CuentaDelProveedor cuenta;
  final bool angosto;

  const _Arriba({required this.cuenta, required this.angosto});

  @override
  Widget build(BuildContext context) {
    final deuda = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1D1910),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaBarra.dorado),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LE DEBO AL PROVEEDOR',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFFC9C4BA))),
            Text(
              _plata(cuenta.leDebo),
              key: const Key('jefe_ganancia_le_debo'),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: TemaBarra.dorado),
            ),
            const Text('por lo que se vendió y lo que se perdió, a precio de lista',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFA7A29A))),
          ],
        ),
      ),
    );
    Widget renglon(String a, String b, {Key? key, bool ganancia = false}) => Row(
          children: [
            Expanded(
              child: Text(a,
                  style: TextStyle(
                    fontWeight: ganancia ? FontWeight.w800 : FontWeight.w500,
                    fontSize: ganancia ? 17 : 14,
                    color: ganancia ? const Color(0xFF59D38A) : null,
                  )),
            ),
            Text(b,
                key: key,
                style: TextStyle(
                  fontWeight: ganancia ? FontWeight.w800 : FontWeight.w600,
                  fontSize: ganancia ? 19 : 14,
                  color: ganancia ? const Color(0xFF59D38A) : null,
                )),
          ],
        );
    final resto = DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xFF17161A), borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            renglon('Se vendió', _plata(cuenta.seVendio), key: const Key('jefe_ganancia_se_vendio')),
            const SizedBox(height: 6),
            renglon('Le debo al proveedor', '− ${_plata(cuenta.leDebo)}'),
            const Divider(height: 18),
            renglon('Ganancia', _plata(cuenta.ganancia), key: const Key('jefe_ganancia_ganancia'), ganancia: true),
          ],
        ),
      ),
    );
    if (angosto) return Column(children: [deuda, const SizedBox(height: 10), resto]);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(flex: 5, child: deuda), const SizedBox(width: 10), Expanded(flex: 4, child: resto)],
      ),
    );
  }
}

/// Un renglón de las tablas de GANANCIA: el primero a la izquierda, los números a la
/// derecha. En un celular, el nombre arriba y los números debajo.
class _Fila extends StatelessWidget {
  final List<String> celdas;
  final String? debajo;
  final bool encabezado;
  final bool total;
  final bool angosto;

  const _Fila({super.key, required this.celdas, this.debajo, this.encabezado = false, this.total = false, this.angosto = false});

  @override
  Widget build(BuildContext context) {
    final estilo = encabezado
        ? const TextStyle(fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: Color(0xFFA7A29A))
        : TextStyle(fontWeight: total ? FontWeight.w800 : FontWeight.w500);
    final primera = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(celdas.first, style: estilo),
        if (debajo != null && debajo!.isNotEmpty)
          Text(debajo!, style: const TextStyle(fontSize: 12, color: Color(0xFFA7A29A))),
      ],
    );
    final numeros = [
      for (final c in celdas.skip(1))
        SizedBox(width: angosto ? null : 150, child: Text(c, textAlign: TextAlign.right, style: estilo)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: total ? const Color(0xFF6A6470) : const Color(0xFF2A2830), width: total ? 1.5 : 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: angosto
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primera,
                  const SizedBox(height: 4),
                  Wrap(alignment: WrapAlignment.end, spacing: 14, children: [
                    for (final c in celdas.skip(1))
                      if (c.isNotEmpty) Text(c, style: estilo),
                  ]),
                ],
              )
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: primera), ...numeros]),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final VoidCallback? onIrAPrecios;

  const _Aviso({required this.texto, this.onIrAPrecios});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2210),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF6E5A1E)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(texto,
                      key: const Key('jefe_ganancia_falta_lista'), style: const TextStyle(color: Color(0xFFF2D77C))),
                ),
                if (onIrAPrecios != null)
                  TextButton(key: const Key('jefe_ganancia_ir_a_precios'), onPressed: onIrAPrecios, child: const Text('IR A PRECIOS')),
              ],
            ),
          ),
        ),
      );
}

/// CAMBIAR: qué fiestas se rinden juntas.
class _ElegirFiestas extends StatefulWidget {
  final List<Evento> todas;
  final List<Evento> elegidas;

  const _ElegirFiestas({required this.todas, required this.elegidas});

  @override
  State<_ElegirFiestas> createState() => _ElegirFiestasState();
}

class _ElegirFiestasState extends State<_ElegirFiestas> {
  late final _ids = {for (final e in widget.elegidas) e.id};

  @override
  Widget build(BuildContext context) {
    final orden = [...widget.todas]..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
    return AlertDialog(
      title: const Text('¿Qué fiestas rendís juntas?'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in orden)
              CheckboxListTile(
                key: Key('jefe_ganancia_elegir_${e.id}'),
                value: _ids.contains(e.id),
                onChanged: (v) => setState(() => v == true ? _ids.add(e.id) : _ids.remove(e.id)),
                title: Text(EventoPresentacion.tituloPrincipal(e)),
                subtitle: Text(_diaCorto(e.fechaEvento)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(
          key: const Key('jefe_ganancia_elegir_listo'),
          onPressed: () => Navigator.pop(context, [for (final e in orden) if (_ids.contains(e.id)) e]),
          child: const Text('LISTO'),
        ),
      ],
    );
  }
}

/// GANANCIA en una A4: los tres números, lo que se le debe al proveedor cosa por cosa y,
/// si estaba abierta, la ganancia de cada producto. Lo mismo que se ve.
class GananciaPdf {
  GananciaPdf._();

  static Future<Uint8List> armar(
    CuentaDelProveedor c, {
    required String periodo,
    required bool conProductos,
    (pw.Font, pw.Font)? fuentes,
  }) async {
    final tema = fuentes == null ? null : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2);
    final doc = pw.Document(theme: tema);
    final gris = PdfColor.fromInt(0xFF5D6078);
    pw.Widget tabla(List<String> cabeza, List<List<String>> filas, {List<String>? pie}) => pw.TableHelper.fromTextArray(
          headers: cabeza,
          data: [...filas, ?pie],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: gris),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(),
          cellAlignments: {for (var i = 1; i < cabeza.length; i++) i: pw.Alignment.centerRight},
          cellAlignment: pw.Alignment.centerLeft,
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(width: .4, color: PdfColors.grey400)),
        );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
      build: (_) => [
        pw.Text('GANANCIA DE LA BARRA', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(periodo, style: pw.TextStyle(fontSize: 11, color: gris)),
        pw.Text([for (final f in c.fiestas) f.nombre].join(' · '), style: pw.TextStyle(fontSize: 10, color: gris)),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('LE DEBO AL PROVEEDOR', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(_plata(c.leDebo), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text('por lo que se vendió y lo que se perdió, a precio de lista',
                  style: pw.TextStyle(fontSize: 9, color: gris)),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(children: [
              for (final (a, b) in [
                ('Se vendió', _plata(c.seVendio)),
                ('Le debo al proveedor', '- ${_plata(c.leDebo)}'),
                ('Ganancia', _plata(c.ganancia)),
              ])
                pw.Row(children: [pw.Expanded(child: pw.Text(a)), pw.Text(b, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
            ]),
          ),
        ]),
        if (c.faltaLaLista.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('Falta el precio de lista de: ${[for (final p in c.faltaLaLista) p.nombre].join(', ')}.'),
        ],
        pw.SizedBox(height: 16),
        pw.Text('LO QUE LE DEBO AL PROVEEDOR, COSA POR COSA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        tabla(
          ['Qué', 'Cuántas', 'De dónde sale', 'Precio de lista', 'Le debo'],
          [
            for (final u in c.paraElProveedor)
              if (deLoQueSePaga(u)) [u.nombre, cuantasDe(u), porqueDe(u), listaDe(u), _plata(u.leDebo)],
          ],
          pie: ['Le debo al proveedor', '', '', '', _plata(c.leDebo)],
        ),
        if (conProductos) ...[
          pw.SizedBox(height: 16),
          pw.Text('LO QUE GANÉ CON CADA PRODUCTO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          tabla(
            ['Producto', 'Vendidas', 'Se vendió', 'Gané'],
            [
              for (final p in c.productos)
                if (p.vendidas > 0)
                  [p.nombre, '${p.vendidas}', _plata(p.seVendio), p.ganancia == null ? 'falta la lista' : _plata(p.ganancia!)],
            ],
          ),
        ],
      ],
    ));
    return doc.save();
  }
}
