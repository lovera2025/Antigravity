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
//
// 6.9.2: la mesa adicional "a confirmar". Con familias sentadas, PEREZ tiene su
// adicional sin nada pagado y SOSA con una parte: se ven punteadas, y en su tarjeta
// están COBRAR y ANULAR con las mismas cuentas de la app (`CambiosDeMesa.soltarUna`,
// `BajaDeAdicional`). COBRAR acá anota el pago en esta ventana (en la app cierra el
// plano y abre el cobro de siempre). "Modo jefe" apagado muestra lo que ve cualquiera.
//
// Para recorrerla en el navegador de la app (IMPRIMIR ahí no deja el PDF):
//   flutter build web -t tool/plano_prueba.dart --no-web-resources-cdn --output build/plano_prueba_web
//   python -I -m http.server 8795 --directory build/plano_prueba_web

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/adicional_a_confirmar.dart';
import 'package:arguello_events/features/eventos/services/edicion_de_alumno.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_del_cartel.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/modelo/reserva_de_mesa.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/historial_sorteo.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/plano/services/numeracion_recordada.dart';
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

void main() {
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const PruebaDelPlano(),
    ),
  );
}

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
      // Lo de la adicional, como si todavía la debiera: con saldo 0 no se la
      // podría bajar del contrato (6.9.2).
      saldoDeudor: 70000.0 * extras,
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

  /// Lo que la sesión puede: apagado, la pantalla muestra lo que ve cualquiera.
  bool _esJefe = true;

  /// La mesa adicional "a confirmar" (6.9.2): cuánto lleva pagado de su adicional
  /// cada familia que no la pagó entera. Las demás la tienen paga.
  static const _sinPagarAlEmpezar = {'dos': 0.0, 'otra': 30000.0};
  Map<String, double> _pagadoDeLaAdicional = {..._sinPagarAlEmpezar};

  /// Las familias a las que se les anuló una adicional: ya no la tienen en su
  /// contrato.
  final _anuladas = <String>{};

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
          if (_anuladas.contains(a.id))
            _familia(
              a.id,
              a.nombreAlumno,
              extras: a.mesaExtraCantidad - 1,
              mesas: _asignaciones?[a.id],
            )
          else
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

  /// Los pagos de cada familia: los de [pagosDePrueba], sin lo que no pagó de su
  /// mesa adicional quien la tiene "a confirmar".
  Map<String, List<Map<String, dynamic>>> get _pagos => {
        for (final e in pagosDePrueba().entries)
          e.key: [
            for (final p in e.value)
              if (p['concepto'] != 'Mesa extra (1/1)' ||
                  !_pagadoDeLaAdicional.containsKey(e.key))
                p
              else if (_pagadoDeLaAdicional[e.key]! > 0)
                {
                  ...p,
                  'monto': _pagadoDeLaAdicional[e.key],
                  'monto_gross': _pagadoDeLaAdicional[e.key],
                },
          ],
      };

  PlanoDeLaFiesta get _plano => PlanoDeLaFiesta.desde(
        armado: _armado,
        config: _config,
        alumnos: _alumnos,
        pagos: _pagos,
      );

  /// COBRAR: en la app el plano se cierra y la fiesta abre el cobro de siempre.
  /// Acá se anota el pago en esta ventana, para ver que la mesa vuelve sola a la
  /// normalidad.
  void _cobrarAConfirmar(String alumnoId) {
    final a = _alumnos.firstWhere((a) => a.id == alumnoId);
    setState(() {
      _pagadoDeLaAdicional = {..._pagadoDeLaAdicional}..remove(alumnoId);
      _aviso = AvisoDelPlano(
        'En la app, acá el plano se cierra y se abre el cobro de siempre para '
        '${CambiosDeMesa.apellido(a)}. En esta ventana quedó anotado el pago.',
      );
    });
  }

  /// ANULAR, con las cuentas de la app: la familia deja esa mesa
  /// (`CambiosDeMesa.soltarUna`) y la adicional se baja de su contrato
  /// (`BajaDeAdicional`). Solo con internet.
  Future<void> _anularAConfirmar(String alumnoId, int mesa) async {
    final alumnos = _alumnos;
    final a = alumnos.firstWhere((a) => a.id == alumnoId);
    final apellido = CambiosDeMesa.apellido(a);
    var cambio = CambiosDeMesa.soltarUna(
      config: _config,
      alumnos: alumnos,
      alumnoId: alumnoId,
      mesa: mesa,
    );
    if (cambio.sePuede) {
      final x = AdicionalesDeLaFamilia.aConfirmar(a, _pagos[alumnoId])
          .where((x) => x.mesa == mesa)
          .firstOrNull;
      final problema = x == null
          ? 'La mesa $mesa ya no está a confirmar.'
          : !x.sePuedeAnular
              ? textoNoSeAnula(x)
              : BajaDeAdicional.de(a).problema;
      if (problema != null) {
        cambio = CambioDeMesas.noSePuede(cambio.tipo, problema);
      }
    }
    if (!cambio.sePuede) {
      setState(() => _aviso = AvisoDelPlano(cambio.problema!, esError: true));
      return;
    }
    final ok = await confirmarCambioDeMesa(
      context: context,
      titulo: 'Anular la mesa $mesa de $apellido',
      renglones: cambio.renglones((_) => apellido),
      avisos: cambio.avisos,
      pedirMotivo: false,
      textoConfirmar: 'ANULAR',
    );
    if (ok == null || !mounted) return;
    if (!_conInternet) {
      setState(
        () => _aviso = const AvisoDelPlano(
          'Sin conexión: para anular una mesa hace falta internet. Antes hay '
          'que mirar en la nube que nadie la haya pagado recién.',
          esError: true,
        ),
      );
      return;
    }
    setState(() {
      _asignaciones = {
        ...?_asignaciones,
        for (final e in cambio.despues.entries)
          e.key: MesasExtraUtils.numerosMesaDesdeTexto(e.value).toList()..sort(),
      };
      final config = cambio.config;
      if (config != null) _config = config;
      _anuladas.add(alumnoId);
      _pagadoDeLaAdicional = {..._pagadoDeLaAdicional}..remove(alumnoId);
      _aviso = AvisoDelPlano(
        '${cambio.textoHecho((_) => apellido)} La mesa adicional se bajó de su '
        'contrato.',
      );
    });
  }

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
  ///
  /// Desde la 6.7.1 el cartel trae el tilde **"Cumplimiento debido"**: tildado,
  /// reparte de la familia que mejor cumplió a la que peor (con los pagos
  /// inventados de [pagosDePrueba]). Sirve con el salón vacío y con familias ya
  /// sentadas (ahí reacomoda), con la misma cuenta que la pantalla de la fiesta.
  Future<void> _sortearConElCartel() async {
    final alumnos = _alumnos;
    final ahora = DateTime.now().toUtc();
    final pagos = {
      for (final a in alumnos)
        a.id: PagoAlumno(base: 1000, mesas: a.mesaExtraPrecio),
    };
    final crudos = pagosDePrueba();
    final plano = PlanoEvento.nuevo(
      eventoId: 'prueba',
      armado: _armado,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: ahora,
    ).copyWith(config: _config, ahora: ahora);
    final elegido = await mostrarSorteoMesasDialog(
      context: context,
      tituloInstitucion: 'VENTANA DE PRUEBA',
      alumnos: alumnos,
      avisos: const [],
      pagos: pagos,
      plano: plano,
      eventoId: 'prueba',
      pagosCrudos: crudos,
    );
    if (!mounted || elegido == null) return;
    final exclusion = exclusionSorteo(
      candidatos: candidatosPorPago(alumnos, pagos),
      soloPagado: elegido.soloPagado,
      incluirBase: elegido.incluirBase,
      incluirExtras: elegido.incluirExtras,
    );
    // El mismo camino que la pantalla de la fiesta (16-nov-2026): de lo elegido
    // en el cartel al sorteo y el control final.
    final delCartel = SorteoDelCartel.armar(
      eventoId: 'prueba',
      plano: plano,
      alumnos: alumnos,
      config: elegido,
      exclusion: exclusion,
      pagos: pagos,
      pagosCrudos: crudos,
      hoyAr: DateTime(2026, 11, 12),
      ahora: ahora,
      por: 'Prueba',
    );
    if (!delCartel.sePuede) {
      setState(
        () => _aviso = AvisoDelPlano(delCartel.problema!, esError: true),
      );
      return;
    }
    final orden = delCartel.orden;
    final entrada = delCartel.entrada!;
    setState(() {
      final ResultadoSorteoPlano resultado;
      try {
        resultado = delCartel.sortear();
      } on StateError catch (e) {
        _aviso = AvisoDelPlano('No entra: ${e.message}', esError: true);
        return;
      }
      final problema = delCartel.controlFinal(resultado);
      if (problema != null) {
        _aviso = AvisoDelPlano('El control final: $problema', esError: true);
        return;
      }
      _asignaciones = {...?_asignaciones, ...resultado.asignaciones};
      _armado = delCartel.nuevas?.armado ?? _armado;
      _config = delCartel.configDelPlano!.copyWith(
        bloques: resultado.bloques.isNotEmpty
            ? resultado.bloques
            : delCartel.configDelPlano!.bloques,
      );
      if (orden != null) {
        _aviso = AvisoDelPlano(
          'Sorteo por cumplimiento: ${orden.ubicadas} familias.'
          '${orden.cambian == 0 ? '' : ' ${orden.cambian} cambiaron de mesa.'}'
          '${elegido.unaMesaPrimero ? ' Primero las de una sola mesa.' : ''}',
        );
        return;
      }
      final delFinal = [
        for (final l in SorteoConPlano.delFinal(entrada, resultado).values) ...l,
      ]..sort();
      _aviso = AvisoDelPlano(
        'Sorteo con el cartel: ${resultado.asignaciones.length} familias.'
        '${elegido.unaMesaPrimero ? ' Primero las de una sola mesa.' : ''}'
        '${delFinal.isEmpty ? ' Cada familia con sus mesas juntas.' : ' Al final: ${delFinal.join(', ')}.'}',
      );
    });
  }

  /// El Historial de la app, con "Ver el porqué" del sorteo por cumplimiento.
  /// En esta ventana no hay registros: se ve lo que sale del plano.
  void _historial() => mostrarHistorialSorteo(
        context: context,
        historial: HistorialSorteo.armar(
          registros: const [],
          movimientos: const [],
          config: _config,
          alumnos: _alumnos,
        ),
        onVerElPorque: _config.frente == null
            ? null
            : () => mostrarElOrden(
                  context,
                  orden: _config.frente!,
                  alumnos: _alumnos,
                ),
      );

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
        // El modo jefe va a la izquierda: a la derecha ya no entra nada más.
        leading: IconButton(
          key: const Key('prueba_jefe'),
          tooltip: _esJefe
              ? 'En modo jefe (tocá para ver lo que ve cualquiera)'
              : 'Sin modo jefe (tocá para entrar en modo jefe)',
          onPressed: () => setState(() => _esJefe = !_esJefe),
          icon: Icon(
            _esJefe
                ? Icons.admin_panel_settings
                : Icons.admin_panel_settings_outlined,
          ),
        ),
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
            onPressed: _sortearConElCartel,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            key: const Key('prueba_historial'),
            tooltip: 'Historial',
            onPressed: _historial,
            icon: const Icon(Icons.history),
          ),
          TextButton(
            key: const Key('prueba_deshacer'),
            onPressed: sinMesa
                ? null
                : () => setState(() {
                      _asignaciones = null;
                      _llegaron = 0;
                      _anuladas.clear();
                      _pagadoDeLaAdicional = {..._sinPagarAlEmpezar};
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
              _anuladas.clear();
              _pagadoDeLaAdicional = {..._sinPagarAlEmpezar};
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
              _anuladas.clear();
              _pagadoDeLaAdicional = {..._sinPagarAlEmpezar};
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
              _anuladas.clear();
              _pagadoDeLaAdicional = {..._sinPagarAlEmpezar};
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
        soloJefe: !_esJefe,
        acciones: !_esJefe
            ? null
            : AccionesPlano(
          onCobrarAConfirmar: _cobrarAConfirmar,
          onAnularAConfirmar: _anularAConfirmar,
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
        ),
      ),
    );
  }
}
