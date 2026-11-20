// El único camino para guardar una entrega por partes (`EntregarParte`), con
// dos equipos en memoria y una nube de mentira compartida
// (`helpers/entrega_por_partes_en_memoria.dart`): la PC de la oficina y la
// tablet de la entrega, con y sin internet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/services/entrega_por_partes.dart';
import 'package:arguello_events/features/eventos/services/entregar_parte.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

import 'helpers/entrega_por_partes_en_memoria.dart';

const _evento = 'e0000000-0000-4000-8000-000000000001';

ContratoAlumno _alumno({
  required String id,
  required String nombre,
  List<String> acompanantes = const ['MAMÁ', 'PAPÁ'],
  List<int> mesas = const [12],
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _evento,
      // La baja temporal se marca en el nombre (`ContratoAlumno.esBajaTemporal`).
      nombreAlumno: baja ? '[BAJA] $nombre' : nombre,
      cantidadAcompanantes: acompanantes.length,
      nombresAcompanantes: acompanantes,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      totalCuotas: 9,
      cuotasPagadas: 9,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
      createdAt: DateTime(2026, 2, 1),
    );

final _ana = _alumno(id: 'c0000000-0000-4000-8000-00000000000a', nombre: 'GÓMEZ, ANA');
final _beto = _alumno(
  id: 'c0000000-0000-4000-8000-00000000000b',
  nombre: 'LÓPEZ, BETO',
  mesas: const [13],
);

/// Lo que pagó cada uno: la base entera.
Map<String, List<Map<String, dynamic>>> _pagos(Iterable<ContratoAlumno> alumnos) => {
      for (final a in alumnos)
        a.id: [
          {
            'monto': 300000.0,
            'monto_gross': 300000.0,
            'concepto': 'Cuota Base (9/9)',
            'anulado': 0,
            'fecha_pago': '2026-08-10',
          },
        ],
    };

DatosDeLaParte _pulseras({int cantidad = 3, String nombre = 'MADRE, UNA'}) =>
    DatosDeLaParte(
      parte: ParteEntrega.pulseras,
      cantidad: cantidad,
      parentesco: ParentescoRetiro.madre,
      nombre: nombre,
      escribioEnPlanilla: true,
    );

DatosDeLaParte _generales({
  int cantidad = 5,
  List<TramoTalonario> tramos = const [],
  String nombre = 'PADRE, UNO',
  int menores10 = 0,
}) =>
    DatosDeLaParte(
      parte: ParteEntrega.generales,
      cantidad: cantidad,
      tramos: tramos,
      menores10: menores10,
      parentesco: ParentescoRetiro.padre,
      nombre: nombre,
      escribioEnPlanilla: true,
    );

void main() {
  late NubeDeEntregas nube;
  late RelojDeLaEntrega reloj;
  late EquipoDeEntrega pc;
  late EquipoDeEntrega tablet;
  late int preguntasSinInternet;
  late bool sigueSinInternet;

  EquipoDeEntrega equipo(String nombre) => EquipoDeEntrega(
        nombre: nombre,
        nube: nube,
        reloj: reloj,
        alumnos: [_ana, _beto],
        pagos: _pagos([_ana, _beto]),
      );

  setUp(() {
    nube = NubeDeEntregas();
    reloj = RelojDeLaEntrega();
    pc = equipo('pc-oficina');
    tablet = equipo('tablet-1');
    preguntasSinInternet = 0;
    sigueSinInternet = true;
  });

  Future<ResultadoDeLaEntrega> entregar(
    EquipoDeEntrega en,
    DatosDeLaParte datos, {
    ContratoAlumno? a,
    String quien = 'Carla',
  }) =>
      EntregarParte(en).entregar(
        eventoId: _evento,
        contratoAlumnoId: (a ?? _ana).id,
        datos: datos,
        quien: quien,
        seguirSinInternet: () async {
          preguntasSinInternet++;
          return sigueSinInternet;
        },
      );

  Future<ResultadoDeAnular> anular(
    EquipoDeEntrega en,
    Set<ParteEntrega> partes, {
    bool esJefe = true,
    String motivo = 'se anotaron mal los números',
    ContratoAlumno? a,
  }) =>
      EntregarParte(en).anularParte(
        eventoId: _evento,
        contratoAlumnoId: (a ?? _ana).id,
        partes: partes,
        motivo: motivo,
        quien: 'Jefe',
        esJefe: esJefe,
      );

  EstadoDeLaEntrega estadoEn(EquipoDeEntrega en, [ContratoAlumno? a]) {
    final alumno = a ?? _ana;
    return EstadoDeLaEntrega.deAlumno(
      alumno,
      retiro: en.retiros[alumno.id],
      renglones: en.renglonesDe(alumno.id),
    );
  }

  EstadoDeLaEntrega estadoEnLaNube([ContratoAlumno? a]) {
    final alumno = a ?? _ana;
    return EstadoDeLaEntrega.deAlumno(
      alumno,
      retiro: nube.retiros[alumno.id],
      renglones: nube.renglonesDe(alumno.id),
    );
  }

  group('entregar una parte', () {
    test('las pulseras primero: un renglón, sube, y la fila de la entrega no se toca',
        () async {
      final r = await entregar(pc, _pulseras());
      expect(r, isA<Entregada>());
      final e = r as Entregada;
      expect(e.subio, isTrue);
      expect(e.todoEntregado, isFalse);
      expect(e.conFilaCompleta, isFalse);
      expect(e.renglon.parte, ParteEntrega.pulseras);
      expect(e.renglon.cantidad, 3);
      expect(e.renglon.hechoPor, 'Carla');
      expect(e.renglon.deviceId, 'pc-oficina');
      expect(nube.renglones, hasLength(1));
      expect(nube.retiros, isEmpty, reason: 'una entrega a medias no escribe la fila');
      expect(preguntasSinInternet, 0);
      expect(estadoEnLaNube().pulseras.entregada, isTrue);
      expect(estadoEnLaNube().generales.falta, isTrue);
    });

    test('con las dos partes se escribe la fila completa, una sola vez', () async {
      await entregar(pc, _pulseras());
      final r = await entregar(
        pc,
        _generales(tramos: const [TramoTalonario(1043, 1047)], menores10: 1),
      ) as Entregada;
      expect(r.todoEntregado, isTrue);
      expect(r.conFilaCompleta, isTrue);
      expect(pc.filasEscritas, 1);
      final fila = nube.retiros[_ana.id]!;
      expect(fila.id, UuidUtils.entradasRetiroId(_ana.id));
      expect(fila.entregado, isTrue);
      expect(fila.vip, 3);
      expect(fila.generales, 5);
      expect(fila.tramos, const [TramoTalonario(1043, 1047)]);
      expect(fila.retiroNombre, 'PADRE, UNO');
      expect(fila.entregadoAt, r.renglon.createdAt, reason: 'es el reflejo del renglón');
      // Una 6.9.x la ve "Retiró", sin "cambió la cuenta".
      expect(RetiroEntradas.cambioLaCuenta(fila, RetiroEntradas.entradasDe(_ana)),
          isFalse);
      // Esta versión la sigue leyendo por los renglones.
      final e = estadoEnLaNube();
      expect(e.todoEntregado, isTrue);
      expect(e.pulseras.retiroNombre, 'MADRE, UNA');
      expect(e.pulseras.deLaFila, isFalse);

      // Otra vez: ya está, no se escribe nada más.
      expect(await entregar(pc, _generales()), isA<YaEntregadaEnOtroEquipo>());
      expect(await entregar(pc, _pulseras()), isA<YaEntregadaEnOtroEquipo>());
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        isFalse,
      );
      expect(pc.filasEscritas, 1);
      expect(nube.filasSubidas, 1);
      expect(nube.renglones, hasLength(2));
    });

    test('con 8 o más con cena no hay generales: las pulseras completan la fila',
        () async {
      final grande = _alumno(
        id: 'c0000000-0000-4000-8000-0000000000aa',
        nombre: 'GRANDE, FAMILIA',
        acompanantes: List.generate(9, (i) => 'ACOMPAÑANTE $i'),
        mesas: const [20, 21],
      );
      final conMesa = ContratoAlumno(
        id: grande.id,
        eventoId: _evento,
        nombreAlumno: grande.nombreAlumno,
        cantidadAcompanantes: 9,
        nombresAcompanantes: grande.nombresAcompanantes,
        montoTotalPactado: 370000,
        saldoDeudor: 0,
        totalCuotas: 9,
        cuotasPagadas: 9,
        mesaExtraPrecio: 70000,
        mesaExtraCantidad: 1,
        mesaExtraCuotas: 1,
        mesaExtraCuotasPagadas: 1,
        numeroMesa: grande.numeroMesa,
        createdAt: DateTime(2026, 2, 1),
      );
      pc.alumnos = [conMesa];
      pc.pagos[conMesa.id] = [
        {'monto': 300000.0, 'monto_gross': 300000.0, 'concepto': 'Cuota Base (9/9)', 'anulado': 0, 'fecha_pago': '2026-08-10'},
        {'monto': 70000.0, 'monto_gross': 70000.0, 'concepto': 'Mesa Extra 1', 'anulado': 0, 'fecha_pago': '2026-08-10'},
      ];
      expect(
        await entregar(pc, _generales(cantidad: 0), a: conMesa),
        isA<CambioAlgo>(),
        reason: 'no hay generales que entregar',
      );
      final r = await entregar(pc, _pulseras(cantidad: 10), a: conMesa) as Entregada;
      expect(r.todoEntregado, isTrue);
      expect(nube.retiros[conMesa.id]!.vip, 10);
      expect(nube.retiros[conMesa.id]!.generales, 0);
    });
  });

  group('dos equipos', () {
    test('una tablet sin internet entrega las generales después de que la PC '
        'entregó las pulseras: no se pierde nada', () async {
      expect(await entregar(pc, _pulseras()), isA<Entregada>());

      tablet.hayInternet = false;
      final r = await entregar(
        tablet,
        _generales(tramos: const [TramoTalonario(2001, 2005)]),
        quien: 'Sofi',
      );
      expect(preguntasSinInternet, 1, reason: 'sin internet, pregunta antes de seguir');
      expect(r, isA<Entregada>());
      expect((r as Entregada).subio, isFalse);
      // La tablet no sabía de las pulseras: no escribe la fila.
      expect(r.conFilaCompleta, isFalse);
      expect(tablet.filasEscritas, 0);

      // Vuelve la red: sube lo suyo y baja lo de la PC.
      tablet.hayInternet = true;
      tablet.subirLaCola();
      tablet.bajar();
      pc.bajar();

      for (final (donde, e) in [
        ('en la nube', estadoEnLaNube()),
        ('en la PC', estadoEn(pc)),
        ('en la tablet', estadoEn(tablet)),
      ]) {
        expect(e.todoEntregado, isTrue, reason: donde);
        expect(e.pulseras.retiroNombre, 'MADRE, UNA', reason: donde);
        expect(e.pulseras.anotadoPor, 'Carla', reason: donde);
        expect(e.generales.retiroNombre, 'PADRE, UNO', reason: donde);
        expect(e.generales.anotadoPor, 'Sofi', reason: donde);
        expect(e.generales.tramos, const [TramoTalonario(2001, 2005)], reason: donde);
      }
      // La fila de la entrega todavía no está: ningún equipo vio las dos partes.
      expect(nube.retiros, isEmpty);

      // El que la ve completa con internet la escribe, como reflejo de la última.
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        isTrue,
      );
      final fila = nube.retiros[_ana.id]!;
      expect(fila.entregado, isTrue);
      expect(fila.vip, 3);
      expect(fila.generales, 5);
      expect(fila.tramos, const [TramoTalonario(2001, 2005)]);
      expect(fila.entregadoPor, 'Sofi');
      expect(
        fila.entregadoAt,
        nube.renglonesDe(_ana.id).last.createdAt,
        reason: 'la hora de la última entrega: nunca le gana a una anulación',
      );
      tablet.bajar();
      expect(estadoEn(tablet).todoEntregado, isTrue);
      expect(estadoEn(tablet).pulseras.deLaFila, isFalse);
      // Y la segunda vez no hace falta.
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        isFalse,
      );
    });

    test('sin internet, completar la fila no escribe nada', () async {
      await entregar(pc, _pulseras());
      tablet.hayInternet = false;
      await entregar(tablet, _generales());
      tablet.hayInternet = true;
      tablet.subirLaCola();
      pc.bajar();
      pc.hayInternet = false;
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        isFalse,
      );
      expect(pc.filasEscritas, 0);
    });

    test('ya entregada en otro equipo: la nube lo dice antes de guardar', () async {
      await entregar(pc, _pulseras());
      // La tablet tiene internet pero todavía no bajó lo de la PC.
      expect(tablet.renglones, isEmpty);
      final r = await entregar(tablet, _pulseras(nombre: 'TÍA, OTRA'));
      expect(r, isA<YaEntregadaEnOtroEquipo>());
      final texto = (r as YaEntregadaEnOtroEquipo).texto;
      expect(texto, contains('las pulseras VIP con cena'));
      expect(texto, contains('Madre MADRE, UNA'));
      expect(texto, contains('(lo registró Carla)'));
      expect(texto, endsWith('No se guardó nada.'));
      expect(nube.renglones, hasLength(1));
      expect(tablet.colaDeRenglones, isEmpty);
      // Lo que bajó de la nube ya se ve en la tablet.
      expect(estadoEn(tablet).pulseras.entregada, isTrue);
      expect(preguntasSinInternet, 0);
    });

    test('sin internet, si quien atiende no sigue, no se guarda nada', () async {
      tablet.hayInternet = false;
      sigueSinInternet = false;
      expect(await entregar(tablet, _pulseras()), isA<Cancelada>());
      expect(preguntasSinInternet, 1);
      expect(tablet.renglones, isEmpty);
    });

    test('si la nube no contesta, pregunta igual que sin internet', () async {
      final caida = _NubeQueNoContesta(pc);
      final r = await EntregarParte(caida).entregar(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
        datos: _pulseras(),
        quien: 'Carla',
        seguirSinInternet: () async {
          preguntasSinInternet++;
          return true;
        },
      );
      expect(preguntasSinInternet, 1);
      expect(r, isA<Entregada>());
    });

    test('el jefe anuló desde una 6.9.x la fila completa: las dos partes se pueden '
        'volver a entregar', () async {
      await entregar(pc, _pulseras());
      await entregar(pc, _generales());
      // Una 6.9.x anula la fila entera (sin renglones), después.
      final fila = nube.retiros[_ana.id]!;
      nube.retiros[_ana.id] = RetiroEntradas.anular(
        fila,
        motivo: 'se equivocó de familia',
        quien: 'Jefe',
        ahora: reloj.ahora(),
      );
      pc.bajar();
      expect(estadoEn(pc).algoEntregado, isFalse);
      final r = await entregar(pc, _pulseras(nombre: 'ABUELA, UNA'));
      expect(r, isA<Entregada>());
      expect((r as Entregada).conFilaCompleta, isFalse);
      expect(estadoEn(pc).pulseras.retiroNombre, 'ABUELA, UNA');
      expect(estadoEn(pc).generales.falta, isTrue);
    });
  });

  group('frena si algo cambió', () {
    test('cambió la cuenta mientras el diálogo estaba abierto', () async {
      // Sumaron un acompañante: ahora le corresponden 4 pulseras, no 3.
      pc.alumnos = [
        _alumno(id: _ana.id, nombre: _ana.nombreAlumno,
            acompanantes: const ['MAMÁ', 'PAPÁ', 'TÍA']),
        _beto,
      ];
      final r = await entregar(pc, _pulseras(cantidad: 3));
      expect(r, isA<CambioAlgo>());
      expect((r as CambioAlgo).motivo,
          contains('hoy le corresponden 4 pulseras VIP con cena, no 3'));
      expect(pc.renglones, isEmpty);
    });

    test('se anuló un cobro: ahora debe', () async {
      pc.pagos[_ana.id] = const [];
      final r = await entregar(pc, _pulseras());
      expect(r, isA<CambioAlgo>());
      expect(pc.renglones, isEmpty);
    });

    test('pasó a baja', () async {
      pc.alumnos = [
        _alumno(id: _ana.id, nombre: _ana.nombreAlumno, baja: true),
        _beto,
      ];
      expect(await entregar(pc, _pulseras()), isA<CambioAlgo>());
      expect(pc.renglones, isEmpty);
    });

    test('falta quién retira', () async {
      final r = await entregar(
        pc,
        const DatosDeLaParte(
          parte: ParteEntrega.pulseras,
          cantidad: 3,
          parentesco: ParentescoRetiro.madre,
          nombre: 'SOLO',
          escribioEnPlanilla: true,
        ),
      );
      expect((r as CambioAlgo).motivo, contains('Escribí nombre y apellido.'));
      expect(pc.renglones, isEmpty);
    });
  });

  group('los números de las generales', () {
    test('son opcionales: puede que no vengan numeradas', () async {
      final r = await entregar(pc, _generales()) as Entregada;
      expect(r.renglon.tramos, isEmpty);
    });

    test('si se escriben, la cantidad justa', () async {
      final r = await entregar(
        pc,
        _generales(tramos: const [TramoTalonario(1, 4)]),
      );
      expect((r as CambioAlgo).motivo,
          contains('Son 4 números y tiene que llevar 5 generales.'));
      expect(pc.renglones, isEmpty);
    });

    test('no repiten los de la entrega de otro alumno: los de su renglón y los de '
        'una entrega de una sola vez', () async {
      await entregar(pc, _generales(tramos: const [TramoTalonario(1, 5)]), a: _beto);
      var r = await entregar(pc, _generales(tramos: const [TramoTalonario(5, 9)]));
      expect((r as CambioAlgo).motivo, contains('El 5 ya se le dio a LÓPEZ, BETO'));

      // Y una entrega de las 8 juntas, hecha con la 6.9.x.
      final carla = _alumno(
        id: 'c0000000-0000-4000-8000-00000000000c',
        nombre: 'PÉREZ, CARLA',
        mesas: const [14],
      );
      pc.alumnos = [...pc.alumnos, carla];
      pc.retiros[carla.id] = RetiroEntradas.nuevaEntrega(
        alumno: carla,
        entradas: RetiroEntradas.entradasDe(carla),
        tramos: const [TramoTalonario(100, 104)],
        menores10: 0,
        parentesco: ParentescoRetiro.madre,
        nombre: 'MADRE, OTRA',
        quien: 'Marta',
        ahora: DateTime.utc(2026, 11, 18, 15),
      );
      r = await entregar(pc, _generales(tramos: const [TramoTalonario(104, 108)]));
      expect((r as CambioAlgo).motivo, contains('El 104 ya se le dio a PÉREZ, CARLA'));
      expect(pc.renglonesDe(_ana.id), isEmpty);

      // Con otros números, sí.
      expect(
        await entregar(pc, _generales(tramos: const [TramoTalonario(200, 204)])),
        isA<Entregada>(),
      );
    });

    test('los de una entrega anulada quedan libres', () async {
      await entregar(pc, _pulseras(), a: _beto);
      await entregar(pc, _generales(tramos: const [TramoTalonario(1, 5)]), a: _beto);
      await anular(pc, {ParteEntrega.generales}, a: _beto);
      expect(
        await entregar(pc, _generales(tramos: const [TramoTalonario(1, 5)])),
        isA<Entregada>(),
      );
    });

    test('no miran lo vendido: las generales de los alumnos son otro talonario',
        () {
      // El servicio ni lee las ventas: un número vendido de las anticipadas no
      // frena la entrega de las generales.
      final fuente = File('lib/features/eventos/services/entregar_parte.dart')
          .readAsStringSync();
      final porPartes = File('lib/features/eventos/services/entrega_por_partes.dart')
          .readAsStringSync();
      for (final f in [fuente, porPartes]) {
        final codigo = f
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(codigo, isNot(contains('NumerosDeEntradas')));
        expect(codigo, isNot(contains('VentaEntradas')));
        expect(codigo, isNot(contains('entradas_ventas')));
      }
    });
  });

  group('anular', () {
    test('una parte: su renglón, la fila anulada con el motivo de esa parte, y la '
        'otra sigue entregada', () async {
      await entregar(pc, _pulseras());
      await entregar(pc, _generales(tramos: const [TramoTalonario(1, 5)]));
      final r = await anular(pc, {ParteEntrega.generales});
      expect(r, isA<Anulada>());
      expect((r as Anulada).partes, {ParteEntrega.generales});
      expect(r.subio, isTrue);
      final fila = nube.retiros[_ana.id]!;
      expect(fila.entregado, isFalse);
      expect(fila.anuladoMotivo,
          'Solo las entradas generales: se anotaron mal los números');
      expect(fila.anuladoAt, nube.renglonesDe(_ana.id).last.createdAt,
          reason: 'es el reflejo de la anulación');
      final e = estadoEnLaNube();
      expect(e.pulseras.entregada, isTrue);
      expect(e.generales.entregada, isFalse);
      expect(e.generales.motivoAnulacion, 'se anotaron mal los números');
      final anulacion = nube.renglonesDe(_ana.id).last;
      expect(anulacion.esAnulacion, isTrue);
      expect(anulacion.cantidad, 5);
      expect(anulacion.tramos, const [TramoTalonario(1, 5)]);
      expect(anulacion.hechoPor, 'Jefe');

      // Se vuelven a entregar las generales: otra vez la fila completa.
      final otraVez = await entregar(pc, _generales()) as Entregada;
      expect(otraVez.conFilaCompleta, isTrue);
      expect(nube.retiros[_ana.id]!.entregado, isTrue);
      expect(nube.retiros[_ana.id]!.anuladoMotivo,
          'Solo las entradas generales: se anotaron mal los números');
    });

    test('todo: las dos partes, y la fila con el motivo tal cual', () async {
      await entregar(pc, _pulseras());
      await entregar(pc, _generales());
      final r = await anular(pc, {ParteEntrega.pulseras, ParteEntrega.generales},
          motivo: 'se equivocó de familia');
      expect((r as Anulada).partes, {ParteEntrega.pulseras, ParteEntrega.generales});
      expect(nube.retiros[_ana.id]!.anuladoMotivo, 'se equivocó de familia');
      expect(estadoEnLaNube().algoEntregado, isFalse);
    });

    test('una entrega a medias: solo su renglón, la fila no se toca', () async {
      await entregar(pc, _pulseras());
      final r = await anular(pc, {ParteEntrega.pulseras, ParteEntrega.generales});
      expect((r as Anulada).partes, {ParteEntrega.pulseras});
      expect(pc.filasEscritas, 0);
      expect(nube.retiros, isEmpty);
      expect(estadoEnLaNube().algoEntregado, isFalse);
    });

    test('solo el jefe: sin él no se escribe nada', () async {
      await entregar(pc, _pulseras());
      final antes = pc.renglones.length;
      final r = await anular(pc, {ParteEntrega.pulseras}, esJefe: false);
      expect(r, isA<NoSeAnulo>());
      expect(pc.renglones, hasLength(antes));
      expect(estadoEn(pc).pulseras.entregada, isTrue);
    });

    test('sin motivo, o sin nada entregado, no se anula', () async {
      expect(await anular(pc, {ParteEntrega.pulseras}), isA<NoSeAnulo>());
      await entregar(pc, _pulseras());
      expect(await anular(pc, {ParteEntrega.pulseras}, motivo: '  '), isA<NoSeAnulo>());
      expect(await anular(pc, const {}), isA<NoSeAnulo>());
      expect(estadoEn(pc).pulseras.entregada, isTrue);
    });

    test('una entrega de una sola vez (6.9.x): anular las pulseras copia la fila '
        'antes, y al volver a entregarlas las generales siguen con sus números',
        () async {
      final vieja = RetiroEntradas.nuevaEntrega(
        alumno: _ana,
        entradas: RetiroEntradas.entradasDe(_ana),
        tramos: const [TramoTalonario(1043, 1047)],
        menores10: 1,
        parentesco: ParentescoRetiro.padre,
        nombre: 'PADRE, UNO',
        quien: 'Marta',
        ahora: DateTime.utc(2026, 11, 18, 15),
      );
      nube.retiros[_ana.id] = vieja;
      pc.bajar();
      expect(estadoEn(pc).todoEntregado, isTrue);

      expect(await anular(pc, {ParteEntrega.pulseras}), isA<Anulada>());
      // Las copias de la fila (una por parte, a la hora de la entrega vieja) y la
      // anulación.
      final renglones = nube.renglonesDe(_ana.id);
      expect(renglones, hasLength(3));
      expect(renglones.where((r) => r.motivo == EntregaEntradas.kCopiaDeLaFila),
          hasLength(2));
      expect(nube.retiros[_ana.id]!.entregado, isFalse);
      var e = estadoEnLaNube();
      expect(e.pulseras.entregada, isFalse);
      expect(e.generales.entregada, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(1043, 1047)]);

      final r = await entregar(pc, _pulseras(nombre: 'MADRE, UNA')) as Entregada;
      expect(r.conFilaCompleta, isTrue);
      final fila = nube.retiros[_ana.id]!;
      expect(fila.entregado, isTrue);
      expect(fila.tramos, const [TramoTalonario(1043, 1047)]);
      expect(fila.generales, 5);
      e = estadoEnLaNube();
      expect(e.todoEntregado, isTrue);
      expect(e.generales.tramos, const [TramoTalonario(1043, 1047)]);
      expect(e.generales.retiroNombre, 'PADRE, UNO');
      expect(e.pulseras.retiroNombre, 'MADRE, UNA');

      // Otro equipo que copia lo mismo no duplica: las copias tienen el mismo id.
      final ids = {for (final r in nube.renglones.values) r.id};
      expect(ids, hasLength(nube.renglones.length));
    });
  });

  test('nadie más agrega renglones de la entrega por partes ni guarda la fila '
      'junto con ellos', () {
    final escribe = RegExp(r'\.(agregar|agregarEn)\(');
    final quienes = <String>{};
    final guardanEn = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final fuente = f.readAsStringSync();
      if (ruta.endsWith('entradas_entregas_repository.dart')) continue;
      if ((fuente.contains('EntradasEntregasRepository') ||
              fuente.contains('entradasEntregasRepositoryProvider')) &&
          escribe.hasMatch(fuente)) {
        quienes.add(ruta);
      }
      if (fuente.contains('_retiros.guardarEn(') ||
          RegExp(r'entradasRetiroRepositoryProvider\)\s*\.guardarEn\(')
              .hasMatch(fuente)) {
        guardanEn.add(ruta);
      }
    }
    const adaptador = 'lib/features/eventos/repositories/entregar_parte_de_la_app.dart';
    expect(quienes, {adaptador});
    expect(guardanEn, {adaptador});
  });
}

/// Un equipo con internet cuya nube no contesta (se cae a mitad de la consulta).
class _NubeQueNoContesta extends EquipoDeEntrega {
  _NubeQueNoContesta(EquipoDeEntrega base)
      : super(
          nombre: base.nombre,
          nube: base.nube,
          reloj: base.reloj,
          alumnos: base.alumnos,
          pagos: base.pagos,
        );

  @override
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId) async =>
      throw StateError('la nube no contesta');
}
