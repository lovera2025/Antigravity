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
        ResultadoDeLaFila.alDia,
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
        ResultadoDeLaFila.escrita,
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
        ResultadoDeLaFila.alDia,
      );
    });

    // Desde la revisión del 20-nov completarLaFila dice si pudo mirar la nube
    // (`ResultadoDeLaFila.sinNube`): antes devolvía false igual que "no hacía
    // falta", y las pantallas no volvían a intentar.
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
        ResultadoDeLaFila.sinNube,
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

  // Revisión del 20-nov-2026: cada equipo tiene su reloj. Antes, una tablet
  // atrasada que volvía a entregar algo anulado anotaba su entrega antes que la
  // anulación: decía "Entregada" y la parte seguía pendiente.
  group('relojes distintos', () {
    test('la tablet atrasada vuelve a entregar lo que el jefe anuló: queda '
        'entregada en todos lados', () async {
      final pcReloj = RelojCorrido(DateTime.utc(2026, 11, 20, 18));
      final tabletReloj = RelojCorrido(DateTime.utc(2026, 11, 20, 17, 57));
      pc.reloj = pcReloj;
      tablet.reloj = tabletReloj;
      expect(await entregar(pc, _pulseras()), isA<Entregada>());
      pcReloj.hora = DateTime.utc(2026, 11, 20, 18, 5);
      expect(await anular(pc, {ParteEntrega.pulseras}), isA<Anulada>());

      // 18:06 de verdad; la tablet, con 4 minutos de atraso, marca 18:02.
      tabletReloj.hora = DateTime.utc(2026, 11, 20, 18, 2);
      final r = await entregar(tablet, _pulseras(nombre: 'TÍA, OTRA'));
      expect(r, isA<Entregada>());
      final renglon = (r as Entregada).renglon;
      final anulacion =
          nube.renglonesDe(_ana.id).firstWhere((x) => x.esAnulacion).createdAt;
      expect(renglon.createdAt.isAfter(anulacion), isTrue,
          reason: 'va después de la anulación que la tablet ya vio');
      expect(renglon.createdAt, anulacion.add(const Duration(milliseconds: 1)));
      pc.bajar();
      expect(estadoEnLaNube().pulseras.entregada, isTrue);
      expect(estadoEn(tablet).pulseras.entregada, isTrue);
      expect(estadoEn(pc).pulseras.retiroNombre, 'TÍA, OTRA');
    });

    test('el jefe atrasado anula lo que entregó una tablet adelantada: queda '
        'anulada', () async {
      final pcReloj = RelojCorrido(DateTime.utc(2026, 11, 20, 18));
      final tabletReloj = RelojCorrido(DateTime.utc(2026, 11, 20, 18, 10));
      pc.reloj = pcReloj;
      tablet.reloj = tabletReloj;
      await entregar(tablet, _pulseras());
      await entregar(tablet, _generales());
      expect(nube.retiros[_ana.id]!.entregado, isTrue);

      // La PC, 10 minutos atrasada, anula todo.
      pcReloj.hora = DateTime.utc(2026, 11, 20, 18, 3);
      final r = await anular(pc, {ParteEntrega.pulseras, ParteEntrega.generales});
      expect(r, isA<Anulada>());
      expect(estadoEnLaNube().algoEntregado, isFalse);
      expect(nube.retiros[_ana.id]!.entregado, isFalse);
      tablet.bajar();
      expect(estadoEn(tablet).algoEntregado, isFalse);
    });

    // Arreglo 9 (20-nov-2026): una 6.9.x atrasada volvió a entregar después de
    // una anulación, así que la fila dice "entregado" con un `anulado_at` más
    // nuevo que la entrega, y el estado pone esa entrega un milisegundo después
    // de la anulación. Al anular desde un equipo con la hora de antes de esa
    // anulación, la anulación caía en el mismo milisegundo que la copia de la
    // fila: se ordenaban por id, y la mitad de las veces la parte seguía
    // figurando entregada.
    test('la anulación queda después de las copias de la fila aunque la 6.9.x '
        'haya vuelto a entregar con la hora atrasada', () async {
      final alumnos = [
        for (var i = 0; i < 6; i++)
          _alumno(
            id: 'c0000000-0000-4000-8000-00000000010$i',
            nombre: 'ALUMNO $i, UNO',
            mesas: [20 + i],
          ),
      ];
      final oficina = EquipoDeEntrega(
        nombre: 'pc-oficina',
        nube: nube,
        reloj: RelojCorrido(DateTime.utc(2026, 11, 20, 18, 8)),
        alumnos: alumnos,
        pagos: _pagos(alumnos),
      );
      for (final a in alumnos) {
        final entregada = RetiroEntradas.nuevaEntrega(
          alumno: a,
          entradas: RetiroEntradas.entradasDe(a),
          tramos: const [],
          menores10: 0,
          parentesco: ParentescoRetiro.padre,
          nombre: 'PADRE, UNO',
          quien: 'Marta',
          ahora: DateTime.utc(2026, 11, 20, 18),
        );
        final anulada = RetiroEntradas.anular(
          entregada,
          motivo: 'se equivocó de familia',
          quien: 'Jefe',
          ahora: DateTime.utc(2026, 11, 20, 18, 10),
        );
        // La tablet con la 6.9.x, cinco minutos atrasada, la vuelve a entregar.
        nube.retiros[a.id] = RetiroEntradas.nuevaEntrega(
          alumno: a,
          entradas: RetiroEntradas.entradasDe(a),
          tramos: const [],
          menores10: 0,
          parentesco: ParentescoRetiro.madre,
          nombre: 'MADRE, UNA',
          quien: 'Marta',
          ahora: DateTime.utc(2026, 11, 20, 18, 5),
          anterior: anulada,
        );
      }
      oficina.bajar();

      for (final a in alumnos) {
        expect(
          EstadoDeLaEntrega.deAlumno(
            a,
            retiro: oficina.retiros[a.id],
            renglones: oficina.renglonesDe(a.id),
          ).todoEntregado,
          isTrue,
        );
        final r = await EntregarParte(oficina).anularParte(
          eventoId: _evento,
          contratoAlumnoId: a.id,
          partes: {ParteEntrega.pulseras},
          motivo: 'se anotaron mal los números',
          quien: 'Jefe',
          esJefe: true,
        );
        expect(r, isA<Anulada>(), reason: a.nombreAlumno);
        final renglones = nube.renglonesDe(a.id);
        final copias = renglones
            .where((x) => x.motivo == EntregaEntradas.kCopiaDeLaFila)
            .toList();
        expect(copias, hasLength(2), reason: a.nombreAlumno);
        final anulacion = renglones.singleWhere((x) => x.esAnulacion);
        for (final c in copias) {
          expect(anulacion.createdAt.isAfter(c.createdAt), isTrue,
              reason: '${a.nombreAlumno}: la anulación va después de la copia '
                  'de ${c.parteClave}, no en el mismo milisegundo');
        }
        final e = EstadoDeLaEntrega.deAlumno(
          a,
          retiro: nube.retiros[a.id],
          renglones: renglones,
        );
        expect(e.pulseras.entregada, isFalse, reason: a.nombreAlumno);
        expect(e.generales.entregada, isTrue, reason: a.nombreAlumno);
      }
    });

    test('si al releer la parte no quedó entregada, no dice que salió bien',
        () async {
      // Mientras la PC sube, baja una anulación de otro equipo con la hora más
      // nueva: lo anotado ya no es lo último.
      pc.alTerminarDeSubir = () {
        final nueva = EntregaEntradas.anulacion(
          contratoAlumnoId: _ana.id,
          eventoId: _evento,
          parte: ParteEntrega.pulseras,
          cantidad: 3,
          motivo: 'se anotó en otra familia',
          hechoPor: 'Jefe',
          deviceId: 'pc-jefe',
          ahora: DateTime.utc(2027),
        );
        pc.renglones[nueva.id] = nueva;
      };
      final r = await entregar(pc, _pulseras());
      expect(r, isA<CambioAlgo>());
      expect((r as CambioAlgo).motivo,
          contains('Se anotó la entrega de las pulseras VIP con cena, pero figura sin entregar'));
    });

    test('lo mismo al anular: si sigue entregada, no dice "Anulada"', () async {
      await entregar(pc, _pulseras());
      pc.alTerminarDeSubir = () {
        final otra = EntregaEntradas.entrega(
          contratoAlumnoId: _ana.id,
          eventoId: _evento,
          parte: ParteEntrega.pulseras,
          cantidad: 3,
          parentesco: ParentescoRetiro.padre,
          nombre: 'PADRE, UNO',
          escribioEnPlanilla: true,
          hechoPor: 'Sofi',
          deviceId: 'tablet-2',
          ahora: DateTime.utc(2027),
        );
        pc.renglones[otra.id] = otra;
      };
      final r = await anular(pc, {ParteEntrega.pulseras});
      expect(r, isA<CambioAlgo>());
      expect((r as CambioAlgo).motivo, contains('siguen figurando entregadas'));
    });
  });

  // Revisión del 20-nov-2026: sin internet (con SEGUIR) la fila completa de
  // `entradas_retiro` se escribía con lo que sabía ese equipo, y podía volver a
  // poner "entregado" sobre una anulación de la otra parte que no había bajado.
  group('sin internet, la fila completa espera', () {
    test('la tablet ve las dos partes pero está sin internet: solo su renglón',
        () async {
      await entregar(pc, _pulseras());
      tablet.bajar();
      tablet.hayInternet = false;
      final r = await entregar(tablet, _generales()) as Entregada;
      expect(r.todoEntregado, isTrue);
      expect(r.conFilaCompleta, isFalse);
      expect(tablet.filasEscritas, 0);
      // Con internet, la escribe completarLaFila.
      tablet.hayInternet = true;
      tablet.subirLaCola();
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      expect(nube.retiros[_ana.id]!.entregado, isTrue);
    });

    test('el jefe anuló las pulseras mientras la tablet estaba sin internet: la '
        'fila no vuelve a decir "entregado"', () async {
      await entregar(pc, _pulseras());
      tablet.bajar();
      tablet.hayInternet = false;
      expect(await anular(pc, {ParteEntrega.pulseras}), isA<Anulada>());
      final r = await entregar(tablet, _generales()) as Entregada;
      expect(r.conFilaCompleta, isFalse);
      expect(tablet.filasEscritas, 0);

      tablet.hayInternet = true;
      tablet.subirLaCola();
      tablet.bajar();
      pc.bajar();
      expect(nube.retiros[_ana.id]?.entregado ?? false, isFalse);
      final e = estadoEnLaNube();
      expect(e.pulseras.entregada, isFalse);
      expect(e.generales.entregada, isTrue);
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.alDia,
      );
    });
  });

  // Revisión del 20-nov-2026: la fila de `entradas_retiro` podía quedar en
  // "entregado" con una parte anulada, y nada la corregía (completarLaFila solo
  // escribía si la fila NO estaba entregada). Lo que lee la fila sola (el PLANO,
  // una PC con la 6.9.x) veía "Retiró" a una familia a la que el jefe le anuló
  // las pulseras. Ahora completarLaFila la pone al día también al revés: la
  // escribe anulada, como reflejo de la anulación del renglón.
  group('la fila que quedó vieja se pone al día', () {
    test('A) carrera: el jefe anula las pulseras mientras la tablet escribe la fila '
        'completa', () async {
      final tablet = _EquipoConPausa(equipo('tablet-1'));
      expect(await entregar(pc, _pulseras()), isA<Entregada>());
      tablet.bajar();
      tablet.hayInternet = false;
      final g = await entregar(tablet, _generales()) as Entregada;
      expect(g.conFilaCompleta, isFalse);
      tablet.hayInternet = true;
      tablet.subirLaCola();
      pc.bajar();
      // Entre que la tablet mira la nube y guarda la fila, el jefe anula las
      // pulseras en la PC: en la nube la fila todavía no dice "entregado", y la
      // anulación no la toca.
      ResultadoDeAnular? anulo;
      tablet.antesDeGuardar = () async {
        anulo = await anular(pc, {ParteEntrega.pulseras}, motivo: 'eran de otro');
      };
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      expect(anulo, isA<Anulada>());
      expect(nube.retiros[_ana.id]!.entregado, isTrue,
          reason: 'la carrera deja la fila vieja en la nube');
      expect(estadoEnLaNube().pulseras.entregada, isFalse);

      // El que la ve después, con internet, la pone al día.
      pc.bajar();
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      _laFilaDiceLoMismo(nube, _ana, estadoEnLaNube());
      final anulacion = nube
          .renglonesDe(_ana.id)
          .lastWhere((r) => r.parte == ParteEntrega.pulseras && !r.esEntrega);
      final fila = nube.retiros[_ana.id]!;
      expect(fila.anuladoAt, anulacion.createdAt,
          reason: 'es el reflejo de la anulación del renglón');
      expect(fila.anuladoMotivo, 'Solo las pulseras VIP con cena: eran de otro');
      expect(fila.anuladoPor, 'Jefe');
      // Las generales siguen entregadas: la anulación de la fila no las tapa.
      expect(estadoEnLaNube().generales.entregada, isTrue);
      expect(estadoEnLaNube().pulseras.entregada, isFalse);
      // Y la segunda vez no hace falta.
      tablet.bajar();
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.alDia,
      );

      // El jefe vuelve a entregar las pulseras: la fila vuelve a "entregado".
      pc.bajar();
      expect(await entregar(pc, _pulseras(nombre: 'TÍA, OTRA')), isA<Entregada>());
      expect(nube.retiros[_ana.id]!.entregado, isTrue);
      expect(estadoEnLaNube().todoEntregado, isTrue);
      _laFilaDiceLoMismo(nube, _ana, estadoEnLaNube());
    });

    test('B) el jefe anula sin internet, antes de bajar la fila completa', () async {
      expect(await entregar(pc, _pulseras()), isA<Entregada>());
      tablet.bajar();
      tablet.hayInternet = false;
      expect(await entregar(tablet, _generales()), isA<Entregada>());
      pc.hayInternet = false;
      tablet.hayInternet = true;
      tablet.subirLaCola();
      expect(
        await EntregarParte(tablet).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      expect(nube.retiros[_ana.id]!.entregado, isTrue);
      // En la PC del jefe la fila no está: la anulación es solo un renglón.
      expect(await anular(pc, {ParteEntrega.pulseras}, motivo: 'eran de otro'),
          isA<Anulada>());
      pc.hayInternet = true;
      pc.subirLaCola();
      pc.bajar();
      tablet.bajar();
      expect(nube.retiros[_ana.id]!.entregado, isTrue,
          reason: 'sin arreglarla, la fila sigue vieja');
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      _laFilaDiceLoMismo(nube, _ana, estadoEnLaNube());
      expect(estadoEnLaNube().generales.entregada, isTrue);
      expect(nube.retiros[_ana.id]!.anuladoMotivo,
          'Solo las pulseras VIP con cena: eran de otro');
    });

    test('con las dos partes anuladas, la fila dice el motivo sin "Solo"', () async {
      await entregar(pc, _pulseras());
      tablet.bajar();
      tablet.hayInternet = false;
      await entregar(tablet, _generales());
      tablet.hayInternet = true;
      tablet.subirLaCola();
      // La PC ve las dos partes, pero todavía no la fila que escribe la tablet.
      pc.bajar();
      await EntregarParte(tablet).completarLaFila(
        eventoId: _evento,
        contratoAlumnoId: _ana.id,
      );
      pc.hayInternet = false;
      expect(await anular(pc, ParteEntrega.values.toSet(), motivo: 'se anotó mal'),
          isA<Anulada>());
      pc.hayInternet = true;
      pc.subirLaCola();
      pc.bajar();
      expect(
        await EntregarParte(pc).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.escrita,
      );
      _laFilaDiceLoMismo(nube, _ana, estadoEnLaNube());
      expect(nube.retiros[_ana.id]!.anuladoMotivo, 'se anotó mal');
      expect(estadoEnLaNube().algoEntregado, isFalse);
    });

    test('una parte que falta porque cambió la cuenta no es una anulación: la fila '
        'no se toca', () {
      final fila = RetiroEntradas.nuevaEntrega(
        alumno: _ana,
        entradas: RetiroEntradas.entradasDe(_ana),
        tramos: const [],
        menores10: 0,
        parentesco: ParentescoRetiro.madre,
        nombre: 'MADRE, UNA',
        quien: 'Jefe',
        ahora: DateTime.utc(2026, 11, 7, 18),
      );
      // Entregó las 8 juntas con la 6.9.x, y después le sacaron un acompañante:
      // le cambió la cuenta, pero nadie anuló nada.
      final conMenos = _alumno(
        id: _ana.id,
        nombre: _ana.nombreAlumno,
        acompanantes: const ['MAMÁ'],
      );
      final estado =
          EstadoDeLaEntrega.deAlumno(conMenos, retiro: fila, renglones: const []);
      expect(estado.algoEntregado, isTrue);
      expect(EntregaPorPartes.filaConLaAnulacion(retiro: fila, estado: estado), isNull);
      expect(EntregaPorPartes.filaParaPonerAlDia(retiro: fila, estado: estado), isFalse);
    });

    test('si la nube no contesta, dice que hay que volver a intentar', () async {
      await entregar(pc, _pulseras());
      tablet.hayInternet = false;
      await entregar(tablet, _generales());
      tablet.hayInternet = true;
      tablet.subirLaCola();
      pc.bajar();
      expect(
        await EntregarParte(_NubeQueNoContesta(pc)).completarLaFila(
          eventoId: _evento,
          contratoAlumnoId: _ana.id,
        ),
        ResultadoDeLaFila.sinNube,
      );
      expect(pc.filasEscritas, 0);
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

    // Revisión independiente del 20-nov-2026: entre las dos partes se podían
    // llevar 9 sin cargo si cambiaban los acompañantes en el medio.
    test('las generales se dieron con 1 acompañante y después se sumó otro: las '
        'pulseras no se dan (serían 9 sin cargo)', () async {
      final conUno = _alumno(id: _ana.id, nombre: _ana.nombreAlumno,
          acompanantes: const ['MAMÁ']);
      pc.alumnos = [conUno, _beto];
      expect(await entregar(pc, _generales(cantidad: 6)), isA<Entregada>());
      pc.alumnos = [_ana, _beto];
      final r = await entregar(pc, _pulseras(cantidad: 3));
      expect(r, isA<CambioAlgo>());
      expect((r as CambioAlgo).motivo, contains('Pedile al jefe'));
      expect((r).motivo, contains('No se guardó nada.'));
      expect(pc.renglones, hasLength(1), reason: 'solo el de las generales');
      expect(nube.retiros, isEmpty, reason: 'no hay fila completa');
    });

    test('las pulseras se dieron con 2 acompañantes y después se sacó uno: las '
        'generales no se dan', () async {
      expect(await entregar(pc, _pulseras(cantidad: 3)), isA<Entregada>());
      pc.alumnos = [
        _alumno(id: _ana.id, nombre: _ana.nombreAlumno, acompanantes: const ['MAMÁ']),
        _beto,
      ];
      final r = await entregar(pc, _generales(cantidad: 6));
      expect(r, isA<CambioAlgo>());
      expect(pc.renglones, hasLength(1));
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

  // Paso 1 del plan del 20-nov: un solo camino para guardar la entrega. Hasta la
  // 6.9.2 la pantalla de la entrega escribía `entradas_retiro` por su cuenta; desde
  // la 6.9.3 todo pasa por `EntregarParte`, y su adaptador es el único que escribe
  // las dos tablas (además de sus repositorios). El motor de sync no cuenta: sube y
  // baja todas las tablas igual, sin nombrarlas.
  test('nadie más escribe la entrega por partes ni la fila de la entrega', () {
    const repoPartes =
        'lib/features/eventos/repositories/entradas_entregas_repository.dart';
    const repoRetiro =
        'lib/features/eventos/repositories/entradas_retiro_repository.dart';
    const adaptador =
        'lib/features/eventos/repositories/entregar_parte_de_la_app.dart';
    final escribenPartes = <String>{};
    final escribenRetiro = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final codigo = _sinComentarios(f.readAsStringSync());
      if (_escribe(
        codigo,
        tabla: 'entradas_entregas',
        constante: 'EntradasEntregasRepository.tabla',
        tipo: 'EntradasEntregasRepository',
        provider: 'entradasEntregasRepositoryProvider',
        metodos: const ['agregar', 'agregarEn'],
      )) {
        escribenPartes.add(ruta);
      }
      if (_escribe(
        codigo,
        tabla: 'entradas_retiro',
        tipo: 'EntradasRetiroRepository',
        provider: 'entradasRetiroRepositoryProvider',
        metodos: const ['guardar', 'guardarEn'],
      )) {
        escribenRetiro.add(ruta);
      }
    }
    expect(escribenPartes, contains(adaptador));
    expect(escribenPartes.difference({repoPartes, adaptador}), isEmpty,
        reason: 'escriben entradas_entregas por fuera de EntregarParte');
    expect(escribenRetiro, containsAll({repoRetiro, adaptador}));
    expect(escribenRetiro.difference({repoRetiro, adaptador}), isEmpty,
        reason: 'escriben entradas_retiro por fuera de EntregarParte');
  });

  test('la vigilancia de quién escribe ve cada forma de escribir', () {
    bool partes(String codigo) => _escribe(
          codigo,
          tabla: 'entradas_entregas',
          constante: 'EntradasEntregasRepository.tabla',
          tipo: 'EntradasEntregasRepository',
          provider: 'entradasEntregasRepositoryProvider',
          metodos: const ['agregar', 'agregarEn'],
        );
    bool retiro(String codigo) => _escribe(
          codigo,
          tabla: 'entradas_retiro',
          tipo: 'EntradasRetiroRepository',
          provider: 'entradasRetiroRepositoryProvider',
          metodos: const ['guardar', 'guardarEn'],
        );
    for (final c in [
      "await db.insert('entradas_entregas', fila);",
      "await txn.rawInsert('INSERT INTO entradas_entregas (id) VALUES (?)', [id]);",
      "await db.update('entradas_entregas', {'cantidad': 0});",
      "await db.delete('entradas_entregas', where: 'id = ?');",
      "await db.rawDelete('DELETE FROM entradas_entregas WHERE id = ?', [id]);",
      "await supabase.from('entradas_entregas').upsert(fila);",
      'await db.insert(EntradasEntregasRepository.tabla, fila);',
      'await ref.read(entradasEntregasRepositoryProvider).agregar([r]);',
      'final repo = ref.read(entradasEntregasRepositoryProvider);\nawait repo.agregar([r]);',
    ]) {
      expect(partes(c), isTrue, reason: c);
    }
    for (final c in [
      "await db.insert('entradas_retiro', r.toMap());",
      "await db.rawUpdate('UPDATE entradas_retiro SET estado = ?', ['x']);",
      "await supabase\n    .from('entradas_retiro')\n    .update({'estado': 'x'});",
      'await ref.read(entradasRetiroRepositoryProvider).guardar(r);',
      'final repo = ref.read(entradasRetiroRepositoryProvider);\nawait repo.guardar(r);',
      'EntradasRetiroRepository get _retiros => x;\nawait _retiros.guardarEn(txn, r);',
    ]) {
      expect(retiro(c), isTrue, reason: c);
    }
    // Leer no es escribir.
    for (final c in [
      "final filas = await db.query('entradas_entregas');",
      'await ref.read(entradasEntregasRepositoryProvider).deContratos(ids);',
      "const tablas = {'entradas_retiro', 'entradas_entregas'};",
      'await ref.read(entradasRetiroRepositoryProvider).obtenerPorContratoIds(ids);',
      'await otroRepo.guardar(x);',
    ]) {
      expect(partes(c), isFalse, reason: c);
      expect(retiro(c), isFalse, reason: c);
    }
  });
}

String _sinComentarios(String fuente) => fuente
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// Si [codigo] escribe [tabla]: un `insert`/`update`/`delete`/`upsert` con su
/// nombre (o con [constante]), un SQL que la escribe, o [metodos] llamados sobre
/// su repositorio (por el [provider], o por una variable o un campo del [tipo]).
bool _escribe(
  String codigo, {
  required String tabla,
  String? constante,
  required String tipo,
  required String provider,
  required List<String> metodos,
}) {
  final nombres = [
    "['\"]$tabla['\"]",
    if (constante != null) RegExp.escape(constante),
  ];
  for (final n in nombres) {
    if (RegExp('(insert|rawInsert|update|rawUpdate|delete|rawDelete|upsert)'
            '\\s*\\(\\s*$n')
        .hasMatch(codigo)) {
      return true;
    }
    if (RegExp('from\\s*\\(\\s*$n\\s*\\)\\s*\\.\\s*(insert|upsert|update|delete)\\s*\\(')
        .hasMatch(codigo)) {
      return true;
    }
  }
  if (RegExp(
    '(INSERT\\s+(OR\\s+\\w+\\s+)?INTO|REPLACE\\s+INTO|UPDATE|DELETE\\s+FROM)\\s+$tabla\\b',
    caseSensitive: false,
  ).hasMatch(codigo)) {
    return true;
  }
  final llamada = '\\.\\s*(${metodos.join('|')})\\s*\\(';
  if (RegExp('$provider\\s*\\)\\s*$llamada').hasMatch(codigo)) return true;
  final variables = <String>{
    for (final m in RegExp('(\\w+)\\s*=\\s*\\w+\\s*\\.\\s*(read|watch)\\s*\\(\\s*$provider\\s*\\)')
        .allMatches(codigo))
      m.group(1)!,
    for (final m in RegExp('\\b$tipo\\??\\s+(?:get\\s+)?(\\w+)').allMatches(codigo))
      m.group(1)!,
  };
  for (final v in variables) {
    if (RegExp('\\b${RegExp.escape(v)}\\s*$llamada').hasMatch(codigo)) return true;
  }
  return false;
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

/// Un equipo que deja hacer algo justo antes de guardar: lo que otro equipo
/// anota en ese mismo momento (una carrera).
class _EquipoConPausa extends EquipoDeEntrega {
  _EquipoConPausa(EquipoDeEntrega base)
      : super(
          nombre: base.nombre,
          nube: base.nube,
          reloj: base.reloj,
          alumnos: base.alumnos,
          pagos: base.pagos,
        );

  Future<void> Function()? antesDeGuardar;

  @override
  Future<void> guardar(List<EntregaEntradas> nuevos, {EntradasRetiro? retiro}) async {
    final h = antesDeGuardar;
    antesDeGuardar = null;
    if (h != null) await h();
    return super.guardar(nuevos, retiro: retiro);
  }
}

/// La fila de `entradas_retiro` en la nube dice lo mismo que los renglones: lo
/// que la lee sola (el PLANO, una PC con la 6.9.x) ve "Retiró" solo con las dos
/// partes; y leída junto con los renglones, la fila no cambia nada.
void _laFilaDiceLoMismo(NubeDeEntregas nube, ContratoAlumno a, EstadoDeLaEntrega e) {
  final fila = nube.retiros[a.id];
  expect(fila?.entregado ?? false, e.todoEntregado,
      reason: 'la fila dice "entregado" solo con las dos partes');
  final sinLaFila = EstadoDeLaEntrega.deAlumno(a, renglones: nube.renglonesDe(a.id));
  for (final p in ParteEntrega.values) {
    expect(e.parte(p).entregada, sinLaFila.parte(p).entregada,
        reason: 'la fila es reflejo de los renglones (${p.clave})');
  }
}
