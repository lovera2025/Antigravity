// El color que la fiesta elige para una división es el que sale impreso.
//
// La hoja va siempre sobre blanco, y antes pintaba las divisiones con la paleta
// de Arquitecto por posición: en una fiesta en Gala el verde salía celeste y el
// azul, salmón. Ahora cada estilo lleva sus colores a papel: el mismo tono, en
// claro para el relleno y en oscuro para el anillo y el número.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/plano_pdf.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/leer_pdf.dart';

/// Cuánto se lee un color sobre otro (la cuenta de contraste de WCAG): con 4,5
/// o más, un texto chico se lee bien.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Qué tan distintos se ven dos colores (0 a 441).
double _distancia(Color a, Color b) => math.sqrt(
      math.pow((a.r - b.r) * 255, 2) +
          math.pow((a.g - b.g) * 255, 2) +
          math.pow((a.b - b.b) * 255, 2),
    );

double _tono(Color c) => HSLColor.fromColor(c).hue;

/// La diferencia entre dos tonos, por el lado corto de la rueda.
double _entreTonos(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

bool _esNeutro(Color c) => HSLColor.fromColor(c).saturation < 0.12;

/// Los rellenos que usa el PDF, como 0xRRGGBB.
Set<int> _rellenos(String contenido) => {
      for (final m in RegExp(r'([\d.]+) ([\d.]+) ([\d.]+) rg')
          .allMatches(contenido))
        ((double.parse(m.group(1)!) * 255).round() << 16) |
            ((double.parse(m.group(2)!) * 255).round() << 8) |
            (double.parse(m.group(3)!) * 255).round(),
    };

int _rgb(Color c) => c.toARGB32() & 0xFFFFFF;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arquitecto imprime igual que siempre', () {
    final tema = TemaPlano.arquitecto;
    expect(tema.papel, tema.divisiones);
    expect(tema.papelNumero, tema.numeroDivision);
  });

  for (final estilo in [EstiloPlano.gala, EstiloPlano.neon]) {
    final tema = TemaPlano.de(estilo);

    group('${estilo.nombre} en papel', () {
      test('un color por cada color de la pantalla, en el mismo orden', () {
        expect(tema.papel, hasLength(tema.divisiones.length));
        expect(tema.papelNumero, hasLength(tema.divisiones.length));
      });

      test('cada color sale con su mismo tono', () {
        for (final (i, enPantalla) in tema.divisiones.indexed) {
          if (_esNeutro(enPantalla)) {
            expect(_esNeutro(tema.papel[i]), isTrue, reason: 'el $i');
            continue;
          }
          expect(
            _entreTonos(_tono(tema.papel[i]), _tono(enPantalla)),
            lessThan(3),
            reason: 'el relleno del $i cambió de color',
          );
          expect(
            _entreTonos(_tono(tema.papelNumero[i]), _tono(enPantalla)),
            lessThan(3),
            reason: 'el número del $i cambió de color',
          );
        }
      });

      test('es claro: va sobre papel blanco, sin gastar tinta', () {
        for (final (i, c) in tema.papel.indexed) {
          expect(
            HSLColor.fromColor(c).lightness,
            greaterThanOrEqualTo(0.79),
            reason: 'el $i',
          );
        }
      });

      test('el número se lee sobre su relleno', () {
        for (var i = 0; i < tema.papel.length; i++) {
          expect(
            _contraste(tema.papelNumero[i], tema.papel[i]),
            greaterThanOrEqualTo(4.5),
            reason: 'el número del $i sobre su relleno',
          );
          // El apellido va en negro, al lado.
          expect(
            _contraste(const Color(0xFF1F2328), tema.papel[i]),
            greaterThanOrEqualTo(4.5),
            reason: 'el negro sobre el relleno del $i',
          );
        }
      });

      test('no hay dos que se confundan', () {
        // Los dos pasteles más parecidos de Arquitecto están a 14.
        for (var i = 0; i < tema.papel.length; i++) {
          for (var j = i + 1; j < tema.papel.length; j++) {
            expect(
              _distancia(tema.papel[i], tema.papel[j]),
              greaterThan(14),
              reason: 'el $i y el $j salen casi iguales',
            );
          }
        }
      });

      test('ninguno queda blanco: una mesa con familia no parece vacía', () {
        for (final (i, c) in tema.papel.indexed) {
          expect(
            _distancia(c, const Color(0xFFFFFFFF)),
            greaterThan(20),
            reason: 'el $i',
          );
        }
      });
    });
  }

  test('el más fuerte en pantalla sale más fuerte en papel', () {
    // El rubí y el cuarzo rosa de Gala tienen el mismo tono: en papel siguen
    // siendo dos.
    const rubi = Color(0xFFD94FA3);
    const cuarzo = Color(0xFFE89AC7);
    expect(
      HSLColor.fromColor(TemaPlano.enPapel(rubi)).lightness,
      lessThan(HSLColor.fromColor(TemaPlano.enPapel(cuarzo)).lightness),
    );
  });

  group('en el PDF', () {
    ContratoAlumno alumno(int mesa, String division) => ContratoAlumno(
          id: 'f$mesa',
          eventoId: 'e',
          nombreAlumno: 'FAMILIA$mesa, ALUMNO',
          cantidadAcompanantes: 0,
          montoTotalPactado: 300000,
          saldoDeudor: 0,
          numeroMesa: MesasExtraUtils.formatearAsignacionMesas([mesa]),
          cursoDivision: division,
        );

    Future<Set<int>> rellenos(
      EstiloPlano estilo, {
      Map<String, int> colores = const {},
      bool blancoYNegro = false,
    }) async =>
        _rellenos(contenidoDelPdf(await PlanoPdf.construir(
          institucion: 'ESCUELA DE PRUEBA',
          plano: PlanoDeLaFiesta.desde(
            armado: ArmadosPredefinidos.normal2aPagina3(),
            config: ConfigPlano(colores: colores),
            alumnos: [
              for (var n = 1; n <= 10; n++) alumno(n, '5° A'),
              for (var n = 11; n <= 20; n++) alumno(n, '5° B'),
            ],
          ),
          estilo: estilo,
          blancoYNegro: blancoYNegro,
          generada: DateTime(2026, 11, 13, 9, 15),
        )));

    for (final estilo in EstiloPlano.values) {
      test('una fiesta en ${estilo.nombre} sale con los colores de '
          '${estilo.nombre}', () async {
        final tema = TemaPlano.de(estilo);
        final usados = await rellenos(estilo);
        expect(usados, contains(_rgb(tema.papel[0])));
        expect(usados, contains(_rgb(tema.papel[1])));
        // Y con los de ningún otro estilo.
        for (final otro in EstiloPlano.values.where((e) => e != estilo)) {
          expect(usados, isNot(contains(_rgb(TemaPlano.de(otro).papel[0]))));
        }
      });
    }

    test('el color que se eligió es el que sale', () async {
      final tema = TemaPlano.gala;
      final usados = await rellenos(
        EstiloPlano.gala,
        colores: const {'5A': 5, '5B': 2},
      );
      expect(usados, contains(_rgb(tema.papel[5])));
      expect(usados, contains(_rgb(tema.papel[2])));
      expect(usados, isNot(contains(_rgb(tema.papel[0]))));
      expect(usados, isNot(contains(_rgb(tema.papel[1]))));
    });

    test('en blanco y negro no sale ningún color, en ningún estilo', () async {
      for (final estilo in EstiloPlano.values) {
        final usados = await rellenos(estilo, blancoYNegro: true);
        for (final c in TemaPlano.de(estilo).papel) {
          // El gris de Arquitecto es un gris: puede coincidir con uno del papel.
          if (_esNeutro(c)) continue;
          expect(usados, isNot(contains(_rgb(c))), reason: estilo.nombre);
        }
      }
    });
  });
}
