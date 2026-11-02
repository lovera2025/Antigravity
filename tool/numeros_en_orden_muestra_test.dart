// Arnés manual: Puerto Viejo antes y después de ordenar los números, con el
// plano real de la nube y el mismo dibujo de la app, sin levantar la app ni tocar
// la base. La línea va de un número al siguiente: es el camino que sigue el
// sorteo, y donde se corta, una familia no puede quedar junta.
//
//   flutter test tool/numeros_en_orden_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sale Numeros_en_orden_Puerto_Viejo.png. El plano solo tiene lugares y números,
// ningún nombre.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
