import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../repositories/revision_de_lugares_de_la_app.dart';
import '../services/lugares_al_sorteo.dart';
import '../services/revision_de_lugares.dart';

/// La lista de una fiesta **sorteada antes de la regla del descuento**
/// (17-nov-2026): qué mesas adicionales y sillas extra se agregaron después del
/// sorteo, según las huellas, para que el jefe la acepte. Se abre desde
/// PRECIOS. Devuelve true si algo quedó anotado (o ya lo estaba).
///
/// **Solo en modo jefe**, con doble llave: quien la abre ya preguntó, y
/// `_aceptar` vuelve sin guardar si `esRolJefeProvider` da falso
/// (`test/solo_modo_jefe_test.dart`).
Future<bool> mostrarRevisionDeLugares(
  BuildContext context, {
  required String eventoId,
  required String fiesta,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RevisionDeLugaresDialog(eventoId: eventoId, fiesta: fiesta),
    ) ??
    false;

class RevisionDeLugaresDialog extends ConsumerStatefulWidget {
  final String eventoId;
  final String fiesta;

  const RevisionDeLugaresDialog({
    super.key,
    required this.eventoId,
    required this.fiesta,
  });

  @override
  ConsumerState<RevisionDeLugaresDialog> createState() =>
      _RevisionDeLugaresDialogState();
}

class _RevisionDeLugaresDialogState
    extends ConsumerState<RevisionDeLugaresDialog> {
  ListaDeLugares? _lista;

  /// Los lugares que van sin descuento, al precio del día
  /// (`LugarEnDuda.clave`).
  Set<String> _tildados = {};
  bool _cargando = true;
  bool _guardando = false;

  /// Al releer, la fiesta ya no tenía nada para revisar: al cerrar, quien abrió
  /// tiene que volver a leer.
  bool _yaEstaba = false;
  String? _problema;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    ListaDeLugares? lista;
    String? problema;
    try {
      lista = await ref.read(revisionDeLugaresProvider).leer(widget.eventoId);
    } catch (_) {
      problema = 'No se pudo leer la lista. Cerrá y probá de nuevo.';
    }
    if (!mounted) return;
    setState(() {
      _lista = lista;
      _tildados = lista?.tildadosDeEntrada ?? {};
      _problema = problema;
      _cargando = false;
    });
  }

  /// La segunda llave: sin modo jefe no se guarda, aunque alguien llegue hasta
  /// acá con el botón apagado.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    setState(() => _problema = '$kSoloEnModoJefe: esta lista la acepta el jefe.');
    return true;
  }

  Future<void> _aceptar() async {
    if (_frenaSinModoJefe()) return;
    final lista = _lista;
    if (lista == null) return;
    setState(() {
      _guardando = true;
      _problema = null;
    });
    ResultadoDeAceptar resultado;
    ListaDeLugares? nueva;
    try {
      final r = await ref.read(revisionDeLugaresProvider).aceptar(
            widget.eventoId,
            mostrada: lista,
            pagaEntera: _tildados,
          );
      resultado = r.resultado;
      nueva = r.lista;
    } catch (_) {
      resultado = ResultadoDeAceptar.noSeGuardo;
    }
    if (!mounted) return;
    switch (resultado) {
      case ResultadoDeAceptar.aceptado:
        Navigator.pop(context, true);
      case ResultadoDeAceptar.yaNoHaceFalta:
        setState(() {
          _guardando = false;
          _lista = null;
          _yaEstaba = true;
        });
      case ResultadoDeAceptar.cambio:
        final antes = {for (final d in lista.enDuda) d.clave};
        setState(() {
          _guardando = false;
          _lista = nueva;
          // Lo que ya había decidido queda; lo nuevo entra como viene.
          _tildados = {
            for (final d in nueva?.enDuda ?? const <LugarEnDuda>[])
              if (antes.contains(d.clave)
                  ? _tildados.contains(d.clave)
                  : d.despues)
                d.clave,
          };
          _problema = 'La lista cambió mientras la mirabas: en otra PC se '
              'cargó algo. Revisala de nuevo y aceptá.';
        });
      case ResultadoDeAceptar.sinInternet:
        setState(() {
          _guardando = false;
          _problema = 'Para aceptar hace falta internet: la lista tiene que '
              'quedar igual en todas las PCs. No se guardó nada.';
        });
      case ResultadoDeAceptar.noSeGuardo:
        setState(() {
          _guardando = false;
          _problema = 'No se pudo guardar. Probá de nuevo.';
        });
    }
  }

  static String _entradas(int n) => n == 1 ? '1 entrada' : '$n entradas';

  Widget _renglon(LugarEnDuda d, bool esJefe) => CheckboxListTile(
        key: Key('revision_${d.clave}'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: _tildados.contains(d.clave),
        onChanged: !esJefe || _guardando
            ? null
            : (v) => setState(() {
                  _problema = null;
                  if (v ?? false) {
                    _tildados.add(d.clave);
                  } else {
                    _tildados.remove(d.clave);
                  }
                }),
        title: Text(
          '${d.nombre} · ${d.queEs} (${_entradas(d.entradas)})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(d.huellas.join('\n')),
      );

  List<Widget> _cuerpo(ListaDeLugares lista, bool esJefe, TextStyle ayuda) {
    final conHuella = [for (final d in lista.enDuda) if (d.despues) d];
    final paraRevisar = [for (final d in lista.enDuda) if (!d.despues) d];
    final total = lista.pagaEntera(_tildados);
    Widget titulo(String texto) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w800)),
        );
    return [
      Text(
        'El sorteo fue el ${ArTime.formatFechaHora(lista.sorteo.createdAt)}.',
        key: const Key('revision_sorteo'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        'El descuento vale para la mesa adicional y las sillas extra que cada '
        'familia ya tenía cargadas ese día, pagadas o no. Lo que se agregó '
        'después paga el precio del día, sin descuento.',
        style: ayuda,
      ),
      if (lista.enDuda.isEmpty)
        Padding(
          key: const Key('revision_sin_dudas'),
          padding: const EdgeInsets.only(top: 14),
          child: const Text(
            'No hay nada para revisar: todo lo que las familias tienen cargado '
            'ya estaba al sorteo.',
          ),
        ),
      if (conHuella.isNotEmpty) ...[
        titulo('Se agregaron después del sorteo'),
        Text(
          'Vienen tildados: pagan el precio del día, sin descuento. Destildá '
          'el que no corresponda.',
          style: ayuda,
        ),
        for (final d in conHuella) _renglon(d, esJefe),
      ],
      if (paraRevisar.isNotEmpty) ...[
        titulo('Para revisar'),
        Text(
          'No hay huella de cuándo se cargaron. Sin tildar quedan con '
          'descuento: tildá solo los que sepas que se agregaron después.',
          style: ayuda,
        ),
        for (final d in paraRevisar) _renglon(d, esJefe),
      ],
      const Divider(height: 28),
      Text(
        total.entradas == 0
            ? 'Nadie va sin descuento: todo lo cargado hoy queda con descuento.'
            : 'Sin descuento, al precio del día: ${_entradas(total.entradas)} de '
                '${total.familias == 1 ? '1 familia' : '${total.familias} familias'}. '
                'Lo demás queda con descuento.',
        key: const Key('revision_resumen'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        'Al aceptar queda fijo para esta fiesta, en todas las PCs. Lo que se '
        'agregue desde ahora paga el precio del día, sin descuento.',
        style: ayuda,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final esJefe = ref.watch(esRolJefeProvider);
    final gris = Theme.of(context).hintColor;
    final ayuda = TextStyle(fontSize: 12, color: gris);
    final lista = _lista;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lugares agregados después del sorteo'),
          Text(
            widget.fiesta,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: gris),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: _cargando
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lista != null)
                      ..._cuerpo(lista, esJefe, ayuda)
                    else if (_problema == null)
                      Text(
                        _yaEstaba
                            ? 'Esta fiesta ya no tiene nada para revisar: la '
                                'lista se aceptó desde otra PC, o el sorteo se '
                                'deshizo.'
                            : 'Esta fiesta no tiene nada para revisar.',
                        key: const Key('revision_nada'),
                      ),
                    if (_problema != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _problema!,
                          key: const Key('revision_problema'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('revision_cancelar'),
          onPressed:
              _guardando ? null : () => Navigator.pop(context, _yaEstaba),
          child: Text(lista == null ? 'CERRAR' : 'CANCELAR'),
        ),
        if (lista != null)
          Tooltip(
            message: esJefe ? 'Dejar la lista fija' : kSoloEnModoJefe,
            child: FilledButton(
              key: const Key('revision_aceptar'),
              onPressed: !esJefe || _guardando ? null : _aceptar,
              child: const Text('ACEPTAR'),
            ),
          ),
      ],
    );
  }
}
