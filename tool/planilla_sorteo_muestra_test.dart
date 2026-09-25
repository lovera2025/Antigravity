// Arnés manual: sortea un evento inventado con el motor real y genera la
// planilla del sorteo en sus cuatro versiones, para mirar el papel sin levantar
// la app ni tocar la base.
//
//   flutter test tool/planilla_sorteo_muestra_test.dart
//   flutter test tool/planilla_sorteo_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen cuatro PDF: interna y para repartir, cada una en color y en blanco y
// negro. Lo que se mira:
//   • la hoja de resumen: tarjetas con los totales, las divisiones con sus
//     números y, en la interna, a quién llamar por el reparto de sillas;
//   • una hoja acostada por división, con las columnas del Excel del jefe
//     primero: egresado, acompañantes (uno por renglón), mesa principal (en
//     verde, con "N con cena · M generales"), adicional, sillas ("2P · 1A");
//   • que una división larga siga en la hoja siguiente con los títulos
//     repetidos;
//   • la fila roja de quien no tiene mesa (no pagó la cuota base) y la amarilla
//     de quien tiene algo para avisar (solo en la interna);
//   • que la versión para repartir no tenga teléfonos ni observaciones;
//   • que en blanco y negro se lea todo igual.
//
// Los nombres son inventados: la muestra nunca usa datos reales.
//
// No vive en test/ a propósito: guarda PDFs, y eso no tiene que pasar en cada
// corrida de la suite.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/nota_operativa_contrato.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'AGUIRRE', 'ALVAREZ', 'BARRIOS', 'BENÍTEZ', 'CABRERA', 'CANTEROS',
  'CÁCERES', 'DUARTE', 'ESCOBAR', 'FERNÁNDEZ', 'FIGUEROA', 'GIMÉNEZ', 'GÓMEZ',
  'HERRERA', 'INSFRÁN', 'JARA', 'LEDESMA', 'LÓPEZ', 'MEDINA', 'MOLINA',
  'NÚÑEZ', 'OJEDA', 'ORTIZ', 'PEREYRA', 'QUIROGA', 'RAMÍREZ', 'RÍOS', 'ROMERO',
  'SOSA', 'TORRES', 'VALLEJOS', 'VERA', 'ZARATE',
];
const _nombres = [
  'LUCÍA', 'TOMÁS', 'MARTINA', 'JULIÁN', 'SOFÍA', 'NAHUEL', 'CAMILA',
  'FRANCO', 'VALENTINA', 'MATEO', 'AGUSTINA', 'BRUNO', 'CATALINA', 'IVÁN',
  'MILAGROS', 'DANTE', 'ABRIL', 'RAMIRO', 'EMMA', 'THIAGO', 'OLIVIA', 'BENJAMÍN',
];
const _musica = ['Cumbia', 'Cuarteto', 'Reggaetón', 'Rock nacional', 'Electrónica', ''];

ContratoAlumno _alumno(
  int i,
  String curso, {
  int extras = 0,
  int sillas = 0,
  List<String> acompanantes = const [],
  int acompanantesSinNombre = 0,
}) {
  final nombre =
      '${_apellidos[i % _apellidos.length]}, ${_nombres[(i * 7) % _nombres.length]}';
  return ContratoAlumno(
    id: 'a$i',
    eventoId: 'muestra',
    nombreAlumno: nombre,
    cantidadAcompanantes: acompanantes.length + acompanantesSinNombre,
    nombresAcompanantes: acompanantes,
    montoTotalPactado: 300000,
    saldoDeudor: 0,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: 8000.0 * sillas,
    cursoDivision: curso,
    telefono: '370 4${(100000 + i * 7919) % 900000}',
    musicaElegida: _musica[i % _musica.length],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('planilla_sorteo').path;

  test('planilla del sorteo — tres divisiones del tamaño de la Normal', () async {
    // Tres divisiones de unos 25 egresados; la A es larga a propósito para que
    // pase de hoja.
    final alumnos = <ContratoAlumno>[];
    var i = 0;
    for (final (curso, cantidad) in [('5° A', 34), ('5° B', 24), ('5° C', 22)]) {
      for (var k = 0; k < cantidad; k++, i++) {
        final extras = i % 9 == 0 ? 1 : (i % 23 == 0 ? 2 : 0);
        final sillas = i % 7 == 0 ? 2 : (i % 11 == 0 ? 3 : 0);
        final acompanantes = i % 3 == 0
            ? ['MAMÁ DE ${_nombres[i % _nombres.length]}', 'PAPÁ']
            : (i % 5 == 0 ? ['ABUELA'] : const <String>[]);
        alumnos.add(
          _alumno(
            i,
            curso,
            extras: extras,
            sillas: sillas,
            acompanantes: acompanantes,
            acompanantesSinNombre: i % 13 == 0 ? 1 : 0,
          ),
        );
      }
    }
    alumnos.add(
      _alumno(900, '5° B', extras: 1).copyWith(
        nombreAlumno: '[BAJA] SIN MESA, NO VA',
      ),
    );

    // Lo pagado: todos pagaron algo de todo, salvo tres sin nada de la base
    // (quedan sin mesa, fila roja) y uno con la mesa extra en $0.
    final sinBase = {'a4', 'a31', 'a52'};
    final pagos = <String, PagoAlumno>{
      for (final a in alumnos)
        a.id: sinBase.contains(a.id)
            ? PagoAlumno.nada
            : a.id == 'a18'
                ? const PagoAlumno(base: 30000)
                : const PagoAlumno(base: 30000, mesas: 10000, sillas: 8000),
    };

    // Notas operativas: dos para avisar y una ya resuelta, que no aparece.
    final ahora = DateTime(2026, 11, 10);
    NotaOperativaContrato nota(String id, String texto, {bool resuelto = false}) =>
        NotaOperativaContrato(
          id: 'n$id',
          contratoAlumnoId: id,
          texto: texto,
          resuelto: resuelto,
          createdAt: ahora,
          updatedAt: ahora,
        );
    final notas = {
      'a2': nota('a2', 'Vianda sin sal para la abuela'),
      'a27': nota('a27', 'Silla de ruedas: mesa cerca del ingreso'),
      'a40': nota('a40', 'Ya pagó la silla extra', resuelto: true),
    };

    final exclusion = exclusionSorteo(
      candidatos: candidatosPorPago(alumnos, pagos),
      soloPagado: true,
    );
    final pedidos = SorteoMesasMotor.pedidos(
      alumnos,
      separaciones: const {'a23': 1},
      sinMesa: exclusion.sinMesa,
      soloBase: exclusion.soloBase,
    );
    final ocupadas = SorteoMesasMotor.ocupadas(alumnos);
    final capacidad =
        SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: ocupadas);
    final asignaciones = SorteoMesasMotor.sortear(
      pedidos: pedidos,
      ocupadas: ocupadas,
      capacidad: capacidad,
      random: Random(7),
    );
    expect(
      SorteoMesasMotor.validar(
        pedidos: pedidos,
        ocupadas: ocupadas,
        capacidad: capacidad,
        asignaciones: asignaciones,
      ),
      isNull,
    );
    final sorteados = [
      for (final a in alumnos)
        asignaciones.containsKey(a.id)
            ? a.copyWith(
                numeroMesa:
                    MesasExtraUtils.formatearAsignacionMesas(asignaciones[a.id]!),
              )
            : a,
    ];

    final evento = Evento(
      id: 'muestra',
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: DateTime(2026, 12, 5),
      estado: EstadoEvento.planificacion,
      modalidad: 'masivo',
      cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE MUESTRA'),
    );

    for (final version in VersionPlanillaSorteo.values) {
      for (final bn in [false, true]) {
        final bytes = await PdfService.construirPlanillaSorteoPdf(
          evento,
          sorteados,
          pagos: pagos,
          notas: notas,
          version: version,
          blancoYNegro: bn,
          generada: DateTime(2026, 11, 12, 21, 30),
        );
        final nombre = 'Planilla_Sorteo_MUESTRA_'
            '${version == VersionPlanillaSorteo.interna ? 'interna' : 'para_repartir'}'
            '${bn ? '_BN' : ''}.pdf';
        final archivo = File('$destino${Platform.pathSeparator}$nombre')
          ..writeAsBytesSync(bytes);
        stdout.writeln('── PDF en: ${archivo.path}');
        expect(archivo.lengthSync(), greaterThan(1000));
      }
    }
    stdout.writeln('── capacidad sorteada: $capacidad');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
