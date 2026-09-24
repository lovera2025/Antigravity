// Arnés manual: sortea un evento inventado con el motor real y genera la
// Planilla de cursos, para mirar el papel sin levantar la app ni tocar la base.
//
//   flutter test tool/planilla_cursos_muestra_test.dart
//   flutter test tool/planilla_cursos_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Lo que se mira:
//   • la hoja de resumen: totales del salón y quién tiene mesas o sillas extra,
//     con sus números, juntas o separadas, y en qué mesa van las sillas;
//   • en cada curso, la columna MESA (con "(!)" si no coincide con la cuenta) y
//     SILLAS EXTRA;
//   • que los de baja no aparezcan.
//
// No vive en test/ a propósito: guarda un PDF, y eso no tiene que pasar en cada
// corrida de la suite.
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

ContratoAlumno _alumno(
  String nombre,
  String curso, {
  int extras = 0,
  int sillas = 0,
  List<String> acompanantes = const [],
  String? mesa,
}) =>
    ContratoAlumno(
      id: nombre,
      eventoId: 'muestra',
      nombreAlumno: nombre,
      cantidadAcompanantes: acompanantes.length,
      nombresAcompanantes: acompanantes,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      cursoDivision: curso,
      numeroMesa: mesa,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('planilla_cursos').path;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => destino,
        );
  });

  test('planilla de cursos — evento sorteado con extras', () async {
    final base = [
      _alumno('ACOSTA, LUCÍA', '5° A',
          extras: 1, sillas: 4, acompanantes: ['Mamá', 'Papá']),
      _alumno('AGUIRRE, TOMÁS', '5° A'),
      _alumno('BARRIOS, MARTINA', '5° A', extras: 2, sillas: 3),
      _alumno('CANTEROS, JULIÁN', '5° A',
          sillas: 2, acompanantes: List.filled(10, 'Familiar')),
      _alumno('DUARTE, SOFÍA', '5° A',
          acompanantes: ['Mamá', 'Papá', 'Abuela']),
      _alumno('ESCOBAR, NAHUEL', '5° A'),
      _alumno('FERNÁNDEZ, CAMILA', '5° A', extras: 1),
      _alumno('GIMÉNEZ, FRANCO', '5° A'),
      _alumno('[BAJA] HERRERA, PAULA', '5° A', extras: 1),
      _alumno('INSFRÁN, VALENTINA', '5° B', extras: 4),
      _alumno('JARA, MATEO', '5° B'),
      _alumno('LEDESMA, AGUSTINA', '5° B', sillas: 1),
      _alumno('MEDINA, BRUNO', '5° B'),
      _alumno('NÚÑEZ, CATALINA', '5° B', extras: 1, sillas: 2),
      _alumno('OJEDA, IVÁN', '5° B'),
      _alumno('PEREYRA, MILAGROS', '5° B'),
      _alumno('QUIROGA, DANTE', '5° B'),
      _alumno('ROMERO, ABRIL', '5° B'),
    ];

    // Se sortea con el motor real; BARRIOS separa una mesa.
    final pedidos = SorteoMesasMotor.pedidos(
      base,
      separaciones: const {'BARRIOS, MARTINA': 1},
    );
    final ocupadas = SorteoMesasMotor.ocupadas(base);
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
      for (final a in base)
        asignaciones.containsKey(a.id)
            ? a.copyWith(
                numeroMesa:
                    MesasExtraUtils.formatearAsignacionMesas(asignaciones[a.id]!),
              )
            : a,
    ];
    // Después del sorteo: FERNÁNDEZ compró otra mesa extra (le falta una) y
    // llegó un alumno nuevo sin mesa todavía.
    final alumnos = [
      for (final a in sorteados)
        a.id == 'FERNÁNDEZ, CAMILA'
            ? a.copyWith(mesaExtraCantidad: 2, mesaExtraPrecio: 140000)
            : a,
      _alumno('VALLEJOS, RAMIRO', '5° B', extras: 1),
    ];

    final evento = Evento(
      id: 'muestra',
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: DateTime(2026, 12, 1),
      estado: EstadoEvento.planificacion,
      modalidad: 'masivo',
      cliente: Cliente(id: 'c', nombreCompleto: 'COLEGIO DE MUESTRA'),
    );

    final bytes = await PdfService.construirPlanillaCursosPdf(evento, alumnos);
    final archivo = File(
      '$destino${Platform.pathSeparator}Planilla_Cursos_MUESTRA.pdf',
    )..writeAsBytesSync(bytes);

    stdout.writeln('── capacidad sorteada: $capacidad');
    for (final a in sorteados.where((a) => a.numeroMesa != null)) {
      stdout.writeln('   ${a.nombreAlumno}: ${a.numeroMesa}');
    }
    stdout.writeln('── PDF en: ${archivo.path}');
    expect(archivo.lengthSync(), greaterThan(1000));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
