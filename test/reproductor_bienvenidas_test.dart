// La cola de bienvenidas en el tiempo (`reproductor_bienvenidas.dart`): cuándo
// aparece cada tarjeta, cuánto dura, cuándo se va y cuándo sigue la próxima. Con
// el reloj de los tests: los temporizadores corren con `tester.pump`.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/services/reproductor_bienvenidas.dart';
import 'package:arguello_events/models/invitado.dart';

Invitado _inv(String id) => Invitado(
      id: id,
      eventoId: 'evento',
      nombreCompleto: 'INVITADO $id',
      dni: '',
      estadoIngreso: EstadoIngreso.ingresado,
    );

/// Un reproductor con un reloj que avanza junto con los temporizadores.
class _Noche {
  var ahora = DateTime(2026, 12, 12, 22);
  late final r = ReproductorBienvenidas(
    ahora: () => ahora,
    salida: const Duration(milliseconds: 700),
    pausa: const Duration(milliseconds: 300),
  )
    ..familiaDe = ((i) => i.id.split('-').first)
    ..leyo(const []);

  /// Avanza [ms] de a cien, como un cuadro de pantalla cada tanto.
  Future<void> pasan(WidgetTester tester, int ms) async {
    for (var hecho = 0; hecho < ms; hecho += 100) {
      final paso = ms - hecho < 100 ? ms - hecho : 100;
      ahora = ahora.add(Duration(milliseconds: paso));
      await tester.pump(Duration(milliseconds: paso));
    }
  }

  List<String>? get enPantalla =>
      r.actual?.personas.map((i) => i.id).toList();
}

void main() {
  testWidgets('sola dura 7 s, se va en 0,7 y vuelve a la espera', (tester) async {
    final n = _Noche();
    n.r.aviso(_inv('garcia'));
    await tester.pump();
    expect(n.enPantalla, ['garcia']);
    await n.pasan(tester, 6900);
    expect(n.r.saliendo, isFalse);
    await n.pasan(tester, 200);
    expect(n.r.saliendo, isTrue, reason: 'a los 7 s empieza a irse');
    expect(n.r.fin, isNull);
    await n.pasan(tester, 700);
    expect(n.r.actual, isNull);
    n.r.dispose();
  });

  testWidgets('con cola, cada una dura 3 s y la última 7', (tester) async {
    final n = _Noche();
    for (final id in ['acosta', 'benitez', 'garcia']) {
      n.r.aviso(_inv(id));
    }
    await tester.pump();
    expect(n.enPantalla, ['acosta']);
    expect(n.r.enCamino, 2);
    final vistas = <String>[];
    var ms = 0;
    while (n.r.actual != null || n.r.enCamino > 0) {
      final id = n.enPantalla?.single;
      if (id != null && (vistas.isEmpty || vistas.last != id)) vistas.add(id);
      await n.pasan(tester, 100);
      ms += 100;
      if (ms > 30000) fail('la cola no se vació');
    }
    expect(vistas, ['acosta', 'benitez', 'garcia']);
    // 3 + 1 (se va y la pausa) + 3 + 1 + 7 + 0,7: unos 15,7 s.
    expect(ms, inInclusiveRange(15500, 16100));
    n.r.dispose();
  });

  testWidgets('llega alguien a los 5 s: la que está se va enseguida',
      (tester) async {
    final n = _Noche();
    n.r.aviso(_inv('acosta'));
    await tester.pump();
    await n.pasan(tester, 5000);
    expect(n.r.saliendo, isFalse);
    n.r.aviso(_inv('garcia'));
    await n.pasan(tester, 100);
    expect(n.r.saliendo, isTrue);
    await n.pasan(tester, 1000);
    expect(n.enPantalla, ['garcia']);
    n.r.dispose();
  });

  testWidgets('la familia que se marca de a uno se suma a la tarjeta',
      (tester) async {
    final n = _Noche();
    n.r.aviso(_inv('perez'));
    await tester.pump();
    await n.pasan(tester, 1500);
    n.r.aviso(_inv('perez-1'));
    await n.pasan(tester, 1500);
    n.r.aviso(_inv('perez-2'));
    await tester.pump();
    expect(n.enPantalla, ['perez', 'perez-1', 'perez-2']);
    expect(n.r.enCamino, 0);
    await n.pasan(tester, 3900);
    expect(n.r.saliendo, isFalse, reason: 'sigue hasta los 7 s');
    await n.pasan(tester, 200);
    expect(n.r.saliendo, isTrue);
    n.r.dispose();
  });

  testWidgets('el que llega mientras la tarjeta se va espera la suya, sin '
      'trabarla', (tester) async {
    final n = _Noche();
    n.r.aviso(_inv('perez'));
    await tester.pump();
    await n.pasan(tester, 7100);
    expect(n.r.saliendo, isTrue);
    n.r.aviso(_inv('perez-1'));
    n.r.aviso(_inv('garcia'));
    await tester.pump();
    await n.pasan(tester, 1100);
    expect(n.enPantalla, ['perez-1'], reason: 'la salida no se cortó');
    n.r.dispose();
  });

  testWidgets('sacar al único de la tarjeta la saca, y sigue la cola',
      (tester) async {
    final n = _Noche();
    n.r.aviso(_inv('acosta'));
    n.r.aviso(_inv('garcia'));
    await tester.pump();
    n.r.baja('acosta');
    await tester.pump();
    expect(n.enPantalla, ['garcia']);
    n.r.dispose();
  });

  testWidgets('vaciar, pausar o reiniciar no dejan temporizadores sueltos',
      (tester) async {
    for (final corte in <void Function(ReproductorBienvenidas)>[
      (r) => r.vaciar(),
      (r) => r.pausar(),
      (r) => r.reiniciar(),
    ]) {
      final n = _Noche();
      n.r.aviso(_inv('acosta'));
      n.r.aviso(_inv('garcia'));
      await tester.pump();
      corte(n.r);
      await n.pasan(tester, 12000);
      expect(n.r.actual, isNull);
      n.r.dispose();
    }
  });

  testWidgets('antes de saludar, espera a que se prepare la cola (como mucho '
      '1 s)', (tester) async {
    final n = _Noche();
    var preparadas = 0;
    n.r.prepararCola = (cola) async {
      preparadas++;
      await Future<void>.delayed(const Duration(seconds: 5));
    };
    n.r.aviso(_inv('nuevo'));
    await tester.pump();
    expect(n.r.actual, isNull, reason: 'espera la ficha');
    await n.pasan(tester, 1100);
    expect(n.enPantalla, ['nuevo'], reason: 'no espera más de un segundo');
    expect(preparadas, 1);
    await n.pasan(tester, 5000);
    n.r.dispose();
  });

  testWidgets('avisa a la pantalla cuando cambia algo', (tester) async {
    final n = _Noche();
    var avisos = 0;
    n.r.addListener(() => avisos++);
    n.r.aviso(_inv('garcia'));
    await tester.pump();
    expect(avisos, greaterThanOrEqualTo(2), reason: 'llegó y entró');
    final antes = avisos;
    expect(n.r.aviso(_inv('garcia')), isFalse);
    expect(avisos, antes, reason: 'un aviso repetido no cambia nada');
    n.r.dispose();
  });

  testWidgets('abierto sin internet, la lista de la PC llega sin bienvenidas',
      (tester) async {
    final r = ReproductorBienvenidas()..noPudoLeer();
    var avisos = 0;
    r.addListener(() => avisos++);
    expect(r.leyoDeLaPc([_inv('acosta'), _inv('benitez')]), isTrue);
    await tester.pump();
    expect(avisos, greaterThan(0), reason: 'la pantalla redibuja la cuenta');
    expect(r.ingresados, hasLength(2));
    expect(r.actual, isNull);
    expect(r.conectado, isFalse);
    // Ya con la nube leída, no se toma más.
    r.leyo([_inv('acosta')]);
    expect(r.leyoDeLaPc([_inv('zapata')]), isFalse);
    r.dispose();
  });
}
