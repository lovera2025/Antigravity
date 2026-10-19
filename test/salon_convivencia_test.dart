import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';

/// Una PC con la 6.0.0 tiene que poder abrir un salón armado en la 6.1.0 sin
/// romperlo ni perder nada al volver a guardarlo (salón primero, sección 7 de
/// `docs/PLAN_SALON_PRIMERO_2026-10-16.md`).
///
/// La 6.0.0 lee `armado_json` con este mismo modelo y lo reescribe entero al
/// guardar: **una clave nueva en el JSON se perdería**. Este test se escribió
/// el 18-oct con el código de la 6.0.0 (el modelo no cambió desde `8bb4a1f`),
/// con el JSON a mano tal como lo va a guardar la 6.1.0. Si un cambio del
/// modelo lo rompe, la 6.0.0 ya no puede convivir con lo nuevo.
void main() {
  Map<String, dynamic> ida(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(ArmadoSalon.fromJson(json).toJson()))
          as Map<String, dynamic>;

  // Unidades del Canva: 105 por cada 2 m.
  const mu = 2.0 / 105;
  double u(double metros) => metros / mu;

  /// El playón de Costa Surubí vacío: borde, escenario al frente e Ingreso al
  /// fondo, sin mesas.
  Map<String, dynamic> salonVacio() => {
        'formato': 1,
        'clave': 'vacio@1',
        'nombre': 'Salón vacío',
        'descripcion': 'El espacio, sin mesas',
        'radio': 38.0,
        'm_u': mu,
        'pegadas_u': 1.5 * u(2),
        'lugar_m': 2.0,
        'pasarela_m': 0.0,
        'hojas': [
          {
            'id': 'A',
            'titulo': 'Playón',
            'caja': [0.0, 0.0, 120.0 + u(46), 110.0 + u(39) + 60.0],
            'borde': [
              [60.0 + u(23) - u(15), 110.0],
              [60.0 + u(23) + u(15), 110.0],
              [60.0 + u(46), 110.0 + u(39)],
              [60.0, 110.0 + u(39)],
            ],
          },
        ],
        'mesas': <Object>[],
        'sectores': [
          {
            't': 'escenario',
            'texto': 'Escenario',
            'h': 'A',
            'caja': [60.0 + u(23) - u(15), 60.0, u(30), 50.0],
          },
          {
            't': 'ingreso',
            'texto': 'Ingreso',
            'h': 'A',
            'caja': [60.0 + u(23) - u(2), 110.0 + u(36.5), u(4), u(2)],
          },
        ],
      };

  test('el salón vacío vuelve igual', () {
    final json = salonVacio();
    final vuelta = ida(json);
    expect(vuelta['clave'], 'vacio@1');
    expect(vuelta['mesas'], isEmpty);
    expect(vuelta['hojas'], json['hojas']);
    expect(vuelta['sectores'], _sectoresComoGuarda(json['sectores']));
    expect(vuelta['lugar_m'], 2.0);
    expect(vuelta['pasarela_m'], 0.0);
  });

  test('el escenario corrido y el playón torcido vuelven igual', () {
    final json = salonVacio();
    // Un lado del playón movido a mano: ya no es un trapecio parejo.
    (json['hojas'] as List).first['borde'] = [
      [70.0, 104.0],
      [60.0 + u(40), 110.0],
      [60.0 + u(52), 110.0 + u(44)],
      [55.0, 110.0 + u(39)],
    ];
    // El escenario a un costado, y una pista y una barra.
    (json['sectores'] as List)
      ..first['caja'] = [90.0, 75.0, u(12), u(6)]
      ..add({
        't': 'pista',
        'texto': 'Pista',
        'h': 'A',
        'caja': [300.0, 600.0, u(10), u(10)],
      })
      ..add({
        't': 'barra',
        'texto': 'Barra',
        'h': 'A',
        'caja': [100.0, 900.0, u(2), u(8)],
        'v': true,
      });
    final vuelta = ida(json);
    expect(vuelta['hojas'], json['hojas']);
    expect(vuelta['sectores'], _sectoresComoGuarda(json['sectores']));
  });

  test('con las mesas acomodadas, vuelve igual', () {
    final json = salonVacio()
      ..['clave'] = 'vacio@1'
      ..['mesas'] = [
        for (var i = 1; i <= 12; i++)
          {'n': i, 'h': 'A', 'x': 200.0 + 30 * i, 'y': 300.0},
      ]
      ..['ultimo_numero'] = 12;
    final vuelta = ida(json);
    expect(vuelta['mesas'], json['mesas']);
    expect(vuelta['ultimo_numero'], 12);
  });

  // Los predios con nombre (6.1.0): el salón de una fiesta que arrancó de uno
  // lleva su id en el valor de `clave` y su nombre en `nombre`, dos claves
  // que ya existen. Nada más: la 6.0.0 lo abre como un salón cualquiera (sin
  // "Volver al armado original", igual que el vacío) y lo guarda igual.
  test('un salón que salió de un predio vuelve igual, con su clave', () {
    const clave = 'predio@d0000000-0000-4000-8000-000000000001';
    final json = salonVacio()
      ..['clave'] = clave
      ..['nombre'] = 'Buena Vista'
      ..['mesas'] = [
        for (var i = 1; i <= 6; i++)
          {'n': i, 'h': 'A', 'x': 200.0 + 30 * i, 'y': 300.0},
      ];
    final vuelta = ida(json);
    expect(vuelta['clave'], clave);
    expect(vuelta['nombre'], 'Buena Vista');
    expect(vuelta['mesas'], json['mesas']);
    expect(vuelta['hojas'], json['hojas']);
    expect(vuelta.keys.toSet(), json.keys.toSet(),
        reason: 'ninguna clave nueva, ninguna perdida');
  });

  test('una clave que el modelo no conoce se pierde: por eso no se agregan',
      () {
    final json = salonVacio()..['manijas'] = {'algo': 1};
    expect(ida(json).containsKey('manijas'), isFalse);
  });
}

/// Los sectores como los escribe el modelo (sin `v` cuando no es vertical).
List<Object?> _sectoresComoGuarda(Object? sectores) => [
      for (final s in sectores as List)
        {
          for (final e in (s as Map).entries)
            if (!(e.key == 'v' && e.value == false)) e.key: e.value,
        },
    ];
