import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_update_checker.dart';
import '../../barra/providers/barra_del_jefe_provider.dart' show enLaWebProvider;
import '../../dashboard/widgets/actualizar_app.dart';
import '../models/permisos_operador.dart';
import '../providers/app_role_provider.dart';
import '../services/entrada_de_operador.dart';
import '../services/operador_por_la_nube.dart';
import '../services/pin_de_operador.dart';
import 'abrir_caja_dialog.dart';

/// Pantalla post-login Supabase: entrar como jefe o como operador, con su PIN.
///
/// **Un PIN y se despliegan las opciones:** con un solo permiso entra derecho; con
/// varios, elige acá mismo; sin ninguno, se le dice y no pasa de esta pantalla.
class RoleGateScreen extends ConsumerStatefulWidget {
  const RoleGateScreen({super.key});

  @override
  ConsumerState<RoleGateScreen> createState() => _RoleGateScreenState();
}

class _RoleGateScreenState extends ConsumerState<RoleGateScreen> {
  bool _busy = false;
  String? _error;

  /// Tiene varios permisos: se despliegan y elige.
  OperadorYPermisos? _eligiendo;
  bool _abriendoCaja = false;

  Future<void> _entrarJefe() async {
    final pin = await _pedirPin(
      titulo: 'Modo jefe',
      subtitulo: 'Ingresá el PIN maestro',
    );
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Esperar a que el route del diálogo termine de desmontarse.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final ok = await ref.read(appRoleProvider.notifier).loginJefe(pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'PIN de jefe incorrecto';
      });
    }
    // Si ok, el router reemplaza esta pantalla; no setState.
  }

  Future<void> _entrarOperador() async {
    final pin = await _pedirPin(
      titulo: 'Operador',
      subtitulo: 'Ingresá tu PIN',
    );
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final OperadorYPermisos? encontrado;
    try {
      encontrado = await ref.read(appRoleProvider.notifier).buscarOperador(pin);
    } on SinNubeParaElPin {
      // En la web el PIN se le pregunta a la nube: que no conteste no es un PIN malo.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = kSinNubeParaElPin;
        });
      }
      return;
    }
    if (!mounted) return;
    if (encontrado == null) {
      setState(() {
        _busy = false;
        _error = 'PIN incorrecto o operador inactivo';
      });
      return;
    }
    final opciones = OpcionesDeEntrada.de(
      encontrado.permisos,
      enLaWeb: ref.read(enLaWebProvider),
    );
    if (opciones.aviso != null) {
      setState(() {
        _busy = false;
        _error = opciones.aviso;
      });
      return;
    }
    final directo = opciones.directo;
    if (directo != null) {
      await _entrarA(directo, encontrado);
      return;
    }
    setState(() {
      _busy = false;
      _eligiendo = encontrado;
    });
  }

  Future<void> _entrarA(
    PermisoOperador permiso,
    OperadorYPermisos quien,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _eligiendo = null;
    });
    final notifier = ref.read(appRoleProvider.notifier);
    switch (permiso) {
      case PermisoOperador.cobros:
        await notifier.entrarComoCaja(quien.operador, quien.permisos);
      case PermisoOperador.entradas:
        await notifier.entrarComoEntradas(quien.operador, quien.permisos);
      // La encargada entra por el mismo botón BARRA: la barra sabe que es ella
      // por sus permisos (`AppRoleState.esEncargadaDeBarra`).
      case PermisoOperador.barra:
      case PermisoOperador.encargadaBarra:
        await notifier.entrarComoBarra(quien.operador, quien.permisos);
    }
    // Si entró, el router reemplaza esta pantalla; si falta abrir la caja, la
    // pide [_abrirCaja].
  }

  /// Entró a Cobros sin caja abierta, desde acá o desde PASAR A CAJA.
  Future<void> _abrirCaja() async {
    final opened = await showAbrirCajaDialog(context);
    if (opened != true && mounted) {
      await ref.read(appRoleProvider.notifier).noAbrioLaCaja();
    }
    if (mounted) {
      setState(() {
        _abriendoCaja = false;
        _busy = false;
      });
    }
  }

  Future<String?> _pedirPin({
    required String titulo,
    required String subtitulo,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PinDialog(titulo: titulo, subtitulo: subtitulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (ref.watch(appRoleProvider).pideAbrirCaja && !_abriendoCaja) {
      _abriendoCaja = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirCaja();
      });
    }
    final eligiendo = _eligiendo;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ref.watch(versionNuevaEnLaTabletProvider).value
                    case final nueva?) ...[
                  _VersionNueva(info: nueva),
                  const SizedBox(height: 24),
                ],
                const Icon(Icons.storefront_rounded, size: 48, color: gold),
                const SizedBox(height: 16),
                Text(
                  'Junior Eventos',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  eligiendo == null
                      ? 'Elegí cómo entrar'
                      : 'Hola, ${eligiendo.operador.nombre}. ¿Qué vas a hacer?',
                  key: const Key('entrada_subtitulo'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: gold),
                  )
                else if (eligiendo != null)
                  ..._opciones(eligiendo)
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('entrar_jefe'),
                      onPressed: _entrarJefe,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      style: FilledButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      label: const Text(
                        'MODO JEFE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('entrar_operador'),
                      onPressed: _entrarOperador,
                      icon: const Icon(Icons.badge_outlined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: gold,
                        side: const BorderSide(color: gold),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      label: const Text(
                        'OPERADOR',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lo que tiene el operador, en el mismo lugar donde estaban los dos botones.
  List<Widget> _opciones(OperadorYPermisos quien) {
    const gold = Color(0xFFD4AF37);
    IconData icono(PermisoOperador p) => switch (p) {
          PermisoOperador.cobros => Icons.point_of_sale_outlined,
          PermisoOperador.entradas => Icons.confirmation_number_outlined,
          PermisoOperador.barra || PermisoOperador.encargadaBarra => Icons.local_bar_outlined,
        };
    return [
      for (final p in quien.permisos.lista) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: Key('entrada_${p.name}'),
            onPressed: () => _entrarA(p, quien),
            icon: Icon(icono(p)),
            style: OutlinedButton.styleFrom(
              foregroundColor: gold,
              side: const BorderSide(color: gold),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            label: Text(
              nombreDePermiso(p).toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      TextButton(
        key: const Key('entrada_volver'),
        onPressed: () => setState(() => _eligiendo = null),
        child: const Text('VOLVER'),
      ),
    ];
  }
}

/// En la tablet (6.4.0), arriba de todo: hay una versión nueva en GitHub.
/// ACTUALIZAR muestra las novedades y abre la descarga del APK.
class _VersionNueva extends StatelessWidget {
  const _VersionNueva({required this.info});

  final AppUpdateInfo info;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Container(
      key: const Key('entrada_version_nueva'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_outlined, color: gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hay una versión nueva: ${info.latestVersion}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            key: const Key('entrada_actualizar'),
            onPressed: () => mostrarDialogoActualizacion(context, info),
            child: const Text(
              'ACTUALIZAR',
              style: TextStyle(color: gold, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog que posee el controller y lo dispone en su propio [dispose].
class _PinDialog extends StatefulWidget {
  final String titulo;
  final String subtitulo;

  const _PinDialog({required this.titulo, required this.subtitulo});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitulo, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Entrar'),
        ),
      ],
    );
  }
}
