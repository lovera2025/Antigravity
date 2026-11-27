import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/providers/admin_provider.dart';

/// **La notebook de la barra, a la vista de todos** (27-nov-2026, pedido del usuario): la
/// notebook del jefe queda toda la noche con la central prendida y la pantalla abierta, y
/// cualquiera que pasaba podía hacer clic y mirar las cajas.
///
/// Queda en **la vista simple**: solo la central (PRENDER / APAGAR, las cajas conectadas,
/// si está todo subido). Lo del jefe (las cajas con la plata, el catálogo, los precios,
/// GANANCIA) aparece **manteniendo apretado el logo de arriba** y escribiendo **la clave
/// de esa notebook**: la que ese aparato ya tiene para el modo jefe, no una nueva.
///
/// Es un freno para el que pasa y hace clic. La central no se entera: sigue andando.

/// Cuánto hay que mantener apretado el logo.
const kApretarElLogo = Duration(seconds: 2);

/// Sin tocar la notebook ese tiempo, con la central prendida, vuelve a la vista simple.
const kVistaSimpleSinUso = Duration(minutes: 2);

/// Los tests lo acortan.
final esperaParaLaVistaSimpleProvider = Provider<Duration>((ref) => kVistaSimpleSinUso);

/// Si lo escrito es **la clave de este aparato** (el PIN del modo jefe de esta notebook;
/// se cambia donde siempre). Los tests lo reemplazan.
final esLaClaveDeEstaNotebookProvider = Provider<Future<bool> Function(String)>((ref) => (escrita) async {
      final clave = escrita.trim();
      if (clave.isEmpty) return false;
      return clave == (await ref.read(adminAuthProvider.notifier).pinMaestroDeEstaPc()).trim();
    });

const _preferencia = 'barra_notebook_vuelve_sola_v1';

/// "Se bloquea sola": si la notebook vuelve a la vista simple cuando nadie la toca. **Viene
/// apagado** (el usuario, 27-nov-2026: "que haya una opción para activar esa seguridad,
/// porque si no el jefe va a estar a cada rato después de las fiestas"): el jefe lo prende
/// desde el candado o al desbloquear, y se recuerda en este equipo.
class VuelveSolaALaVistaSimple extends Notifier<bool> {
  @override
  bool build() {
    _leer();
    return false;
  }

  Future<void> _leer() async {
    try {
      final guardado = (await SharedPreferences.getInstance()).getBool(_preferencia);
      if (guardado != null && ref.mounted) state = guardado;
    } catch (_) {
      // Sin preferencias queda apagado, como viene.
    }
  }

  Future<void> poner(bool valor) async {
    state = valor;
    await (await SharedPreferences.getInstance()).setBool(_preferencia, valor);
  }
}

final vuelveSolaALaVistaSimpleProvider =
    NotifierProvider<VuelveSolaALaVistaSimple, bool>(VuelveSolaALaVistaSimple.new);

/// El cartel que abre el logo: la clave de la notebook y, con la clave bien, ENTRAR y si
/// se bloquea sola. Devuelve true si entró.
class ClaveDeLaNotebookDialog extends ConsumerStatefulWidget {
  const ClaveDeLaNotebookDialog({super.key});

  @override
  ConsumerState<ClaveDeLaNotebookDialog> createState() => _ClaveDeLaNotebookDialogState();
}

class _ClaveDeLaNotebookDialogState extends ConsumerState<ClaveDeLaNotebookDialog> {
  final _clave = TextEditingController();
  String? _error;
  bool _comprobando = false;
  bool _pasoLaClave = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _comprobar() async {
    if (_comprobando) return;
    setState(() => _comprobando = true);
    final bien = await ref.read(esLaClaveDeEstaNotebookProvider)(_clave.text);
    if (!mounted) return;
    setState(() {
      _comprobando = false;
      _pasoLaClave = bien;
      _error = bien ? null : 'Esa no es la clave de esta notebook.';
      if (!bien) _clave.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_pasoLaClave) {
      final vuelveSola = ref.watch(vuelveSolaALaVistaSimpleProvider);
      return AlertDialog(
        title: const Text('La notebook de la barra'),
        content: SizedBox(
          width: 380,
          child: SwitchListTile(
            key: const Key('notebook_se_bloquea_sola'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Se bloquea sola'),
            subtitle: Text(
              vuelveSola
                  ? 'A los ${kVistaSimpleSinUso.inMinutes} minutos sin tocarla, con la central prendida, '
                      'queda solo la central a la vista.'
                  : 'Queda abierta hasta que toques el candado de arriba.',
            ),
            value: vuelveSola,
            onChanged: (v) => ref.read(vuelveSolaALaVistaSimpleProvider.notifier).poner(v),
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('notebook_entrar'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ENTRAR'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('La clave de esta notebook'),
      content: SizedBox(
        width: 320,
        child: TextField(
          key: const Key('notebook_clave'),
          controller: _clave,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(errorText: _error, border: const OutlineInputBorder()),
          onSubmitted: (_) => _comprobar(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('VOLVER')),
        FilledButton(
          key: const Key('notebook_clave_listo'),
          onPressed: _comprobando ? null : _comprobar,
          child: const Text('LISTO'),
        ),
      ],
    );
  }
}
