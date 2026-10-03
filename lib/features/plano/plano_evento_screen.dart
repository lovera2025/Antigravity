import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_engine.dart';
import '../../core/utils/uuid_utils.dart';
import '../../models/contrato_alumno.dart';
import '../../models/evento.dart';
import '../../models/movimiento_mesas.dart';
import '../../models/plano_evento.dart';
import '../../models/sillas_reparto.dart';
import '../../models/sorteo_mesas_registro.dart';
import '../common/services/pdf_service.dart';
import '../common/utils/quien_opera.dart';
import '../common/utils/subir_ya.dart';
import '../eventos/repositories/contratos_repository.dart';
import '../eventos/repositories/entradas_retiro_repository.dart';
import '../eventos/repositories/sillas_reparto_repository.dart';
import '../eventos/repositories/sorteos_mesas_repository.dart';
import '../eventos/services/registro_sorteo.dart';
import '../eventos/services/salon_mesas.dart';
import 'estilos/estilo_plano.dart';
import 'modelo/medidas_salon.dart';
import 'repositories/mesas_movimientos_repository.dart';
import 'repositories/planos_evento_repository.dart';
import 'services/aplicar_eleccion.dart';
import 'services/armar_a_medida.dart';
import 'services/cambios_de_mesa.dart';
import 'services/colores_y_textos.dart';
import 'services/historial_sorteo.dart';
import 'services/plano_de_la_fiesta.dart';
import 'widgets/cambio_de_mesa_dialogs.dart';
import 'widgets/elegir_plano_dialog.dart';
import 'widgets/imprimir_plano_dialog.dart';
import 'widgets/plano_evento_cuerpo.dart';

/// El plano del salón de una fiesta: el armado con sus medidas, las familias
/// en sus mesas y lo que hay que revisar.
///
/// Lee siempre los datos del momento (las fichas, el reparto de sillas y el
/// plano), y se refresca sola cuando baja un cambio de la otra PC.
///
/// IMPRIMIR arma el plano en papel con lo mismo que se ve: no lee ni guarda
/// nada.
///
/// Escribe tres cosas, y antes de escribir relee de la nube:
/// - `planos_evento`: el armado, el estilo, las mesas fijas y las libres;
/// - el número de mesa de las familias que se cambian o se mueven, igual que
///   el sorteo (`ContratosRepository.asignarNumerosMesa`);
/// - un renglón en `mesas_movimientos` por cada cambio, con su motivo, en la
///   misma transacción que los números.
class PlanoEventoScreen extends ConsumerStatefulWidget {
  final Evento evento;

  /// La familia que se abre resaltada, cuando se llega desde su renglón.
  final String? resaltarAlumnoId;

  /// Se llegó desde PLANILLAS → "Plano impreso": apenas carga, pregunta cómo
  /// se imprime. Si la fiesta no tiene plano no pregunta nada.
  final bool imprimirAlAbrir;

  const PlanoEventoScreen({
    super.key,
    required this.evento,
    this.resaltarAlumnoId,
    this.imprimirAlAbrir = false,
  });

  @override
  ConsumerState<PlanoEventoScreen> createState() => _PlanoEventoScreenState();
}

class _PlanoEventoScreenState extends ConsumerState<PlanoEventoScreen> {
  bool _cargando = true;
  bool _ocupado = false;
  String? _errorCarga;
  List<ContratoAlumno> _alumnos = [];
  Map<String, SillasReparto> _repartos = {};
  PlanoEvento? _plano;

  /// Los sorteos y los cambios de mesa registrados, para el Historial.
  List<SorteoMesasRegistro> _registros = [];
  List<MovimientoMesas> _movimientos = [];

  /// Las familias que ya retiraron sus entradas: si se les cambia la mesa hay
  /// que avisarles.
  Set<String> _yaRetiraron = {};

  /// Lo que se muestra, ya calculado. Null si la fiesta no tiene plano o si su
  /// armado no se puede leer.
  PlanoDeLaFiesta? _vista;
  bool _yaOfrecioArmar = false;

  /// Bajó algo de la otra PC mientras se guardaba un cambio: se relee al
  /// terminar. Si se descartara, la pantalla quedaría mostrando mesas viejas
  /// justo después de decir "esperá a que llegue lo de la otra PC".
  bool _llegoAlgoMientrasGuardaba = false;
  StreamSubscription<Set<String>>? _cambiosSub;

  /// Para cerrar el aviso con DESHACER al salir: si quedara a la vista en la
  /// pantalla de atrás, el botón no haría nada y parecería que deshizo.
  ScaffoldMessengerState? _mensajes;

  /// Lo que, si baja de la otra PC, cambia lo que se ve acá.
  static const _tablasQueMiro = {
    'planos_evento',
    'contratos_alumnos',
    'sillas_reparto',
    'mesas_movimientos',
    'sorteos_mesas',
    'entradas_retiro',
  };

  @override
  void initState() {
    super.initState();
    _cargar(nube: true).then((_) {
      _ofrecerArmar();
      if (mounted && widget.imprimirAlAbrir) _imprimir();
    });
    _cambiosSub = ref.read(syncEngineProvider).cambiosBajadosStream.listen((
      tablas,
    ) {
      if (!tablas.any(_tablasQueMiro.contains)) return;
      // Lo que bajó ya está en la base de esta PC: alcanza con releerla.
      if (_ocupado) {
        _llegoAlgoMientrasGuardaba = true;
      } else {
        _cargar(silencioso: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mensajes = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _cambiosSub?.cancel();
    final mensajes = _mensajes;
    if (mensajes != null) {
      // Después de este cuadro: cerrar el aviso en medio del desmontaje no se
      // puede.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mensajes.mounted) mensajes.hideCurrentSnackBar();
      });
    }
    super.dispose();
  }

  bool get _hayConexion =>
      ref.read(connectivityServiceProvider).currentStatus ==
      AppConnectivity.online;

  /// El plano de la fiesta: con [nube], primero el de la nube (por si la otra
  /// PC lo tocó hace un momento) y, si no se pudo, el de esta PC. [deLaNube]
  /// dice si se pudo consultar: sin eso no se sabe si la otra PC lo cambió.
  Future<({PlanoEvento? plano, bool deLaNube})> _leerPlano({
    required bool nube,
  }) async {
    final planos = ref.read(planosEventoRepositoryProvider);
    final id = widget.evento.id;
    if (nube && _hayConexion) {
      try {
        final plano = await planos.traerDeLaNube(id);
        // Si la nube no lo tiene puede estar acá, esperando subir.
        return (plano: plano ?? await planos.obtener(id), deLaNube: true);
      } catch (_) {
        // Sin red, o la tabla todavía no existe en la nube: manda esta PC.
      }
    }
    return (plano: await planos.obtener(id), deLaNube: false);
  }

  Future<void> _cargar({bool nube = false, bool silencioso = false}) async {
    try {
      final alumnos = await ref
          .read(contratosRepositoryProvider)
          .getByEvento(widget.evento.id);
      final ids = [for (final a in alumnos) a.id];
      final repartos = await ref
          .read(sillasRepartoRepositoryProvider)
          .obtenerPorContratoIds(ids);
      final retiros = await ref
          .read(entradasRetiroRepositoryProvider)
          .obtenerPorContratoIds(ids);
      final registros = await ref
          .read(sorteosMesasRepositoryProvider)
          .delEvento(widget.evento.id);
      final movimientos = await ref
          .read(mesasMovimientosRepositoryProvider)
          .delEvento(widget.evento.id);
      final plano = (await _leerPlano(nube: nube)).plano;
      final armado = plano?.armadoONull;
      final vista = plano == null || armado == null
          ? null
          : PlanoDeLaFiesta.desde(
              armado: armado,
              config: plano.config,
              alumnos: alumnos,
              repartos: repartos,
            );
      if (!mounted) return;
      setState(() {
        _alumnos = alumnos;
        _repartos = repartos;
        _registros = registros;
        _movimientos = movimientos;
        _yaRetiraron = {
          for (final e in retiros.entries)
            if (e.value.entregado) e.key,
        };
        _plano = plano;
        _vista = vista;
        _cargando = false;
        _errorCarga = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (!silencioso) _errorCarga = '$e';
      });
    }
  }

  /// Termina un guardado: suelta la pantalla y, si mientras tanto bajó algo de
  /// la otra PC, lo relee.
  void _terminar() {
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (_llegoAlgoMientrasGuardaba) {
      _llegoAlgoMientrasGuardaba = false;
      _cargar(silencioso: true);
    }
  }

  /// La primera vez que se entra, la fiesta no tiene plano: se abren los tres
  /// pasos sin que haya que buscar el botón.
  void _ofrecerArmar() {
    if (!mounted || _yaOfrecioArmar || _errorCarga != null) return;
    _yaOfrecioArmar = true;
    if (_plano == null) _elegir();
  }

  bool get _hayFamiliasConMesa =>
      _alumnos.any((a) => !a.esBajaTemporal && SalonMesas.tieneNumeros(a));

  // ── Avisos y preguntas ──────────────────────────────────────────────────

  void _decir(String texto, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        action: accion,
        duration: Duration(seconds: accion == null ? 4 : 8),
        persist: false,
      ));
  }

  Future<void> _avisar(String titulo, String texto) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ENTENDIDO'),
          ),
        ],
      ),
    );
  }

  Future<bool> _preguntar(String titulo, String texto) async {
    if (!mounted) return false;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('SEGUIR'),
          ),
        ],
      ),
    );
    return seguir == true;
  }

  /// El plano sube como una fila entera: si no se pudo leer el de la nube,
  /// guardar desde acá puede pisar lo que la otra PC hizo recién. Se pregunta,
  /// nombrando el riesgo.
  Future<bool> _seguirSinLaNube() => _preguntar(
        'Sin conexión',
        'No se pudo leer el plano de la nube. Si la otra PC lo cambió hace un '
            'momento (fijó o liberó una mesa), al guardar desde acá se pierde '
            'lo que hizo. Seguí solo si el plano se toca únicamente desde esta '
            'PC.',
      );

  static String _textoOtraPc(int familias) =>
      'La otra PC cambió mesas de $familias '
      '${familias == 1 ? 'familia' : 'familias'} y todavía no llegaron acá. '
      'Esperá unos segundos y probá de nuevo.';

  String _apellidoDe(String id, [List<ContratoAlumno>? alumnos]) {
    for (final a in alumnos ?? _alumnos) {
      if (a.id == id) return CambiosDeMesa.apellido(a);
    }
    return 'La familia';
  }

  // ── Estilo y armado ─────────────────────────────────────────────────────

  Future<void> _elegir() async {
    if (_ocupado) return;
    final actual = _plano;
    final tieneArmado = actual?.armadoONull != null;
    final eleccion = await mostrarElegirPlano(
      context: context,
      mesasNecesarias: PlanoDeLaFiesta.mesasQueNecesita(_alumnos),
      medidas: actual?.config.medidas ?? const MedidasPlano(),
      actual: actual,
      ocupantes: PlanoDeLaFiesta.ocupantes(_alumnos, _repartos),
      armadoTrabado: tieneArmado && _hayFamiliasConMesa
          ? 'Ya hay familias con mesa: para cambiar el armado hay que deshacer '
              'el sorteo. El estilo se cambia siempre.'
          : null,
    );
    if (eleccion == null || !mounted) return;
    await _guardar(eleccion);
  }

  Future<void> _guardar(EleccionPlano eleccion) async {
    setState(() => _ocupado = true);
    try {
      final planos = ref.read(planosEventoRepositoryProvider);
      final motor = ref.read(syncEngineProvider);
      final quien = quienOpera(ref);
      final desde = DateTime.now().toUtc();
      // Antes de escribir, lo que diga la nube: sube la fila entera, y con la
      // de esta PC se pisaría lo que la otra acaba de cambiar.
      final lectura = await _leerPlano(nube: true);
      if (!lectura.deLaNube && !await _seguirSinLaNube()) return;
      final resultado = aplicarEleccionAlPlano(
        eventoId: widget.evento.id,
        fresco: lectura.plano,
        armado: eleccion.armado,
        estilo: eleccion.estilo,
        modo: eleccion.modo,
        hayFamiliasConMesa: _hayFamiliasConMesa,
        hechoPor: quien,
        ahora: DateTime.now().toUtc(),
      );
      final nuevo = resultado.plano;
      // El diálogo ya no dejaba cambiar el armado si acá se veía el plano. Si
      // se conservó sin que se viera, es que lo armó la otra PC.
      final aviso = resultado.conservoArmado && _plano?.armadoONull == null
          ? 'La otra PC ya había armado el plano: se conservó su armado.'
          : null;
      await planos.guardar(nuevo);
      await _cargar();
      final subio = await subirYa(
        motor,
        tabla: 'planos_evento',
        registroId: nuevo.id,
        desde: desde,
      );
      _decir(
        '${aviso ?? 'Plano guardado.'}'
        '${subio ? '' : ' Quedó en esta PC; sube cuando vuelva la conexión.'}',
      );
    } catch (e) {
      _decir('No se pudo guardar el plano. ($e)');
    } finally {
      _terminar();
    }
  }

  // ── Personalizar: fijar y dejar libres ──────────────────────────────────

  /// Cambia lo configurado del plano (fijar, dejar libre): relee el plano de
  /// la nube y las familias, vuelve a hacer la cuenta sobre eso y recién ahí
  /// guarda.
  Future<void> _cambiarConfig(
    CambioDeConfig Function(PlanoEvento plano, List<ContratoAlumno> alumnos)
        calcular, {
    required String Function(CambioDeConfig cambio) hecho,
  }) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final contratos = ref.read(contratosRepositoryProvider);
      final planos = ref.read(planosEventoRepositoryProvider);
      final motor = ref.read(syncEngineProvider);
      final quien = quienOpera(ref);
      final eventoId = widget.evento.id;
      final desde = DateTime.now().toUtc();
      // Si la otra PC sorteó o movió mesas y todavía no bajaron, fijar o dejar
      // libre sobre lo que se ve acá puede caer en una mesa que ya se dio.
      final distintos = await contratos.mesasDeOtraPcSinBajar(eventoId);
      if (distintos != null && distintos > 0) {
        await _avisar('Todavía no', _textoOtraPc(distintos));
        return;
      }
      final lectura = await _leerPlano(nube: distintos != null);
      if (!lectura.deLaNube && !await _seguirSinLaNube()) return;
      final fresco = lectura.plano;
      if (fresco == null || fresco.armadoONull == null) {
        await _avisar(
          'No se puede',
          'El plano de la fiesta ya no se puede leer. Tocá Actualizar y probá '
              'de nuevo.',
        );
        await _cargar();
        return;
      }
      final alumnos = await contratos.getByEvento(eventoId);
      final cambio = calcular(fresco, alumnos);
      final config = cambio.config;
      if (config == null) {
        await _avisar('No se puede', cambio.problema ?? 'No se puede.');
        await _cargar();
        return;
      }
      final nuevo = fresco.copyWith(
        config: config,
        armado: cambio.armado,
        hechoPor: quien,
        ahora: DateTime.now().toUtc(),
      );
      await planos.guardar(nuevo);
      await _cargar();
      final subio = await subirYa(
        motor,
        tabla: 'planos_evento',
        registroId: nuevo.id,
        desde: desde,
      );
      _decir(
        '${hecho(cambio)}'
        '${subio ? '' : ' Quedó en esta PC; sube cuando vuelva la conexión.'}',
      );
    } catch (e) {
      _decir('No se pudo guardar. ($e)');
    } finally {
      _terminar();
    }
  }

  CambioDeConfig _calcularFijar(
    PlanoEvento plano,
    List<ContratoAlumno> alumnos,
    String alumnoId,
    int desdeMesa,
    String motivo,
    String? por,
  ) =>
      CambiosDeMesa.fijar(
        armado: plano.armado,
        config: plano.config,
        alumnos: alumnos,
        alumnoId: alumnoId,
        desdeMesa: desdeMesa,
        motivo: motivo,
        por: por,
        ahora: DateTime.now().toUtc(),
      );

  String _hechoFijar(CambioDeConfig c, String alumnoId) =>
      '${c.mesas.length == 1 ? 'Quedó fijada' : 'Quedaron fijadas'} '
      '${CambiosDeMesa.textoMesas(c.mesas)} para ${_apellidoDe(alumnoId)}.';

  /// Una familia sin mesa eligió, en el plano, dónde empiezan sus mesas.
  Future<void> _fijar(String alumnoId, int desdeMesa) async {
    final plano = _plano;
    if (_ocupado || plano == null || plano.armadoONull == null) return;
    final quien = quienOpera(ref);
    // Antes de pedir el motivo, que se pueda: si no, se dice por qué.
    final previa =
        _calcularFijar(plano, _alumnos, alumnoId, desdeMesa, '-', quien);
    if (!previa.sePuede) {
      await _avisar('No se puede fijar ahí', previa.problema!);
      return;
    }
    final motivo = await confirmarCambioDeMesa(
      context: context,
      titulo: 'Fijar ${CambiosDeMesa.textoMesas(previa.mesas)} para '
          '${_apellidoDe(alumnoId)}',
      renglones: const ['El sorteo le va a dar esas mesas.'],
      sugerencias: motivosParaFijar,
      textoConfirmar: 'FIJAR',
    );
    if (motivo == null || !mounted) return;
    await _cambiarConfig(
      (p, alumnos) =>
          _calcularFijar(p, alumnos, alumnoId, desdeMesa, motivo, quien),
      hecho: (c) => _hechoFijar(c, alumnoId),
    );
  }

  /// Desde una mesa vacía: falta elegir para qué familia.
  Future<void> _fijarEnMesa(int mesa) async {
    final plano = _plano;
    if (_ocupado || plano == null || plano.armadoONull == null) return;
    final quien = quienOpera(ref);
    final eleccion = await elegirFamiliaParaFijar(
      context: context,
      mesa: mesa,
      candidatos: [
        for (final a in _alumnos)
          if (!a.esBajaTemporal && (a.numeroMesa ?? '').trim().isEmpty) a,
      ],
      resultadoDe: (id) {
        final r = _calcularFijar(plano, _alumnos, id, mesa, '-', quien);
        return (mesas: r.mesas, problema: r.problema);
      },
    );
    if (eleccion == null || !mounted) return;
    await _cambiarConfig(
      (p, alumnos) => _calcularFijar(
        p,
        alumnos,
        eleccion.alumnoId,
        mesa,
        eleccion.motivo,
        quien,
      ),
      hecho: (c) => _hechoFijar(c, eleccion.alumnoId),
    );
  }

  /// Quitar una fijada pierde su motivo y deja la mesa para cualquiera: se
  /// confirma, diciendo qué se pierde.
  Future<void> _quitarFijadas(String alumnoId) async {
    final plano = _plano;
    if (_ocupado || plano == null) return;
    final mesas = plano.config.fijadasPorAlumno[alumnoId] ?? const <int>[];
    if (mesas.isEmpty) return;
    final motivo = plano.config.fijadas[mesas.first]?.motivo?.trim() ?? '';
    final quien = _apellidoDe(alumnoId);
    final ok = await confirmarCambioDeMesa(
      context: context,
      titulo: 'Quitarle a $quien sus mesas fijadas',
      renglones: [
        '${mesas.length == 1 ? 'Era' : 'Eran'} '
            '${CambiosDeMesa.textoMesas(mesas)}'
            '${motivo.isEmpty ? '' : ' ($motivo)'}.',
        'El sorteo se las puede dar a otra familia.',
      ],
      pedirMotivo: false,
      textoConfirmar: 'QUITAR',
    );
    if (ok == null || !mounted) return;
    await _cambiarConfig(
      (p, _) => CambiosDeMesa.quitarFijadas(p.config, alumnoId),
      hecho: (_) => 'Se quitaron las mesas fijadas de $quien.',
    );
  }

  Future<void> _quitarFijadaDeMesa(int mesa) => _cambiarConfig(
        (p, _) => CambiosDeMesa.quitarFijadaDeMesa(p.config, mesa),
        hecho: (_) => 'Se quitó la fijada de la mesa $mesa.',
      );

  Future<void> _dejarLibre(int mesa) async {
    final plano = _plano;
    if (_ocupado || plano == null || plano.armadoONull == null) return;
    final quien = quienOpera(ref);
    CambioDeConfig calcular(
      PlanoEvento p,
      List<ContratoAlumno> alumnos,
      String? motivo,
    ) =>
        CambiosDeMesa.dejarLibre(
          armado: p.armado,
          config: p.config,
          alumnos: alumnos,
          mesa: mesa,
          motivo: motivo,
          por: quien,
          ahora: DateTime.now().toUtc(),
        );

    final previa = calcular(plano, _alumnos, null);
    if (!previa.sePuede) {
      await _avisar('No se puede dejar libre', previa.problema!);
      return;
    }
    final motivo = await confirmarCambioDeMesa(
      context: context,
      titulo: 'Dejar libre la mesa $mesa',
      renglones: const ['El sorteo no la va a dar a ninguna familia.'],
      motivoObligatorio: false,
      sugerencias: motivosParaLibre,
      textoConfirmar: 'DEJAR LIBRE',
    );
    if (motivo == null || !mounted) return;
    await _cambiarConfig(
      (p, alumnos) => calcular(p, alumnos, motivo),
      hecho: (_) => 'La mesa $mesa quedó libre.',
    );
  }

  Future<void> _volverAUsar(int mesa) => _cambiarConfig(
        (p, _) => CambiosDeMesa.volverAUsar(p.config, mesa),
        hecho: (_) => 'La mesa $mesa vuelve a entrar en el sorteo.',
      );

  // ── Personalizar: medidas ───────────────────────────────────────────────

  /// Las medidas del playón y de las mesas. En un salón armado a medida, con
  /// otro playón se redibuja el borde del hormigón; las mesas no se mueven.
  Future<void> _guardarMedidas(MedidasPlano medidas) => _cambiarConfig(
        (p, _) {
          final armado = ArmarAMedida.conPlayon(p.armado, medidas.playon);
          return CambioDeConfig.ok(
            p.config.copyWith(medidas: medidas),
            const [],
            armado: identical(armado, p.armado) ? null : armado,
          );
        },
        hecho: (c) => c.armado == null
            ? 'Medidas guardadas.'
            : 'Medidas guardadas. Se redibujó el borde del hormigón.',
      );

  // ── Personalizar: colores y textos ──────────────────────────────────────

  /// El color de cada división, el título y los textos de los sectores. Los
  /// textos van en el armado: si la otra PC acomodó el salón mientras tanto y
  /// un sector ya no está como se veía, no se guarda nada.
  Future<void> _guardarColoresYTextos(ColoresYTextos cambio) => _cambiarConfig(
        (p, _) => cambio.aplicar(p.armado, p.config),
        hecho: (_) => 'Colores y textos guardados.',
      );

  // ── Personalizar: cambiar y mover familias ──────────────────────────────

  /// Cambia los números de mesa de una o dos familias y deja el renglón con el
  /// motivo, todo junto.
  ///
  /// [calcular] se llama dos veces: con lo que se ve, para mostrar cómo queda
  /// antes de confirmar; y después de releer la nube y la base, para guardar
  /// sobre lo que hay de verdad. **Si la segunda cuenta no da lo mismo que se
  /// mostró, no se guarda**: se avisa y se vuelve a mostrar.
  Future<void> _cambiarMesas(
    CambioDeMesas Function(
      PlanoEvento plano,
      List<ContratoAlumno> alumnos,
      List<MovimientoMesas> movimientos,
    ) calcular, {
    required String titulo,
    String? motivoFijo,
    String textoConfirmar = 'CONFIRMAR',
  }) async {
    final plano = _plano;
    if (!mounted || _ocupado || plano == null || plano.armadoONull == null) {
      return;
    }
    final previa = calcular(plano, _alumnos, _movimientos);
    if (!previa.sePuede) {
      await _avisar('No se puede', previa.problema!);
      return;
    }
    final escrito = await confirmarCambioDeMesa(
      context: context,
      titulo: titulo,
      renglones: previa.renglones(_apellidoDe),
      avisos: previa.avisos,
      pedirMotivo: motivoFijo == null,
      sugerencias: motivosParaCambiar,
      hayQueAvisarALaFamilia: previa.hayQueAvisarALaFamilia,
      textoConfirmar: textoConfirmar,
    );
    if (escrito == null || !mounted) return;

    setState(() => _ocupado = true);
    try {
      final contratos = ref.read(contratosRepositoryProvider);
      final movimientosRepo = ref.read(mesasMovimientosRepositoryProvider);
      final motor = ref.read(syncEngineProvider);
      final quien = quienOpera(ref);
      final eventoId = widget.evento.id;
      final desde = DateTime.now().toUtc();
      // Si la otra PC cambió mesas y todavía no bajaron, escribir encima sería
      // darle a dos familias la misma mesa.
      final distintos = await contratos.mesasDeOtraPcSinBajar(eventoId);
      if (distintos != null && distintos > 0) {
        await _avisar('Todavía no', _textoOtraPc(distintos));
        return;
      }
      if (distintos == null &&
          !await _preguntar(
            'Sin conexión',
            'No se puede verificar si la otra PC cambió mesas o el plano de '
                'esta fiesta. Seguí solo si las mesas se tocan únicamente '
                'desde esta PC.',
          )) {
        return;
      }
      final lectura = await _leerPlano(nube: distintos != null);
      // Había conexión para las mesas pero el plano no se pudo leer.
      if (distintos != null &&
          !lectura.deLaNube &&
          !await _seguirSinLaNube()) {
        return;
      }
      final fresco = lectura.plano;
      if (fresco == null || fresco.armadoONull == null) {
        await _avisar(
          'No se puede',
          'El plano de la fiesta ya no se puede leer. Tocá Actualizar y probá '
              'de nuevo.',
        );
        return;
      }
      final alumnos = await contratos.getByEvento(eventoId);
      final movimientos = await movimientosRepo.delEvento(eventoId);
      final cambio = calcular(fresco, alumnos, movimientos);
      if (!cambio.sePuede) {
        await _avisar('Ya no se puede', cambio.problema!);
        await _cargar();
        return;
      }
      if (!cambio.esElMismoQue(previa)) {
        await _avisar(
          'Las mesas cambiaron recién',
          'Las mesas de estas familias cambiaron en la otra PC mientras '
              'confirmabas. No se guardó nada: mirá cómo quedaron y hacé el '
              'cambio de nuevo.',
        );
        await _cargar();
        return;
      }
      final ahora = DateTime.now().toUtc();
      final renglon = cambio.movimiento(
        id: UuidUtils.generate(),
        eventoId: eventoId,
        motivo: motivoFijo ?? escrito,
        hechoPor: quien,
        ahora: ahora,
      );
      final config = cambio.config;
      final planoNuevo = config == null
          ? null
          : fresco.copyWith(config: config, hechoPor: quien, ahora: ahora);
      // Los números, el renglón y el plano, en una sola transacción.
      await contratos.asignarNumerosMesa(
        cambio.despues,
        movimiento: renglon,
        plano: planoNuevo,
      );
      await _cargar();
      final subio = await subirYa(
            motor,
            tabla: 'mesas_movimientos',
            registroId: renglon.id,
            desde: desde,
          ) &&
          !await quedaEnCola({
            'contratos_alumnos': cambio.despues.keys,
            if (planoNuevo != null) 'planos_evento': [planoNuevo.id],
          });
      _decir(
        '${cambio.textoHecho((id) => _apellidoDe(id, alumnos))}'
        '${subio ? '' : ' Quedó en esta PC; sube cuando vuelva la conexión.'}',
        accion: cambio.tipo == TipoMovimientoMesas.deshacer
            ? null
            : SnackBarAction(
                label: 'DESHACER',
                onPressed: () {
                  if (mounted) _deshacer(renglon);
                },
              ),
      );
    } catch (e) {
      _decir('No se pudo guardar el cambio. ($e)');
    } finally {
      _terminar();
    }
  }

  Future<void> _cambiar(String alumnoId, String otroId) => _cambiarMesas(
        (plano, alumnos, _) => CambiosDeMesa.intercambiar(
          armado: plano.armado,
          config: plano.config,
          alumnos: alumnos,
          alumnoId: alumnoId,
          otroId: otroId,
          yaRetiraron: _yaRetiraron,
        ),
        titulo: '${_apellidoDe(alumnoId)} y ${_apellidoDe(otroId)} cambian '
            'de lugar',
        textoConfirmar: 'CAMBIAR',
      );

  Future<void> _mover(String alumnoId, int desdeMesa) => _cambiarMesas(
        (plano, alumnos, _) => CambiosDeMesa.mover(
          armado: plano.armado,
          config: plano.config,
          alumnos: alumnos,
          alumnoId: alumnoId,
          desdeMesa: desdeMesa,
          yaRetiraron: _yaRetiraron,
        ),
        titulo: '${_apellidoDe(alumnoId)} pasa a otras mesas',
        textoConfirmar: 'MOVER',
      );

  /// Vuelve atrás un cambio. El renglón nuevo guarda como motivo el del
  /// cambio que se deshace: el Historial lo muestra como "El cambio era por…".
  Future<void> _deshacer(MovimientoMesas movimiento) => _cambiarMesas(
        (plano, alumnos, movimientos) => CambiosDeMesa.deshacer(
          movimiento: movimiento,
          movimientos: movimientos,
          alumnos: alumnos,
          config: plano.config,
          yaRetiraron: _yaRetiraron,
        ),
        titulo: 'Deshacer el cambio',
        motivoFijo: movimiento.motivo,
        textoConfirmar: 'DESHACER',
      );

  /// El plano en papel, con lo que la pantalla muestra en este momento. Lleva
  /// arriba quién sorteó y cuándo, como la planilla del sorteo.
  Future<void> _imprimir() async {
    final plano = _plano;
    final vista = _vista;
    if (_ocupado || plano == null || vista == null) return;
    final blancoYNegro = await elegirComoImprimirPlano(
      context,
      hojas: vista.armado.hojas.length,
    );
    if (blancoYNegro == null || !mounted) return;
    try {
      await PdfService.generarPlanoPdf(
        widget.evento,
        vista,
        estilo: plano.estiloPlano ?? EstiloPlano.arquitecto,
        lineaSorteo: RegistroSorteo.lineaParaPlanilla(
          RegistroSorteo.resumir(
            _registros,
            _alumnos,
            movimientos: _movimientos,
          ),
        ),
        blancoYNegro: blancoYNegro,
      );
    } catch (e) {
      _decir('No se pudo armar el plano para imprimir. ($e)');
    }
  }

  Future<void> _abrirHistorial() => mostrarHistorialSorteo(
        context: context,
        historial: HistorialSorteo.armar(
          registros: _registros,
          movimientos: _movimientos,
          config: _plano?.config ?? ConfigPlano.vacia,
          alumnos: _alumnos,
          yaRetiraron: _yaRetiraron,
        ),
        onDeshacer: _deshacer,
      );

  @override
  Widget build(BuildContext context) {
    final institucion = widget.evento.cliente?.nombreCompleto ?? 'Evento';
    // Mientras se guarda no se sale: lo confirmado tiene que terminar de
    // escribirse y de avisar cómo quedó.
    return PopScope(
      canPop: !_ocupado,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plano del salón'),
              Text(
                institucion,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _ocupado ? null : () => _cargar(nube: true),
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _errorCarga != null
                ? Center(child: Text('No se pudo cargar: $_errorCarga'))
                : _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    final plano = _plano;
    final vista = _vista;
    if (plano == null || vista == null) {
      return _SinPlano(
        ilegible: plano != null,
        onArmar: _ocupado ? null : _elegir,
      );
    }
    return PlanoEventoCuerpo(
      // Con otro armado se arranca de cero: hoja, zoom y selección. Va por la
      // clave del armado y no por su contenido: acomodar el salón o redibujar
      // el hormigón cambia el contenido, y no tiene que sacar a nadie de
      // Personalizar.
      key: ValueKey(plano.armadoClave),
      plano: vista,
      estilo: plano.estiloPlano ?? EstiloPlano.arquitecto,
      alumnos: _alumnos,
      repartos: _repartos,
      resaltarAlumnoId: widget.resaltarAlumnoId,
      ocupado: _ocupado,
      onEstiloYArmado: _elegir,
      acciones: AccionesPlano(
        onFijarEnMesa: _fijarEnMesa,
        onFijar: _fijar,
        onQuitarFijadas: _quitarFijadas,
        onQuitarFijadaDeMesa: _quitarFijadaDeMesa,
        onDejarLibre: _dejarLibre,
        onVolverAUsar: _volverAUsar,
        onCambiar: _cambiar,
        onMover: _mover,
        onGuardarMedidas: _guardarMedidas,
        onGuardarColoresYTextos: _guardarColoresYTextos,
      ),
      onImprimir: _imprimir,
      onHistorial: _abrirHistorial,
    );
  }
}

/// La fiesta todavía no tiene plano (o el que tiene no se puede leer).
class _SinPlano extends StatelessWidget {
  final bool ilegible;
  final VoidCallback? onArmar;

  const _SinPlano({required this.ilegible, required this.onArmar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant_outlined,
                size: 56, color: tema.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              ilegible
                  ? 'El armado de esta fiesta no se puede leer'
                  : 'Esta fiesta todavía no tiene plano',
              style: tema.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              ilegible
                  ? 'Elegí el armado de nuevo. Lo demás del plano se conserva.'
                  : 'Se arma en tres pasos y ya viene todo elegido: el armado '
                      'del salón, el estilo y cómo se sortea.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('armar_plano'),
              onPressed: onArmar,
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: Text(ilegible ? 'ELEGIR EL ARMADO' : 'ARMAR EL PLANO'),
            ),
          ],
        ),
      ),
    );
  }
}
