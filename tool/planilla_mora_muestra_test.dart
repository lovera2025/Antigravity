// Arnés manual: genera la planilla de mora con alumnos inventados, para mirar
// el papel sin levantar la app ni tocar la base.
//
//   flutter test tool/planilla_mora_muestra_test.dart
//
// Es la hoja con la que se llama a las familias, así que lo que se mira es:
//   • que estén TODOS (el conteo lo verifica test/planilla_mora_pdf_test.dart);
//   • que se lean los teléfonos y el desglose por cuota;
//   • cuántas hojas salen — si son muchas, hay que bajar el objetivo de
//     `_ajustarParaPaginas` o recortar el desglose antes de descubrirlo en la
//     impresora.
//
// No vive en test/ a propósito: guarda un PDF, y eso no tiene que pasar en cada
// corrida de la suite.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';

/// Carpeta de salida: se pasa por -Dsalida=... o cae en el temporal del sistema.
const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'AGUIRRE', 'ALIVERTI', 'AQUINO', 'ARANDA', 'BARRIOS', 'BEJARANO',
  'CANTEROS', 'DUARTE', 'ESCOBAR', 'FERNÁNDEZ', 'GIMÉNEZ', 'HERRERA', 'INSFRÁN',
  'JARA', 'LEDESMA', 'MEDINA', 'NÚÑEZ', 'OJEDA', 'PEREYRA', 'QUIROGA', 'ROMERO',
  'SOSA', 'TOLEDO', 'URBANO', 'VALLEJOS',
];

const _cursos = ['1', '2', '3', 'EPJA', 'SAN GREGORIO', 'EXT PAGO REDONDO'];

MoraPdfFila _fila(int i) {
  final apellido = _apellidos[i % _apellidos.length];
  final vencida = i % 4 == 0 ? 0.0 : 4200.0 * ((i % 9) + 1);
  final noCobrada = i % 3 == 0 ? 0.0 : 3100.0 * ((i % 7) + 1);
  return MoraPdfFila(
    nombre: '$apellido, ALUMNO ${i + 1}',
    curso: _cursos[i % _cursos.length],
    telefono: i % 11 == 0 ? '' : '3777${(200000 + i * 137) % 900000}',
    cuotas: '${(i % 9)}/9',
    moraVencida: vencida,
    detalleVencida: vencida <= 0
        ? ''
        : 'C1 (Abr) 113d \$30.400,00 · C2 (May) 82d \$18.000,00 · '
              'C3 (Jun) 52d \$6.000,00',
    moraNoCobrada: noCobrada,
    detalleNoCobrada:
        noCobrada <= 0 ? '' : 'C1 (Abr) 26 días \$10.400,00 · C4 (Jul) 21d',
    saldoPlan: 40000.0 * ((i % 6) + 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('planilla_mora').path;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => destino,
        );
  });

  test('planilla de mora — 50 activos, con y sin bajas', () async {
    final activos = [for (var i = 0; i < 50; i++) _fila(i)]
        .where((f) => f.moraTotal > 0.01)
        .toList();
    final bajas = [for (var i = 50; i < 56; i++) _fila(i)]
        .where((f) => f.moraTotal > 0.01)
        .toList();

    final data = PdfService.planillaMoraFilasTabla(activos);
    stdout.writeln('── activos con mora: ${activos.length}');
    stdout.writeln('── filas en la tabla: ${data.length}');
    stdout.writeln('── bajas con mora:   ${bajas.length}');
    stdout.writeln('── primeros tres (los que más deben):');
    for (final f in data.take(3)) {
      stdout.writeln('   • ${f[1].replaceAll('\n', ' / ')}  tel ${f[2]}  '
          'total ${f[6]}');
    }
    // Lo que no puede fallar: que no se caiga nadie entre la lista y la tabla.
    expect(data.length, activos.length);

    await PdfService.generarPlanillaMoraPdf(
      eventoTitulo: 'COLEGIO BUENA VISTA',
      filtroTitulo: 'Con mora',
      generadoEn: DateTime(2026, 8, 21, 21, 40),
      filas: activos,
    );

    await PdfService.generarPlanillaMoraPdf(
      eventoTitulo: 'COLEGIO BUENA VISTA (con bajas)',
      filtroTitulo: 'Con mora · incluye baja temporal',
      generadoEn: DateTime(2026, 8, 21, 21, 40),
      filas: activos,
      bajas: bajas,
    );

    final pdfs = Directory(
      '$destino${Platform.pathSeparator}Junior Eventos'
      '${Platform.pathSeparator}PDFs',
    );
    stdout.writeln('── PDF en: ${pdfs.path}');
    expect(pdfs.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
