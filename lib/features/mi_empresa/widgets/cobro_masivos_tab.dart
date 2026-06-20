import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/eventos_repository.dart';
import '../../eventos/services/mora_cuota_calculator.dart';
import '../providers/finanzas_provider.dart';

/// Fila agregada para el listado Cobro (evento + institución).
@immutable
class _CobroFila {
  final ContratoAlumno contrato;
  final DateTime? primeraCuotaBase;
  final DateTime? ultimoPago;
  final MoraCuotaResumen mora;
  final double moraPendiente;
  final int cuotasVencidasCount;
  final double cuotasVencidasMonto;

  const _CobroFila({
    required this.contrato,
    this.primeraCuotaBase,
    this.ultimoPago,
    required this.mora,
    this.moraPendiente = 0,
    this.cuotasVencidasCount = 0,
    this.cuotasVencidasMonto = 0,
  });
}

bool _esInteresPago(String? concepto) =>
    esPagoInteresMoraPorConcepto(concepto);

double _sumMoraCobradaDesdePagos(Iterable<Map<String, dynamic>> pagos) {
  double s = 0;
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final lk = (p['line_kind'] as String?)?.trim();
    final c = p['concepto']?.toString() ?? '';
    if (lk == kLineKindInteresMora || _esInteresPago(c)) {
      s += (p['monto'] as num).toDouble();
    }
  }
  return s;
}

/// Pago que cuenta como abono al plan de cuota base (alineado a [ContratosRepository.registrarPago]).
bool _pagoEsCuotaBase(Map<String, dynamic> p) {
  if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
  if (_esInteresPago(p['concepto']?.toString())) return false;
  final c = (p['concepto']?.toString() ?? '').toLowerCase();
  if (c.contains('mesa') || c.contains('silla')) return false;
  if (c.contains('base') || c.trim().isEmpty) return true;
  return false;
}

/// Último pago "al plan" (cualquier concepto distinto de solo interés).
DateTime? _ultimoPagoAlPlan(Iterable<Map<String, dynamic>> pagos) {
  final list = pagos.toList();
  DateTime? last;
  for (final p in list) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    if (_esInteresPago(p['concepto']?.toString()) ||
        esPagoCargoCanalPorConcepto(p['concepto']?.toString())) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (last == null || d.isAfter(last)) last = d;
  }
  if (last != null) return last;
  for (final p in list) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (last == null || d.isAfter(last)) last = d;
  }
  return last;
}

DateTime? _minFechaBase(Iterable<Map<String, dynamic>> pagos) {
  DateTime? min;
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    if (!_pagoEsCuotaBase(p)) continue;
    final fp = p['fecha_pago']?.toString();
    if (fp == null) continue;
    final d = DateTime.tryParse(fp);
    if (d == null) continue;
    if (min == null || d.isBefore(min)) min = d;
  }
  return min;
}

/// Nombre de institución unificado para el listado COBRO (evita duplicados por typo, sin tocar la DB).
String _institucionCanonica(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.isEmpty) return '';
  switch (t.toLowerCase()) {
    case 'sgarado':
    case 'sagrado':
      return 'SAGRADO';
    default:
      return t;
  }
}

/// Valor del combo "Institución" para listar todos los contratos del evento (sin filtrar por campo institución).
const String _kCobroTodosInstitucion = '__COBRO_TODOS_EL_EVENTO__';
const String _kCobroMarcaMensaje = 'Junior Eventos';

/// Filtro de cuota base: [todos] | al menos abonó una | ninguna.
enum _CobroFiltroCuota { todos, conAlMenosUna, ninguna }

bool _contratoEsBaja(ContratoAlumno a) => a.nombreAlumno.trim().startsWith('[BAJA]');

const Map<String, String> _localidadesCaracteristicas = {
  'san gregorio': '3382',
  'diego de alvear': '3382',
  'rufino': '3382',
  'maria teresa': '3382',
  'christophersen': '3382',
  'aarón castellanos': '3382',
  'venado tuerto': '3462',
  'villa cañás': '3462',
  'goya': '3777',
  'córdoba': '351',
  'rosario': '341',
  'buenos aires': '11',
};

String? _extraerCaracteristica(String n10) {
  if (n10.length != 10) return null;
  if (n10.startsWith('11')) return '11';
  final tresDigitosPrefixes = {
    '220', '221', '223', '230', '249', '260', '261', '263', '264', '280', '291', '294', '297', '298', '299',
    '341', '342', '343', '348', '351', '353', '358', '370', '376', '379', '380', '381', '383', '385', '387', '388'
  };
  final prefix3 = n10.substring(0, 3);
  if (tresDigitosPrefixes.contains(prefix3)) {
    return prefix3;
  }
  return n10.substring(0, 4);
}

String _inferirCaracteristica(ContratoAlumno? contrato, List<ContratoAlumno>? todosContratos) {
  if (contrato != null) {
    final curso = contrato.cursoDivision?.toLowerCase() ?? '';
    final inst = contrato.institucion?.toLowerCase() ?? '';
    for (final entry in _localidadesCaracteristicas.entries) {
      if (curso.contains(entry.key) || inst.contains(entry.key)) {
        return entry.value;
      }
    }
  }

  if (todosContratos != null && todosContratos.isNotEmpty) {
    final frecuencias = <String, int>{};
    for (final c in todosContratos) {
      final tel = c.telefono;
      if (tel == null) continue;
      
      var n = tel.replaceAll(RegExp(r'\D'), '');
      if (n.isEmpty) continue;

      if (n.startsWith('0')) {
        n = n.replaceFirst(RegExp(r'^0+'), '');
      }
      if (n.startsWith('54') && n.length > 10) {
        n = n.substring(2);
      }
      if (n.startsWith('9') && n.length == 11) {
        n = n.substring(1);
      }

      if (n.length == 12) {
        if (n.substring(2, 4) == '15') {
          n = n.substring(0, 2) + n.substring(4);
        } else if (n.substring(3, 5) == '15') {
          n = n.substring(0, 3) + n.substring(5);
        } else if (n.substring(4, 6) == '15') {
          n = n.substring(0, 4) + n.substring(6);
        }
      }

      if (n.length == 10) {
        final caract = _extraerCaracteristica(n);
        if (caract != null) {
          frecuencias[caract] = (frecuencias[caract] ?? 0) + 1;
        }
      }
    }

    if (frecuencias.isNotEmpty) {
      var maxFrec = 0;
      String? mejorCaract;
      frecuencias.forEach((caract, frec) {
        if (frec > maxFrec) {
          maxFrec = frec;
          mejorCaract = caract;
        }
      });
      if (mejorCaract != null) {
        return mejorCaract!;
      }
    }
  }

  return '3382';
}

String? _whatsAppUri(
  String? telefono, {
  ContratoAlumno? contrato,
  List<ContratoAlumno>? todosContratos,
}) {
  if (telefono == null) return null;
  
  final trimOriginal = telefono.trim();
  final esInternacionalExplicito = trimOriginal.startsWith('+') || trimOriginal.startsWith('00');
  
  var n = trimOriginal.replaceAll(RegExp(r'\D'), '');
  if (n.isEmpty) return null;

  // Pre-proceso: Limpiar "54" o "549" mal colocados después de una característica conocida
  final knownAreaCodes = {
    '3382', '3462', '3777', '3772', '351', '341', '11', '3482', '3468', '3388', '261', '291', '342', '379', '381'
  };
  for (final areaCode in knownAreaCodes) {
    if (n.startsWith(areaCode)) {
      final rest = n.substring(areaCode.length);
      if (rest.startsWith('549') && rest.length > 3) {
        n = areaCode + rest.substring(3);
        break;
      } else if (rest.startsWith('54') && rest.length > 2) {
        n = areaCode + rest.substring(2);
        break;
      }
    }
  }

  if (esInternacionalExplicito) {
    if (trimOriginal.startsWith('00')) {
      n = n.replaceFirst(RegExp(r'^00+'), '');
    }
    return 'https://wa.me/$n';
  }

  if (n.startsWith('549') && n.length == 13) {
    return 'https://wa.me/$n';
  }

  if (n.startsWith('0')) {
    n = n.replaceFirst(RegExp(r'^0+'), '');
  }

  bool tenia54 = false;
  if (n.startsWith('54') && n.length > 10) {
    tenia54 = true;
    n = n.substring(2);
  }

  bool tenia9 = false;
  if (n.startsWith('9') && n.length == 11) {
    tenia9 = true;
    n = n.substring(1);
  }

  bool esLocalIncompleto = false;
  String subscriber = n;

  if (n.startsWith('15')) {
    final sin15 = n.substring(2);
    if (sin15.length >= 6 && sin15.length <= 8) {
      esLocalIncompleto = true;
      subscriber = sin15;
    }
  } else if (n.length >= 6 && n.length <= 8) {
    esLocalIncompleto = true;
    subscriber = n;
  }

  if (esLocalIncompleto) {
    final caract = _inferirCaracteristica(contrato, todosContratos);
    n = '$caract$subscriber';
  }

  final iniciaConCaracteristicaValida = n.startsWith('1') || n.startsWith('2') || n.startsWith('3');

  if (iniciaConCaracteristicaValida) {
    if (n.length == 12) {
      if (n.substring(2, 4) == '15') {
        n = n.substring(0, 2) + n.substring(4);
      } else if (n.substring(3, 5) == '15') {
        n = n.substring(0, 3) + n.substring(5);
      } else if (n.substring(4, 6) == '15') {
        n = n.substring(0, 4) + n.substring(6);
      }
    }

    if (n.length == 10) {
      return 'https://wa.me/549$n';
    }
  }

  if (tenia54) {
    if (tenia9 || n.length == 10) {
      return 'https://wa.me/549$n';
    }
    return 'https://wa.me/54$n';
  }

  if (iniciaConCaracteristicaValida && n.length >= 8 && n.length <= 11) {
    return 'https://wa.me/549$n';
  }

  return 'https://wa.me/$n';
}

/// Primera palabra de [nombreAlumno] (según carga, puede ser nombre o apellido).
/// Quitar puntuación al final (p. ej. "Pérez,") para no duplicar comas con el cuerpo.
String _primeraPalabraNombreAlumno(String nombreAlumno) {
  var t = nombreAlumno.trim();
  if (t.toUpperCase().startsWith('[BAJA]')) {
    t = t.replaceFirst(RegExp(r'^\[BAJA\]\s*', caseSensitive: false), '').trim();
  }
  if (t.isEmpty) return '';
  var w = t.split(RegExp(r'\s+')).first;
  w = w.replaceAll(RegExp(r'[,.;:\s]+$'), '');
  w = w.replaceAll(RegExp(r'^[,\.;:\s]+'), '');
  return w;
}

/// Pestaña **Cobro**: seguimiento por evento masivo + institución (Mi Empresa).
class CobroMasivosTab extends ConsumerStatefulWidget {
  final bool isDark;
  final Color gold;

  const CobroMasivosTab({super.key, required this.isDark, required this.gold});

  @override
  ConsumerState<CobroMasivosTab> createState() => _CobroMasivosTabState();
}

class _CobroMasivosTabState extends ConsumerState<CobroMasivosTab> {
  bool _loadingEventos = true;
  String? _error;
  List<Evento> _eventosMasivos = [];
  String? _eventoId;
  bool _loadingDetalle = false;
  List<ContratoAlumno> _contratos = [];
  String? _institucion;
  List<String> _instituciones = [];
  List<_CobroFila> _filas = [];
  final _busquedaCtrl = TextEditingController();
  _CobroFiltroCuota _filtroCuota = _CobroFiltroCuota.todos;
  final Set<String> _seleccionados = {};
  bool _verSoloCuotasVencidas = true;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarEventos();
  }

  void _resetFiltrosVista() {
    _busquedaCtrl.clear();
    _filtroCuota = _CobroFiltroCuota.todos;
  }

  Future<void> _cargarEventos() async {
    setState(() {
      _loadingEventos = true;
      _error = null;
    });
    try {
      final evRepo = ref.read(eventosRepositoryProvider);
      final list = await evRepo.getAll(modalidad: 'masivo');
      if (!mounted) return;
      setState(() {
        _eventosMasivos = list;
        _loadingEventos = false;
        if (_eventoId != null && !_eventosMasivos.any((e) => e.id == _eventoId)) {
          _eventoId = null;
          _contratos = [];
          _instituciones = [];
          _institucion = null;
          _filas = [];
          _seleccionados.clear();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingEventos = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _cargarContratosYarmar(String? eventoId) async {
    if (eventoId == null) {
      setState(() {
        _contratos = [];
        _instituciones = [];
        _institucion = null;
        _filas = [];
        _loadingDetalle = false;
        _resetFiltrosVista();
      });
      return;
    }
    setState(() {
      _loadingDetalle = true;
      _error = null;
      _institucion = null;
      _filas = [];
      _seleccionados.clear();
      _resetFiltrosVista();
    });
    try {
      final cRepo = ref.read(contratosRepositoryProvider);
      final c = await cRepo.getByEvento(eventoId);
      final inst = c
          .map((a) => _institucionCanonica(a.institucion))
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _contratos = c;
        _instituciones = inst;
        _institucion = _kCobroTodosInstitucion;
      });
      await _armarFilas(_kCobroTodosInstitucion);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetalle = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _armarFilas(String? institucion) async {
    if (_eventoId == null) {
      if (mounted) {
        setState(() {
          _filas = [];
          _loadingDetalle = false;
        });
      }
      return;
    }
    if (institucion == null || institucion.isEmpty) {
      if (mounted) {
        setState(() {
          _filas = [];
          _seleccionados.clear();
          _loadingDetalle = false;
        });
      }
      return;
    }
    setState(() {
      _loadingDetalle = true;
      _error = null;
    });
    try {
      var alumnos = institucion == _kCobroTodosInstitucion
          ? List<ContratoAlumno>.from(_contratos)
          : _contratos
              .where((a) => _institucionCanonica(a.institucion) == institucion)
              .toList();
      alumnos = alumnos.where((a) => !_contratoEsBaja(a)).toList();
      final ids = alumnos.map((a) => a.id).toList();
      final cRepo = ref.read(contratosRepositoryProvider);
      final pagos = await cRepo.getPagosForContratoIds(ids);
      final porContrato = <String, List<Map<String, dynamic>>>{};
      for (final p in pagos) {
        final id = p['contrato_alumno_id'] as String?;
        if (id == null) continue;
        porContrato.putIfAbsent(id, () => []).add(p);
      }
      final filas = <_CobroFila>[];
      for (final a in alumnos) {
        final list = porContrato[a.id] ?? [];
        final primera = _minFechaBase(list);
        final ultimo = _ultimoPagoAlPlan(list);
        final mora = MoraCuotaCalculator.calcular(a);
        final moraPagada = _sumMoraCobradaDesdePagos(list);
        final moraPeriodo = moraCobradaDelPeriodoVigente(
          list,
          inicioMoraPeriodoVigente(mora.fechaVencimientoProximaCuota),
        );
        final moraPend = MoraCuotaCalculator.pendienteDisplay(
          interesAcumulado: mora.interesAcumulado,
          moraCobradaHistorial: moraPagada,
          moraPendienteTracked: a.moraPendienteTracked,
          moraCobradaOffset: a.moraCobradaOffset,
          moraCobradaPeriodo: moraPeriodo,
        );

        // Cálculo de cuotas vencidas
        final c = a;
        final now = ArTime.nowAr();
        final inscAr = c.createdAt != null ? ArTime.toAr(c.createdAt!) : now;
        final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;
        
        final totalBase = (c.montoTotalPactado - c.mesaExtraPrecio - c.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
        final cuotaBase = tCuotas > 0 ? totalBase / tCuotas : 0.0;
        final cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));

        int cuotasVencidasCount = 0;
        for (int k = c.cuotasPagadas + 1; k <= tCuotas; k++) {
          var m = inscAr.month + k;
          var y = inscAr.year;
          while (m > 12) { m -= 12; y++; }
          final vK = DateTime(y, m, DateTime(y, m + 1, 0).day);
          final vKSolo = DateTime(vK.year, vK.month, vK.day);
          final hoySolo = DateTime(now.year, now.month, now.day);

          if (hoySolo.isAfter(vKSolo)) {
            cuotasVencidasCount++;
          } else {
            break; 
          }
        }
        final cuotasVencidasMonto = (cuotasVencidasCount * cuotaBaseR).clamp(0.0, c.saldoDeudor);

        filas.add(_CobroFila(
          contrato: a,
          primeraCuotaBase: primera,
          ultimoPago: ultimo,
          mora: mora,
          moraPendiente: moraPend,
          cuotasVencidasCount: cuotasVencidasCount,
          cuotasVencidasMonto: cuotasVencidasMonto,
        ));
      }
      filas.sort((x, y) {
        if (x.mora.enMora != y.mora.enMora) return x.mora.enMora ? -1 : 1;
        return x.contrato.nombreAlumno.toLowerCase().compareTo(y.contrato.nombreAlumno.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _loadingDetalle = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetalle = false;
          _error = '$e';
        });
      }
    }
  }

  String _etiquetaEvento(Evento e) {
    final f = ArTime.formatFechaCorta(e.fechaEvento);
    final nombre = e.cliente != null ? e.cliente!.nombreCompleto.trim() : '';
    if (nombre.isNotEmpty) {
      return '$f · $nombre';
    }
    return '$f · ${e.tipo}';
  }

  /// Filas a mostrar: búsqueda por nombre + filtro de cuota base (el listado base ya excluye [BAJA]).
  List<_CobroFila> _filasFiltradasVista() {
    var list = _filas;
    final q = _busquedaCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((f) => f.contrato.nombreAlumno.toLowerCase().contains(q))
          .toList();
    }
    switch (_filtroCuota) {
      case _CobroFiltroCuota.todos:
        break;
      case _CobroFiltroCuota.conAlMenosUna:
        list = list.where((f) => f.contrato.cuotasPagadas >= 1).toList();
        break;
      case _CobroFiltroCuota.ninguna:
        list = list.where((f) => f.contrato.cuotasPagadas == 0).toList();
        break;
    }
    return list;
  }

  String _valorFiltroInstitucionValido() {
    if (_institucion == _kCobroTodosInstitucion) return _kCobroTodosInstitucion;
    if (_institucion != null && _instituciones.contains(_institucion)) {
      return _institucion!;
    }
    return _kCobroTodosInstitucion;
  }

  void _toggleSeleccionTodos(List<_CobroFila> filasVista) {
    final todosSeleccionados = filasVista.every((f) => _seleccionados.contains(f.contrato.id));
    setState(() {
      if (todosSeleccionados) {
        for (final f in filasVista) {
          _seleccionados.remove(f.contrato.id);
        }
      } else {
        for (final f in filasVista) {
          _seleccionados.add(f.contrato.id);
        }
      }
    });
  }

  Widget _buildResumenSeleccion(List<_CobroFila> filasVista) {
    if (filasVista.isEmpty) return const SizedBox.shrink();
    
    final seleccionadasActual = filasVista.where((f) => _seleccionados.contains(f.contrato.id)).toList();
    final todosSeleccionados = seleccionadasActual.length == filasVista.length && filasVista.isNotEmpty;
    
    double totalMontoDeuda = 0;
    double totalMoraPendiente = 0;
    
    for (final f in seleccionadasActual) {
      if (_verSoloCuotasVencidas) {
        totalMontoDeuda += f.cuotasVencidasMonto;
      } else {
        totalMontoDeuda += f.contrato.saldoDeudor;
      }
      totalMoraPendiente += f.moraPendiente;
    }
    
    final totalCobrar = totalMontoDeuda + totalMoraPendiente;
    final muted = widget.isDark ? Colors.white54 : Colors.black54;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: widget.gold.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.gold.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: todosSeleccionados,
                  activeColor: widget.gold,
                  onChanged: (v) => _toggleSeleccionTodos(filasVista),
                ),
                Expanded(
                  child: Text(
                    'Seleccionar filtrados (${seleccionadasActual.length}/${filasVista.length})',
                    style: TextStyle(fontWeight: FontWeight.w800, color: widget.gold),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Modo de visualización:',
                  style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.bold),
                ),
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity(horizontal: -3, vertical: -3),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Solo Cuotas Vencidas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Total Global', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  selected: {_verSoloCuotasVencidas},
                  onSelectionChanged: (Set<bool> val) {
                    setState(() {
                      _verSoloCuotasVencidas = val.first;
                    });
                  },
                ),
              ],
            ),
            if (seleccionadasActual.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _verSoloCuotasVencidas ? 'Cuotas Vencidas:' : 'Saldo Deudor:',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  Text(totalMontoDeuda.toCurrency(), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              if (totalMoraPendiente > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Mora Pendiente:', style: TextStyle(color: muted, fontSize: 13)),
                      Text(totalMoraPendiente.toCurrency(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _verSoloCuotasVencidas ? 'TOTAL VENCIDO:' : 'TOTAL GLOBAL:',
                    style: TextStyle(color: widget.gold, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  Text(
                    totalCobrar.toCurrency(),
                    style: TextStyle(color: widget.gold, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cuando el realtime de finanzas refresca (anulación de cobros, etc.), reconsultamos
    // los contratos del evento elegido para que el contador "X / N" no quede desfasado.
    ref.listen<AsyncValue<FinanzasState>>(finanzasProvider, (prev, next) async {
      if (_eventoId == null || !mounted) return;
      final c = await ref.read(contratosRepositoryProvider).getByEvento(_eventoId!);
      if (!mounted) return;
      setState(() => _contratos = c);
      await _armarFilas(_institucion);
    });

    ref.listen<int>(contratosMutationTickProvider, (prev, next) async {
      if (prev == next || _eventoId == null || !mounted) return;
      await _cargarContratosYarmar(_eventoId);
    });

    final filasVista = _filasFiltradasVista();
    final muted = widget.isDark ? Colors.white54 : Colors.black54;
    if (_error != null && _eventosMasivos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No se pudo cargar: $_error', style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COBRO — EVENTOS MASIVOS',
                    style: GoogleFonts.oswald(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elegí un evento masivo. No se listan alumnos dados de baja. Podés buscar por nombre y filtrar por cuota base del plan: todos, al menos 1 cuota base, o ninguna.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              color: widget.gold,
              tooltip: 'Recargar',
              onPressed: _loadingEventos
                  ? null
                  : () async {
                      await _cargarEventos();
                      if (_eventoId != null) {
                        await _cargarContratosYarmar(_eventoId);
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loadingEventos)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else ...[
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — value controla el evento seleccionado (no solo valor inicial).
            value: _eventoId,
            decoration: const InputDecoration(
              labelText: 'Evento masivo',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Seleccionar evento...')),
              ..._eventosMasivos.map(
                (e) => DropdownMenuItem<String>(
                  value: e.id,
                  child: Text(_etiquetaEvento(e), overflow: TextOverflow.ellipsis, maxLines: 2),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _eventoId = v);
              _cargarContratosYarmar(v);
            },
          ),
          if (_eventoId != null && _loadingDetalle) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_eventoId != null && !_loadingDetalle) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _valorFiltroInstitucionValido(),
              decoration: const InputDecoration(
                labelText: 'Vista (institución opcional)',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(
                  value: _kCobroTodosInstitucion,
                  child: Text('Todos los alumnos del evento', overflow: TextOverflow.ellipsis),
                ),
                ..._instituciones.map(
                  (i) => DropdownMenuItem<String>(value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _institucion = v);
                _armarFilas(v);
              },
            ),
            if (_instituciones.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ningún contrato tiene el campo Institución cargado; igual podés ver a todos con la opción de arriba. Podés completar el dato en el detalle del evento masivo para filtrar por escuela.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.35),
                ),
              ),
            if (_filas.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _busquedaCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Buscar alumno',
                  hintText: 'Nombre…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _busquedaCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            setState(() {
                              _busquedaCtrl.clear();
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text('Cuota base (plan)', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Semantics(
                label: 'Filtro: todos, al menos 1 cuota base, o ninguna',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_CobroFiltroCuota>(
                    style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
                    segments: const [
                      ButtonSegment(
                        value: _CobroFiltroCuota.todos,
                        label: Text('Todos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      ButtonSegment(
                        value: _CobroFiltroCuota.conAlMenosUna,
                        label: Text('Al menos 1 cuota base', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      ButtonSegment(
                        value: _CobroFiltroCuota.ninguna,
                        label: Text('Ninguna', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    showSelectedIcon: false,
                    selected: <_CobroFiltroCuota>{_filtroCuota},
                    onSelectionChanged: (Set<_CobroFiltroCuota> s) {
                      if (s.isEmpty) return;
                      setState(() => _filtroCuota = s.first);
                    },
                  ),
                ),
              ),
            ],
          ],
        ],
        if (_error != null && _eventosMasivos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Aviso: $_error', style: const TextStyle(color: Colors.orange, fontSize: 12)),
        ],
        if (_institucion != null && !_loadingDetalle && _filas.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            _filas.length == filasVista.length
                ? '${_filas.length} alumno(s) activo(s) (excl. bajas)'
                : 'Mostrando ${filasVista.length} de ${_filas.length} alumno(s) activo(s) (excl. bajas)',
            style: TextStyle(color: widget.gold, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildResumenSeleccion(filasVista),
          if (filasVista.isEmpty)
            Text(
              'Ningún alumno coincide con la búsqueda o con el filtro de cuota.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.3),
            )
          else
            ...filasVista.map((f) => _tarjetaAlumno(f, muted)),
        ],
        if (_institucion != null && !_loadingDetalle && _filas.isEmpty && _error == null) ...[
          const SizedBox(height: 20),
          Text(
            _institucion == _kCobroTodosInstitucion
                ? 'No hay alumnos cargados en este evento.'
                : 'Sin alumnos para esta institución.',
            style: TextStyle(color: muted),
          ),
        ],
      ],
    );
  }

  Widget _tarjetaAlumno(_CobroFila f, Color muted) {
    final a = f.contrato;
    final mora = f.mora;
    final saldo = a.saldoDeudor;
    String estado;
    Color chipColor;
    if (saldo <= 0.01) {
      estado = 'LIQUIDADO';
      chipColor = Colors.green.shade700;
    } else if (mora.enMora) {
      estado = 'MORA${mora.diasMora > 0 ? ' · ${mora.diasMora} d' : ''}';
      chipColor = Colors.red.shade700;
    } else {
      estado = 'AL DÍA (saldo ${saldo.toCurrency()})';
      chipColor = Colors.blueGrey.shade600;
    }

    final wUri = _whatsAppUri(a.telefono, contrato: a, todosContratos: _contratos);
    final curso = a.cursoDivision?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _seleccionados.contains(a.id),
                  activeColor: widget.gold,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _seleccionados.add(a.id);
                      } else {
                        _seleccionados.remove(a.id);
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nombreAlumno,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      if (curso != null && curso.isNotEmpty)
                        Text(curso, style: TextStyle(fontSize: 12, color: muted)),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              a.contratoFirmado ? Icons.assignment_turned_in_outlined : Icons.pending_actions_outlined,
                              size: 14,
                              color: a.contratoFirmado ? Colors.teal : muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                a.contratoFirmado ? 'Contrato firmado' : 'Aún no firmó contrato',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: a.contratoFirmado ? Colors.teal : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (wUri != null)
                  IconButton(
                    icon: const Icon(Icons.chat_rounded, size: 20),
                    color: const Color(0xFF25D366),
                    tooltip: 'WhatsApp',
                    onPressed: () => _abrirWhatsappOClipboard(wUri, a),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(estado, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  backgroundColor: chipColor.withValues(alpha: 0.2),
                  side: BorderSide(color: chipColor.withValues(alpha: 0.4)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (f.primeraCuotaBase != null)
                  Text('1.ª cuota base: ${ArTime.formatFechaHora(f.primeraCuotaBase!)}', style: TextStyle(fontSize: 11, color: muted))
                else
                  Text('1.ª cuota base: —', style: TextStyle(fontSize: 11, color: muted)),
                if (f.ultimoPago != null)
                  Text('Últ. pago: ${ArTime.formatFechaHora(f.ultimoPago!)}', style: TextStyle(fontSize: 11, color: muted))
                else
                  Text('Últ. pago: —', style: TextStyle(fontSize: 11, color: muted)),
                if (a.telefono != null && a.telefono!.trim().isNotEmpty)
                  Text('Tel: ${a.telefono}', style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
            if (mora.fechaVencimientoProximaCuota != null && saldo > 0.01)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Vto. próx. cuota base: ${ArTime.formatFechaCorta(mora.fechaVencimientoProximaCuota!)}',
                  style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9)),
                ),
              ),
            if (f.cuotasVencidasCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 13, color: Colors.redAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Cuotas vencidas: ${f.cuotasVencidasCount} (${f.cuotasVencidasMonto.toCurrency()})',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            if (mora.enMora && f.moraPendiente > 0.01)
              Text(
                'Mora pendiente: ${f.moraPendiente.toCurrency()}',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirWhatsappOClipboard(String wUri, ContratoAlumno a) async {
    final nombreCorto = _primeraPalabraNombreAlumno(a.nombreAlumno);
    final saludo = nombreCorto.isNotEmpty ? 'Hola $nombreCorto, t' : 'T';
    final msg =
        '$saludo''e contactamos desde Junior Eventos para recordarte que la cuota de la recepción se encuentra vencida.\n\nMantener los pagos al día nos permite seguir organizando cada detalle del evento tal como fue planificado, garantizando la calidad y todo lo que los chicos esperan para esa noche tan especial ✨\n\nAdemás, abonando en fecha evitás intereses por mora y mantenés el valor acordado de la cuota.\n\nTe invitamos a acercarte a regularizar el pago por nuestra oficina Brasil 1346\n\nAnte cualquier consulta, estamos a disposición.';

    final n = wUri.replaceAll('https://wa.me/', '').split('?').first;
    
    final desktopUri = Uri.parse('whatsapp://send?phone=$n&text=${Uri.encodeComponent(msg)}');
    final webUri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(msg)}');

    try {
      bool ok = await launchUrl(desktopUri);
      if (!ok) {
        ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
      
      if (!mounted) return;
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: msg));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp. El mensaje quedó copiado al portapapeles.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: msg));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir WhatsApp. Mensaje copiado. ($e)')),
      );
    }
  }
}
