import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../barra/cuentas/pesos.dart';
import '../../eventos/services/entrega_por_partes.dart';
import '../../eventos/services/entregar_parte.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../../eventos/widgets/formulario_entrega_parte.dart';
import 'vender_a_pagar.dart';

/// GRATIS · SE ENTREGA, en la tarjeta del alumno de VENDER (20-nov-2026): las 8
/// de la mesa del contrato, **en dos partes, cada una cuando llega su
/// material**: las pulseras VIP con cena (el egresado y sus acompañantes) y las
/// entradas generales que completan las 8.
///
/// - Cada parte con ENTREGAR, que abre su formulario acá adentro
///   ([FormularioEntregaParte]), o su ✓ con quién y cuándo. Con las dos,
///   "✓ Todo entregado".
/// - **Si debe algo de su contrato (cuotas, extras o mora) no hay ENTREGAR**:
///   lo dice, y MANDAR A CAJA (o PASAR A CAJA, con el permiso de Cobros).
///   Cuando paga, se destraba solo.
/// - Otro bloqueo (la ficha y los pagos no coinciden, sin mesa…): lo dice, y
///   "pedile al jefe que lo revise", sin botón.
///
/// GRATIS no necesita caja ni precio. **No guarda nada**: lo que se elige en el
/// formulario va a [alConfirmar], y VENDER lo guarda por `EntregarParte`.
/// VENDER no anula entregas: eso es del jefe, desde ENTRADAS de la fiesta.
class BloqueGratis extends StatelessWidget {
  const BloqueGratis({
    super.key,
    required this.alumno,
    required this.estado,
    required this.deuda,
    required this.bloqueo,
    this.abierta,
    this.ocupado = false,
    this.deOtros = const {},
    this.retiro,
    this.renglones = const [],
    this.enCaja = false,
    this.puedePasarACaja = false,
    required this.alAbrir,
    required this.alCancelar,
    required this.alConfirmar,
    required this.alMandarACaja,
    required this.alPasarACaja,
  });

  final ContratoAlumno alumno;
  final EstadoDeLaEntrega estado;
  final DeudaAlumno deuda;
  final BloqueoRetiro bloqueo;

  /// La parte cuyo formulario está abierto (una a la vez), o null.
  final ParteEntrega? abierta;

  /// Mientras se guarda una entrega.
  final bool ocupado;

  /// Los números de las generales ya entregadas a las otras familias.
  final Map<String, List<TramoTalonario>> deOtros;

  /// Lo suyo de la entrega: para ofrecer lo de una entrega anulada.
  final EntradasRetiro? retiro;
  final List<EntregaEntradas> renglones;

  /// Ya está en "En caja".
  final bool enCaja;

  /// Quien vende también tiene Cobros: PASAR A CAJA lo lleva sin el PIN.
  final bool puedePasarACaja;

  final ValueChanged<ParteEntrega> alAbrir;
  final VoidCallback alCancelar;
  final ValueChanged<DatosDeLaParte> alConfirmar;
  final VoidCallback alMandarACaja;
  final VoidCallback alPasarACaja;

  /// Le falta algo y no se le puede entregar todavía.
  bool get _bloqueado => !estado.todoEntregado && bloqueo != BloqueoRetiro.ninguno;

  TextStyle get _gris => TextStyle(fontSize: 13, color: Colors.grey.shade700);

  /// "Por contrato: 8 de su mesa." Con más de 8 con cena, los de más van en sus
  /// lugares adicionales, también sin cargo: si no, la parte de las pulseras
  /// decía 10 y arriba 8 (revisión del 20-nov-2026).
  String get _porContrato {
    final deMas = estado.pulseras.leToca - 8;
    if (deMas <= 0) {
      return 'Por contrato: 8 de su mesa. Cada parte se entrega cuando llega.';
    }
    return 'Por contrato: las 8 de su mesa, y ${deMas == 1 ? '1 VIP más' : '$deMas VIP más'} '
        'en sus lugares adicionales, sin cargo. Cada parte se entrega cuando llega.';
  }

  @override
  Widget build(BuildContext context) {
    final verde = Colors.green.shade700;
    final rojo = Colors.red.shade700;
    final naranja = Colors.orange.shade800;
    final color = !_bloqueado
        ? verde
        : (bloqueo == BloqueoRetiro.debe ? rojo : naranja);
    return Container(
      key: const Key('vender_gratis'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _bloqueado ? 'GRATIS · TODAVÍA NO SE ENTREGA' : 'GRATIS · SE ENTREGA',
                  key: const Key('vender_gratis_titulo'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: color,
                  ),
                ),
              ),
              Text(
                pesos(0),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _porContrato,
            key: const Key('vender_gratis_por_contrato'),
            style: _gris,
          ),
          if (_bloqueado) ..._porQueNo(context, color),
          for (final p in ParteEntrega.values) _parte(context, p),
          if (estado.todoEntregado)
            Container(
              key: const Key('vender_todo_entregado'),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: verde,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '✓ Todo entregado',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  /// Por qué todavía no se le entrega, y qué hacer.
  List<Widget> _porQueNo(BuildContext context, Color color) {
    final d = deuda;
    final e = RetiroEntradas.entradasDe(alumno);
    final String texto;
    var aCaja = false;
    switch (bloqueo) {
      case BloqueoRetiro.debe:
        aCaja = true;
        final cuotas = d.saldoPagos > d.saldoFicha ? d.saldoPagos : d.saldoFicha;
        final partes = [
          if (cuotas > RetiroEntradas.margen) 'cuotas y extras ${pesos(cuotas)}',
          if (d.mora > RetiroEntradas.margen) 'mora ${pesos(d.mora)}',
        ];
        texto = 'Debe ${pesos(d.total)} de su contrato: ${partes.join(' · ')}. '
            'Primero pasa por caja a saldar todo. Cuando pague, se destraba solo.';
      case BloqueoRetiro.cuentaNoCoincide:
        texto = 'La ficha dice que debe ${pesos(d.saldoFicha)} y los pagos dan '
            '${pesos(d.saldoPagos)}: hasta aclararlo no se entrega. Pedile al jefe '
            'que lo revise.';
      case BloqueoRetiro.sinMesa:
        texto = 'No tiene mesa asignada: la entrada dice dónde sentarse. Pedile al '
            'jefe que lo revise.';
      case BloqueoRetiro.mesasNoCoinciden:
        texto = '${SalonMesas.avisoMesas(alumno) ?? 'Sus mesas no coinciden con su cuenta'}. '
            'Las entradas salen de las mesas que tiene: pedile al jefe que lo revise.';
      case BloqueoRetiro.noEntran:
        texto = 'No entran: tiene ${e.vip} con cena y ${e.lugares} lugares. Pedile al '
            'jefe que lo revise.';
      case BloqueoRetiro.ninguno:
        return const [];
    }
    return [
      const SizedBox(height: 8),
      Text(
        texto,
        key: Key(aCaja ? 'vender_gratis_debe' : 'vender_gratis_revisar'),
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      if (aCaja) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (enCaja)
              Text(
                'Ya está en caja: cuando pague, avisa arriba.',
                key: const Key('vender_ya_en_caja'),
                style: _gris,
              ),
            if (puedePasarACaja)
              OutlinedButton.icon(
                key: const Key('vender_pasar_a_caja'),
                onPressed: ocupado ? null : alPasarACaja,
                icon: const Icon(Icons.point_of_sale),
                label: const Text('PASAR A CAJA'),
              ),
            FilledButton(
              key: const Key('vender_mandar_a_caja'),
              onPressed: ocupado || enCaja ? null : alMandarACaja,
              child: const Text('MANDAR A CAJA'),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _parte(BuildContext context, ParteEntrega p) {
    final e = estado.parte(p);
    // La otra parte se llevó otra cuenta: entregar esta se pasaría de lo sin
    // cargo. Lo revisa el jefe (la misma regla que `EntregarParte`).
    final porLaOtra = EntregaPorPartes.frenoPorLaOtraParte(estado, p);
    final verde = Colors.green.shade700;
    final cuantas = e.entregada ? e.cantidad : e.leToca;
    final pulseras = p == ParteEntrega.pulseras;
    final titulo = pulseras
        ? 'Pulseras VIP con cena · $cuantas'
        : 'Entradas generales · $cuantas';
    final detalle = pulseras
        ? EntregaPorPartes.quienesVanConCena(alumno, cuantas)
        : (e.leToca <= 0 && !e.entregada
            ? 'No lleva: las 8 de la mesa son con cena.'
            : (e.entregada && e.tramos.isNotEmpty
                ? 'Del ${TramoTalonario.legible(e.tramos)}'
                : 'Completan las 8 de la mesa del contrato.'));

    final Widget derecha;
    if (e.entregada) {
      derecha = ChipDeVender(
        '✓ Entregadas',
        key: Key('vender_entregada_${p.clave}'),
        color: verde,
      );
    } else if (e.leToca <= 0) {
      derecha = Text('No lleva', style: _gris);
    } else if (_bloqueado || porLaOtra != null) {
      derecha = ChipDeVender(
        'Pendiente',
        key: Key('vender_pendiente_${p.clave}'),
        color: Colors.blueGrey.shade600,
      );
    } else if (abierta == p) {
      derecha = const SizedBox.shrink();
    } else {
      derecha = FilledButton(
        key: Key('vender_entregar_${p.clave}'),
        style: FilledButton.styleFrom(backgroundColor: verde),
        // Una a la vez: si estaba abierta la otra, se cierra (no se guardó nada).
        onPressed: ocupado ? null : () => alAbrir(p),
        child: const Text('ENTREGAR'),
      );
    }

    final acompanantes = e.leToca - 1;
    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          key: Key('vender_parte_titulo_${p.clave}'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        Text(detalle, key: Key('vender_parte_detalle_${p.clave}'), style: _gris),
      ],
    );
    // En un celular, el botón debajo del nombre: al lado, el nombre se parte.
    final cabeza = LayoutBuilder(
      builder: (context, caja) => caja.maxWidth < 400
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                nombre,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: derecha),
              ],
            )
          : Row(
              children: [
                Expanded(child: nombre),
                const SizedBox(width: 8),
                derecha,
              ],
            ),
    );

    return Container(
      key: Key('vender_parte_${p.clave}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: e.entregada
              ? verde.withValues(alpha: 0.6)
              : Colors.grey.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabeza,
          if (pulseras && !e.entregada && acompanantes > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tiene $acompanantes acompañantes con cena (el máximo es 2): '
                'confirmalo con el jefe.',
                key: const Key('vender_mas_de_dos'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
          if (e.entregada) ...[
            const SizedBox(height: 4),
            Text(
              EntregaPorPartes.quienYCuando(e, fecha: ArTime.formatFechaHora),
              key: Key('vender_quien_${p.clave}'),
              style: const TextStyle(fontSize: 13),
            ),
            if (pulseras && e.menores10 > 0)
              Text('Menores de 10: ${e.menores10}', style: _gris),
            if (e.cambioLaCuenta)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Cambió la cuenta después de entregar: hoy le corresponden '
                  '${e.leToca} y se llevó ${e.cantidad}. Para darle lo que falta, el '
                  'jefe anula esta parte desde ENTRADAS de la fiesta y se vuelve a '
                  'entregar.',
                  key: Key('vender_cambio_la_cuenta_${p.clave}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
          ],
          if (porLaOtra != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                porLaOtra,
                key: Key('vender_por_la_otra_${p.clave}'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
          if (!e.entregada && e.anulada)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tuvo una entrega anulada'
                '${e.anuladaAt == null ? '' : ' el ${ArTime.formatFechaHora(e.anuladaAt!)}'}'
                '${(e.anuladaPor ?? '').isEmpty ? '' : ' por ${e.anuladaPor}'}'
                '${(e.motivoAnulacion ?? '').isEmpty ? '' : ': ${e.motivoAnulacion}'}.',
                style: _gris,
              ),
            ),
          if (abierta == p &&
              !e.entregada &&
              !_bloqueado &&
              porLaOtra == null &&
              e.leToca > 0) ...[
            const Divider(height: 20),
            FormularioEntregaParte(
              key: Key('vender_formulario_${p.clave}'),
              alumno: alumno,
              parte: p,
              cantidad: e.leToca,
              deOtros: p == ParteEntrega.generales ? deOtros : const {},
              antes: LoDeAntes.de(
                parte: p,
                estado: e,
                retiro: retiro,
                renglones: renglones,
              ),
              ocupado: ocupado,
              alConfirmar: alConfirmar,
              alCancelar: alCancelar,
            ),
          ],
        ],
      ),
    );
  }
}
