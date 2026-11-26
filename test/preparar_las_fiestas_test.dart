import 'package:arguello_events/core/services/pulso_entre_equipos.dart';
import 'package:arguello_events/features/recepcion/services/lista_sin_internet.dart';
import 'package:arguello_events/features/tele/preparar_las_fiestas.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/totem_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/puerta_en_memoria.dart';

/// Todas las escuelas listas sin internet (25-nov-2026): la tele, con internet,
/// baja todo lo de las fiestas de los próximos 30 días (hasta 10).
void main() {
  // Lunes 23-nov-2026 a las 15.
  final ahora = DateTime(2026, 11, 23, 15);

  Evento fiesta(int n, DateTime dia, {String modalidad = 'masivo'}) => Evento(
        id: 'e${n.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
        clienteId: 'c0000000-0000-4000-8000-000000000001',
        tipo: 'Egresados',
        fechaEvento: dia,
        estado: EstadoEvento.confirmado,
        modalidad: modalidad,
      );

  late SinInternetEnMemoria mundo;
  late PrepararLasFiestas preparar;

  setUp(() {
    mundo = SinInternetEnMemoria()..ahora = ahora;
    preparar = PrepararLasFiestas(accesos: mundo.fiestas);
  });
  tearDown(() => preparar.dispose());

  group('cuáles', () {
    test('las de los próximos 30 días, hasta 10, empezando por la de hoy', () {
      final eventos = [
        fiesta(1, DateTime(2026, 11, 20)), // ya pasó
        fiesta(2, DateTime(2026, 11, 23)), // hoy
        fiesta(3, DateTime(2026, 12, 4)),
        fiesta(4, DateTime(2026, 12, 23)), // el día 30
        fiesta(5, DateTime(2026, 12, 24)), // el 31: no
        for (var i = 10; i < 25; i++) fiesta(i, DateTime(2026, 12, 1)),
      ];
      final cuales = PrepararLasFiestas.cuales(eventos, ahora);
      expect(cuales, hasLength(10));
      expect(cuales.first.id, eventos[1].id);
      expect(cuales.map((e) => e.id), isNot(contains(eventos[0].id)));
      expect(cuales.map((e) => e.id), isNot(contains(eventos[4].id)));
      final pocas = PrepararLasFiestas.cuales(eventos.take(5).toList(), ahora);
      expect(pocas.map((e) => e.id), [eventos[1].id, eventos[2].id, eventos[3].id]);
    });
  });

  group('con internet', () {
    test('baja la lista de cada una, las tablas de la puerta una sola vez y las '
        'apariencias en una sola consulta', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      final b = fiesta(2, DateTime(2026, 12, 5));
      final c = fiesta(3, DateTime(2026, 12, 6), modalidad: 'particular');
      mundo.aparienciasEnLaNube[a.id] = TotemConfig(
        eventoId: a.id,
        titulo: 'TÉCNICA',
        imagenUrl: 'https://nube/a.jpg',
      );
      mundo.aparienciasEnLaNube[b.id] = TotemConfig(
        eventoId: b.id,
        estilo: 'tu_fondo',
        fondoUrl: 'https://nube/b-fondo.jpg',
      );
      await preparar.preparar([a, b, c]);
      expect(mundo.listasDeFiestas, [a.id, b.id, c.id]);
      expect(mundo.alumnosBajados, 1, reason: 'las tablas de la puerta, una vez');
      expect(mundo.aparienciasLeidas, 1, reason: 'una sola consulta para todas');
      expect(mundo.aparienciasGuardadas.keys, unorderedEquals([a.id, b.id]));
      expect(mundo.fotosGuardadas, ['https://nube/a.jpg']);
      expect(mundo.fondosGuardados, ['https://nube/b-fondo.jpg']);
      for (final e in [a, b, c]) {
        final como = preparar.como[e.id]!;
        expect(como.completa, isTrue, reason: e.id);
        expect(mundo.alDia[e.id], ahora, reason: 'queda al día, como en Recepción');
        expect(como.texto(ahora), 'Lista sin internet · al día hoy 15:00');
      }
      // La de siempre (sin fila): ni apariencia que guardar ni foto.
      expect(preparar.como[c.id]!.apariencia, isNull);
    });

    test('lo que falta se dice, y no queda al día', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      mundo.aparienciasEnLaNube[a.id] = TotemConfig(eventoId: a.id, imagenUrl: 'https://nube/a.jpg');
      mundo.bajaFoto = false;
      await preparar.preparar([a]);
      final como = preparar.como[a.id]!;
      expect(como.completa, isFalse);
      expect(como.falta, ['la foto']);
      expect(como.texto(ahora), 'Falta la foto · se vuelve a intentar sola');
      expect(mundo.alDia[a.id], isNull);
    });

    test('un masivo sin los alumnos no queda listo', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      final p = fiesta(2, DateTime(2026, 12, 4), modalidad: 'particular');
      mundo.bajanAlumnos = false;
      await preparar.preparar([a, p]);
      expect(preparar.como[a.id]!.falta, ['la lista']);
      expect(preparar.como[p.id]!.completa, isTrue);
    });

    test('si no puede leer las apariencias, sirve la que ya estaba guardada', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      final b = fiesta(2, DateTime(2026, 12, 5));
      mundo.aparienciasGuardadas[a.id] = TotemConfig(eventoId: a.id, titulo: 'DE ANTES');
      mundo.leeApariencias = false;
      await preparar.preparar([a, b]);
      expect(preparar.como[a.id]!.completa, isTrue);
      expect(preparar.como[b.id]!.falta, ['la apariencia']);
    });

    test('no vuelve a bajar todo a cada rato: cada 30 minutos, o al volver internet', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      await preparar.preparar([a]);
      await preparar.preparar([a]);
      expect(mundo.listasBajadas, 1);
      // Una fiesta nueva: se prepara ya.
      final b = fiesta(2, DateTime(2026, 12, 5));
      await preparar.preparar([a, b]);
      expect(mundo.listasBajadas, 3);
      // Volvió internet.
      await preparar.preparar([a, b], forzar: true);
      expect(mundo.listasBajadas, 5);
      mundo.ahora = ahora.add(const Duration(minutes: 31));
      await preparar.preparar([a, b]);
      expect(mundo.listasBajadas, 7);
    });

    test('lo guardado en Personalizar en otra PC se vuelve a leer, con su foto', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      await preparar.preparar([a]);
      mundo.aparienciasEnLaNube[a.id] =
          TotemConfig(eventoId: a.id, titulo: 'NUEVA', imagenUrl: 'https://nube/nueva.jpg');
      await preparar.releerApariencia(a.id);
      expect(mundo.aparienciasGuardadas[a.id]!.titulo, 'NUEVA');
      expect(mundo.fotosGuardadas, contains('https://nube/nueva.jpg'));
      expect(preparar.como[a.id]!.completa, isTrue);
    });
  });

  group('sin internet', () {
    test('dice lo que tiene guardado cada una', () async {
      final a = fiesta(1, DateTime(2026, 12, 4));
      final b = fiesta(2, DateTime(2026, 12, 5));
      mundo.alDia[a.id] = DateTime(2026, 11, 21, 10);
      mundo.aparienciasGuardadas[a.id] = TotemConfig(eventoId: a.id, imagenUrl: 'https://nube/a.jpg');
      mundo.fotosGuardadas.add('https://nube/a.jpg');
      await preparar.mirar([a, b]);
      expect(preparar.como[a.id]!.completa, isTrue);
      expect(preparar.como[a.id]!.texto(ahora), 'Lista sin internet · al día 21/11 10:00');
      expect(preparar.como[b.id]!.completa, isFalse);
      expect(preparar.como[b.id]!.texto(ahora),
          'Sin internet, y no tiene guardado: la lista y la apariencia');
      expect(mundo.listasBajadas, 0, reason: 'sin internet no baja nada');
    });
  });

  group('el aviso de la apariencia, por el pulso', () {
    test('lleva la fiesta, sin tablas del motor', () {
      final aviso = avisoDeLaApariencia(origen: 'pc-1', eventoId: 'e0000001-0000-4000-8000-000000000000');
      expect(aviso['tablas'], isEmpty);
      expect(aparienciasDelPulso(aviso, yo: 'tele'), {'e0000001-0000-4000-8000-000000000000'});
      // El propio no cuenta; un id raro tampoco.
      expect(aparienciasDelPulso(aviso, yo: 'pc-1'), isEmpty);
      expect(aparienciasDelPulso({'totem_config': ['x; drop']}, yo: null), isEmpty);
      expect(aparienciasDelPulso({'totem_config': 'no es lista'}, yo: null), isEmpty);
    });
  });

  group('"Lista para trabajar sin internet" mira la apariencia', () {
    test('si no se pudo guardar, lo dice', () {
      final e = EstadoSinInternet.de(
        DatosSinInternet(hayInternet: true, alDia: ahora, aparienciaGuardada: false),
        personas: 10,
        ahora: ahora,
      );
      expect(e.tipo, TipoSinInternet.falta);
      expect(e.texto, contains('falta guardar la apariencia del tótem'));
      expect(e.detalle, contains(('Apariencia del tótem', 'no bajó · se reintenta')));
    });

    test('guardada, o la de siempre: lista', () {
      for (final a in [true, null]) {
        final e = EstadoSinInternet.de(
          DatosSinInternet(hayInternet: true, alDia: ahora, aparienciaGuardada: a),
          personas: 10,
          ahora: ahora,
        );
        expect(e.tipo, TipoSinInternet.lista, reason: '$a');
      }
    });

    test('la puesta al día la guarda con internet y la mira sin internet', () async {
      var guardadas = 0, miradas = 0;
      final base = SinInternetEnMemoria()..ahora = ahora;
      final a = base.accesos;
      final accesos = AccesosPuerta(
        bajarLista: a.bajarLista,
        bajarAlumnos: a.bajarAlumnos,
        guardarFoto: a.guardarFoto,
        fotoGuardada: a.fotoGuardada,
        guardarFondo: a.guardarFondo,
        fondoGuardado: a.fondoGuardado,
        contarSinSubir: a.contarSinSubir,
        leerAlDia: a.leerAlDia,
        anotarAlDia: a.anotarAlDia,
        ahora: a.ahora,
        guardarApariencia: (_) async {
          guardadas++;
          return false;
        },
        aparienciaGuardada: (_) async {
          miradas++;
          return true;
        },
      );
      final con = PuestaAlDiaPuerta(eventoId: 'e1', accesos: accesos, hayInternet: true);
      await con.arrancar();
      expect(guardadas, 1);
      expect(con.datos.aparienciaGuardada, isFalse);
      con.dispose();
      final sin = PuestaAlDiaPuerta(eventoId: 'e1', accesos: accesos, hayInternet: false);
      await sin.arrancar();
      expect(miradas, 1);
      expect(sin.datos.aparienciaGuardada, isTrue);
      sin.dispose();
    });
  });
}
