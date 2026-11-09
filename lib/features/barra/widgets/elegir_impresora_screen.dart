import 'dart:async';

import 'package:flutter/material.dart';

import '../impresion/canal_ble.dart';
import '../impresion/impresora_bluetooth.dart';
import '../impresion/modelo_ticket.dart';
import '../impresion/ticket_esc_pos.dart' show finDelId;
import '../services/papel_de_la_barra.dart';

/// Elegir la impresora de este equipo, una sola vez: se busca por Bluetooth, se toca
/// CONECTAR y queda recordada (después se conecta sola). CAMBIAR la olvida.
///
/// Desde la 6.4.0, además: **IMPRIMIR UNA PRUEBA** (ver que anda sin cargar una venta que
/// nadie compró) y **el nombre de cada impresora** (las cuatro TP-POS58 se llaman igual:
/// "Impresora caja 1"), guardado en este equipo. En la lista, cada una muestra el final
/// de su id, el de la etiqueta de abajo.
class ElegirImpresoraScreen extends StatefulWidget {
  final ImpresoraBluetooth impresora;

  /// Por dónde sale la prueba. Sin esto, la misma impresora ([PapelPorBluetooth]).
  final PapelDeLaBarra? papel;

  /// La hora del papel de prueba. Para los tests.
  final DateTime Function() ahora;

  const ElegirImpresoraScreen({
    super.key,
    required this.impresora,
    this.papel,
    this.ahora = DateTime.now,
  });

  @override
  State<ElegirImpresoraScreen> createState() => _ElegirImpresoraScreenState();
}

/// El nombre de una impresora. El texto vive con el diálogo: si se soltaba al cerrarlo,
/// la animación de salida todavía lo usaba.
class _NombreDeLaImpresora extends StatefulWidget {
  final String actual;

  const _NombreDeLaImpresora({required this.actual});

  @override
  State<_NombreDeLaImpresora> createState() => _NombreDeLaImpresoraState();
}

class _NombreDeLaImpresoraState extends State<_NombreDeLaImpresora> {
  late final _texto = TextEditingController(text: widget.actual);

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('El nombre de esta impresora'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Las impresoras se llaman todas igual. Ponele uno que diga cuál es, el mismo que '
            'en una etiqueta pegada. Queda en este equipo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('impresora_nombre_texto'),
            controller: _texto,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Impresora caja 1'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(
          key: const Key('impresora_nombre_guardar'),
          onPressed: () => Navigator.pop(context, _texto.text),
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }
}

/// Lo que dice la pantalla después de IMPRIMIR UNA PRUEBA.
const kSalioLaPrueba =
    'Salió la prueba. Mirá el papel: si se leen los acentos y la regla entra justa en un renglón, '
    'la impresora anda.';
const kNoSalioLaPrueba = 'No salió. ¿La impresora está prendida y cerca?';

class _ElegirImpresoraScreenState extends State<ElegirImpresoraScreen> {
  final _encontrados = <String, DispositivoBle>{};
  StreamSubscription<DispositivoBle>? _busqueda;
  Timer? _fin;
  ImpresoraElegida? _elegida;
  Map<String, String> _apodos = const {};
  bool _buscando = false;
  bool _ocupado = false;
  String? _aviso;

  /// Lo que pasó con la prueba: null sin probar.
  ({String texto, bool bien})? _prueba;
  bool _probando = false;

  late final PapelDeLaBarra _papel = widget.papel ?? PapelPorBluetooth(widget.impresora);

  @override
  void initState() {
    super.initState();
    unawaited(_empezar());
  }

  @override
  void dispose() {
    _fin?.cancel();
    unawaited(_busqueda?.cancel());
    super.dispose();
  }

  Future<void> _empezar() async {
    final elegida = await widget.impresora.elegida();
    final apodos = await widget.impresora.apodos();
    if (!mounted) return;
    setState(() {
      _elegida = elegida;
      _apodos = apodos;
    });
    if (elegida == null) await _buscar();
  }

  /// "Impresora caja 1" si se lo pusieron; si no, el nombre del aparato.
  String _nombre(String id, String delAparato) =>
      _apodos[id] ?? (delAparato.isEmpty ? 'Sin nombre' : delAparato);

  Future<void> _ponerNombre(ImpresoraElegida elegida) async {
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => _NombreDeLaImpresora(actual: _apodos[elegida.id] ?? ''),
    );
    if (nuevo == null) return;
    await widget.impresora.ponerApodo(elegida.id, nuevo);
    final apodos = await widget.impresora.apodos();
    if (mounted) setState(() => _apodos = apodos);
  }

  /// IMPRIMIR UNA PRUEBA: un papel corto que no es una venta. Pasa por la pregunta del
  /// papel como cualquier otro.
  Future<void> _probar(ImpresoraElegida elegida) async {
    if (_probando) return;
    setState(() {
      _probando = true;
      _prueba = null;
    });
    var salio = false;
    try {
      await _papel.preparar();
      salio = await _papel.imprimir(ModeloTicket.dePrueba(
        nombre: _apodos[elegida.id] ?? '',
        id: elegida.id,
        ahora: widget.ahora(),
      ));
    } catch (_) {
      salio = false;
    }
    if (!mounted) return;
    setState(() {
      _probando = false;
      _prueba = salio
          ? (texto: kSalioLaPrueba, bien: true)
          : (texto: siNoSalio(_papel, kNoSalioLaPrueba), bien: false);
    });
  }

  Future<void> _buscar() async {
    final canal = widget.impresora.canal;
    setState(() {
      _buscando = true;
      _aviso = null;
    });
    try {
      await canal.pedirPermisos();
      final ya = await canal.emparejados();
      if (!mounted) return;
      setState(() {
        for (final d in ya) {
          _encontrados[d.id] = d;
        }
      });
      _cortarBusqueda();
      _busqueda = canal.buscar().listen(
            (d) {
              if (mounted && !(_encontrados[d.id]?.emparejado ?? false)) {
                setState(() => _encontrados[d.id] = d);
              }
            },
            onError: (Object _) {},
          );
      _fin?.cancel();
      _fin = Timer(const Duration(seconds: 10), () {
        _cortarBusqueda();
        if (mounted) setState(() => _buscando = false);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _buscando = false;
          _aviso = 'No se pudo buscar: ¿está prendido el Bluetooth?';
        });
      }
    }
  }

  /// Deja de escuchar la búsqueda, sin esperar a que el Bluetooth conteste: lo que
  /// sigue (apagar la ruedita, conectar) no depende de eso.
  void _cortarBusqueda() {
    final b = _busqueda;
    _busqueda = null;
    if (b != null) unawaited(b.cancel());
  }

  Future<void> _conectar(DispositivoBle d) async {
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    _cortarBusqueda();
    var ok = false;
    try {
      ok = await widget.impresora.conectar(d.id, nombre: d.nombre);
    } catch (_) {}
    final elegida = ok ? await widget.impresora.elegida() : null;
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _buscando = false;
      _prueba = null;
      if (ok) {
        _elegida = elegida;
      } else {
        _aviso = 'No se conectó a ${_nombre(d.id, d.nombre)}. ¿Está prendida y cerca?';
      }
    });
  }

  Future<void> _cambiar() async {
    await widget.impresora.olvidar();
    if (!mounted) return;
    setState(() {
      _elegida = null;
      _prueba = null;
    });
    await _buscar();
  }

  List<DispositivoBle> get _ordenados {
    final lista = _encontrados.values.toList();
    int peso(DispositivoBle d) => (pareceImpresora(d.nombre) ? 0 : 2) + (d.emparejado ? 0 : 1);
    lista.sort((a, b) {
      final p = peso(a).compareTo(peso(b));
      return p != 0 ? p : a.nombre.compareTo(b.nombre);
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final elegida = _elegida;
    return Scaffold(
      appBar: AppBar(title: const Text('La impresora de este equipo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (elegida != null) ...[
                Card(
                  child: ListTile(
                    leading: Icon(
                      widget.impresora.conectadaA == elegida.id ? Icons.print : Icons.print_outlined,
                      color: Colors.green.shade700,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _apodos[elegida.id] ??
                                (elegida.nombre.isEmpty ? 'La impresora de este equipo' : elegida.nombre),
                            key: const Key('impresora_elegida_nombre'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const Key('impresora_nombre'),
                          tooltip: 'Ponerle nombre',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: _ocupado ? null : () => _ponerNombre(elegida),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${elegida.nombre.isEmpty ? '' : '${elegida.nombre} · '}${finDelId(elegida.id)}'
                      ' · Queda recordada: se conecta sola cada vez.',
                    ),
                    trailing: TextButton(
                      key: const Key('impresora_cambiar'),
                      onPressed: _ocupado ? null : _cambiar,
                      child: const Text('CAMBIAR'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('impresora_probar'),
                      onPressed: _probando || _ocupado ? null : () => _probar(elegida),
                      icon: _probando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.receipt_outlined),
                      label: const Text('IMPRIMIR UNA PRUEBA'),
                    ),
                    const Text(
                      'Saca un papel corto para ver que anda. No es una venta: no cuenta en ninguna caja.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
                if (_prueba != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _prueba!.texto,
                      key: const Key('impresora_prueba_aviso'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _prueba!.bien
                            ? Colors.green.shade600
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ] else ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Prendé la impresora y tocá CONECTAR en la tuya. Si se llaman igual, '
                        'fijate el final del código: es el de la etiqueta de abajo de la impresora.',
                      ),
                    ),
                    if (_buscando)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      TextButton(
                        key: const Key('impresora_buscar'),
                        onPressed: _ocupado ? null : _buscar,
                        child: const Text('BUSCAR'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final d in _ordenados)
                  Card(
                    child: ListTile(
                      key: Key('impresora_encontrada_${d.id}'),
                      title: Text.rich(TextSpan(children: [
                        TextSpan(text: _nombre(d.id, d.nombre)),
                        TextSpan(
                          text: '  ${finDelId(d.id)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ])),
                      subtitle: Text([
                        if (_apodos.containsKey(d.id)) ...[
                          if (d.nombre.isNotEmpty) d.nombre,
                          'ya la usaste en este equipo',
                        ] else if (d.emparejado)
                          'Emparejada en este equipo',
                      ].join(' · ')),
                      trailing: FilledButton(
                        onPressed: _ocupado ? null : () => _conectar(d),
                        child: const Text('CONECTAR'),
                      ),
                    ),
                  ),
              ],
              if (_aviso != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_aviso!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
