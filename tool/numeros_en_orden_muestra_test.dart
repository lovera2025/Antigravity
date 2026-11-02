// Arnés manual: Puerto Viejo antes y después de ordenar los números, con el
// plano real de la nube y el mismo dibujo de la app, sin levantar la app ni tocar
// la base. La línea va de un número al siguiente: es el camino que sigue el
// sorteo, y donde se corta, una familia no puede quedar junta.
//
//   flutter test tool/numeros_en_orden_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen Numeros_en_orden_Puerto_Viejo.png; Familias_<estilo>.png, con familias
// inventadas juntas y separadas; y Familias_color.pdf y Familias_bn.pdf. El plano solo
// tiene lugares y números: los apellidos son de mentira.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

import '../test/helpers/salon_puerto_viejo.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _pegada = Color(0xFF1D9E75);
const _cortada = Color(0xFFD64541);

/// Solo para la imagen: la hoja recortada a las mesas, sin el borde del playón
/// ni los sectores. El plano de verdad no cambia.
ArmadoSalon _encuadrado(ArmadoSalon a) => a.copyWith(
      hojas: const [
        HojaPlano(
          id: 'A',
          titulo: 'Playón',
          caja: RectPlano(760, 1180, 1560, 800),
        ),
      ],
      sectores: const [],
    );

/// La línea de un número al siguiente: verde si las dos mesas están pegadas,
/// roja donde hay un salto.
class _Recorrido extends CustomPainter {
  _Recorrido(this.armado);

  final ArmadoSalon armado;

  @override
  void paint(Canvas canvas, Size size) {
    final encuadre = EncuadrePlano.de(armado.hojas.first.caja, size);
    for (final m in armado.mesas) {
      final o = armado.mesa(m.numero + 1);
      if (o == null) continue;
      final corte = armado.cortes.contains(m.numero);
      // De borde a borde, para que la línea no tape los números.
      final desde = Offset(m.x, m.y);
      final hasta = Offset(o.x, o.y);
      final borde = (hasta - desde) / (hasta - desde).distance * armado.radio;
      canvas.drawLine(
        encuadre.aPantalla(desde + borde),
        encuadre.aPantalla(hasta - borde),
        Paint()
          ..color = (corte ? _cortada : _pegada).withValues(alpha: 0.75)
          ..strokeWidth = corte ? 2.5 : 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Recorrido oldDelegate) => oldDelegate.armado != armado;
}

Widget _columna(String titulo, String detalle, ArmadoSalon armado) {
  final visto = _encuadrado(armado);
  final plano = PlanoDeLaFiesta.desde(
    armado: visto,
    config: ConfigPlano.vacia,
    alumnos: const [],
  );
  return Expanded(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontFamily: FuentesPlano.linea,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          Text(
            detalle,
            style: const TextStyle(
              fontFamily: FuentesPlano.linea,
              fontSize: 17,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                VistaPlano(
                  armado: visto,
                  hoja: 'A',
                  tema: TemaPlano.de(EstiloPlano.arquitecto),
                  estado: plano.estado,
                  animar: false,
                ),
                CustomPaint(painter: _Recorrido(visto)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Familias inventadas: unas juntas, otras separadas, otras con una mesa sola.
ContratoAlumno _familia(String apellido, List<int> mesas, String division) =>
    ContratoAlumno(
      id: apellido,
      eventoId: 'muestra',
      nombreAlumno: '$apellido, DE PRUEBA',
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * (mesas.length - 1),
      mesaExtraCantidad: mesas.length - 1,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

final _familias = [
  _familia('ACOSTA', [1], '5° A'),
  _familia('BENITEZ', [2, 3], '5° A'),
  _familia('CASTRO', [4], '5° A'),
  _familia('DOMINGUEZ', [6, 7, 8, 9], '5° A'),
  _familia('ESPINDOLA', [11, 30], '5° B'),
  _familia('FERREYRA', [13], '5° B'),
  _familia('GOMEZ', [15, 16, 26], '5° B'),
  _familia('HERRERA', [20, 21], '5° B'),
  _familia('IBARRA', [33], '5° B'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final estilo in EstiloPlano.values) {
    testWidgets('las familias en el plano, en ${estilo.name}', (tester) async {
      await cargarFuentesPlano();
      final carpeta = _salida.isNotEmpty
          ? _salida
          : Directory.systemTemp.createTempSync('familias').path;
      final recortado = _encuadrado(
        ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado,
      );
      final plano = PlanoDeLaFiesta.desde(
        armado: recortado,
        config: ConfigPlano.vacia,
        alumnos: _familias,
      );
      tester.view.physicalSize = const Size(1500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final clave = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: clave,
            child: VistaPlano(
              armado: recortado,
              hoja: 'A',
              tema: TemaPlano.de(estilo),
              estado: plano.estado,
              familias: plano.familias,
              animar: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await boundary.toImage(pixelRatio: 1.5);
        final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
        File('$carpeta${Platform.pathSeparator}Familias_${estilo.name}.png')
            .writeAsBytesSync(datos!.buffer.asUint8List());
      });
    });
  }

  test('las familias en papel', () async {
    final carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('familias').path;
    // Recortado a las mesas: con el playón entero salen chicas y sin apellido.
    final plano = PlanoDeLaFiesta.desde(
      armado: _encuadrado(
        ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado,
      ),
      config: ConfigPlano.vacia,
      alumnos: _familias,
    );
    final evento = Evento(
      id: 'muestra',
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: DateTime(2026, 12, 1),
      estado: EstadoEvento.planificacion,
      modalidad: 'masivo',
      cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE MUESTRA'),
    );
    for (final bn in [false, true]) {
      final bytes = await PdfService.construirPlanoPdf(
        evento,
        plano,
        estilo: EstiloPlano.arquitecto,
        blancoYNegro: bn,
        generada: DateTime(2026, 11, 2, 12),
      );
      File('$carpeta${Platform.pathSeparator}Familias_${bn ? 'bn' : 'color'}.pdf')
          .writeAsBytesSync(bytes);
    }
  });

  testWidgets('Puerto Viejo, antes y después', (tester) async {
    await cargarFuentesPlano();
    final carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('numeros_en_orden').path;
    final antes = armadoDePuertoViejo();
    final despues = ArmarAMedida.ordenarNumeros(antes).armado;

    tester.view.physicalSize = const Size(1500, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final clave = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: clave,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _columna(
                  'Hoy',
                  '${antes.cortes.length} saltos en ${antes.mesas.length} mesas',
                  antes,
                ),
                _columna(
                  'Ordenado, sin mover ninguna mesa',
                  '${despues.cortes.length} salto: el paso de un lado al otro',
                  despues,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1.5);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File(
        '$carpeta${Platform.pathSeparator}Numeros_en_orden_Puerto_Viejo.png',
      )..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  });
}
