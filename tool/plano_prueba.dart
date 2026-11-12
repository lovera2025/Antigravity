// Ventana de prueba: la pantalla del plano de verdad (Personalizar, Acomodar, los
// avisos, el botón de guardar e IMPRIMIR) con el plano real de Puerto Viejo, **sin
// tocar la base de la PC ni la nube**. Guardar se queda en esta ventana y al cerrarla
// se olvida todo.
//
//   flutter run -d windows -t tool/plano_prueba.dart
//
// No corre `main.dart`: no abre la base ni inicia sesión. Las familias son inventadas
// y justas para las 35 mesas: dos "lejos" (una cerca y una bien lejos), tres con
// adicional y el resto con una. Arriba, una barra para sortear con el sorteo de verdad
// (y ver que con sorteo ningún número cambia), deshacerlo, y volver al plano mezclado.
// IMPRIMIR deja el PDF en `build/plano_prueba`, sin abrir el diálogo de la impresora.
//
// 6.5.0: "Dejar libre" pregunta **No se usa · Es para alguien** y una mesa libre tiene
// "Para quién es", con la misma cuenta que la pantalla de la app (la mesa de los profes).
// Para recorrerla en el navegador de la app (IMPRIMIR ahí no deja el PDF):
//   flutter build web -t tool/plano_prueba.dart --no-web-resources-cdn --output build/plano_prueba_web
//   python -I -m http.server 8795 --directory build/plano_prueba_web

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/modelo/reserva_de_mesa.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/plano/services/numeracion_recordada.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/widgets/ver_el_orden_dialog.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/features/plano/widgets/cambio_de_mesa_dialogs.dart';
import 'package:arguello_events/features/plano/widgets/imprimir_plano_dialog.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/features/plano/widgets/reserva_de_mesa_dialog.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

import '../test/helpers/salon_puerto_viejo.dart';

void main() => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: const PruebaDelPlano(),
      ),
    );

/// Una familia inventada: [extras] mesas adicionales y, si ya tiene, sus [mesas].
ContratoAlumno _familia(
  String id,
  String nombre, {
  int extras = 0,
  List<int>? mesas,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'prueba',
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas == null ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
      // Alta el 30/3: la cuota 1 vence el 30/4 (para "Mesas por orden", 6.7.0).
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

/// Los pagos inventados de cada familia, para "Mesas por orden" (6.7.0): unas
/// cancelaron, otras están al día, otras pagaron tarde y otras deben. Todas
/// pagaron sus mesas adicionales.
Map<String, List<Map<String, dynamic>>> pagosDePrueba() {
  var n = 0;
  Map<String, dynamic> pago(int mes, int dia, double monto,
      {String concepto = 'Cuota Base'}) {
    n++;
    final fecha = DateTime.utc(2026, mes, dia, 15);
    return {
      'id': 'p$n',
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'fecha_pago': fecha.toIso8601String(),
      'created_at': fecha.add(Duration(seconds: n)).toIso8601String(),
      'anulado': 0,
    };
  }

  final r = <String, List<Map<String, dynamic>>>{};
  final alumnos = alumnosDePrueba();
  for (var i = 0; i < alumnos.length; i++) {
    final a = alumnos[i];
    final cuota = MoraCuotaCalculator.cuotaBaseDe(a);
    r[a.id] = [
      ...switch (i % 4) {
        // Canceló todo, cada una un día distinto de abril.
        0 => [pago(4, 3 + i % 25, cuota * 9)],
        // Al día: las siete vencidas, pagadas juntas en término.
        1 => [pago(4, 30, cuota * 7)],
        // Pagó tarde la primera, cada una con distintos días.
        2 => [pago(5, 1 + i % 28, cuota), pago(5, 31, cuota * 6)],
        // Debe las dos últimas.
        _ => [pago(4, 30, cuota * 5)],
      },
      if (a.mesaExtraPrecio > 0)
        pago(6, 1, a.mesaExtraPrecio, concepto: 'Mesa extra (1/1)'),
    ];
  }
  return r;
}

/// Las familias, con las mesas de [asignaciones] (sin nada, nadie tiene mesa). Piden
/// 35 mesas en total, justo lo que hay: así es una fiesta de verdad.
List<ContratoAlumno> alumnosDePrueba({Map<String, List<int>>? asignaciones}) {
  ContratoAlumno f(String id, String nombre, {int extras = 0}) => _familia(
        id,
        nombre,
        extras: extras,
        mesas: asignaciones?[id],
      );
  return [
    f('cerca', 'GOMEZ, ANA', extras: 1),
    f('lejana', 'FERNANDEZ DE LA TORRE, LUCIA', extras: 1),
    f('dos', 'PEREZ, JUAN', extras: 1),
    f('tres', 'RODRIGUEZ, MARTA', extras: 2),
    f('otra', 'SOSA, PEDRO', extras: 1),
    for (var i = 1; i <= 24; i++) f('s$i', 'FAMILIA $i, ALUMNO'),
  ];
}

/// Una mesa detrás de otra, sin sortear: para mirar cómo queda con familias sentadas
/// sin depender de la suerte.
Map<String, List<int>> sentadasEnFila() {
  final asignaciones = <String, List<int>>{};
  var mesa = 1;
  for (final a in alumnosDePrueba()) {
    asignaciones[a.id] = [
      for (var i = 0; i <= a.mesaExtraCantidad; i++) mesa++,
    ];
  }
  return asignaciones;
}

final _evento = Evento(
  id: 'prueba',
  clienteId: 'c',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 1),
  estado: EstadoEvento.planificacion,
  modalidad: 'masivo',
  cliente: Cliente(id: 'c', nombreCompleto: 'VENTANA DE PRUEBA'),
);

class PruebaDelPlano extends StatefulWidget {
  const PruebaDelPlano({super.key});

  @override
  State<PruebaDelPlano> createState() => _PruebaDelPlanoState();
}

class _PruebaDelPlanoState extends State<PruebaDelPlano> {
  ArmadoSalon _armado = armadoDePuertoViejo();
  ConfigPlano _config = ConfigPlano.vacia;

  /// Las mesas de cada familia. Null: nadie tiene mesa.
  Map<String, List<int>>? _asignaciones;
  bool _conInternet = true;
  AvisoDelPlano? _aviso;

  /// Cuántas familias llegaron después del sorteo (6.5.1). La primera es una que
  /// ya tenía mesa y compró una adicional; las demás son familias nuevas.
  int _llegaron = 0;

  /// Lo guardado en las fiestas anteriores de esta ventana (OTRA FIESTA): de ahí
  /// sale la última numeración elegida, como en la app sale de los planos de la
  /// base (`NumeracionRecordada`).
  final _otrasFiestas = <ConfigPlano>[];
  int _fiesta = 1;

  List<ContratoAlumno> get _alumnos => [
        for (final a in alumnosDePrueba(asignaciones: _asignaciones))
          a.id == 's1' && _llegaron >= 1
              ? _familia(
                  's1',
                  a.nombreAlumno,
                  extras: 1,
                  mesas: _asignaciones?['s1'],
                )
              : a,
        for (var i = 2; i <= _llegaron; i++)
          _familia('t$i', 'TARDE $i, ALUMNO', mesas: _asignaciones?['t$i']),
      ];

  /// LLEGA UNA FAMILIA: con el sorteo ya hecho, abre **el cartel del SORTEO de la
  /// app** y hace lo mismo que la pantalla de la fiesta al confirmar: las mesas
  /// nuevas al fondo (si se eligió), el sorteo de verdad y el control final.
  Future<void> _llegaUnaFamilia() async {
    setState(() => _llegaron++);
    final alumnos = _alumnos;
    final ahora = DateTime.now().toUtc();
    final pagos = {
      for (final a in alumnos)
        a.id: PagoAlumno(base: 1000, mesas: 1000, ultimo: ahora),
    };
    final elegido = await mostrarSorteoMesasDialog(
      context: context,
      tituloInstitucion: 'VENTANA DE PRUEBA',
      alumnos: alumnos,
      avisos: const [],
      pagos: pagos,
      plano: PlanoEvento.nuevo(
        eventoId: 'prueba',
        armado: _armado,
        estilo: EstiloPlano.arquitecto,
        modo: ModoSorteo.entera,
        ahora: ahora,
      ).copyWith(config: _config, ahora: ahora),
    );
    if (!mounted) return;
    if (elegido == null) {
      setState(() => _llegaron--);
      return;
    }
    PlanMesasNuevas? nuevas;
    if (elegido.mesasNuevasAlFondo &&
        MesasNuevasAlFondo.motivoSinMesasNuevas(_armado, alumnos) == null) {
      final plan = MesasNuevasAlFondo.planear(
        armado: _armado,
        config: _config,
        alumnos: alumnos,
        pedidos: SorteoMesasMotor.pedidos(
          alumnos,
          separaciones: elegido.separaciones,
        ),
        llegada: llegadaPorPago(pagos),
        por: 'Prueba',
        ahora: ahora,
      );
      if (!plan.vacio) nuevas = plan;
    }
    final entrada = EntradaSorteoPlano(
      armado: nuevas?.armado ?? _armado,
      config: nuevas?.config ?? _config,
      alumnos: alumnos,
      separaciones: elegido.separaciones,
      distancias: elegido.distancias,
      modo: elegido.modo ?? ModoSorteo.entera,
      ordenDivisiones: elegido.ordenDivisiones,
      usarPasto: elegido.usarPasto,
      hastaMesa: elegido.hastaMesa,
      zonas: elegido.zonas,
      alFinal: elegido.alFinal,
    );
    setState(() {
      final ResultadoSorteoPlano resultado;
      try {
        resultado = SorteoConPlano.sortear(entrada);
      } on StateError catch (e) {
        _llegaron--;
        _aviso = AvisoDelPlano('No entra: ${e.message}', esError: true);
        return;
      }
      final problema = SorteoConPlano.validar(entrada, resultado);
      if (problema != null) {
        _llegaron--;
        _aviso = AvisoDelPlano('El control final: $problema', esError: true);
        return;
      }
      _armado = nuevas?.armado ?? _armado;
      _config = nuevas?.config ?? _config;
      _asignaciones = {...?_asignaciones, ...resultado.asignaciones};
      _aviso = AvisoDelPlano(
        nuevas == null
            ? 'Quedó en una mesa libre del salón: '
                '${resultado.asignaciones.values.map((l) => l.join(', ')).join(' · ')}.'
            : 'Mesa nueva al fondo: '
                '${nuevas.mesas.map((m) => m.numero).join(', ')}. Nadie más se '
                'movió.',
      );
    });
  }

  PlanoDeLaFiesta get _plano => PlanoDeLaFiesta.desde(
        armado: _armado,
        config: _config,
        alumnos: _alumnos,
      );

  /// Lo mismo que hace la pantalla de la app al tocar GUARDAR EL SALÓN, sobre lo
  /// que hay en esta ventana.
  void _guardarSalon(
    ArmadoSalon base,
    ArmadoSalon nuevo,
    Map<int, String> enUso,
    bool rehecho,
    double? lugarBarraM,
    FinNumeracion fin,
    DateTime? finEl,
  ) {
    final cambio = EditarArmado.paraGuardar(
      base: base,
      nuevo: nuevo,
      fresco: _armado,
      config: _config,
      alumnos: _alumnos,
      enUsoVisto: enUso,
      rehecho: rehecho,
      leidoDeLaNube: _conInternet,
      lugarBarraM: lugarBarraM,
      fin: fin,
      finEl: finEl,
    );
    setState(() {
      final config = cambio.config;
      final armado = cambio.armado;
      if (config == null || armado == null) {
        _aviso = AvisoDelPlano(cambio.problema ?? 'No se puede.', esError: true);
        return;
      }
      _config = config;
      _armado = armado;
      _aviso = AvisoDelPlano(
        EditarArmado.seRenumero(nuevo, armado)
            ? 'Guardado en esta ventana, con los números en orden: '
                '${armado.cortes.length} salto.'
            : 'Guardado en esta ventana. Los números no cambiaron.',
      );
    });
  }

  /// El sorteo de verdad, con las mismas tres cuentas que la pantalla de la fiesta:
  /// si entra, sortear y el control final. Lo sorteado se queda en esta ventana.
  void _sortear() {
    final entrada = EntradaSorteoPlano(
      armado: _armado,
      config: _config,
      alumnos: alumnosDePrueba(),
      separaciones: const {'cerca': 1, 'lejana': 1},
      distancias: const {
        'cerca': DistanciaLejos.cerca,
        'lejana': DistanciaLejos.bienLejos,
      },
    );
    setState(() {
      final plan = SorteoConPlano.preparar(entrada);
      if (!plan.entra) {
        _aviso = AvisoDelPlano(
          'No entra: ${plan.avisos.join(' ')}',
          esError: true,
        );
        return;
      }
      final ResultadoSorteoPlano resultado;
      try {
        resultado = SorteoConPlano.sortear(entrada);
      } on StateError catch (e) {
        _aviso = AvisoDelPlano('No entra: ${e.message}', esError: true);
        return;
      }
      final problema = SorteoConPlano.validar(entrada, resultado);
      if (problema != null) {
        _aviso = AvisoDelPlano('El control final: $problema', esError: true);
        return;
      }
      _asignaciones = resultado.asignaciones;
      _aviso = AvisoDelPlano(
        'Sorteo en esta ventana: ${resultado.asignaciones.length} familias.'
        '${resultado.avisos.isEmpty ? '' : ' ${resultado.avisos.join(' ')}'}',
      );
    });
  }

  /// CON EL CARTEL (6.6.1): el primer sorteo con **el cartel del SORTEO de la app**,
  /// para recorrer con el mouse "Las mesas adicionales: Con su familia · Al final",
  /// cuántas quedan pegadas y "Dejar juntas". Después hace lo mismo que la pantalla
  /// de la fiesta: sortear y el control final.
  Future<void> _sortearConElCartel() async {
    final alumnos = alumnosDePrueba();
    final ahora = DateTime.now().toUtc();
    final elegido = await mostrarSorteoMesasDialog(
      context: context,
      tituloInstitucion: 'VENTANA DE PRUEBA',
      alumnos: alumnos,
      avisos: const [],
      pagos: {
        for (final a in alumnos)
          a.id: PagoAlumno(base: 1000, mesas: a.mesaExtraPrecio),
      },
      plano: PlanoEvento.nuevo(
        eventoId: 'prueba',
        armado: _armado,
        estilo: EstiloPlano.arquitecto,
        modo: ModoSorteo.entera,
        ahora: ahora,
      ).copyWith(config: _config, ahora: ahora),
    );
    if (!mounted || elegido == null) return;
    final entrada = EntradaSorteoPlano(
      armado: _armado,
      config: _config,
      alumnos: alumnos,
      separaciones: elegido.separaciones,
      distancias: elegido.distancias,
      modo: elegido.modo ?? ModoSorteo.entera,
      ordenDivisiones: elegido.ordenDivisiones,
      usarPasto: elegido.usarPasto,
      hastaMesa: elegido.hastaMesa,
      zonas: elegido.zonas,
      alFinal: elegido.alFinal,
    );
    setState(() {
      final ResultadoSorteoPlano resultado;
      try {
        resultado = SorteoConPlano.sortear(entrada);
      } on StateError catch (e) {
        _aviso = AvisoDelPlano('No entra: ${e.message}', esError: true);
        return;
      }
      final problema = SorteoConPlano.validar(entrada, resultado);
      if (problema != null) {
        _aviso = AvisoDelPlano('El control final: $problema', esError: true);
        return;
      }
      _asignaciones = resultado.asignaciones;
      final delFinal = [
        for (final l in SorteoConPlano.delFinal(entrada, resultado).values) ...l,
      ]..sort();
      _aviso = AvisoDelPlano(
        'Sorteo con el cartel: ${resultado.asignaciones.length} familias.'
        '${delFinal.isEmpty ? ' Cada familia con sus mesas juntas.' : ' Al final: ${delFinal.join(', ')}.'}',
      );
    });
  }

  /// Un cambio de lo que se configura del plano, como lo deja la pantalla de la app:
  /// acá se queda en esta ventana.
  void _aplicar(CambioDeConfig cambio, String hecho) => setState(() {
        final config = cambio.config;
        if (config == null) {
          _aviso = AvisoDelPlano(cambio.problema ?? 'No se puede.', esError: true);
          return;
        }
        _config = config;
        _armado = cambio.armado ?? _armado;
        _aviso = AvisoDelPlano(hecho);
      });

  /// "Dejar libre", con la misma pregunta de la app: **No se usa · Es para alguien**
  /// (la mesa reservada para los profes, 6.5.0) y la misma cuenta (`CambiosDeMesa`).
  Future<void> _dejarLibre(int mesa) async {
    CambioDeConfig calcular(String? motivo) => CambiosDeMesa.dejarLibre(
          armado: _armado,
          config: _config,
          alumnos: _alumnos,
          mesa: mesa,
          motivo: motivo,
          por: 'Prueba',
          ahora: DateTime.now().toUtc(),
        );
    final previa = calcular(null);
    if (!previa.sePuede) {
      setState(() => _aviso = AvisoDelPlano(previa.problema!, esError: true));
      return;
    }
    final motivo = await pedirReservaDeMesa(context: context, mesa: mesa);
    if (motivo == null || !mounted) return;
    final reserva = ReservaDeMesa.deMotivo(motivo);
    _aplicar(
      calcular(motivo),
      reserva == null
          ? 'La mesa $mesa quedó libre.'
          : 'La mesa $mesa quedó reservada para ${reserva.para}.',
    );
  }

  /// "Para quién es", sobre una mesa que ya está libre.
  Future<void> _editarLibre(int mesa) async {
    final actual = _config.libres[mesa];
    if (actual == null) return;
    final motivo = await pedirReservaDeMesa(
      context: context,
      mesa: mesa,
      motivoActual: actual.motivo,
      yaEstaLibre: true,
    );
    if (motivo == null || !mounted) return;
    final reserva = ReservaDeMesa.deMotivo(motivo);
    _aplicar(
      CambiosDeMesa.cambiarMotivoDeLibre(
        config: _config,
        mesa: mesa,
        motivo: motivo,
        por: 'Prueba',
        ahora: DateTime.now().toUtc(),
      ),
      reserva == null
          ? 'La mesa $mesa sigue libre.'
          : 'La mesa $mesa quedó reservada para ${reserva.para}.',
    );
  }

  /// Cambiar o mover familias (la entera, o una sola de sus mesas): el mismo cartel
  /// de la app, con cómo queda, los avisos y el motivo. El cambio queda en esta
  /// ventana.
  Future<void> _cambiarMesas(
    CambioDeMesas cambio,
    String titulo,
    String boton,
  ) async {
    if (!cambio.sePuede) {
      setState(() => _aviso = AvisoDelPlano(cambio.problema!, esError: true));
      return;
    }
    final alumnos = _alumnos;
    String apellidoDe(String id) =>
        CambiosDeMesa.apellido(alumnos.firstWhere((a) => a.id == id));
    final motivo = await confirmarCambioDeMesa(
      context: context,
      titulo: titulo,
      renglones: cambio.renglones(apellidoDe),
      avisos: cambio.avisos,
      sugerencias: motivosParaCambiar,
      textoConfirmar: boton,
    );
    if (motivo == null || !mounted) return;
    setState(() {
      _asignaciones = {
        ...?_asignaciones,
        for (final e in cambio.despues.entries)
          e.key: MesasExtraUtils.numerosMesaDesdeTexto(e.value).toList()..sort(),
      };
      final config = cambio.config;
      if (config != null) _config = config;
      _aviso = AvisoDelPlano(cambio.textoHecho(apellidoDe));
    });
  }

  /// El mismo diálogo de la app, pero el PDF queda en una carpeta en vez de ir a la
  /// impresora: en esta ventana se lo quiere mirar, no gastar papel.
  Future<void> _imprimir() async {
    final plano = _plano;
    final como = await elegirComoImprimirPlano(
      context,
      hojas: plano.armado.hojas.length,
      hayFamilias: plano.familias.hayAlguna,
    );
    if (como == null || !mounted) return;
    try {
      final bytes = await PdfService.construirPlanoPdf(
        _evento,
        plano,
        estilo: EstiloPlano.arquitecto,
        blancoYNegro: como.blancoYNegro,
        familias: como.familias,
      );
      final carpeta = Directory('build/plano_prueba').absolute
        ..createSync(recursive: true);
      final hora = DateTime.now().millisecondsSinceEpoch;
      final archivo = File(
        '${carpeta.path}/${hora}_${como.blancoYNegro ? 'bn' : 'color'}'
        '_${como.familias ? 'familias' : 'sin_familias'}.pdf',
      )..writeAsBytesSync(bytes);
      if (!mounted) return;
      setState(() => _aviso = AvisoDelPlano('PDF en ${archivo.path}'));
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _aviso = AvisoDelPlano('No se armó el PDF: $e', esError: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sinMesa = _asignaciones == null;
    return Scaffold(
      appBar: AppBar(
        // Corto: arriba van siete botones y tienen que entrar.
        title: const Text('Prueba'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _armado.cortes.length == 1
                    ? '1 salto'
                    : '${_armado.cortes.length} saltos',
              ),
            ),
          ),
          TextButton(
            key: const Key('prueba_sortear'),
            onPressed: sinMesa ? _sortear : null,
            child: const Text('SORTEAR'),
          ),
          // Un ícono y no otro rótulo: arriba ya no entra un botón más.
          IconButton(
            key: const Key('prueba_cartel'),
            tooltip: 'Sortear con el cartel de la app',
            onPressed: sinMesa ? _sortearConElCartel : null,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          TextButton(
            key: const Key('prueba_deshacer'),
            onPressed: sinMesa
                ? null
                : () => setState(() {
                      _asignaciones = null;
                      _llegaron = 0;
                      _aviso = const AvisoDelPlano(
                        'Sorteo deshecho: nadie tiene mesa.',
                      );
                    }),
            child: const Text('DESHACER'),
          ),
          TextButton(
            key: const Key('prueba_llega'),
            onPressed: sinMesa ? null : _llegaUnaFamilia,
            child: const Text('LLEGA UNA FAMILIA'),
          ),
          const Text('Familias con mesa'),
          Switch(
            key: const Key('prueba_sentados'),
            value: !sinMesa,
            onChanged: (v) => setState(() {
              _asignaciones = v ? sentadasEnFila() : null;
              _llegaron = 0;
              _aviso = null;
            }),
          ),
          const Text('Internet'),
          Switch(
            key: const Key('prueba_internet'),
            value: _conInternet,
            onChanged: (v) => setState(() => _conInternet = v),
          ),
          TextButton(
            key: const Key('prueba_volver'),
            onPressed: () => setState(() {
              _armado = armadoDePuertoViejo();
              _config = ConfigPlano.vacia;
              _asignaciones = null;
              _llegaron = 0;
              _aviso = null;
            }),
            child: const Text('MEZCLADO'),
          ),
          // Otra fiesta, sin sortear y que nunca eligió su numeración: Acomodar
          // tiene que venir con la última que se guardó en las anteriores.
          TextButton(
            key: const Key('prueba_otra_fiesta'),
            onPressed: () => setState(() {
              _otrasFiestas.add(_config);
              _fiesta++;
              _armado = armadoDePuertoViejo();
              _config = ConfigPlano.vacia;
              _asignaciones = null;
              _llegaron = 0;
              _aviso = AvisoDelPlano('Fiesta $_fiesta: nueva, sin sortear.');
            }),
            child: const Text('OTRA'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PlanoEventoCuerpo(
        key: ValueKey(_fiesta),
        numeracionRecordada: NumeracionRecordada.de(_otrasFiestas),
        plano: _plano,
        estilo: EstiloPlano.arquitecto,
        alumnos: _alumnos,
        aviso: _aviso,
        onImprimir: _imprimir,
        acciones: AccionesPlano(
          onFijarEnMesa: (_) {},
          onFijar: (_, _) {},
          onQuitarFijadas: (_) {},
          onQuitarFijadaDeMesa: (_) {},
          onDejarLibre: _dejarLibre,
          onEditarLibre: _editarLibre,
          onVolverAUsar: (mesa) => _aplicar(
            CambiosDeMesa.volverAUsar(_config, mesa),
            'La mesa $mesa vuelve a entrar en el sorteo.',
          ),
          onCambiar: (a, b) => _cambiarMesas(
            CambiosDeMesa.intercambiar(
              armado: _armado,
              config: _config,
              alumnos: _alumnos,
              alumnoId: a,
              otroId: b,
            ),
            'Cambian de lugar',
            'CAMBIAR',
          ),
          onMover: (a, desde) => _cambiarMesas(
            CambiosDeMesa.mover(
              armado: _armado,
              config: _config,
              alumnos: _alumnos,
              alumnoId: a,
              desdeMesa: desde,
            ),
            'Pasa a otras mesas',
            'MOVER',
          ),
          onMoverUna: (a, mesa, aMesa) => _cambiarMesas(
            CambiosDeMesa.moverUna(
              armado: _armado,
              config: _config,
              alumnos: _alumnos,
              alumnoId: a,
              mesa: mesa,
              aMesa: aMesa,
            ),
            'La $mesa pasa a la $aMesa',
            'MOVER',
          ),
          onCambiarUna: (a, mesa, otra) => _cambiarMesas(
            CambiosDeMesa.intercambiarUna(
              armado: _armado,
              config: _config,
              alumnos: _alumnos,
              alumnoId: a,
              mesa: mesa,
              otraMesa: otra,
            ),
            'La $mesa se cambia por la $otra',
            'CAMBIAR',
          ),
          onGuardarArmado: _guardarSalon,
          // "Mesas por orden" (6.7.0), con la misma cuenta que la pantalla de
          // la app: fija las mesas; SORTEAR, arriba, las entrega.
          onPorOrden: (prender) => _aplicar(
            prender
                ? OrdenEnElSalon.prender(
                    eventoId: 'prueba',
                    armado: _armado,
                    config: _config,
                    alumnos: _alumnos,
                    pagos: pagosDePrueba(),
                    hoyAr: DateTime(2026, 11, 12),
                    ahora: DateTime.now().toUtc(),
                    por: 'Prueba',
                  )
                : OrdenEnElSalon.apagar(config: _config, alumnos: _alumnos),
            prender
                ? 'Cumplimiento debido: quedaron ubicadas. Miralas en el plano; con SORTEAR '
                    'se les entrega la mesa.'
                : 'Cumplimiento debido, apagado: ya no hay mesas ubicadas.',
          ),
          onVerElOrden: () {
            final orden = _config.frente;
            if (orden == null) return;
            mostrarElOrden(context, orden: orden, alumnos: _alumnos);
          },
        ),
      ),
    );
  }
}
