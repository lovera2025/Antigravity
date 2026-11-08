import 'package:flutter/painting.dart' show ImageProvider;
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/estilos/disenio_barra.dart';
import 'package:arguello_events/features/barra/services/imagen_de_producto.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/services/papel_de_la_barra.dart';
import 'package:arguello_events/models/evento.dart';

/// La barra de un equipo, en memoria: lo que hace `BarraLocal` sin base. Para montar
/// las pantallas de la cajera de verdad, para que Recepción vea qué vales de silla
/// anuló la barra (`BarraDelJefe`), y para la central de la barra (`BarraDeLaRed`).
class BarraEnMemoria implements BarraDeLaCaja, BarraDelJefe, BarraDeLaRed {
  final productosGuardados = <ProductoBarra>[];
  final preciosGuardados = <PrecioBarra>[];
  final cajasGuardadas = <CajaBarra>[];
  final ventasGuardadas = <VentaBarra>[];
  final anulacionesGuardadas = <AnulacionBarra>[];
  final valesGuardados = <ValeBarra>[];
  final recargosGuardados = <RecargoBarra>[];
  String equipo = 'tablet-1';
  DateTime Function() reloj = () => DateTime.utc(2026, 12, 5, 2);

  /// Si vender tira: la base no pudo guardar.
  bool venderFalla = false;

  /// Las ventas que todavía no subieron.
  final sinSubir = <String>{};

  /// Lo demás de la barra que todavía no subió: cajas, anulaciones y vales.
  final otrosSinSubir = <String>{};

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
  Future<RecargoBarra?> recargo(String eventoId) async =>
      recargosGuardados.where((r) => r.eventoId == eventoId).firstOrNull;

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) async {
    final sellado = recargo.sellado(hechoPor: quien, deviceId: equipo, ahora: reloj());
    recargosGuardados
      ..removeWhere((r) => r.id == recargo.id)
      ..add(sellado);
    return sellado;
  }

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
    otrosSinSubir.add(caja.id);
    return caja;
  }

  CajaBarra _reemplazar(CajaBarra nueva) {
    final i = cajasGuardadas.indexWhere((c) => c.id == nueva.id);
    cajasGuardadas[i] = nueva;
    otrosSinSubir.add(nueva.id);
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
  Future<List<VentaBarra>> ventas(String eventoId) async =>
      [for (final v in ventasGuardadas) if (v.eventoId == eventoId) v];

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) async =>
      [for (final a in anulacionesGuardadas) if (a.eventoId == eventoId) a];

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

  @override
  Future<CajaBarra> anotarCierre(CajaBarra caja, {String? nota, required String quien}) async {
    final enLaBase = cajasGuardadas.firstWhere((c) => c.id == caja.id);
    if (enLaBase.abierta) return enLaBase;
    return _reemplazar(enLaBase.conNota(nota).sellada(hechoPor: quien, deviceId: equipo, ahora: reloj()));
  }

  // ── Lo del jefe (`BarraDelJefe`) ─────────────────────────────────────────

  @override
  Future<List<CajaBarra>> cajas(String eventoId) async =>
      [for (final c in cajasGuardadas) if (c.eventoId == eventoId) c];

  @override
  Future<ProductoBarra> guardarProducto(ProductoBarra producto, {required String quien}) async {
    productosGuardados
      ..removeWhere((p) => p.id == producto.id)
      ..add(producto);
    return producto;
  }

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) async {
    preciosGuardados
      ..removeWhere((p) => p.id == precio.id)
      ..add(precio);
    return precio;
  }

  @override
  Future<AnulacionBarra> anular(
    VentaBarra venta, {
    required String motivo,
    required String quien,
  }) async {
    final ya = anulacionesGuardadas.where((a) => a.ventaId == venta.id).firstOrNull;
    if (ya != null) return ya;
    final anulacion =
        AnulacionBarra.de(venta, motivo: motivo, hechoPor: quien, deviceId: equipo, ahora: reloj());
    anulacionesGuardadas.add(anulacion);
    otrosSinSubir.add(anulacion.id);
    return anulacion;
  }

  @override
  Future<ValeBarra> anotarVale(ValeBarra vale) async {
    final conEquipo = ValeBarra.fromMap(vale.toMap()..['device_id'] = equipo);
    valesGuardados.add(conEquipo);
    otrosSinSubir.add(conEquipo.id);
    return conEquipo;
  }

  // ── La red del salón (`BarraDeLaRed`) ─────────────────────────────────────

  /// Cuántas filas llegaron de otro equipo y se guardaron.
  var llegaronDeOtro = 0;

  Map<String, Object?>? _filaDe(String tabla, String id) {
    Map<String, Object?>? de<T>(List<T> lista, String Function(T) idDe, Map<String, Object?> Function(T) mapa) {
      for (final x in lista) {
        if (idDe(x) == id) return mapa(x);
      }
      return null;
    }

    return switch (tabla) {
      'barra_cajas' => de(cajasGuardadas, (c) => c.id, (c) => c.toMap()),
      'barra_ventas' => de(ventasGuardadas, (v) => v.id, (v) => v.toMap()),
      'barra_anulaciones' => de(anulacionesGuardadas, (a) => a.id, (a) => a.toMap()),
      'barra_vales' => de(valesGuardados, (v) => v.id, (v) => v.toMap()),
      _ => null,
    };
  }

  void _ponerDeOtro<T>(List<T> lista, T nueva, String Function(T) idDe) {
    final i = lista.indexWhere((x) => idDe(x) == idDe(nueva));
    if (i < 0) {
      lista.add(nueva);
    } else {
      lista[i] = nueva;
    }
  }

  @override
  Future<bool> guardarDeOtroEquipo(String tabla, Map<String, Object?> fila) async {
    if (!tablasDeLaRed.contains(tabla)) return false;
    final id = fila['id'];
    if (id is! String || id.length != 36) return false;
    if (sinSubir.contains(id) || otrosSinSubir.contains(id)) return false;
    final vieja = _filaDe(tabla, id);
    if (vieja != null && !cambiaLaFila(nueva: fila, vieja: vieja)) return false;
    final m = Map<String, dynamic>.from(fila);
    switch (tabla) {
      case 'barra_cajas':
        _ponerDeOtro(cajasGuardadas, CajaBarra.fromMap(m), (c) => c.id);
      case 'barra_ventas':
        _ponerDeOtro(ventasGuardadas, VentaBarra.fromMap(m), (v) => v.id);
      case 'barra_anulaciones':
        _ponerDeOtro(anulacionesGuardadas, AnulacionBarra.fromMap(m), (a) => a.id);
      case 'barra_vales':
        _ponerDeOtro(valesGuardados, ValeBarra.fromMap(m), (v) => v.id);
    }
    llegaronDeOtro++;
    return true;
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> filasDeLaFiesta(String eventoId) async => {
        'barra_cajas': [for (final c in cajasGuardadas) if (c.eventoId == eventoId) c.toMap()],
        'barra_ventas': [for (final v in ventasGuardadas) if (v.eventoId == eventoId) v.toMap()],
        'barra_anulaciones': [
          for (final a in anulacionesGuardadas) if (a.eventoId == eventoId) a.toMap(),
        ],
        'barra_vales': [for (final v in valesGuardados) if (v.eventoId == eventoId) v.toMap()],
      };

  @override
  Future<Map<String, Object?>?> filaDeLaRed(String tabla, String id) async => _filaDe(tabla, id);

  @override
  Future<PendientesDeLaBarra> pendientesDeLaBarra() async =>
      PendientesDeLaBarra(ventas: sinSubir.length, otros: otrosSinSubir.length);

  /// Como si todo hubiera subido a la nube.
  void subioTodo() {
    sinSubir.clear();
    otrosSinSubir.clear();
  }

  @override
  Future<List<ValeBarra>> valesDeLaCaja(String cajaId) async =>
      [for (final v in valesGuardados) if (v.cajaBarraId == cajaId) v];

  @override
  Future<List<ValeBarra>> vales(String eventoId) async =>
      [for (final v in valesGuardados) if (v.eventoId == eventoId) v];

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

  /// Los mismos papeles, con todas sus líneas (el logo, los precios, el QR).
  final enCrudo = <List<LineaTicket>>[];
  EstadoImpresora estado = EstadoImpresora.lista;
  bool anda = true;
  var preparadas = 0;

  /// La impresora dice que no tiene papel: no sale nada.
  bool sinRollo = false;

  @override
  bool sinPapel = false;

  @override
  Future<EstadoImpresora> preparar() async {
    preparadas++;
    return estado;
  }

  @override
  Future<bool> imprimir(List<LineaTicket> lineas) async {
    sinPapel = sinRollo;
    if (sinRollo || !anda) return false;
    enCrudo.add(lineas);
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

/// El diseño recordado, en memoria.
class DisenioEnMemoria extends DisenioRecordado {
  DisenioBarra disenio;
  var guardados = 0;

  DisenioEnMemoria([this.disenio = DisenioBarra.nocheDorada]);

  @override
  Future<DisenioBarra> leer() async => disenio;

  @override
  Future<void> guardar(DisenioBarra d) async {
    disenio = d;
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
  final disenio = DisenioEnMemoria();

  /// La foto de cada producto. Por defecto ninguna (la inicial): así los tests no leen
  /// archivos. Un test la cambia para ver la foto.
  ImageProvider? Function(ProductoBarra) imagen = (_) => null;
  final eventos = <Evento>[];
  final subidas = <String>[];

  /// Lo que no es una venta y se mandó a subir ya: "tabla id".
  final subidasDeLaBarra = <String>[];

  /// Los PDF que se guardaron: el nombre del archivo y sus renglones.
  final pdfs = <({String nombre, String titulo, List<LineaTicket> lineas})>[];
  var bajadas = 0;
  bool bajaBien = true;
  DateTime? alDia;
  final aviso = AvisoALaRed();

  List<Override> get reemplazos => [
        // Las pantallas, sin la red del salón: no abren conexiones de verdad.
        redDeLaBarraHabilitadaProvider.overrideWithValue(false),
        barraDeLaRedProvider.overrideWithValue(barra),
        // Como en la app: lo que escribe la caja avisa (sin red del salón, no sale nada), así
        // la línea de VENDER vuelve a contar lo que espera subir.
        avisoALaRedProvider.overrideWithValue(aviso),
        barraDeLaCajaProvider.overrideWithValue(BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso)),
        papelDeLaBarraProvider.overrideWithValue(papel),
        recargoRecordadoProvider.overrideWithValue(recargo),
        disenioRecordadoProvider.overrideWithValue(disenio),
        imagenDelProductoProvider.overrideWithValue((p) => imagen(p)),
        eventosDeLaBarraProvider.overrideWith((ref) async => eventos),
        subirVentaProvider.overrideWithValue((v) async => subidas.add(v.id)),
        subirDeLaBarraProvider.overrideWithValue(
          (tabla, id) async => subidasDeLaBarra.add('$tabla $id'),
        ),
        guardarPdfDeLaBarraProvider.overrideWithValue(
          (lineas, {required titulo, required nombre, context}) async =>
              pdfs.add((nombre: nombre, titulo: titulo, lineas: lineas)),
        ),
        accesosBarraProvider.overrideWithValue(AccesosBarra(
          bajar: () async {
            bajadas++;
            return bajaBien;
          },
          contarFiestas: () async => (await barra.fiestasConPrecio()).length,
          contarSinSubir: barra.ventasSinSubir,
          contarPendientes: barra.pendientesDeLaBarra,
          leerAlDia: () async => alDia,
          anotarAlDia: (cuando) async => alDia = cuando,
          ahora: () => DateTime.utc(2026, 12, 5, 0, 40),
        )),
      ];

  /// Un id de evento válido.
  static String id(int n) => 'e0000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  static String nuevoId() => UuidUtils.generate();
}
