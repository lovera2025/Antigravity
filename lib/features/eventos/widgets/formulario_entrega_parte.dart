import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import '../services/entrega_por_partes.dart';
import '../services/entregar_parte.dart';
import '../services/retiro_entradas.dart';

/// Lo que se llevó la última vez que se entregó esta parte, si después se
/// anuló: se ofrece para no volver a tipearlo. **El tilde de la planilla no**:
/// esa persona tiene que volver a escribir su nombre.
class LoDeAntes {
  final ParentescoRetiro? parentesco;
  final String nombre;
  final String motivo;
  final bool autorizacionFirmada;
  final int menores10;
  final List<TramoTalonario> tramos;

  const LoDeAntes({
    this.parentesco,
    this.nombre = '',
    this.motivo = '',
    this.autorizacionFirmada = false,
    this.menores10 = 0,
    this.tramos = const [],
  });

  /// De la última entrega de [parte] que quedó anulada: su renglón o, si fue
  /// una entrega de las 8 juntas (6.9.x) anulada, la fila de `entradas_retiro`.
  /// Null si la parte está entregada o nunca se entregó.
  static LoDeAntes? de({
    required ParteEntrega parte,
    required EstadoDeUnaParte estado,
    EntradasRetiro? retiro,
    List<EntregaEntradas> renglones = const [],
  }) {
    if (estado.entregada || !estado.anulada) return null;
    final entregas = [
      for (final r in renglones)
        if (r.parte == parte && r.esEntrega) r,
    ]..sort(EntregaEntradas.enOrden);
    if (entregas.isNotEmpty) {
      final r = entregas.last;
      return LoDeAntes(
        parentesco: r.parentesco,
        nombre: r.retiroNombre ?? '',
        motivo: r.otraPersonaMotivo ?? '',
        autorizacionFirmada: r.autorizacionFirmada,
        menores10: r.menores10,
        tramos: r.tramos,
      );
    }
    final f = retiro;
    if (f == null || f.entregado) return null;
    return LoDeAntes(
      parentesco: f.parentesco,
      nombre: f.retiroNombre ?? '',
      motivo: f.otraPersonaMotivo ?? '',
      autorizacionFirmada: f.autorizacionFirmada,
      menores10: f.menores10,
      tramos: parte == ParteEntrega.generales ? f.tramos : const [],
    );
  }
}

/// El formulario para entregar **una parte** de lo sin cargo de un egresado:
/// las pulseras VIP con cena, o las entradas generales que completan las 8 de
/// la mesa del contrato (20-nov-2026: cada una llega en su tanda).
///
/// - **Pulseras:** los menores de 10 y quién retira.
/// - **Generales:** "Vienen con número" (los números son opcionales: puede que
///   no vengan numeradas), con "del" y el "al" calculado, y quién retira.
///
/// **Cuántas y quiénes no las repite**: las dice el renglón de la parte, justo
/// arriba, en VENDER y en el diálogo (revisión del 20-nov-2026: se leían dos
/// veces seguidas y en el celular empujaban hacia abajo quién retira). La
/// cantidad no se elige: es [cantidad].
///
/// **No guarda nada**: con todo bien, llama a [alConfirmar] con lo elegido, y
/// quien lo usa lo guarda por `EntregarParte`. Lo usan el diálogo de la entrega
/// (ENTRADAS de la fiesta y el mostrador) y el bloque GRATIS de VENDER, adentro
/// de su tarjeta.
class FormularioEntregaParte extends StatefulWidget {
  const FormularioEntregaParte({
    super.key,
    required this.alumno,
    required this.parte,
    required this.cantidad,
    this.deOtros = const {},
    this.antes,
    this.ocupado = false,
    required this.alConfirmar,
    this.alCancelar,
  });

  final ContratoAlumno alumno;
  final ParteEntrega parte;

  /// Cuántas le corresponden hoy (`EstadoDeUnaParte.leToca`): no se elige.
  final int cantidad;

  /// Los números de las generales ya entregadas a las otras familias
  /// (`EntregaPorPartes.numerosDeOtros`): no se repiten. **No mira lo
  /// vendido**: es otro talonario.
  final Map<String, List<TramoTalonario>> deOtros;

  /// Lo de la última entrega anulada de esta parte, para no volver a tipearlo.
  final LoDeAntes? antes;

  /// Mientras se guarda: CONFIRMAR apagado.
  final bool ocupado;

  final ValueChanged<DatosDeLaParte> alConfirmar;
  final VoidCallback? alCancelar;

  @override
  State<FormularioEntregaParte> createState() => _FormularioEntregaParteState();
}

class _FormularioEntregaParteState extends State<FormularioEntregaParte> {
  final _desde1 = TextEditingController();
  final _hasta1 = TextEditingController();
  final _desde2 = TextEditingController();
  final _nombre = TextEditingController();
  final _motivo = TextEditingController();
  bool _conNumero = false;
  bool _dosTramos = false;
  int _menores = 0;
  ParentescoRetiro? _parentesco;
  bool _autorizacion = false;
  bool _escribio = false;
  String? _errorTramos;
  Map<String, String> _errores = const {};

  bool get _esGenerales => widget.parte == ParteEntrega.generales;
  String get _clave => widget.parte.clave;

  @override
  void initState() {
    super.initState();
    final a = widget.antes;
    if (a == null) return;
    _parentesco = a.parentesco;
    _nombre.text = a.nombre;
    _motivo.text = a.motivo;
    _autorizacion = a.autorizacionFirmada;
    if (!_esGenerales) _menores = a.menores10;
    if (_esGenerales && a.tramos.isNotEmpty) {
      // Tildado si ya vienen números escritos.
      _conNumero = true;
      _desde1.text = '${a.tramos.first.desde}';
      if (a.tramos.length > 1) {
        _dosTramos = true;
        _hasta1.text = '${a.tramos.first.hasta}';
        _desde2.text = '${a.tramos[1].desde}';
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_desde1, _hasta1, _desde2, _nombre, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Los tramos que salen de lo escrito, o `null` si falta un número.
  List<TramoTalonario>? _tramos() {
    final n = widget.cantidad;
    if (!_esGenerales || !_conNumero || n <= 0) return const [];
    final d1 = int.tryParse(_desde1.text.trim());
    if (d1 == null) return null;
    if (!_dosTramos) return [TramoTalonario(d1, d1 + n - 1)];
    final h1 = int.tryParse(_hasta1.text.trim());
    final d2 = int.tryParse(_desde2.text.trim());
    if (h1 == null || d2 == null || h1 < d1) return null;
    final resto = n - (h1 - d1 + 1);
    if (resto <= 0) return [TramoTalonario(d1, h1)];
    return [TramoTalonario(d1, h1), TramoTalonario(d2, d2 + resto - 1)];
  }

  void _confirmar() {
    final tramos = _tramos();
    final errorTramos = tramos == null
        ? 'Escribí los números del talonario, o destildá "Vienen con número".'
        : EntregaPorPartes.errorDeLosNumeros(
            parte: widget.parte,
            tramos: tramos,
            cantidad: widget.cantidad,
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
    widget.alConfirmar(
      DatosDeLaParte(
        parte: widget.parte,
        cantidad: widget.cantidad,
        tramos: tramos!,
        menores10: _esGenerales ? 0 : _menores,
        parentesco: _parentesco!,
        nombre: _nombre.text,
        motivo: _motivo.text,
        autorizacionFirmada: _autorizacion,
        escribioEnPlanilla: _escribio,
      ),
    );
  }

  // ── Piezas ───────────────────────────────────────────────────────────────

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

  TextStyle get _gris => TextStyle(fontSize: 12.5, color: Colors.grey.shade700);

  List<Widget> _numeros() {
    if (!_esGenerales || widget.cantidad <= 0) return const [];
    final tramos = _tramos();
    return [
      CheckboxListTile(
        key: const Key('entrega_con_numero'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _conNumero,
        onChanged: (v) => setState(() {
          _conNumero = v ?? false;
          _errorTramos = null;
        }),
        title: const Text('Vienen con número'),
        subtitle: const Text('Si no vienen numeradas, dejalo sin tildar.'),
      ),
      if (_conNumero) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _numero(_desde1, 'Del'),
            if (_dosTramos) _numero(_hasta1, 'Al'),
            if (!_dosTramos)
              Text(
                tramos == null || tramos.isEmpty ? 'al …' : 'al ${tramos.first.hasta}',
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
                tramos != null && tramos.length > 1 ? 'al ${tramos[1].hasta}' : 'al …',
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
            child: Text(_dosTramos ? 'Un solo tramo' : 'El talonario salta: dos tramos'),
          ),
        ),
      ],
      _error(_errorTramos),
    ];
  }

  List<Widget> _menoresDe10() {
    if (_esGenerales) return const [];
    return [
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
    ];
  }

  List<Widget> _quienRetira() => [
        Text('Quién retira', style: _gris),
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
          title: const Text('Escribió su nombre y apellido en la planilla de papel'),
          subtitle: Text(
            _esGenerales
                ? 'En la planilla de las generales. No se firma: se escribe el nombre.'
                : 'En la planilla de las pulseras. No se firma: se escribe el nombre.',
          ),
        ),
        _error(_errores['planilla']),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('entrega_formulario_$_clave'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._numeros(),
        ..._menoresDe10(),
        const SizedBox(height: 6),
        ..._quienRetira(),
        const SizedBox(height: 10),
        // En un celular, adentro de la tarjeta de VENDER, los dos botones pueden
        // no entrar lado a lado: van uno debajo del otro. Contra el borde derecho
        // (el ancho entero: si no, el Wrap mide lo que sus botones).
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.alCancelar != null)
                TextButton(
                  key: Key('entrega_cancelar_$_clave'),
                  onPressed: widget.ocupado ? null : widget.alCancelar,
                  child: const Text('CANCELAR'),
                ),
              FilledButton.icon(
                key: Key('entrega_confirmar_$_clave'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                onPressed: widget.ocupado ? null : _confirmar,
                icon: const Icon(Icons.check),
                label: const Text('CONFIRMAR'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
