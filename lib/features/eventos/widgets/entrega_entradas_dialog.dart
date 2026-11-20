import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/utils/solo_jefe.dart';
import '../../entradas/cuentas/lugares_de_la_familia.dart';
import '../services/entrega_por_partes.dart';
import '../services/entregar_parte.dart';
import '../services/lugares_pagos.dart';
import '../services/permisos_de_entrega.dart';
import '../services/retiro_entradas.dart';
import '../services/salon_mesas.dart';
import 'formulario_entrega_parte.dart';

/// Lo que eligió hacer quien atiende el mostrador.
sealed class AccionEntrega {
  const AccionEntrega();
}

/// Entregar **una parte** (las pulseras o las generales), con lo que se eligió
/// en su formulario. La pantalla lo guarda por `EntregarParte`.
class EntregarUnaParte extends AccionEntrega {
  final DatosDeLaParte datos;
  const EntregarUnaParte(this.datos);
}

/// Anular [partes] (una o las dos), con [motivo]: solo el jefe.
class AnularEntrega extends AccionEntrega {
  final Set<ParteEntrega> partes;
  final String motivo;
  const AnularEntrega(this.partes, this.motivo);
}

class IrACobrar extends AccionEntrega {
  const IrACobrar();
}

/// El mostrador, con Cobros: va a la caja a cobrarle (sin volver a poner el PIN).
class PasarACaja extends AccionEntrega {
  const PasarACaja();
}

/// El mostrador, sin Cobros: la familia va a pagar a la caja y queda en "En caja".
class MandarACaja extends AccionEntrega {
  const MandarACaja();
}

/// La cuenta cambió con el diálogo abierto (pagó en la caja): se vuelve a abrir
/// con los datos nuevos. Lo pide la pantalla, no la persona.
class VolverAAbrir extends AccionEntrega {
  const VolverAAbrir();
}

class EditarAlumno extends AccionEntrega {
  const EditarAlumno();
}

/// VENDERLE ESAS ENTRADAS (6.9.0): las de sus lugares adicionales que ya están
/// pagos, en VENDER con la familia ya elegida.
class VenderAlCincuenta extends AccionEntrega {
  const VenderAlCincuenta();
}

/// Lo de la venta de entradas que la entrega muestra de una familia (6.9.0,
/// sección 9.3 del spec del 13-nov): lo que ya compró de sus lugares
/// adicionales, lo que todavía puede comprar y si quien atiende puede
/// vendérselo. Sin esto (la fiesta sin precio, o en la web) la entrega se ve
/// como siempre.
///
/// **Se le vende solo lo que ya está pago entero, cosa por cosa** (regla del
/// usuario, 20-nov-2026): la cuenta es [LugaresDeLaFamilia], la misma de
/// VENDER, con los pagos que la pantalla ya leyó (`APagarDeLaFamilia`).
class VentaAlCincuenta {
  final LugaresDeLaFamilia lugares;

  /// Si quien atiende tiene "Vende entradas" (o el modo jefe) en este equipo.
  final bool puedeVender;

  /// El descuento de los lugares adicionales que el jefe puso en PRECIOS.
  final double descuentoPct;

  const VentaAlCincuenta({
    required this.lugares,
    required this.puedeVender,
    this.descuentoPct = 50,
  });
}

/// El diálogo del mostrador para un egresado: lo que se le entrega sin cargo,
/// **en dos partes** (20-nov-2026: las pulseras VIP con cena y las entradas
/// generales llegan en tandas distintas), cada una con su ENTREGAR o su ✓; por
/// qué no se le puede entregar todavía; lo que ya se llevó, con la opción de
/// anularlo (solo el jefe); y lo de sus lugares adicionales.
///
/// **Las dos partes se entregan solo si la familia pagó todo su contrato**
/// (cuotas, extras y mora, de los pagos: [bloqueo]). Si debe, no hay ENTREGAR:
/// pasa por caja.
///
/// No guarda nada: devuelve la [AccionEntrega] y la pantalla la aplica.
///
/// [permisos] dice qué botones hay (cobrar, pasar a caja, editar, anular).
/// Cuando [cuentaCambio] avisa con el diálogo mostrando un bloqueo (no un
/// formulario, que puede tener algo escrito), se cierra con [VolverAAbrir].
Future<AccionEntrega?> mostrarEntregaEntradasDialog({
  required BuildContext context,
  required ContratoAlumno alumno,
  required EntradasDeAlumno entradas,
  required EstadoDeLaEntrega estado,
  required DeudaAlumno deuda,
  required BloqueoRetiro bloqueo,
  required PermisosDeEntrega permisos,
  EntradasRetiro? retiro,
  List<EntregaEntradas> renglones = const [],
  Map<String, List<TramoTalonario>> deOtros = const {},
  Listenable? cuentaCambio,
  VentaAlCincuenta? venta,
}) =>
    showDialog<AccionEntrega>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EntregaDialog(
        alumno: alumno,
        entradas: entradas,
        estado: estado,
        deuda: deuda,
        bloqueo: bloqueo,
        permisos: permisos,
        retiro: retiro,
        renglones: renglones,
        deOtros: deOtros,
        cuentaCambio: cuentaCambio,
        venta: venta,
      ),
    );

class _EntregaDialog extends StatefulWidget {
  final ContratoAlumno alumno;
  final EntradasDeAlumno entradas;
  final EstadoDeLaEntrega estado;
  final DeudaAlumno deuda;
  final BloqueoRetiro bloqueo;
  final PermisosDeEntrega permisos;
  final EntradasRetiro? retiro;
  final List<EntregaEntradas> renglones;
  final Map<String, List<TramoTalonario>> deOtros;
  final Listenable? cuentaCambio;
  final VentaAlCincuenta? venta;

  const _EntregaDialog({
    required this.alumno,
    required this.entradas,
    required this.estado,
    required this.deuda,
    required this.bloqueo,
    required this.permisos,
    required this.retiro,
    required this.renglones,
    required this.deOtros,
    required this.cuentaCambio,
    required this.venta,
  });

  @override
  State<_EntregaDialog> createState() => _EntregaDialogState();
}

class _EntregaDialogState extends State<_EntregaDialog> {
  final _motivoAnular = TextEditingController();

  /// La parte cuyo formulario está abierto (una a la vez), o null.
  ParteEntrega? _abierta;
  bool _anulando = false;
  Set<ParteEntrega> _aAnular = const {};
  String? _errorAnular;

  EstadoDeLaEntrega get _estado => widget.estado;

  /// Le falta alguna parte y no se le puede entregar.
  bool get _bloqueado =>
      !_estado.todoEntregado && widget.bloqueo != BloqueoRetiro.ninguno;

  /// Lo que se ve es un bloqueo: no hay nada escrito que perder si se cierra solo.
  bool get _muestraBloqueo => _bloqueado && _abierta == null;

  void _alCambiarLaCuenta() {
    if (mounted && _muestraBloqueo) Navigator.pop(context, const VolverAAbrir());
  }

  @override
  void initState() {
    super.initState();
    widget.cuentaCambio?.addListener(_alCambiarLaCuenta);
  }

  @override
  void dispose() {
    widget.cuentaCambio?.removeListener(_alCambiarLaCuenta);
    _motivoAnular.dispose();
    super.dispose();
  }

  // ── Piezas ───────────────────────────────────────────────────────────────

  TextStyle get _gris => TextStyle(fontSize: 12.5, color: Colors.grey.shade700);

  Widget _cartel(String titulo, String detalle, {required Color color}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 4),
            Text(detalle, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
      );

  Widget _marca(String texto, Color color, {IconData? icono, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 15, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              texto,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      );

  InputDecoration _campo(String etiqueta, {String? error}) => InputDecoration(
        labelText: etiqueta,
        errorText: error,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  // ── Las dos partes ─────────────────────────────────────────────────────

  static String _titulo(ParteEntrega p) =>
      p == ParteEntrega.pulseras ? 'Pulseras VIP con cena' : 'Entradas generales';

  /// Qué se lleva en esta parte, en una línea.
  String _detalle(ParteEntrega p, EstadoDeUnaParte e) {
    if (p == ParteEntrega.generales) {
      if (e.entregada) {
        return e.tramos.isEmpty
            ? 'Sin número'
            : 'Del ${TramoTalonario.legible(e.tramos)}';
      }
      if (e.leToca <= 0) return 'No lleva: las 8 de la mesa son con cena.';
      return 'Completan las 8 de la mesa del contrato.';
    }
    // Separados por un punto, como en VENDER: los nombres llevan coma
    // ("APELLIDO, NOMBRE"), y con comas no se podía contar cuántas pulseras eran
    // (revisión del 20-nov-2026).
    return EntregaPorPartes.quienesVanConCena(
      widget.alumno,
      e.entregada ? e.cantidad : e.leToca,
    );
  }

  Widget _parte(ParteEntrega p) {
    final e = _estado.parte(p);
    // La otra parte se llevó otra cuenta: entregar esta se pasaría de lo sin
    // cargo. Lo revisa el jefe (la misma regla que `EntregarParte`).
    final porLaOtra = EntregaPorPartes.frenoPorLaOtraParte(_estado, p);
    final verde = Colors.green.shade700;
    final cuantas = e.entregada ? e.cantidad : e.leToca;
    final Widget derecha;
    if (e.entregada) {
      derecha = _marca(
        '✓ Entregadas',
        verde,
        key: Key('entrega_hecha_${p.clave}'),
      );
    } else if (e.leToca <= 0) {
      derecha = Text('No lleva', style: _gris);
    } else if (_bloqueado || porLaOtra != null) {
      derecha = _marca('Pendiente', Colors.blueGrey.shade600, icono: Icons.schedule);
    } else if (_abierta == p) {
      derecha = const SizedBox.shrink();
    } else {
      derecha = FilledButton(
        key: Key('entrega_entregar_${p.clave}'),
        // Una a la vez: si estaba abierta la otra, se cierra (no se guardó nada).
        onPressed: () => setState(() => _abierta = p),
        child: const Text('ENTREGAR'),
      );
    }
    final anulada = !e.entregada && e.anulada;
    return Container(
      key: Key('entrega_parte_${p.clave}'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: e.entregada ? verde.withValues(alpha: 0.06) : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: e.entregada ? verde.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_titulo(p)} · $cuantas',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _detalle(p, e),
                      key: Key('entrega_detalle_${p.clave}'),
                      style: _gris,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              derecha,
            ],
          ),
          // Lo decía el formulario al abrirse, repitiendo el renglón: va acá,
          // como en VENDER.
          if (p == ParteEntrega.pulseras && !e.entregada && e.leToca - 1 > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tiene ${e.leToca - 1} acompañantes con cena (el máximo es 2): '
                'confirmalo con el jefe.',
                key: const Key('entrega_mas_de_dos'),
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
              key: Key('entrega_quien_${p.clave}'),
              style: const TextStyle(fontSize: 13),
            ),
            if (p == ParteEntrega.pulseras && e.menores10 > 0)
              Text('Menores de 10: ${e.menores10}', style: _gris),
            if (e.parentesco == ParentescoRetiro.otraPersona)
              Text(
                'Con autorización firmada. Motivo: ${e.otraPersonaMotivo ?? '-'}',
                style: _gris,
              ),
            if (e.cambioLaCuenta)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _cartel(
                  'Cambió la cuenta después de entregar',
                  'Hoy le corresponden ${e.leToca} y se llevó ${e.cantidad}. Para '
                      'darle lo que falta, ${widget.permisos.anular ? 'anulá' : 'el jefe anula'} '
                      'esta parte (motivo: qué cambió) y se vuelve a entregar.',
                  color: Colors.orange.shade800,
                ),
              ),
          ],
          if (porLaOtra != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _cartel(
                'Primero lo revisa el jefe',
                porLaOtra,
                color: Colors.orange.shade800,
              ),
            ),
          if (anulada)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_textoAnulada(e), style: _gris),
            ),
          if (_abierta == p && !e.entregada && !_bloqueado && porLaOtra == null) ...[
            const Divider(height: 20),
            FormularioEntregaParte(
              key: Key('formulario_${p.clave}'),
              alumno: widget.alumno,
              parte: p,
              cantidad: e.leToca,
              deOtros: p == ParteEntrega.generales ? widget.deOtros : const {},
              antes: LoDeAntes.de(
                parte: p,
                estado: e,
                retiro: widget.retiro,
                renglones: widget.renglones,
              ),
              alConfirmar: (datos) => Navigator.pop(context, EntregarUnaParte(datos)),
              alCancelar: () => setState(() => _abierta = null),
            ),
          ],
        ],
      ),
    );
  }

  String _textoAnulada(EstadoDeUnaParte e) =>
      'Tuvo una entrega anulada'
      '${e.anuladaAt == null ? '' : ' el ${ArTime.formatFechaHora(e.anuladaAt!)}'}'
      '${(e.anuladaPor ?? '').isEmpty ? '' : ' por ${e.anuladaPor}'}'
      '${(e.motivoAnulacion ?? '').isEmpty ? '' : ': ${e.motivoAnulacion}'}.';

  // ── Anular (solo el jefe) ──────────────────────────────────────────────

  List<Widget> _anular() {
    final entregadas = [
      for (final p in ParteEntrega.values)
        if (_estado.parte(p).entregada) p,
    ];
    if (entregadas.isEmpty) return const [];
    // Anular es solo del jefe. Sin modo jefe se ve apagado, con el motivo: así
    // quien entrega sabe que existe y a quién pedírselo.
    if (!widget.permisos.anular) {
      return [
        const SizedBox(height: 12),
        Row(
          children: [
            const OutlinedButton(
              key: Key('entrega_anular_apagado'),
              onPressed: null,
              child: Text('ANULAR ENTREGA'),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(kSoloEnModoJefe, style: _gris)),
          ],
        ),
      ];
    }
    if (!_anulando) {
      return [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('entrega_anular'),
            onPressed: () => setState(() {
              _anulando = true;
              _aAnular = entregadas.toSet();
              _abierta = null;
            }),
            icon: const Icon(Icons.undo),
            label: const Text('ANULAR ENTREGA'),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 12),
      Text('Qué se anula', style: _gris),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        children: [
          for (final p in entregadas)
            FilterChip(
              key: Key('entrega_anular_${p.clave}'),
              label: Text(_titulo(p)),
              selected: _aAnular.contains(p),
              onSelected: (si) => setState(() {
                _aAnular = {..._aAnular}..remove(p);
                if (si) _aAnular = {..._aAnular, p};
                _errorAnular = null;
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _motivoAnular,
        autofocus: true,
        decoration: _campo('Por qué se anula', error: _errorAnular),
        onChanged: (_) => setState(() => _errorAnular = null),
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: () => setState(() => _anulando = false),
            child: const Text('NO ANULAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (_aAnular.isEmpty) {
                setState(() => _errorAnular = 'Elegí qué se anula.');
                return;
              }
              if (_motivoAnular.text.trim().isEmpty) {
                setState(() => _errorAnular = 'Escribí el motivo.');
                return;
              }
              Navigator.pop(context, AnularEntrega(_aAnular, _motivoAnular.text));
            },
            child: Text(
              _aAnular.length == ParteEntrega.values.length
                  ? 'CONFIRMAR ANULACIÓN DE TODO'
                  : 'CONFIRMAR ANULACIÓN',
            ),
          ),
        ],
      ),
    ];
  }

  // ── Por qué no se le puede entregar ────────────────────────────────────

  List<Widget> _bloqueo() {
    final a = widget.alumno;
    final d = widget.deuda;
    final e = widget.entradas;
    final p = widget.permisos;
    // En el mostrador no se edita al alumno: lo revisa el jefe.
    final aviseAlJefe = p.editar ? '' : ' Pedile al jefe que lo revise.';
    final Widget cartel;
    var cobrar = false;
    var editar = false;
    switch (widget.bloqueo) {
      case BloqueoRetiro.debe:
        cobrar = p.cobrarAca;
        final partes = [
          if (d.saldoPagos > RetiroEntradas.margen || d.saldoFicha > RetiroEntradas.margen)
            'cuotas y extras ${(d.saldoPagos > d.saldoFicha ? d.saldoPagos : d.saldoFicha).toCurrency()}',
          if (d.mora > RetiroEntradas.margen) 'mora ${d.mora.toCurrency()}',
        ];
        cartel = _cartel(
          'Debe ${d.total.toCurrency()}',
          p.cobrarAca
              ? '${partes.join(' · ')}.\nHasta que pague todo no se entregan las '
                  'pulseras ni las generales. Si trae un comprobante, primero '
                  'cargá el pago en caja.'
              : '${partes.join(' · ')}.\nQue pase por caja a saldar todo; cuando '
                  'pague, la entrega se destraba sola.',
          color: Colors.red.shade700,
        );
      case BloqueoRetiro.cuentaNoCoincide:
        cobrar = p.cobrarAca &&
            (d.saldoPagos > RetiroEntradas.margen || d.mora > RetiroEntradas.margen);
        cartel = _cartel(
          'Revisá la cuenta antes de entregar',
          'La ficha dice que debe ${d.saldoFicha.toCurrency()} y los pagos dan '
              '${d.saldoPagos.toCurrency()}. Hasta aclararlo no se entregan las '
              'entradas: pedile al jefe que la revise.',
          color: Colors.red.shade700,
        );
      case BloqueoRetiro.sinMesa:
        cartel = _cartel(
          'No tiene mesa asignada',
          'Primero hay que sortear o asignarle su mesa: la entrada dice dónde '
              'sentarse.',
          color: Colors.orange.shade800,
        );
      case BloqueoRetiro.mesasNoCoinciden:
        editar = p.editar;
        cartel = _cartel(
          'Sus mesas no coinciden con su cuenta',
          '${SalonMesas.avisoMesas(a) ?? ''}. Revisalo antes de entregar: las '
              'entradas salen de las mesas que tiene.$aviseAlJefe',
          color: Colors.orange.shade800,
        );
      case BloqueoRetiro.noEntran:
        editar = p.editar;
        cartel = _cartel(
          'No entran',
          'Tiene ${e.vip} con cena y ${e.lugares} lugares. Revisá los '
              'acompañantes, o que sume una mesa o sillas extra.$aviseAlJefe',
          color: Colors.orange.shade800,
        );
      case BloqueoRetiro.ninguno:
        return const [];
    }
    return [
      cartel,
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (editar)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, const EditarAlumno()),
              child: const Text('EDITAR ALUMNO'),
            ),
          if (cobrar) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, const IrACobrar()),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('IR A COBRAR'),
            ),
          ],
          // El mostrador: con Cobros, a la caja sin el PIN; sin Cobros, la familia
          // va a pagar y queda en "En caja" hasta que el pago llegue.
          if (widget.bloqueo == BloqueoRetiro.debe && !p.cobrarAca) ...[
            if (p.pasarACaja) ...[
              OutlinedButton.icon(
                key: const Key('entrega_pasar_a_caja'),
                onPressed: () => Navigator.pop(context, const PasarACaja()),
                icon: const Icon(Icons.point_of_sale),
                label: const Text('PASAR A CAJA'),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              key: const Key('entrega_a_la_caja'),
              onPressed: () => Navigator.pop(context, const MandarACaja()),
              child: const Text('ENTENDIDO'),
            ),
          ] else if (!editar && !cobrar)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ENTENDIDO'),
            ),
        ],
      ),
    ];
  }

  // ── Lo de sus lugares adicionales (A PAGAR) ────────────────────────────

  /// "su mesa adicional", "sus 4 mesas adicionales y sus 2 sillas extra".
  static String _deDonde(ContratoAlumno a) {
    final mesas = SalonMesas.mesasExtra(a);
    final sillas = SalonMesas.sillasExtra(a);
    return [
      if (mesas == 1) 'su mesa adicional',
      if (mesas > 1) 'sus $mesas mesas adicionales',
      if (sillas == 1) 'su silla extra',
      if (sillas > 1) 'sus $sillas sillas extra',
    ].join(' y ');
  }

  /// Si se muestra lo de sus lugares adicionales: con lo sin cargo entregado,
  /// sin nada que lo frene, o si solo debe (lo que ya pagó entero se le vende
  /// igual, con la venta andando). Con las mesas mal cargadas no: la cuenta
  /// puede estar mal. **La misma regla que VENDER**
  /// (`APagarDeLaFamilia.seVendeCon`; revisión del 20-nov-2026).
  bool get _muestraLosLugares =>
      APagarDeLaFamilia.seVendeCon(
        // Con `debe`, [widget.bloqueo] tapa los otros frenos (sin mesa, las
        // mesas que no coinciden, no entran): se miran aparte, con el de la
        // venta (revisión del 20-nov-2026).
        widget.bloqueo == BloqueoRetiro.debe
            ? RetiroEntradas.bloqueoDeLaVenta(widget.alumno, widget.deuda)
            : widget.bloqueo,
        todoEntregado: _estado.todoEntregado,
      ) &&
      (_estado.todoEntregado ||
          widget.bloqueo != BloqueoRetiro.debe ||
          widget.venta != null);

  /// Las entradas de la mesa adicional y las sillas extra: no van sin cargo, se
  /// compran aparte. Con la venta de entradas andando (6.9.0), debajo cuántas
  /// ya compró, qué espera el pago y VENDERLE ESAS ENTRADAS, o quién se las
  /// vende.
  ///
  /// **El descuento es solo para lo que ya tenía al sorteo** (17-nov-2026): lo
  /// que agregó después paga el precio del día, sin descuento, y se dice acá
  /// mismo. **Se le vende solo lo que ya está pago entero** (20-nov-2026).
  List<Widget> _alCincuenta() {
    final a = widget.alumno;
    final e = widget.entradas;
    if (e.aComprar <= 0) return const [];
    final venta = widget.venta;
    final con = e.conDescuento;
    final sin = e.sinDescuento;
    final al = alPorcientoQuePaga(venta?.descuentoPct ?? 50);
    final todas = e.aComprar;
    final String texto;
    if (sin == 0) {
      texto = '${todas == 1 ? 'La entrada' : 'Las $todas entradas'} '
          'de ${_deDonde(a)} no ${todas == 1 ? 'va' : 'van'} sin cargo: '
          '${todas == 1 ? 'se compra' : 'se compran'} aparte, $al.';
    } else if (con == 0) {
      texto = '${todas == 1 ? 'La entrada' : 'Las $todas entradas'} '
          'de ${_deDonde(a)} no ${todas == 1 ? 'va' : 'van'} sin cargo. Lo agregó '
          'después del sorteo: ${todas == 1 ? 'paga' : 'pagan'} el precio del día, '
          'sin descuento.';
    } else {
      texto = 'Las $todas entradas de ${_deDonde(a)} no van sin cargo: $con '
          '${con == 1 ? 'se compra' : 'se compran'} aparte, $al, y $sin, de lo que '
          'agregó después del sorteo, ${sin == 1 ? 'paga' : 'pagan'} el precio '
          'del día, sin descuento.';
    }
    final l = venta?.lugares;
    final compradas = l == null ? 0 : l.compradas + l.sueltasCompradas;
    final quedan = l?.quedanTodas ?? 0;
    final esperan = l?.esperanElPago ?? 0;
    final aConfirmar = l?.textoAConfirmar;
    return [
      const SizedBox(height: 12),
      Text(
        key: const Key('entrega_al_cincuenta'),
        texto,
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.orange.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (venta != null) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              key: const Key('entrega_compro'),
              _loQueCompro(compradas: compradas, quedan: quedan, esperan: esperan),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            if (venta.puedeVender && quedan > 0)
              FilledButton.tonal(
                key: const Key('entrega_venderle'),
                onPressed: () => Navigator.pop(context, const VenderAlCincuenta()),
                child: const Text('VENDERLE ESAS ENTRADAS'),
              ),
          ],
        ),
        // Lo que espera el pago: "a confirmar", sin plata.
        if (aConfirmar != null)
          Text(
            aConfirmar,
            key: const Key('entrega_a_confirmar'),
            style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800),
          ),
        if (!venta.puedeVender && quedan > 0)
          Text(
            'Se las vende quien tiene la caja de entradas.',
            key: const Key('entrega_se_las_vende'),
            style: _gris,
          ),
      ],
    ];
  }

  /// "Ya compró 3: le quedan 5." Si lo que le falta espera el pago, lo dice:
  /// "Ya compró las 3." sonaba a que terminó, y le faltaban 5 de una mesa sin
  /// pagar (revisión del 20-nov-2026).
  static String _loQueCompro({
    required int compradas,
    required int quedan,
    required int esperan,
  }) {
    if (compradas == 0) return 'Todavía no compró ninguna.';
    if (quedan > 0) {
      return 'Ya compró $compradas: le ${quedan == 1 ? 'queda 1' : 'quedan $quedan'}.';
    }
    if (esperan > 0) {
      return 'Ya compró $compradas; ${esperan == 1 ? 'la otra espera' : 'las otras $esperan esperan'} '
          'que se pague en caja.';
    }
    return 'Ya compró ${compradas == 1 ? 'la suya' : 'las $compradas'}.';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alumno;
    final division = a.cursoDivision?.trim() ?? '';
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';
    final verde = Colors.green.shade700;
    final pulserasPendientes = _estado.pulseras.falta && !_bloqueado;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entregar entradas · ${division.isEmpty ? '' : '$division · '}mesa $mesa',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                Text(
                  a.nombreAlumno.trim(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_estado.todoEntregado)
                _marca(
                  '✓ Todo entregado',
                  verde,
                  icono: Icons.check_circle,
                  key: const Key('entrega_todo_entregado'),
                )
              else if (_bloqueado)
                ..._bloqueo()
              else
                _marca(
                  'Pagó todo: cuotas, extras y mora',
                  verde,
                  icono: Icons.check_circle,
                ),
              const SizedBox(height: 10),
              Text(
                'Sin cargo, por el contrato',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              _parte(ParteEntrega.pulseras),
              if (pulserasPendientes && widget.permisos.editar && _abierta == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, const EditarAlumno()),
                    child: const Text('Cambiar acompañantes'),
                  ),
                ),
              _parte(ParteEntrega.generales),
              ..._anular(),
              // Solo la mesa del contrato trae sus entradas sin cargo: las de la
              // mesa adicional y las sillas extra se compran aparte.
              if (_muestraLosLugares) ..._alCincuenta(),
            ],
          ),
        ),
      ),
    );
  }
}
