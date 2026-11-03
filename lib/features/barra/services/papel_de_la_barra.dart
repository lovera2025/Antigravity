import '../impresion/impresora_bluetooth.dart';
import '../impresion/ticket_esc_pos.dart';

/// Lo que las pantallas de la barra necesitan de la impresora: estar lista y sacar un
/// papel. Detrás está la TP-POS58 por Bluetooth ([PapelPorBluetooth]); en los tests, uno
/// en memoria que anota lo que salió.
abstract interface class PapelDeLaBarra {
  /// Se conecta a la impresora de este equipo si hace falta. No tira.
  Future<EstadoImpresora> preparar();

  /// Saca un papel. True si salió. No tira: un papel que no sale no frena la venta.
  Future<bool> imprimir(List<LineaTicket> lineas);
}

/// La impresora de verdad: arma los bytes con [TicketEscPos] y los manda por
/// [ImpresoraBluetooth], que reconecta sola antes de cada papel.
class PapelPorBluetooth implements PapelDeLaBarra {
  final ImpresoraBluetooth impresora;
  final Future<TicketEscPos> Function() _armador;
  Future<TicketEscPos>? _cargado;

  PapelPorBluetooth(this.impresora, {Future<TicketEscPos> Function()? armador})
      : _armador = armador ?? (() => TicketEscPos.cargar());

  @override
  Future<EstadoImpresora> preparar() async {
    try {
      await impresora.canal.pedirPermisos();
    } catch (_) {}
    try {
      return await impresora.reconectar();
    } catch (_) {
      return EstadoImpresora.noContesta;
    }
  }

  @override
  Future<bool> imprimir(List<LineaTicket> lineas) async {
    try {
      final armador = await (_cargado ??= _armador());
      return await impresora.imprimir(armador.armar(lineas)) == ResultadoImpresion.impreso;
    } catch (_) {
      return false;
    }
  }
}
