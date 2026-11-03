import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/providers/admin_provider.dart';
import '../../common/utils/solo_jefe.dart';
import '../models/operador_caja.dart';
import '../models/permisos_operador.dart';
import '../providers/app_role_provider.dart';
import '../repositories/operadores_caja_repository.dart';
import '../repositories/permisos_operador_repository.dart';
import '../services/pin_de_operador.dart';

/// OPERADORES: una sola lista, cada uno con su nombre, su PIN y sus permisos
/// (Cobros, Entradas, Barra). Dar permisos es del jefe: los botones se ven apagados
/// sin modo jefe, y cada función que guarda lo vuelve a preguntar.
class OperadoresCajaScreen extends ConsumerStatefulWidget {
  const OperadoresCajaScreen({super.key});

  @override
  ConsumerState<OperadoresCajaScreen> createState() =>
      _OperadoresCajaScreenState();
}

class _OperadoresCajaScreenState extends ConsumerState<OperadoresCajaScreen> {
  List<OperadorCaja> _ops = [];
  Map<String, PermisosOperador> _permisos = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(operadoresCajaRepositoryProvider)
          .listar(soloActivos: true);
      final permisos = await ref.read(permisosOperadorRepositoryProvider).todas();
      if (mounted) {
        setState(() {
          _ops = list;
          _permisos = permisos;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron leer los operadores.';
          _loading = false;
        });
      }
    }
  }

  /// Segunda llave: el botón ya viene apagado sin modo jefe.
  bool _frenaSinModoJefe() {
    if (ref.read(esRolJefeProvider)) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('$kSoloEnModoJefe: los operadores los carga el jefe.'),
        ),
      );
    }
    return true;
  }

  void _decirError(Object e) {
    if (!mounted) return;
    final texto = e is StateError
        ? e.message
        : e is ArgumentError
            ? '${e.message}'
            : 'No se pudo guardar. Probá de nuevo.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _eliminar(OperadorCaja op) async {
    if (_frenaSinModoJefe()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar operador'),
        content: Text(
          '¿Eliminar a ${op.nombre}? No podrá entrar con su PIN. '
          'Si tiene caja abierta, se cerrará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_frenaSinModoJefe()) return;
    try {
      await ref.read(operadoresCajaRepositoryProvider).eliminar(op.id);
      await _cargar();
    } catch (e) {
      _decirError(e);
    }
  }

  Future<String?> _problema(String nombre, String pin, String? idPropio) async {
    final maestro =
        await ref.read(adminAuthProvider.notifier).esPinMaestro(pin.trim());
    final otros = await ref
        .read(operadoresCajaRepositoryProvider)
        .listar(soloActivos: true);
    return problemaDelOperador(
      nombre: nombre,
      pin: pin,
      idPropio: idPropio,
      otros: otros,
      esMaestro: maestro,
    );
  }

  Future<void> _editar([OperadorCaja? existing]) async {
    if (_frenaSinModoJefe()) return;
    final ficha = await showDialog<_Ficha>(
      context: context,
      builder: (ctx) => _FichaOperador(
        existente: existing,
        // Uno de los de antes, sin fila, es de Cobros: viene tildado, y guardar sin
        // tocar nada no le saca el permiso. Uno nuevo arranca igual.
        permisos: PermisosEfectivos.de(
          existing == null ? null : _permisos[existing.id],
        ),
        problema: (nombre, pin) => _problema(nombre, pin, existing?.id),
      ),
    );
    if (ficha == null || !mounted) return;
    if (_frenaSinModoJefe()) return;
    try {
      final repo = ref.read(operadoresCajaRepositoryProvider);
      final op = existing == null
          ? await repo.crear(nombre: ficha.nombre, pin: ficha.pin)
          : await repo.actualizar(
              existing.copyWith(nombre: ficha.nombre, pin: ficha.pin),
            );
      // Pasó el freno: quien da el permiso es el jefe.
      await ref.read(permisosOperadorRepositoryProvider).guardar(
            operadorId: op.id,
            permisos: ficha.permisos,
            quien: 'Jefe',
          );
      await _cargar();
    } catch (e) {
      _decirError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final esJefe = ref.watch(esRolJefeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPERADORES'),
        actions: [
          IconButton(
            key: const Key('operador_nuevo'),
            tooltip: esJefe ? 'Nuevo' : kSoloEnModoJefe,
            onPressed: esJefe ? () => _editar() : null,
            icon: Icon(Icons.person_add_alt_1, color: esJefe ? gold : null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : _error != null
          ? Center(child: Text(_error!))
          : _ops.isEmpty
          ? const Center(
              child: Text(
                'No hay operadores.\nCreá uno con el botón +',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _ops.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final op = _ops[i];
                final permisos = PermisosEfectivos.de(_permisos[op.id]);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: op.activo
                          ? gold.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.person,
                        color: op.activo ? gold : Colors.grey,
                      ),
                    ),
                    title: Text(
                      op.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      textoDePermisos(permisos),
                      key: Key('permisos_de_${op.id}'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: esJefe ? 'Editar' : kSoloEnModoJefe,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: esJefe ? () => _editar(op) : null,
                        ),
                        IconButton(
                          tooltip: esJefe ? 'Eliminar' : kSoloEnModoJefe,
                          icon: Icon(
                            Icons.delete_outline,
                            color: esJefe ? Colors.redAccent : null,
                          ),
                          onPressed: esJefe ? () => _eliminar(op) : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Lo que se cargó en la ficha.
class _Ficha {
  final String nombre;
  final String pin;
  final PermisosEfectivos permisos;

  const _Ficha(this.nombre, this.pin, this.permisos);
}

/// La ficha de un operador. Lo que está mal se dice acá adentro: el diálogo no se
/// cierra, y no se pierde lo escrito.
class _FichaOperador extends StatefulWidget {
  final OperadorCaja? existente;
  final PermisosEfectivos permisos;
  final Future<String?> Function(String nombre, String pin) problema;

  const _FichaOperador({
    required this.existente,
    required this.permisos,
    required this.problema,
  });

  @override
  State<_FichaOperador> createState() => _FichaOperadorState();
}

class _FichaOperadorState extends State<_FichaOperador> {
  late final _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
  late final _pin = TextEditingController(text: widget.existente?.pin ?? '');
  late bool _cobros = widget.permisos.cobros;
  late bool _entradas = widget.permisos.entradas;
  late bool _barra = widget.permisos.barra;
  String? _problema;
  bool _revisando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _revisando = true);
    final problema = await widget.problema(_nombre.text, _pin.text);
    if (!mounted) return;
    if (problema != null) {
      setState(() {
        _problema = problema;
        _revisando = false;
      });
      return;
    }
    Navigator.pop(
      context,
      _Ficha(
        _nombre.text,
        _pin.text,
        PermisosEfectivos(cobros: _cobros, entradas: _entradas, barra: _barra),
      ),
    );
  }

  Widget _casilla({
    required String clave,
    required String titulo,
    required String detalle,
    required bool valor,
    required ValueChanged<bool> cambiar,
  }) =>
      CheckboxListTile(
        key: Key(clave),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: valor,
        onChanged: (v) => setState(() => cambiar(v ?? false)),
        title: Text(titulo),
        subtitle: Text(detalle),
      );

  @override
  Widget build(BuildContext context) {
    final sinNinguno = !_cobros && !_entradas && !_barra;
    return AlertDialog(
      title: Text(widget.existente == null ? 'Nuevo operador' : 'Editar operador'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('operador_nombre'),
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('operador_pin'),
                controller: _pin,
                decoration: const InputDecoration(labelText: 'PIN (mín. 4)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Text('PERMISOS', style: Theme.of(context).textTheme.labelMedium),
              _casilla(
                clave: 'permiso_cobros',
                titulo: 'Cobros',
                detalle: 'Cobrar las cuotas de los eventos masivos y abrir esa caja.',
                valor: _cobros,
                cambiar: (v) => _cobros = v,
              ),
              _casilla(
                clave: 'permiso_entradas',
                titulo: 'Entradas',
                detalle: 'Entregar entradas y pulseras.',
                valor: _entradas,
                cambiar: (v) => _entradas = v,
              ),
              _casilla(
                clave: 'permiso_barra',
                titulo: 'Barra',
                detalle: 'Queda guardado para cuando esté la barra: todavía no abre nada.',
                valor: _barra,
                cambiar: (v) => _barra = v,
              ),
              if (sinNinguno)
                const Padding(
                  key: Key('aviso_sin_permisos'),
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Sin permisos no puede entrar: se lo dice al poner el PIN.',
                  ),
                ),
              if (!_cobros)
                const Padding(
                  key: Key('aviso_sin_cobros'),
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Mientras haya una PC sin esta versión, ahí igual puede entrar '
                    'a cobrar. Cuando las tres la tengan, ya no.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (_problema != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _problema!,
                    key: const Key('operador_problema'),
                    style: const TextStyle(
                      color: Colors.redAccent,
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
          key: const Key('operador_cancelar'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('operador_guardar'),
          onPressed: _revisando ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
