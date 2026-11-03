import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/services/papel_de_la_barra.dart';
import 'package:arguello_events/models/evento.dart';

/// La barra de un equipo, en memoria: lo que hace `BarraLocal` sin base. Para montar
/// las pantallas de la cajera de verdad.
class BarraEnMemoria implements BarraDeLaCaja {
  final productosGuardados = <ProductoBarra>[];
  final preciosGuardados = <PrecioBarra>[];
  final cajasGuardadas = <CajaBarra>[];
  final ventasGuardadas = <VentaBarra>[];
  final anulacionesGuardadas = <AnulacionBarra>[];
  String equipo = 'tablet-1';
  DateTime Function() reloj = () => DateTime.utc(2026, 12, 5, 2);

  /// Si vender tira: la base no pudo guardar.
  bool venderFalla = false;

  /// Las ventas que todavía no subieron.
  final sinSubir = <String>{};

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) async =>
      [for (final p in productosGuardados) if (conBajas || p.activo) p];

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) async => [
        for (final p in preciosGuardados)
          if (p.eventoId == eventoId && (conBajas || p.activo)) p,
      ];

  @override
  Future<Set<String>> fiestasConPrecio() async =>
      {for (final p in preciosGuardados) if (p.activo) p.eventoId};

  @override
  Future<List<CajaBarra>> cajasAbiertas(String eventoId) async =>
      [for (final c in cajasGuardadas) if (c.eventoId == eventoId && c.abierta) c];

  @override
  Future<int> ventasSinSubir() async => sinSubir.length;

  @override
  Future<CajaBarra?> cajaAbierta({required String eventoId, required String operadorId}) async {
    for (final c in cajasGuardadas.reversed) {
      if (c.eventoId == eventoId && c.operadorId == operadorId && c.deviceId == equipo && c.abierta) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<CajaBarra> abrirCaja({
    required String eventoId,
    required String operadorId,
    required String operadorNombre,
    required int numeroCaja,
    String? sede,
    double cambioInicial = 0,
  }) async {
    final ya = await cajaAbierta(eventoId: eventoId, operadorId: operadorId);
    if (ya != null) return ya;
    final ahora = reloj();
    final caja = CajaBarra.abrir(
      eventoId: eventoId,
      operadorId: operadorId,
      operadorNombre: operadorNombre,
      numeroCaja: numeroCaja,
      sede: sede,
      cambioInicial: cambioInicial,
      ahora: ahora,
    ).sellada(hechoPor: operadorNombre, deviceId: equipo, ahora: ahora);
    cajasGuardadas.add(caja);
    return caja;
  }

  CajaBarra _reemplazar(CajaBarra nueva) {
    final i = cajasGuardadas.indexWhere((c) => c.id == nueva.id);
    cajasGuardadas[i] = nueva;
    return nueva;
  }

  @override
  Future<CajaBarra> ponerCambio(CajaBarra caja, double cambio, {required String quien}) async {
    final enLaBase = cajasGuardadas.firstWhere((c) => c.id == caja.id);
    if (!enLaBase.abierta) return enLaBase;
    return _reemplazar(enLaBase.conCambio(cambio).sellada(hechoPor: quien, deviceId: equipo, ahora: reloj()));
  }

  @override
  Future<VentaBarra> vender({
    required CajaBarra caja,
    required List<RenglonVenta> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    double recargo = 0,
    double? recargoPct,
    required String quien,
  }) async {
    if (venderFalla) throw StateError('la base no guardó');
    final numero = ventasGuardadas.where((v) => v.cajaBarraId == caja.id).length + 1;
    final venta = VentaBarra.nueva(
      cajaBarraId: caja.id,
      eventoId: caja.eventoId,
      numero: numero,
      renglones: renglones,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      recargo: recargo,
      recargoPct: recargoPct,
      hechoPor: quien,
      deviceId: equipo,
      ahora: reloj(),
    );
    ventasGuardadas.add(venta);
    sinSubir.add(venta.id);
    return venta;
  }

  @override
  Future<List<VentaBarra>> ventasDeLaCaja(String cajaId) async =>
      [for (final v in ventasGuardadas) if (v.cajaBarraId == cajaId) v];

  @override
  Future<List<AnulacionBarra>> anulacionesDeLaCaja(String cajaId) async =>
      [for (final a in anulacionesGuardadas) if (a.cajaBarraId == cajaId) a];

  @override
  Future<CajaBarra> cerrarCaja(
    CajaBarra caja, {
    required double efectivoContado,
    required double diferencia,
    String? nota,
    required String quien,
  }) async {
    final enLaBase = cajasGuardadas.firstWhere((c) => c.id == caja.id);
    if (!enLaBase.abierta) return enLaBase;
    return _reemplazar(enLaBase
        .cerrada(efectivoContado: efectivoContado, diferencia: diferencia, nota: nota, ahora: reloj())
        .sellada(hechoPor: quien, deviceId: equipo, ahora: reloj()));
  }

  // ── Para armar los datos de la prueba ─────────────────────────────────────

  ProductoBarra producto(String nombre, {String categoria = '', int orden = 0}) {
    final p = ProductoBarra.nuevo(nombre: nombre, categoria: categoria, orden: orden, ahora: reloj());
    productosGuardados.add(p);
    return p;
  }

  PrecioBarra precio(String eventoId, ProductoBarra p, double precio, {int orden = 0, int? stock, int? aviso}) {
    final pr = PrecioBarra.para(
      eventoId: eventoId,
      productoId: p.id,
      precio: precio,
      orden: orden,
      stockInicial: stock,
      avisoStock: aviso,
      ahora: reloj(),
    );
    preciosGuardados.add(pr);
    return pr;
  }
}

/// La impresora, en memoria: anota cada papel como texto (las líneas grandes y chicas).
class PapelEnMemoria implements PapelDeLaBarra {
  final papeles = <List<String>>[];
  EstadoImpresora estado = EstadoImpresora.lista;
  bool anda = true;
  var preparadas = 0;

  @override
  Future<EstadoImpresora> preparar() async {
    preparadas++;
    return estado;
  }

  @override
  Future<bool> imprimir(List<LineaTicket> lineas) async {
    if (!anda) return false;
    papeles.add([
      for (final l in lineas)
        switch (l) {
          GrandeTicket() => l.texto,
          TextoTicket() => l.texto,
          TituloTicket() => l.texto,
          _ => '',
        },
    ]);
    return true;
  }
}

/// El recargo recordado, en memoria.
class RecargoEnMemoria extends RecargoRecordado {
  bool prendido;
  double pct;
  var guardados = 0;

  RecargoEnMemoria({this.prendido = true, this.pct = 5});

  @override
  Future<({bool prendido, double pct})> leer() async => (prendido: prendido, pct: pct);

  @override
  Future<void> guardar({required bool prendido, required double pct}) async {
    this.prendido = prendido;
    this.pct = pct;
    guardados++;
  }
}

/// Una fiesta inventada.
Evento fiestaDePrueba(String id, String nombre, DateTime fecha, {String modalidad = 'masivo'}) => Evento(
      id: id,
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: fecha,
      estado: EstadoEvento.confirmado,
      modalidad: modalidad,
      encabezadoEvento: nombre,
    );

/// Todo junto, listo para un `ProviderScope`.
class BarraEnPrueba {
  final barra = BarraEnMemoria();
  final papel = PapelEnMemoria();
  final recargo = RecargoEnMemoria();
  final eventos = <Evento>[];
  final subidas = <String>[];
  var bajadas = 0;
  bool bajaBien = true;
  DateTime? alDia;

  List<Override> get reemplazos => [
        barraDeLaCajaProvider.overrideWithValue(barra),
        papelDeLaBarraProvider.overrideWithValue(papel),
        recargoRecordadoProvider.overrideWithValue(recargo),
        eventosDeLaBarraProvider.overrideWith((ref) async => eventos),
        subirVentaProvider.overrideWithValue((v) async => subidas.add(v.id)),
        accesosBarraProvider.overrideWithValue(AccesosBarra(
          bajar: () async {
            bajadas++;
            return bajaBien;
          },
          contarFiestas: () async => (await barra.fiestasConPrecio()).length,
          contarSinSubir: barra.ventasSinSubir,
          leerAlDia: () async => alDia,
          anotarAlDia: (cuando) async => alDia = cuando,
          ahora: () => DateTime.utc(2026, 12, 5, 0, 40),
        )),
      ];

  /// Un id de evento válido.
  static String id(int n) => 'e0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  static String nuevoId() => UuidUtils.generate();
}
