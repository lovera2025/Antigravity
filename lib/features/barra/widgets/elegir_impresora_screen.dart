import 'dart:async';

import 'package:flutter/material.dart';

import '../impresion/canal_ble.dart';
import '../impresion/impresora_bluetooth.dart';

/// Elegir la impresora de este equipo, una sola vez: se busca por Bluetooth, se toca
/// CONECTAR y queda recordada (después se conecta sola). CAMBIAR la olvida.
class ElegirImpresoraScreen extends StatefulWidget {
  final ImpresoraBluetooth impresora;

  const ElegirImpresoraScreen({super.key, required this.impresora});

  @override
  State<ElegirImpresoraScreen> createState() => _ElegirImpresoraScreenState();
}

class _ElegirImpresoraScreenState extends State<ElegirImpresoraScreen> {
  final _encontrados = <String, DispositivoBle>{};
  StreamSubscription<DispositivoBle>? _busqueda;
  Timer? _fin;
  ImpresoraElegida? _elegida;
  bool _buscando = false;
  bool _ocupado = false;
  String? _aviso;

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
    if (!mounted) return;
    setState(() => _elegida = elegida);
    if (elegida == null) await _buscar();
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
      await _busqueda?.cancel();
      _busqueda = canal.buscar().listen(
            (d) {
              if (mounted && !(_encontrados[d.id]?.emparejado ?? false)) {
                setState(() => _encontrados[d.id] = d);
              }
            },
            onError: (Object _) {},
          );
      _fin?.cancel();
      _fin = Timer(const Duration(seconds: 10), () async {
        await _busqueda?.cancel();
        _busqueda = null;
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

  Future<void> _conectar(DispositivoBle d) async {
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    await _busqueda?.cancel();
    _busqueda = null;
    var ok = false;
    try {
      ok = await widget.impresora.conectar(d.id, nombre: d.nombre);
    } catch (_) {}
    final elegida = ok ? await widget.impresora.elegida() : null;
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _buscando = false;
      if (ok) {
        _elegida = elegida;
      } else {
        _aviso = 'No se conectó a ${d.nombre}. ¿Está prendida y cerca?';
      }
    });
  }

  Future<void> _cambiar() async {
    await widget.impresora.olvidar();
    if (!mounted) return;
    setState(() => _elegida = null);
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
              if (elegida != null)
                Card(
                  child: ListTile(
                    leading: Icon(
                      widget.impresora.conectadaA == elegida.id ? Icons.print : Icons.print_outlined,
                      color: Colors.green.shade700,
                    ),
                    title: Text(elegida.nombre.isEmpty ? 'La impresora de este equipo' : elegida.nombre),
                    subtitle: const Text('Queda recordada: se conecta sola cada vez.'),
                    trailing: TextButton(
                      key: const Key('impresora_cambiar'),
                      onPressed: _ocupado ? null : _cambiar,
                      child: const Text('CAMBIAR'),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    const Expanded(child: Text('Prendé la impresora y tocá CONECTAR en la tuya.')),
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
                      title: Text(d.nombre.isEmpty ? 'Sin nombre' : d.nombre),
                      subtitle: Text(d.emparejado ? 'Emparejada en este equipo' : d.id),
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
