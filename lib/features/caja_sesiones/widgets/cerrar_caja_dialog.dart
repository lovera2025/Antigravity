import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cierre_caja/repositories/cierre_caja_repository.dart';
import '../../cierre_caja/services/datos_cierre_sesion.dart';
import '../../cierre_caja/services/papeles_cierre_sesion.dart';
import '../../common/utils/currency_extensions.dart';
import '../../common/utils/currency_input_formatter.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../providers/app_role_provider.dart';
import '../repositories/sesiones_caja_repository.dart';

Future<bool?> showCerrarCajaDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CerrarCajaDialog(),
  );
}

/// Los dos pasos del cierre viven en **un solo diálogo**, no en dos `showDialog`
/// en cadena.
///
/// No es una preferencia de estilo: los tres botones que llegan acá hacen
/// `Navigator.pop(context)` para cerrar el drawer y **después** llaman a
/// [showCerrarCajaDialog] con ese mismo context. Hoy funciona porque el
/// `showDialog` sale en el mismo tick. Si entre medio hubiera un `await` o un
/// segundo `showDialog`, ese context ya estaría desmontado y el diálogo no
/// aparecería: la caja no se cerraría y nadie sabría por qué.
enum _Paso { aviso, arqueo }

class CerrarCajaDialog extends ConsumerStatefulWidget {
  const CerrarCajaDialog({super.key});

  @override
  ConsumerState<CerrarCajaDialog> createState() => _CerrarCajaDialogState();
}

class _CerrarCajaDialogState extends ConsumerState<CerrarCajaDialog> {
  final _arqueoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  late _Paso _paso;
  DatosCierreSesion? _datos;
  bool _totalesFallaron = false;
  double? _totalCobrado;

  /// Solo el operario recibe el aviso previo y el papel automático.
  bool get _esOperario => ref.read(appRoleProvider).esCaja;

  @override
  void initState() {
    super.initState();
    final role = ref.read(appRoleProvider);
    _paso = (role.esCaja && role.sesionActiva != null)
        ? _Paso.aviso
        : _Paso.arqueo;
    // El diálogo se dibuja enseguida y los números aterrizan cuando llegan: así
    // no hay ningún await antes de mostrarlo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final sesion = ref.read(appRoleProvider).sesionActiva;
    if (sesion == null) return;
    try {
      if (_paso == _Paso.aviso) {
        final datos = await cargarDatosCierreSesion(
          sesionIds: {sesion.id},
          finanzasRepo: ref.read(finanzasRepositoryProvider),
          egresosRepo: ref.read(egresosRepositoryProvider),
        );
        if (mounted) setState(() => _datos = datos);
      } else {
        final total = await ref
            .read(sesionesCajaRepositoryProvider)
            .totalCobradoSesion(sesion.id);
        if (mounted) setState(() => _totalCobrado = total);
      }
    } catch (_) {
      if (mounted) setState(() => _totalesFallaron = true);
    }
  }

  @override
  void dispose() {
    _arqueoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final arqueoText = _arqueoCtrl.text.trim();
      final arqueo = arqueoText.isEmpty
          ? null
          : CurrencyInputFormatter.parse(arqueoText);
      final role = ref.read(appRoleProvider);
      final esOperario = role.esCaja;
      final etiquetaOperario = [
        role.operador?.nombre ?? 'Operario',
        if ((role.sesionActiva?.etiqueta ?? '').isNotEmpty)
          role.sesionActiva!.etiqueta!,
      ].join(' · ');

      // Los repos se capturan ANTES de cerrar: el cierre del operario desloguea
      // y limpia el estado de rol, y el papel se emite después.
      final finanzasRepo = ref.read(finanzasRepositoryProvider);
      final egresosRepo = ref.read(egresosRepositoryProvider);
      final cierreRepo = ref.read(cierreCajaRepositoryProvider);

      final notifier = ref.read(appRoleProvider.notifier);
      final res = role.esJefe
          ? await notifier.cerrarCajaJefe(
              arqueoCierre: arqueo,
              notaCierre: _notaCtrl.text,
            )
          : await notifier.cerrarSesionCaja(
              arqueoCierre: arqueo,
              notaCierre: _notaCtrl.text,
            );

      if (!mounted) return;
      // Si el cierre quedó solo en esta PC hay que decirlo AHORA, y antes que el
      // papel: el visor de PDF roba el foco y lo que se encole después queda
      // detrás de esa ventana.
      if (!res.sincronizado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Caja cerrada. No se pudo avisar al servidor (sin conexión): '
              'se sincroniza sola cuando vuelva internet. Hasta entonces, en '
              'otra PC puede figurar abierta.',
            ),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 8),
          ),
        );
      }

      final cerrada = res.cerrada;
      if (esOperario && cerrada != null) {
        try {
          // Con timeout: la escalera del papel mide el documento varias veces y
          // ningún problema del PDF puede dejar al operario esperando sin salida.
          await emitirPapelesDeCierre(
            cerrada: cerrada,
            finanzasRepo: finanzasRepo,
            egresosRepo: egresosRepo,
            cierreRepo: cierreRepo,
            emitidoPor: etiquetaOperario,
          ).timeout(const Duration(seconds: 45));
        } catch (_) {
          if (mounted) {
            // El operario ya está deslogueado y no puede volver a Cierre de Caja.
            // No se afirma que el archivo quedó guardado: el fallo también puede
            // haber ocurrido antes de escribirlo (consulta, fuente o layout).
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Caja cerrada. No se pudo abrir la hoja automáticamente. '
                  'Pedile al jefe que la genere desde Cierre de Caja.',
                ),
                backgroundColor: Colors.orangeAccent,
                duration: Duration(seconds: 8),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(appRoleProvider);
    final titulo = role.esJefe
        ? 'Cerrar caja · Modo jefe'
        : 'Cerrar caja${role.operador != null ? ' · ${role.operador!.nombre}' : ''}';

    return AlertDialog(
      title: Text(_paso == _Paso.aviso ? '¿Cerrar la caja?' : titulo),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: _paso == _Paso.aviso ? _contenidoAviso() : _contenidoArqueo(),
        ),
      ),
      actions: _paso == _Paso.aviso ? _accionesAviso() : _accionesArqueo(),
    );
  }

  // ── Paso 1: aviso con los totales ───────────────────────────────────────────

  Widget _contenidoAviso() {
    final sesion = ref.read(appRoleProvider).sesionActiva;
    final datos = _datos;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Revisá los totales antes de confirmar.'),
        const SizedBox(height: 16),
        if (_totalesFallaron)
          const Text(
            'No se pudieron calcular los totales.',
            style: TextStyle(color: Colors.orangeAccent),
          )
        else if (datos == null || sesion == null)
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Calculando…'),
            ],
          )
        else ...[
          _bloqueMedio(
            titulo: 'EFECTIVO',
            // Lo que tiene que haber en el cajón, no lo cobrado: contra el bruto
            // el arqueo daría diferencia siempre.
            total: datos.efectivoEsperado(sesion.cambioInicial),
            color: const Color(0xFF00B894),
            detalle: [
              ('cambio inicial', sesion.cambioInicial),
              ('cobrado en efectivo', datos.efectivoBruto),
              ('retiros / gastos', -datos.egresosEfectivo),
            ],
          ),
          const SizedBox(height: 14),
          _bloqueMedio(
            titulo: 'TRANSFERENCIA',
            total: datos.transferenciaNeta,
            color: const Color(0xFF6C63FF),
            detalle: [
              ('cobrado por transferencia', datos.transferenciaBruta),
              ('retiros / gastos', -datos.egresosTransferencia),
            ],
          ),
        ],
      ],
    );
  }

  Widget _bloqueMedio({
    required String titulo,
    required double total,
    required Color color,
    required List<(String, double)> detalle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: color,
              ),
            ),
            Text(
              total.toCurrency(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...detalle
            .where((d) => d.$2.abs() > 0.001)
            .map(
              (d) => Padding(
                padding: const EdgeInsets.only(left: 12, top: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(d.$1, style: const TextStyle(fontSize: 12)),
                    Text(
                      '${d.$2 < 0 ? '−' : ''}${d.$2.abs().toCurrency()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: d.$2 < 0 ? Colors.redAccent : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  List<Widget> _accionesAviso() => [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: const Text('Cancelar'),
    ),
    FilledButton(
      // Habilitado siempre, incluso si los totales fallaron: cerrar la caja no
      // puede quedar bloqueado porque una consulta no anduvo.
      onPressed: () => setState(() {
        _paso = _Paso.arqueo;
        if (_totalCobrado == null) _cargar();
      }),
      child: const Text('Sí, cerrar caja'),
    ),
  ];

  // ── Paso 2: arqueo ──────────────────────────────────────────────────────────

  Widget _contenidoArqueo() {
    final sesion = ref.read(appRoleProvider).sesionActiva;
    final datos = _datos;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (datos != null && sesion != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'En el cajón tiene que haber: '
              '${datos.efectivoEsperado(sesion.cambioInicial).toCurrency()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else if (_totalCobrado != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Cobrado en esta sesión: ${_totalCobrado!.toCurrency()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        TextField(
          controller: _arqueoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [CurrencyInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Arqueo de cierre (opcional)',
            prefixText: '\$ ',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notaCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Nota de cierre',
            alignLabelWithHint: true,
          ),
        ),
        if (_esOperario) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.print_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Al cerrar se abrirá la hoja de cierre en PDF. Imprimí ese '
                  'documento en una hoja A4 completa.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ],
    );
  }

  List<Widget> _accionesArqueo() => [
    TextButton(
      onPressed: _saving ? null : () => Navigator.pop(context, false),
      child: const Text('Cancelar'),
    ),
    FilledButton(
      onPressed: _saving ? null : _confirmar,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      child: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Cerrar caja'),
    ),
  ];
}
