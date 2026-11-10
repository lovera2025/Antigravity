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
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/reserva_de_mesa.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
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
    );

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

  List<ContratoAlumno> get _alumnos =>
      alumnosDePrueba(asignaciones: _asignaciones);

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
        title: const Text('Ventana de prueba: nada se guarda de verdad'),
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
          TextButton(
            key: const Key('prueba_deshacer'),
            onPressed: sinMesa
                ? null
                : () => setState(() {
                      _asignaciones = null;
                      _aviso = const AvisoDelPlano(
                        'Sorteo deshecho: nadie tiene mesa.',
                      );
                    }),
            child: const Text('DESHACER'),
          ),
          const Text('Familias con mesa'),
          Switch(
            key: const Key('prueba_sentados'),
            value: !sinMesa,
            onChanged: (v) => setState(() {
              _asignaciones = v ? sentadasEnFila() : null;
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
              _aviso = null;
            }),
            child: const Text('VOLVER AL MEZCLADO'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PlanoEventoCuerpo(
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
          onCambiar: (_, _) {},
          onMover: (_, _) {},
          onGuardarArmado: _guardarSalon,
        ),
      ),
    );
  }
}
