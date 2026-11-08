import 'dart:async';

import '../impresion/impresora_bluetooth.dart';
import '../impresion/ticket_esc_pos.dart';

/// Lo que se dice cuando la impresora avisó que no tiene papel.
const kSinPapel = 'La impresora no tiene papel: cambiá el rollo y tocá de nuevo.';

/// Lo que las pantallas de la barra necesitan de la impresora: estar lista y sacar un
/// papel. Detrás está la TP-POS58 por Bluetooth ([PapelPorBluetooth]); en los tests, uno
/// en memoria que anota lo que salió.
abstract interface class PapelDeLaBarra {
  /// Se conecta a la impresora de este equipo si hace falta. No tira.
  Future<EstadoImpresora> preparar();

  /// Saca un papel. True si salió. No tira: un papel que no sale no frena la venta.
  Future<bool> imprimir(List<LineaTicket> lineas);

  /// El último papel no salió porque la impresora dijo que no tiene papel.
  bool get sinPapel;
}

/// Lo que dice una pantalla cuando un papel no salió: "no tiene papel" si la
/// impresora lo avisó, y si no, lo de siempre ([porDefecto]).
String siNoSalio(PapelDeLaBarra papel, String porDefecto) =>
    papel.sinPapel ? kSinPapel : porDefecto;

/// La impresora de verdad: arma los bytes con [TicketEscPos] y los manda por
/// [ImpresoraBluetooth], que reconecta sola antes de cada papel.
class PapelPorBluetooth implements PapelDeLaBarra {
  final ImpresoraBluetooth impresora;
  final Future<TicketEscPos> Function() _armador;
  Future<TicketEscPos>? _cargado;
  bool _sinPapel = false;

  PapelPorBluetooth(this.impresora, {Future<TicketEscPos> Function()? armador})
      : _armador = armador ?? (() => TicketEscPos.cargar());

  @override
  bool get sinPapel => _sinPapel;

  @override
  Future<EstadoImpresora> preparar() async {
    try {
      await impresora.canal.pedirPermisos();
    } catch (_) {}
    EstadoImpresora estado;
    try {
      estado = await impresora.reconectar();
    } catch (_) {
      return EstadoImpresora.noContesta;
    }
    // Una vez por impresora: si contesta por el papel, desde ahí se le pregunta
    // antes de cada papel. No se espera: va en la fila de los papeles.
    if (estado == EstadoImpresora.lista && impresora.contestaElPapel == null) {
      unawaited(impresora.consultarPapel());
    }
    return estado;
  }

  @override
  Future<bool> imprimir(List<LineaTicket> lineas) async {
    try {
      final armador = await (_cargado ??= _armador());
      final r = await impresora.imprimir(armador.armar(lineas));
      _sinPapel = r == ResultadoImpresion.sinPapel;
      return r == ResultadoImpresion.impreso;
    } catch (_) {
      _sinPapel = false;
      return false;
    }
  }
}
