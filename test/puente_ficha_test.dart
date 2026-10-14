// La ficha del evento que arma la ventana principal con la base de la PC, y lo
// que le contesta al tótem cuando la pide (`puente_ficha.dart`). Con los mismos
// repositorios en memoria que usa el test de Recepción: sin base ni red.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/totem/services/ficha_totem.dart';
import 'package:arguello_events/features/totem/services/lista_de_la_pc.dart';
import 'package:arguello_events/features/totem/services/puente_ficha.dart';
import 'package:arguello_events/models/invitado.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

void main() {
  final supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  final contratos = ContratosEnMemoria(supabase, alumnosDeLaFicha());
  final sillas = SillasEnMemoria();
  final eventos = {
    eventoMasivo: eventoDePrueba(eventoMasivo, 'masivo'),
    eventoParticular: eventoDePrueba(eventoParticular, 'particular'),
  };
  var lecturasDeAlumnos = 0;

  Future<FichaTotem> armar(String eventoId) => armarFichaTotem(
        eventoId,
        leerEvento: (id) async => eventos[id],
        leerAlumnos: (id) {
          lecturasDeAlumnos++;
          return leerAlumnosDeLaPuerta(contratos, sillas, id);
        },
      );

  setUp(() => lecturasDeAlumnos = 0);

  test('un masivo: la ficha de sus alumnos, como en Recepción', () async {
    final ficha = await armar(eventoMasivo);
    expect(ficha.eventoId, eventoMasivo);
    expect(ficha.masivo, isTrue);
    expect(ficha.de(idDe('perez'))!.sillas, '10 sillas (8 + 2 extra)');
    expect(ficha.familiaDe(idDe('perez', 2)), idDe('perez'));
    expect(ficha.de(idDe('baja')), isNull, reason: 'las bajas no');
  });

  test('un particular no lee alumnos', () async {
    final ficha = await armar(eventoParticular);
    expect(ficha.masivo, isFalse);
    expect(ficha.personas, isEmpty);
    expect(lecturasDeAlumnos, 0);
  });

  test('un evento que esta PC no tiene se trata como particular', () async {
    final ficha = await armar('e0000000-0000-4000-8000-0000000000ff');
    expect(ficha.masivo, isFalse);
    expect(lecturasDeAlumnos, 0);
  });

  group('el plano de la fiesta', () {
    final salon = ArmadosPredefinidos.normal2aPagina3();

    test('un masivo lleva el salón de su plano', () async {
      final ficha = await armarFichaTotem(
        eventoMasivo,
        leerEvento: (id) async => eventos[id],
        leerAlumnos: (id) => leerAlumnosDeLaPuerta(contratos, sillas, id),
        leerPlano: (id) async => id == eventoMasivo ? salon : null,
      );
      expect(ficha.plano, same(salon));
    });

    test('si el plano no se puede leer, la ficha va sin él', () async {
      final ficha = await armarFichaTotem(
        eventoMasivo,
        leerEvento: (id) async => eventos[id],
        leerAlumnos: (id) => leerAlumnosDeLaPuerta(contratos, sillas, id),
        leerPlano: (id) async => throw StateError('base cerrada'),
      );
      expect(ficha.plano, isNull);
      expect(ficha.de(idDe('perez')), isNotNull);
    });

    test('un particular no lo lee', () async {
      var lecturas = 0;
      final ficha = await armarFichaTotem(
        eventoParticular,
        leerEvento: (id) async => eventos[id],
        leerAlumnos: (id) => leerAlumnosDeLaPuerta(contratos, sillas, id),
        leerPlano: (id) async {
          lecturas++;
          return salon;
        },
      );
      expect(ficha.plano, isNull);
      expect(lecturas, 0);
    });

    test('viaja por el puente hasta la ventana del tótem', () async {
      final r = await PuenteFichaTotem.responder(
        const MethodCall(PuenteFichaTotem.metodo, eventoMasivo),
        (id) => armarFichaTotem(
          id,
          leerEvento: (id) async => eventos[id],
          leerAlumnos: (id) => leerAlumnosDeLaPuerta(contratos, sillas, id),
          leerPlano: (id) async => salon,
        ),
      );
      expect(FichaTotem.decodificar(r)!.plano!.numeros, salon.numeros);
    });
  });

  group('lo que contesta la ventana principal', () {
    test('la ficha codificada, que el tótem lee igual', () async {
      final r = await PuenteFichaTotem.responder(
        const MethodCall(PuenteFichaTotem.metodo, eventoMasivo),
        armar,
      );
      final ficha = FichaTotem.decodificar(r)!;
      expect(ficha.masivo, isTrue);
      expect(ficha.de(idDe('perez', 1))!.titular, 'PÉREZ, JUAN MARTÍN');
    });

    test('nada a otro mensaje o a un id que no es de un evento', () async {
      for (final call in const [
        MethodCall('otra_cosa', eventoMasivo),
        MethodCall(PuenteFichaTotem.metodo),
        MethodCall(PuenteFichaTotem.metodo, 'corto'),
        MethodCall(PuenteFichaTotem.metodo, 42),
      ]) {
        expect(await PuenteFichaTotem.responder(call, armar), isNull,
            reason: '${call.method} ${call.arguments}');
      }
      expect(lecturasDeAlumnos, 0);
    });

    test('si la base falla, contesta nada: el tótem sigue con la que tenía',
        () async {
      final r = await PuenteFichaTotem.responder(
        const MethodCall(PuenteFichaTotem.metodo, eventoMasivo),
        (_) async => throw StateError('la base está ocupada'),
      );
      expect(r, isNull);
    });
  });

  // Sección 5: el tótem que abre sin internet le pide a la ventana principal
  // quién ya entró según la base de la PC.
  group('la lista de la PC', () {
    Invitado inv(String id, {bool adentro = true}) => Invitado(
          id: id,
          eventoId: eventoMasivo,
          nombreCompleto: 'INVITADO $id',
          dni: '',
          numeroMesa: '12',
          estadoIngreso:
              adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
          updatedAt: DateTime.utc(2026, 12, 12, 22, 41),
        );

    Future<ListaDeLaPc> leer(String id) => armarListaDeLaPc(
          id,
          leerInvitados: (_) async => [
            inv('a'),
            inv('b'),
            inv('c', adentro: false),
          ],
          // c tiene un deshacer sin subir; z es de otro evento.
          leerSinSubir: (_) async => {'b', 'c', 'z'},
        );

    test('lleva solo a los que entraron, y cuáles no subieron', () async {
      final lista = await leer(eventoMasivo);
      expect([for (final i in lista.adentro) i.id], ['a', 'b']);
      expect(lista.sinSubir, {'b'});
    });

    test('viaja por el puente y el tótem la lee igual', () async {
      final r = await PuenteFichaTotem.responder(
        const MethodCall(PuenteFichaTotem.metodoLista, eventoMasivo),
        armar,
        lista: leer,
      );
      final lista = ListaDeLaPc.decodificar(r)!;
      expect(lista.eventoId, eventoMasivo);
      expect([for (final i in lista.adentro) i.id], ['a', 'b']);
      expect(lista.adentro.first.numeroMesa, '12');
      expect(lista.adentro.first.updatedAt, DateTime.utc(2026, 12, 12, 22, 41));
      expect(lista.sinSubir, {'b'});
      expect(lecturasDeAlumnos, 0, reason: 'no arma la ficha');
    });

    test('sin quién la arme, o con la base fallando, contesta nada', () async {
      const call = MethodCall(PuenteFichaTotem.metodoLista, eventoMasivo);
      expect(await PuenteFichaTotem.responder(call, armar), isNull);
      expect(
        await PuenteFichaTotem.responder(call, armar,
            lista: (_) async => throw StateError('la base está ocupada')),
        isNull,
      );
      expect(
        await PuenteFichaTotem.responder(
          const MethodCall(PuenteFichaTotem.metodoLista, 'corto'),
          armar,
          lista: leer,
        ),
        isNull,
      );
    });

    test('lo que no se puede leer no rompe al tótem', () {
      expect(ListaDeLaPc.decodificar(null), isNull);
      expect(ListaDeLaPc.decodificar('{"evento_id": 3}'), isNull);
      expect(ListaDeLaPc.decodificar('no es json'), isNull);
    });
  });

  test('lee de la base de la PC lo cargado en el momento', () async {
    final antes = await armar(eventoMasivo);
    expect(antes.de(idDe('garcia', 1)), isNull);
    // Le cargan un acompañante a García (el Excel del delegado, por ejemplo).
    contratos.alumnos = [
      for (final a in alumnosDeLaFicha())
        a.id == 'garcia'
            ? alumnoDePrueba('garcia', 'GARCÍA, BRUNO',
                mesas: [17], acomp: ['GARCÍA, ROCÍO'])
            : a,
    ];
    final despues = await armar(eventoMasivo);
    expect(despues.de(idDe('garcia', 1))!.nombre, 'GARCÍA, ROCÍO');
    contratos.alumnos = alumnosDeLaFicha();
  });

  test('el evento se lee como lo guarda la PC: la modalidad manda', () async {
    eventos[eventoMasivo] = eventoDePrueba(eventoMasivo, 'particular');
    expect((await armar(eventoMasivo)).masivo, isFalse);
    eventos[eventoMasivo] = eventoDePrueba(eventoMasivo, 'masivo');
    expect((await armar(eventoMasivo)).masivo, isTrue);
  });
}
