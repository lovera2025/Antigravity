// Arnés manual: arma fiestas inventadas, las sortea con el sorteo real sobre
// el plano y genera el plano impreso, para mirar el papel sin levantar la app
// ni tocar la base.
//
//   flutter test tool/plano_pdf_muestra_test.dart
//   flutter test tool/plano_pdf_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen:
//   • Plano_a_medida_<estilo>[_BN].pdf: 132 mesas a medida del playón, sorteadas
//     por división, con una mesa fijada, una libre y sillas extra. En los tres
//     estilos, en color y en blanco y negro;
//   • Plano_normal_p3_antes_del_sorteo.pdf: la página 3 del Canva sin sortear,
//     con mesas fijadas y libres;
//   • Plano_normal_2a2b.pdf: dos hojas, sorteadas por división;
//   • Plano_tecnica_con_pasto.pdf: toda la escuela junta, usando el pasto.
//
// Lo que se mira: que cada hoja entre en una A4 acostada, que los números y
// los apellidos se lean, que la leyenda diga qué mesas tiene cada división, y
// que el pasto, las libres y las fijadas se distingan sin color.
//
// Los nombres son inventados: la muestra nunca usa datos reales.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'AGUIRRE', 'ÁLVAREZ', 'BARRIOS', 'BENÍTEZ', 'CABRERA', 'CANTEROS',
  'CÁCERES', 'DUARTE', 'ESCOBAR', 'FERNÁNDEZ', 'FIGUEROA', 'GIMÉNEZ', 'GÓMEZ',
  'HERRERA', 'INSFRÁN', 'JARA', 'LEDESMA', 'LÓPEZ', 'MEDINA', 'MOLINA',
  'NÚÑEZ', 'OJEDA', 'ORTIZ', 'PEREYRA', 'QUIROGA', 'RAMÍREZ', 'RÍOS', 'ROMERO',
  'SOSA', 'TORRES', 'VALLEJOS', 'VERA', 'ZÁRATE', 'MONTENEGRO', 'VILLALBA',
  'DOMÍNGUEZ', 'ESPÍNDOLA', 'FERREYRA', 'GONZÁLEZ ROJAS',
];
const _nombres = [
  'LUCÍA', 'TOMÁS', 'MARTINA', 'JULIÁN', 'SOFÍA', 'NAHUEL', 'CAMILA',
  'FRANCO', 'VALENTINA', 'MATEO', 'AGUSTINA', 'BRUNO',
];

ContratoAlumno _alumno(int i, String curso, {int extras = 0, int sillas = 0}) =>
    ContratoAlumno(
      id: 'a$i',
      eventoId: 'muestra',
      nombreAlumno: '${_apellidos[i % _apellidos.length]}, '
          '${_nombres[(i * 7) % _nombres.length]}',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      cursoDivision: curso,
    );

/// Familias de [divisiones] hasta juntar [mesas] mesas: la mayoría de una, una
/// de cada siete con dos, y algunas con sillas extra.
List<ContratoAlumno> _familias(List<String> divisiones, int mesas) {
  final lista = <ContratoAlumno>[];
  var suma = 0;
  for (var i = 0; suma < mesas; i++) {
    final quedan = mesas - suma;
    final extras = quedan >= 2 && i % 7 == 2 ? 1 : 0;
    lista.add(_alumno(
      i,
      divisiones[i % divisiones.length],
      extras: extras,
      sillas: i % 9 == 4 ? 2 : (i % 13 == 6 ? 1 : 0),
    ));
    suma += 1 + extras;
  }
  return lista;
}

final _evento = Evento(
  id: 'muestra',
  clienteId: 'c',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 5),
  estado: EstadoEvento.planificacion,
  modalidad: 'masivo',
  cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE MUESTRA'),
);

/// Sortea [alumnos] sobre [armado] con el sorteo real y devuelve el plano de la
/// fiesta como lo calcula la pantalla.
PlanoDeLaFiesta _sorteada(
  ArmadoSalon armado,
  List<ContratoAlumno> alumnos, {
  ConfigPlano config = ConfigPlano.vacia,
  ModoSorteo modo = ModoSorteo.bloques,
  bool usarPasto = false,
}) {
  final claves = Divisiones.ordenNatural(
    alumnos.map((a) => Divisiones.clave(a.cursoDivision)),
  );
  final entrada = EntradaSorteoPlano(
    armado: armado,
    config: config,
    alumnos: alumnos,
    modo: modo,
    ordenDivisiones: claves,
    usarPasto: usarPasto,
  );
  final r = SorteoConPlano.sortear(entrada, random: Random(7));
  expect(SorteoConPlano.validar(entrada, r), isNull);
  return PlanoDeLaFiesta.desde(
    armado: armado,
    config: config.copyWith(bloques: r.bloques, ordenDivisiones: claves),
    alumnos: [
      for (final a in alumnos)
        r.asignaciones.containsKey(a.id)
            ? a.copyWith(
                numeroMesa:
                    MesasExtraUtils.formatearAsignacionMesas(r.asignaciones[a.id]!),
              )
            : a,
    ],
  );
}

late String _carpeta;

Future<void> _guardar(
  String nombre,
  PlanoDeLaFiesta plano, {
  required EstiloPlano estilo,
  bool blancoYNegro = false,
  String? lineaSorteo = 'Sorteo del 12/11/2026 21:40 hs · Jefe',
}) async {
  final bytes = await PdfService.construirPlanoPdf(
    _evento,
    plano,
    estilo: estilo,
    lineaSorteo: lineaSorteo,
    blancoYNegro: blancoYNegro,
    generada: DateTime(2026, 11, 13, 9, 15),
  );
  final archivo = File('$_carpeta${Platform.pathSeparator}$nombre')
    ..writeAsBytesSync(bytes);
  stdout.writeln('── PDF en: ${archivo.path}');
  expect(archivo.lengthSync(), greaterThan(1000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('plano_pdf').path;
  });

  test('a medida del playón, sorteado por división', () async {
    final alumnos = _familias(['5° A', '5° B', '5° C'], 130);
    final mesas = alumnos.fold(0, (s, a) => s + SalonMesas.mesas(a));
    // Dos mesas de más: una se deja libre y la otra queda sin usar.
    final armado = ArmarAMedida.armar(OpcionesAMedida(
      playon: PlayonReal.costaSurubi,
      cantidad: mesas + 2,
    )).armado;
    final config = ConfigPlano(
      fijadas: {
        1: MesaFijada(alumnoId: alumnos.first.id, motivo: 'Silla de ruedas'),
      },
      libres: const {66: MesaLibre(motivo: 'Columna de sonido')},
    );
    final plano = _sorteada(armado, alumnos, config: config);
    for (final estilo in EstiloPlano.values) {
      for (final bn in [false, true]) {
        await _guardar(
          'Plano_a_medida_${estilo.name}${bn ? '_BN' : ''}.pdf',
          plano,
          estilo: estilo,
          blancoYNegro: bn,
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('página 3 del Canva, antes del sorteo', () async {
    final armado = ArmadosPredefinidos.normal2aPagina3();
    final alumnos = _familias(['5° A', '5° B'], 70);
    final plano = PlanoDeLaFiesta.desde(
      armado: armado,
      config: ConfigPlano(
        fijadas: {
          1: MesaFijada(alumnoId: alumnos[0].id, motivo: 'Silla de ruedas'),
          31: MesaFijada(alumnoId: alumnos[2].id, motivo: 'Cerca del baño'),
          32: MesaFijada(alumnoId: alumnos[2].id, motivo: 'Cerca del baño'),
        },
        libres: const {76: MesaLibre(), 77: MesaLibre(), 78: MesaLibre()},
      ),
      alumnos: alumnos,
    );
    await _guardar(
      'Plano_normal_p3_antes_del_sorteo.pdf',
      plano,
      estilo: EstiloPlano.arquitecto,
      blancoYNegro: true,
      lineaSorteo: null,
    );
  });

  test('dos hojas (2A + 2B), sorteado por división', () async {
    final armado = ArmadosPredefinidos.normal2a2b();
    final plano = _sorteada(
      armado,
      _familias(['5° A', '5° B', '5° C', '5° D'], 126),
    );
    await _guardar('Plano_normal_2a2b.pdf', plano, estilo: EstiloPlano.gala);
  });

  test('Técnica con el pasto, toda la escuela junta', () async {
    final armado = ArmadosPredefinidos.tecnica1a1b();
    final plano = _sorteada(
      armado,
      _familias(['6° A', '6° B', '6° C', '6° D'], 138),
      modo: ModoSorteo.entera,
      usarPasto: true,
    );
    await _guardar(
      'Plano_tecnica_con_pasto.pdf',
      plano,
      estilo: EstiloPlano.arquitecto,
      blancoYNegro: true,
    );
  });
}
