import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../caja_sesiones/providers/app_role_provider.dart';
import '../cuentas/cierre_de_barra.dart';
import '../cuentas/pedido_de_cierre.dart';
import '../cuentas/pesos.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart';

/// Lo que contesta la encargada (o el jefe) a un pedido de cierre.
enum RespuestaAlCierre { aceptar, recontar }

/// La hora de este equipo, para el cierre con el OK. Los tests la reemplazan: los 3
/// minutos de "cerrar sin esperar" no se pueden esperar de verdad.
final ahoraEnLaBarraProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Cada cuánto el equipo de la encargada mira si alguna caja pide cerrar. En la PC y la
/// tablet se le pregunta a **la base del equipo** (lo que llegó por la red del salón o
/// bajó de la nube): no le pide nada a la nube. En la web no hay base, así que va con la
/// misma relectura de LAS CAJAS.
const kMirarPedidosDeCierre = Duration(seconds: 3);
const kMirarPedidosDeCierreEnLaWeb = Duration(seconds: 30);

/// El sonido del aviso "una caja pide cerrar". Los tests lo reemplazan.
final sonarPedidoDeCierreProvider = Provider<void Function()>((ref) {
  return () {
    try {
      unawaited(SystemSound.play(SystemSoundType.alert).catchError((Object _) {}));
    } catch (_) {}
  };
});

/// El cartel con los totales de la caja que pide cerrar (11-nov-2026): lo que la
/// encargada corrobora antes de aceptar. **Solo lo ve quien manda en la barra**: la
/// cajera contó a ciegas y no ve nada de esto.
///
/// Null si se cierra sin contestar.
Future<RespuestaAlCierre?> mostrarOkDelCierre(
  BuildContext context, {
  required CajaBarra caja,
  required PasoDelCierre pedido,
  required CierreDeBarra cuentas,
}) =>
    showDialog<RespuestaAlCierre>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OkDelCierreDialog(caja: caja, pedido: pedido, cuentas: cuentas),
    );

class OkDelCierreDialog extends StatelessWidget {
  final CajaBarra caja;
  final PasoDelCierre pedido;
  final CierreDeBarra cuentas;

  const OkDelCierreDialog({
    super.key,
    required this.caja,
    required this.pedido,
    required this.cuentas,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final contado = pedido.efectivoContado ?? 0;
    final diferencia = cuentas.diferenciaCon(contado);
    final c = centavos(diferencia);
    final color = c == 0
        ? Colors.green.shade400
        : c < 0
            ? tema.colorScheme.error
            : Colors.amber.shade600;
    Widget renglon(String a, String b, {String? clave, bool fuerte = false, String? al}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(a, style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500)),
              ),
              if (al != null) ...[
                Text(al, style: tema.textTheme.bodySmall),
                const SizedBox(width: 8),
              ],
              Text(
                b,
                key: clave == null ? null : Key(clave),
                style: TextStyle(fontSize: fuerte ? 18 : 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
    final nombre = caja.operadorNombre;
    return AlertDialog(
      title: Text(
        'La Caja ${caja.numeroCaja}${nombre == null ? '' : ' ($nombre)'} pide cerrar',
        key: const Key('ok_cierre_titulo'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                cuentas.ventas == 1 ? '1 venta' : '${cuentas.ventas} ventas',
                key: const Key('ok_cierre_ventas'),
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              renglon('Efectivo esperado', pesos(cuentas.efectivoEsperado), clave: 'ok_cierre_esperado'),
              renglon('Contó', pesos(contado), clave: 'ok_cierre_conto'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  diferenciaEnPalabras(diferencia),
                  key: const Key('ok_cierre_diferencia'),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ),
              const Divider(height: 14),
              renglon(
                'Transferencia',
                pesos(cuentas.transferencia),
                clave: 'ok_cierre_transferencia',
                al: cuentas.conTransferencia == 1 ? '1 venta' : '${cuentas.conTransferencia} ventas',
              ),
              renglon('TOTAL VENDIDO', pesos(cuentas.total), clave: 'ok_cierre_total', fuerte: true),
              if (cuentas.anuladas > 0)
                renglon('Anuladas (no cuentan)', '${cuentas.anuladas}'),
              if ((pedido.nota ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Nota de la cajera: ${pedido.nota!.trim()}', key: const Key('ok_cierre_nota')),
              ],
              const SizedBox(height: 10),
              Text(
                'Al aceptar, la caja se cierra con lo que contó. Mirá las transferencias en '
                'Mercado Pago antes.',
                style: tema.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ok_cierre_despues'),
          onPressed: () => Navigator.pop(context),
          child: const Text('DESPUÉS'),
        ),
        OutlinedButton(
          key: const Key('ok_cierre_recontar'),
          onPressed: () => Navigator.pop(context, RespuestaAlCierre.recontar),
          child: const Text('QUE CUENTE DE NUEVO'),
        ),
        FilledButton(
          key: const Key('ok_cierre_aceptar'),
          onPressed: () => Navigator.pop(context, RespuestaAlCierre.aceptar),
          child: const Text('ACEPTAR Y CERRAR'),
        ),
      ],
    );
  }
}

/// Las cuentas de una caja para el cartel del OK, leídas de [barra] (la base del equipo,
/// o la nube en la web).
Future<CierreDeBarra> cuentasParaElOk(BarraDelJefe barra, CajaBarra caja) async {
  final ventas = await barra.ventas(caja.eventoId);
  final anulaciones = await barra.anulaciones(caja.eventoId);
  var categorias = const <String, String>{};
  try {
    categorias = {for (final p in await barra.productos(conBajas: true)) p.id: p.categoria};
  } catch (_) {}
  return CierreDeBarra.de(caja, ventas, anulaciones, categorias: categorias);
}

/// **"La Caja 2 (Marta) pide cerrar"**: el aviso que le salta a la encargada de barra (o
/// al jefe en modo jefe), con sonido, esté vendiendo o mirando LAS CAJAS. Lo abre, ve
/// los totales y acepta, o pide que cuente de nuevo.
///
/// El aparato de la encargada **solo agrega su respuesta** (`barra_cierres`): la caja de
/// la cajera la cierra su propia tablet cuando le llega el ok, por la red del salón o
/// por la nube.
class AvisoDePedidosDeCierre extends ConsumerStatefulWidget {
  final String eventoId;

  /// La caja de este mismo equipo, si vende: no se avisa a sí misma.
  final String? exceptoCajaId;

  const AvisoDePedidosDeCierre({super.key, required this.eventoId, this.exceptoCajaId});

  @override
  ConsumerState<AvisoDePedidosDeCierre> createState() => _AvisoDePedidosDeCierreState();
}

class _AvisoDePedidosDeCierreState extends ConsumerState<AvisoDePedidosDeCierre> {
  Timer? _reloj;
  List<PedidoEnPie> _enPie = const [];

  /// Los pedidos por los que ya sonó: suena una vez por pedido, no cada 3 segundos.
  final _yaSonaron = <String>{};
  bool _mirando = false;
  bool _ocupado = false;
  String? _dicho;

  @override
  void initState() {
    super.initState();
    unawaited(_mirar());
    _reloj = Timer.periodic(
      ref.read(enLaWebProvider) ? kMirarPedidosDeCierreEnLaWeb : kMirarPedidosDeCierre,
      (_) => _mirar(),
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _mirar() async {
    if (!mounted || _mirando) return;
    // Solo a quien manda en la barra: una cajera común no ve los pedidos de las otras.
    if (!ref.read(mandaEnLaBarraProvider)) {
      if (_enPie.isNotEmpty) setState(() => _enPie = const []);
      return;
    }
    _mirando = true;
    try {
      final barra = ref.read(barraDelJefeProvider);
      final pasos = await barra.pasosDelCierre(widget.eventoId);
      // Sin ningún pedido no hace falta leer las cajas: lo de casi toda la noche.
      final enPie = pasos.isEmpty
          ? const <PedidoEnPie>[]
          : [
              for (final x in PedidoDeCierre.enPie(await barra.cajas(widget.eventoId), pasos))
                if (x.caja.id != widget.exceptoCajaId) x,
            ];
      if (!mounted) return;
      final nuevos = [for (final x in enPie) if (_yaSonaron.add(x.pedido.id)) x];
      if (nuevos.isNotEmpty) ref.read(sonarPedidoDeCierreProvider)();
      final igual = enPie.length == _enPie.length &&
          [for (var i = 0; i < enPie.length; i++) enPie[i].pedido.id == _enPie[i].pedido.id]
              .every((v) => v);
      if (!igual) setState(() => _enPie = enPie);
    } catch (_) {
      // Sin la tabla (una base que todavía no migró) o sin nube: no hay aviso, y nada más.
    } finally {
      _mirando = false;
    }
  }

  Future<void> _ver(PedidoEnPie x) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _dicho = null;
    });
    try {
      final barra = ref.read(barraDelJefeProvider);
      final cuentas = await cuentasParaElOk(barra, x.caja);
      if (!mounted) return;
      final respuesta = await mostrarOkDelCierre(context, caja: x.caja, pedido: x.pedido, cuentas: cuentas);
      if (respuesta == null || !mounted) return;
      // La segunda llave: aceptar un cierre es de quien manda en la barra.
      if (!ref.read(mandaEnLaBarraProvider)) return;
      final quien = ref.read(appRoleProvider).operador?.nombre ?? 'Jefe';
      final paso = await barra.anotarPasoDelCierre(PasoDelCierre.responder(
        pedido: x.pedido,
        tipo: respuesta == RespuestaAlCierre.aceptar ? TipoPasoDelCierre.ok : TipoPasoDelCierre.recontar,
        hechoPor: quien,
        ahora: DateTime.now(),
      ));
      unawaited(ref.read(subirDeLaBarraProvider)('barra_cierres', paso.id));
      if (!mounted) return;
      setState(() {
        _dicho = respuesta == RespuestaAlCierre.aceptar
            ? 'Aceptaste el cierre de la Caja ${x.caja.numeroCaja}: se cierra en su equipo.'
            : 'Le pediste a la Caja ${x.caja.numeroCaja} que cuente de nuevo.';
      });
      await _mirar();
    } catch (_) {
      if (mounted) setState(() => _dicho = 'No se pudo guardar la respuesta. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enPie.isEmpty && _dicho == null) return const SizedBox.shrink();
    return Column(
      key: const Key('aviso_cierres'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final x in _enPie)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Material(
              key: Key('aviso_cierre_${x.caja.id}'),
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock, color: Colors.black),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'La Caja ${x.caja.numeroCaja}'
                        '${x.caja.operadorNombre == null ? '' : ' (${x.caja.operadorNombre})'}'
                        ' pide cerrar',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    FilledButton(
                      key: Key('aviso_cierre_ver_${x.caja.id}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: _ocupado ? null : () => _ver(x),
                      child: const Text('VER'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_dicho != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(_dicho!, key: const Key('aviso_cierre_dicho'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
