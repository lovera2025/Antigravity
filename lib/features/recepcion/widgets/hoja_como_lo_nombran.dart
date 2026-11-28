import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../central/pedidos_de_la_puerta.dart' show horaCorta;
import '../providers/acciones_puerta_provider.dart' show ResultadoNombres;
import '../services/como_lo_nombran.dart';

const _perla = Color(0xFFE2E2E2);
const _ambar = Color(0xFFF2B84B);

TextStyle _letra(BuildContext context, {double size = 14, bool negrita = false, Color? color}) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  return GoogleFonts.outfit(
    fontSize: size,
    fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
    color: color ?? (oscuro ? _perla : Colors.black87),
  );
}

Color _suave(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54;

/// **CÓMO LO NOMBRAN** (el locutor, v85, 28-nov-2026): la recepcionista cambia cómo
/// nombrar al egresado y a sus acompañantes ("Juani 'el Tano' Pérez"). **La ficha de la
/// oficina no cambia.** Lo lee el locutor y lo muestra la tele del salón.
///
/// Sin providers adentro (va igual en la PC y en el celular): recibe cómo está
/// ([nombres]), si se puede guardar ([porQueNo]) y el guardado ([guardar]), que pasa por el
/// candado de la puerta. Si otro lo cambió mientras se editaba, muestra cómo quedó sin
/// borrar lo escrito, y GUARDAR otra vez deja lo suyo, ya a sabiendas. Devuelve lo que
/// hay que decir en el panel (null si se cerró sin guardar).
class HojaComoLoNombran extends StatefulWidget {
  const HojaComoLoNombran({
    super.key,
    required this.nombres,
    required this.guardar,
    this.porQueNo,
  });

  final NombresDeLaFamilia nombres;
  final Future<ResultadoNombres> Function(DatosNombres datos, String id) guardar;
  final String? porQueNo;

  static Future<String?> abrir(
    BuildContext context, {
    required NombresDeLaFamilia nombres,
    required Future<ResultadoNombres> Function(DatosNombres datos, String id) guardar,
    String? porQueNo,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => HojaComoLoNombran(nombres: nombres, guardar: guardar, porQueNo: porQueNo),
      );

  @override
  State<HojaComoLoNombran> createState() => _HojaComoLoNombranState();
}

class _HojaComoLoNombranState extends State<HojaComoLoNombran> {
  late NombresDeLaFamilia _ahora = widget.nombres;
  late final TextEditingController _alumno = TextEditingController(text: widget.nombres.alumno ?? '');
  late final Map<int, TextEditingController> _lugares = {
    for (final l in widget.nombres.lugares) l.lugar: TextEditingController(text: widget.nombres.porLugar[l.lugar] ?? ''),
  };
  final _focos = <Object, FocusNode>{};
  var _guardando = false;
  String? _aviso;
  var _avisoEsError = false;

  /// El pedido que no tuvo respuesta: si se reintenta con lo mismo, va con el mismo id.
  (DatosNombres, String)? _sinRespuesta;

  FocusNode _foco(Object clave) => _focos[clave] ??= FocusNode();

  @override
  void dispose() {
    _alumno.dispose();
    for (final c in _lugares.values) {
      c.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  DatosNombres _datos() => DatosNombres(
        alumno: _alumno.text,
        lugares: {
          for (final e in _lugares.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text,
        },
        antes: _ahora.firma,
      );

  Future<void> _guardar() async {
    if (_guardando) return;
    final datos = _datos();
    final previo = _sinRespuesta;
    final id = previo != null && previo.$1 == datos ? previo.$2 : const Uuid().v4();
    setState(() {
      _guardando = true;
      _aviso = null;
    });
    final r = await widget.guardar(datos, id);
    if (!mounted) return;
    if (r.hecho) {
      Navigator.pop(context, r.texto);
      return;
    }
    setState(() {
      _guardando = false;
      _sinRespuesta = r.sinRespuesta ? (datos, id) : null;
      _aviso = r.texto;
      _avisoEsError = !r.conflicto;
      // Otro lo cambió recién: se toma su firma (GUARDAR de nuevo deja lo de acá, ya
      // a sabiendas) y lo escrito no se toca.
      if (r.conflicto && r.nombres != null) _ahora = r.nombres!;
    });
  }

  Widget _campo({
    required Object clave,
    required TextEditingController ctrl,
    required String etiqueta,
    required String pista,
    String? ahora,
  }) {
    final foco = _foco(clave);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        key: ValueKey('nombrar_$clave'),
        controller: ctrl,
        focusNode: foco,
        maxLength: kTopeNombre,
        enabled: widget.porQueNo == null && !_guardando,
        textCapitalization: TextCapitalization.words,
        style: _letra(context, size: 15),
        onChanged: (_) => setState(() {}),
        // En la web de un celular, soltar el teclado al apoyar el dedo afuera se come el
        // toque: se suelta al levantarlo (como en SUMAR SILLA).
        onTapOutside: kIsWeb ? (_) {} : null,
        onTapUpOutside: kIsWeb ? (_) => foco.unfocus() : null,
        decoration: InputDecoration(
          labelText: etiqueta,
          labelStyle: _letra(context, size: 14, color: _suave(context)),
          hintText: pista,
          hintStyle: _letra(context, size: 14, color: _suave(context)),
          helperText: ahora,
          helperStyle: _letra(context, size: 12, color: _ambar),
          counterStyle: _letra(context, size: 11, color: _suave(context)),
          border: const OutlineInputBorder(),
          suffixIcon: ctrl.text.isEmpty
              ? null
              : IconButton(
                  key: ValueKey('nombrar_volver_$clave'),
                  tooltip: 'Como en la lista',
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  onPressed: () => setState(ctrl.clear),
                ),
        ),
      ),
    );
  }

  /// Lo que dice ahora la central, si es distinto de lo escrito (después de un
  /// conflicto): "Ahora dice: Juani".
  String? _ahoraDice(String? guardado, String escrito) {
    if (_aviso == null || _avisoEsError) return null;
    final g = (guardado ?? '').trim();
    if (g == escrito.trim()) return null;
    return g.isEmpty ? 'Ahora dice: como en la lista' : 'Ahora dice: $g';
  }

  @override
  Widget build(BuildContext context) {
    final n = _ahora;
    final cuando = n.cambiadoAt == null ? null : DateTime.tryParse(n.cambiadoAt!);
    return AlertDialog(
      title: Text('Cómo lo nombran', style: _letra(context, size: 18, negrita: true)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lo lee el locutor y lo muestra la tele del salón. La ficha de la oficina no cambia. '
                'Vacío: como en la lista.',
                key: const Key('nombrar_aviso_tele'),
                style: _letra(context, size: 13, color: _suave(context)),
              ),
              if (n.cambiadoPor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Lo cambió ${n.cambiadoPor}${cuando == null ? '' : ' a las ${horaCorta(cuando)}'}.',
                    key: const Key('nombrar_quien'),
                    style: _letra(context, size: 12, color: _suave(context)),
                  ),
                ),
              _campo(
                clave: 'alumno',
                ctrl: _alumno,
                etiqueta: n.alumnoCargado,
                pista: deCorrido(n.alumnoCargado),
                ahora: _ahoraDice(n.alumno, _alumno.text),
              ),
              for (final l in n.lugares)
                _campo(
                  clave: l.lugar,
                  ctrl: _lugares[l.lugar]!,
                  etiqueta: l.sinNombre ? 'Acompañante ${l.lugar} · sin nombre en la lista' : l.cargado,
                  pista: l.sinNombre ? 'Cómo lo nombran' : deCorrido(l.cargado),
                  ahora: _ahoraDice(n.porLugar[l.lugar], _lugares[l.lugar]!.text),
                ),
              if (n.sobrantes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Ya no corresponde${n.sobrantes.length == 1 ? '' : 'n'} (cambió la lista): '
                    '${n.sobrantes.join(' · ')}. Se descarta al guardar.',
                    key: const Key('nombrar_sobrantes'),
                    style: _letra(context, size: 12, color: _ambar),
                  ),
                ),
              if (widget.porQueNo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.porQueNo!,
                    key: const Key('nombrar_por_que_no'),
                    style: _letra(context, size: 13, negrita: true, color: _ambar),
                  ),
                ),
              if (_aviso != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _aviso!,
                    key: const Key('nombrar_resultado'),
                    style: _letra(
                      context,
                      size: 13,
                      negrita: true,
                      color: _avisoEsError ? Theme.of(context).colorScheme.error : _ambar,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('nombrar_cancelar'),
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: Text('CANCELAR', style: _letra(context, size: 13, negrita: true)),
        ),
        FilledButton(
          key: const Key('nombrar_guardar'),
          onPressed: widget.porQueNo != null || _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('GUARDAR'),
        ),
      ],
    );
  }
}
