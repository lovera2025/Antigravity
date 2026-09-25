import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../common/utils/currency_extensions.dart';
import '../services/retiro_entradas.dart';
import '../services/salon_mesas.dart';

/// Lo que eligió hacer quien atiende el mostrador.
sealed class AccionEntrega {
  const AccionEntrega();
}

class EntregarEntradas extends AccionEntrega {
  final List<TramoTalonario> tramos;
  final int menores10;
  final ParentescoRetiro parentesco;
  final String nombre;
  final String motivo;
  final bool autorizacionFirmada;

  const EntregarEntradas({
    required this.tramos,
    required this.menores10,
    required this.parentesco,
    required this.nombre,
    required this.motivo,
    required this.autorizacionFirmada,
  });
}

class AnularEntrega extends AccionEntrega {
  final String motivo;
  const AnularEntrega(this.motivo);
}

class IrACobrar extends AccionEntrega {
  const IrACobrar();
}

class EditarAlumno extends AccionEntrega {
  const EditarAlumno();
}

/// El diálogo del mostrador para un egresado: lo que se le entrega, a quién y
/// con qué números; por qué no se le puede entregar todavía; o lo que ya se
/// llevó, con la opción de anularlo.
///
/// No guarda nada: devuelve la [AccionEntrega] y la pantalla la aplica.
Future<AccionEntrega?> mostrarEntregaEntradasDialog({
  required BuildContext context,
  required ContratoAlumno alumno,
  required EntradasDeAlumno entradas,
  required DeudaAlumno deuda,
  required BloqueoRetiro bloqueo,
  EntradasRetiro? retiro,
  Map<String, List<TramoTalonario>> deOtros = const {},
}) =>
    showDialog<AccionEntrega>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EntregaDialog(
        alumno: alumno,
        entradas: entradas,
        deuda: deuda,
        bloqueo: bloqueo,
        retiro: retiro,
        deOtros: deOtros,
      ),
    );

class _EntregaDialog extends StatefulWidget {
  final ContratoAlumno alumno;
  final EntradasDeAlumno entradas;
  final DeudaAlumno deuda;
  final BloqueoRetiro bloqueo;
  final EntradasRetiro? retiro;
  final Map<String, List<TramoTalonario>> deOtros;

  const _EntregaDialog({
    required this.alumno,
    required this.entradas,
    required this.deuda,
    required this.bloqueo,
    required this.retiro,
    required this.deOtros,
  });

  @override
  State<_EntregaDialog> createState() => _EntregaDialogState();
}

class _EntregaDialogState extends State<_EntregaDialog> {
  final _desde1 = TextEditingController();
  final _hasta1 = TextEditingController();
  final _desde2 = TextEditingController();
  final _nombre = TextEditingController();
  final _motivo = TextEditingController();
  final _motivoAnular = TextEditingController();
  bool _dosTramos = false;
  int _menores = 0;
  ParentescoRetiro? _parentesco;
  bool _autorizacion = false;
  bool _escribio = false;
  bool _anulando = false;
  String? _errorTramos;
  Map<String, String> _errores = const {};
  String? _errorAnular;

  @override
  void initState() {
    super.initState();
    // Si tuvo una entrega anulada, se ofrece lo mismo para no volver a
    // tipearlo. El tilde de la planilla no: esa persona tiene que volver a
    // escribir su nombre.
    final r = widget.retiro;
    if (r != null && !r.entregado) {
      _menores = r.menores10;
      _parentesco = r.parentesco;
      _nombre.text = r.retiroNombre ?? '';
      _motivo.text = r.otraPersonaMotivo ?? '';
      _autorizacion = r.autorizacionFirmada;
      if (r.tramos.isNotEmpty) {
        _desde1.text = '${r.tramos.first.desde}';
        if (r.tramos.length > 1) {
          _dosTramos = true;
          _hasta1.text = '${r.tramos.first.hasta}';
          _desde2.text = '${r.tramos[1].desde}';
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_desde1, _hasta1, _desde2, _nombre, _motivo, _motivoAnular]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _generales => widget.entradas.generales;

  /// Los tramos que salen de lo escrito, o `null` si falta un número.
  List<TramoTalonario>? _tramos() {
    if (_generales == 0) return const [];
    final d1 = int.tryParse(_desde1.text.trim());
    if (d1 == null) return null;
    if (!_dosTramos) return [TramoTalonario(d1, d1 + _generales - 1)];
    final h1 = int.tryParse(_hasta1.text.trim());
    final d2 = int.tryParse(_desde2.text.trim());
    if (h1 == null || d2 == null || h1 < d1) return null;
    final resto = _generales - (h1 - d1 + 1);
    if (resto <= 0) return [TramoTalonario(d1, h1)];
    return [TramoTalonario(d1, h1), TramoTalonario(d2, d2 + resto - 1)];
  }

  void _confirmar() {
    final tramos = _tramos();
    final errorTramos = tramos == null
        ? 'Escribí los números del talonario.'
        : RetiroEntradas.errorTramos(
            tramos: tramos,
            generales: _generales,
            deOtros: widget.deOtros,
          );
    final errores = RetiroEntradas.erroresQuienRetira(
      parentesco: _parentesco,
      nombre: _nombre.text,
      motivo: _motivo.text,
      autorizacionFirmada: _autorizacion,
      escribioEnPlanilla: _escribio,
    );
    setState(() {
      _errorTramos = errorTramos;
      _errores = errores;
    });
    if (errorTramos != null || errores.isNotEmpty) return;
    Navigator.pop(
      context,
      EntregarEntradas(
        tramos: tramos!,
        menores10: _menores,
        parentesco: _parentesco!,
        nombre: _nombre.text,
        motivo: _motivo.text,
        autorizacionFirmada: _autorizacion,
      ),
    );
  }

  // ── Piezas ───────────────────────────────────────────────────────────────

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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(detalle, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
      );

  Widget _marca(String texto, Color color, {IconData? icono}) => Container(
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
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _error(String? texto) => texto == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );

  Widget _caja(String rotulo, String valor, String detalle) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text(
                valor,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(
                detalle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      );

  InputDecoration _campo(String etiqueta, {String? error}) => InputDecoration(
        labelText: etiqueta,
        errorText: error,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _numero(TextEditingController c, String etiqueta) => SizedBox(
        width: 110,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _campo(etiqueta),
          onChanged: (_) => setState(() => _errorTramos = null),
        ),
      );

  // ── Contenidos ───────────────────────────────────────────────────────────

  List<Widget> _yaRetiro(EntradasRetiro r) {
    final hoy = widget.entradas;
    final cambio = RetiroEntradas.cambioLaCuenta(r, hoy);
    return [
      _marca(
        'Retiró el ${r.entregadoAt == null ? '-' : ArTime.formatFechaHora(r.entregadoAt!)}',
        Colors.green.shade700,
        icono: Icons.check_circle,
      ),
      const SizedBox(height: 10),
      Text(
        '${r.parentesco?.etiqueta ?? 'Quien retiró'}: ${r.retiroNombre ?? '-'}\n'
        '${r.vip} VIP + '
        '${r.generales == 0 ? 'sin generales' : 'generales del ${TramoTalonario.legible(r.tramos)}'}\n'
        'Menores de 10: ${r.menores10}',
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
      if (r.parentesco == ParentescoRetiro.otraPersona)
        Text(
          'Con autorización firmada. Motivo: ${r.otraPersonaMotivo ?? '-'}',
          style: const TextStyle(fontSize: 13),
        ),
      Text(
        'Lo registró ${r.entregadoPor ?? '-'}. Escribió su nombre en la planilla.',
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
      ),
      if (cambio) ...[
        const SizedBox(height: 10),
        _cartel(
          'Cambió la cuenta después de entregar',
          'Hoy le corresponden ${hoy.vip} VIP y ${hoy.generales} generales; se '
              'llevó ${r.vip} VIP y ${r.generales} generales. Para darle lo que '
              'falta, anulá esta entrega (motivo: qué cambió) y volvé a '
              'entregar con todos los números.',
          color: Colors.orange.shade800,
        ),
      ],
      const SizedBox(height: 12),
      if (!_anulando)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _anulando = true),
            icon: const Icon(Icons.undo),
            label: const Text('ANULAR ENTREGA'),
          ),
        )
      else ...[
        TextField(
          controller: _motivoAnular,
          autofocus: true,
          decoration: _campo('Por qué se anula', error: _errorAnular),
          onChanged: (_) => setState(() => _errorAnular = null),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (_motivoAnular.text.trim().isEmpty) {
                setState(() => _errorAnular = 'Escribí el motivo.');
                return;
              }
              Navigator.pop(context, AnularEntrega(_motivoAnular.text));
            },
            child: const Text('CONFIRMAR ANULACIÓN'),
          ),
        ),
      ],
    ];
  }

  List<Widget> _bloqueado() {
    final a = widget.alumno;
    final d = widget.deuda;
    final e = widget.entradas;
    final Widget cartel;
    var cobrar = false;
    var editar = false;
    switch (widget.bloqueo) {
      case BloqueoRetiro.debe:
        cobrar = true;
        final partes = [
          if (d.saldoPagos > RetiroEntradas.margen ||
              d.saldoFicha > RetiroEntradas.margen)
            'cuotas y extras ${(d.saldoPagos > d.saldoFicha ? d.saldoPagos : d.saldoFicha).toCurrency()}',
          if (d.mora > RetiroEntradas.margen) 'mora ${d.mora.toCurrency()}',
        ];
        cartel = _cartel(
          'Debe ${d.total.toCurrency()}',
          '${partes.join(' · ')}.\nHasta que pague todo no se entregan las '
              'entradas. Si trae un comprobante, primero cargá el pago en caja.',
          color: Colors.red.shade700,
        );
      case BloqueoRetiro.cuentaNoCoincide:
        cobrar = d.saldoPagos > RetiroEntradas.margen || d.mora > RetiroEntradas.margen;
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
        editar = true;
        cartel = _cartel(
          'Sus mesas no coinciden con su cuenta',
          '${SalonMesas.avisoMesas(a) ?? ''}. Revisalo antes de entregar: las '
              'entradas salen de las mesas que tiene.',
          color: Colors.orange.shade800,
        );
      case BloqueoRetiro.noEntran:
        editar = true;
        cartel = _cartel(
          'No entran',
          'Tiene ${e.vip} con cena y ${e.lugares} lugares. Revisá los '
              'acompañantes, o que sume una mesa o sillas extra.',
          color: Colors.orange.shade800,
        );
      case BloqueoRetiro.ninguno:
        cartel = const SizedBox.shrink();
    }
    final anulada = widget.retiro;
    return [
      cartel,
      if (anulada != null && !anulada.entregado) ...[
        const SizedBox(height: 8),
        Text(
          _textoAnulada(anulada),
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
      ],
      const SizedBox(height: 12),
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
        ],
      ),
    ];
  }

  String _textoAnulada(EntradasRetiro r) =>
      'Tuvo una entrega anulada'
      '${r.anuladoAt == null ? '' : ' el ${ArTime.formatFechaHora(r.anuladoAt!)}'}'
      '${r.anuladoPor == null ? '' : ' por ${r.anuladoPor}'}'
      '${(r.anuladoMotivo ?? '').isEmpty ? '' : ': ${r.anuladoMotivo}'}.';

  List<Widget> _formulario() {
    final a = widget.alumno;
    final e = widget.entradas;
    final tramos = _tramos();
    final acompanantes = [
      for (final n in a.nombresAcompanantes)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    final cantidadAcomp = e.vip - 1;
    final anulada = widget.retiro;
    return [
      _marca(
        'Pagó todo: cuotas, extras y mora',
        Colors.green.shade700,
        icono: Icons.check_circle,
      ),
      if (anulada != null && !anulada.entregado) ...[
        const SizedBox(height: 6),
        Text(
          '${_textoAnulada(anulada)} Se cargó lo de esa vez: revisalo.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          _caja(
            'VIP con cena',
            '${e.vip}',
            cantidadAcomp == 0
                ? 'solo el egresado'
                : [
                    'el egresado',
                    ...acompanantes,
                    if (acompanantes.length < cantidadAcomp)
                      '${cantidadAcomp - acompanantes.length} sin nombre',
                  ].join(', '),
          ),
          const SizedBox(width: 8),
          _caja(
            'Generales',
            '${e.generales}',
            'del talonario, con número',
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => Navigator.pop(context, const EditarAlumno()),
          child: const Text('Cambiar acompañantes'),
        ),
      ),
      if (cantidadAcomp > 2)
        Text(
          'Tiene $cantidadAcomp acompañantes con cena (el máximo es 2): '
          'confirmalo con el jefe.',
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.orange.shade800,
            fontWeight: FontWeight.w600,
          ),
        ),
      if (_generales > 0) ...[
        const SizedBox(height: 6),
        Text(
          'Números del talonario',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _numero(_desde1, 'Del'),
            if (_dosTramos) _numero(_hasta1, 'Al'),
            if (!_dosTramos)
              Text(
                tramos == null || tramos.isEmpty
                    ? 'al …'
                    : 'al ${tramos.first.hasta}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        if (_dosTramos) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _numero(_desde2, 'Del'),
              Text(
                tramos != null && tramos.length > 1
                    ? 'al ${tramos[1].hasta}'
                    : 'al …',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() {
              _dosTramos = !_dosTramos;
              _errorTramos = null;
            }),
            child: Text(
              _dosTramos
                  ? 'Un solo tramo'
                  : 'El talonario salta: dos tramos',
            ),
          ),
        ),
        _error(_errorTramos),
      ],
      const SizedBox(height: 6),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Menores de 10 (no llevan entrada)',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
          IconButton(
            tooltip: 'Uno menos',
            onPressed: _menores == 0 ? null : () => setState(() => _menores--),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$_menores',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Uno más',
            onPressed: () => setState(() => _menores++),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Quién retira',
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in ParentescoRetiro.values)
            ChoiceChip(
              label: Text(p.etiqueta),
              selected: _parentesco == p,
              onSelected: (_) => setState(() {
                _parentesco = p;
                _errores = const {};
              }),
            ),
        ],
      ),
      _error(_errores['parentesco']),
      const SizedBox(height: 10),
      TextField(
        controller: _nombre,
        textCapitalization: TextCapitalization.words,
        decoration: _campo(
          'Nombre y apellido de quien retira',
          error: _errores['nombre'],
        ),
      ),
      if (_parentesco == ParentescoRetiro.otraPersona) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _motivo,
          decoration: _campo(
            'Motivo: por qué no viene un familiar directo',
            error: _errores['motivo'],
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _autorizacion,
          onChanged: (v) => setState(() => _autorizacion = v ?? false),
          title: const Text('Trajo la autorización firmada por la familia'),
        ),
        _error(_errores['autorizacion']),
      ],
      const SizedBox(height: 6),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _escribio,
        onChanged: (v) => setState(() => _escribio = v ?? false),
        title: const Text(
          'Escribió su nombre y apellido en la planilla de papel',
        ),
        subtitle: const Text('No se firma: se escribe el nombre.'),
      ),
      _error(_errores['planilla']),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alumno;
    final r = widget.retiro;
    final yaRetiro = r != null && r.entregado;
    final bloqueado = !yaRetiro && widget.bloqueo != BloqueoRetiro.ninguno;
    final division = a.cursoDivision?.trim() ?? '';
    final mesa = SalonMesas.textoMesasPuerta(a) ?? 'sin mesa';

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
            children: yaRetiro
                ? _yaRetiro(r)
                : bloqueado
                    ? _bloqueado()
                    : _formulario(),
          ),
        ),
      ),
      actions: yaRetiro || bloqueado
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton.icon(
                onPressed: _confirmar,
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('CONFIRMAR ENTREGA'),
              ),
            ],
    );
  }
}
