// La mesa nueva se da sola (6.5.1), probada con **dos PCs simuladas y una nube de
// mentira** entre las dos (pedido del usuario el 10-nov-2026: "la prueba está a tu
// mano"). Cada PC tiene su base, su cola de subida y su internet; la prueba decide
// cuándo sube y cuándo baja cada una, para armar a propósito las carreras que en la
// oficina pasan una vez cada tanto: las dos cobrando a la vez, una sin internet, una
// que todavía no bajó lo de la otra.
//
// Lo que se usa de verdad: `MesaNuevaSola` entera, `MesasNuevasAlFondo`, el sorteo
// sobre el plano con su control final y la cuenta de lo pagado. Lo que es de
// mentira: las bases y la nube (acá, mapas en memoria). En la app esos caminos son
// los mismos por los que ya guarda el botón SORTEO.
//
// Nunca toca `Documentos\Junior Eventos\data.db` ni Supabase.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/mesa_nueva_sola.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _evento = 'e';

/// Un reloj que avanza solo: cada vez que alguien pregunta la hora pasó un
/// segundo. Así todo lo que pasa en la prueba queda en orden.
class _Reloj {
  DateTime _ahora = DateTime.utc(2026, 11, 10, 22, 42, 50);
  DateTime ahora() => _ahora = _ahora.add(const Duration(seconds: 1));
}

/// La nube: una fila por alumno, por pago y por renglón, y **una sola fila de
/// plano**, que gana quien la sube último.
class _Nube {
  final alumnos = <String, ContratoAlumno>{};
  final pagos = <String, Map<String, dynamic>>{};
  final registros = <String, SorteoMesasRegistro>{};
  PlanoEvento? plano;

  List<int> mesasDe(String id) =>
      MesasExtraUtils.numerosMesaDesdeTexto(alumnos[id]!.numeroMesa).toList()
        ..sort();

  /// Las mesas que figuran en más de una familia activa.
  Map<int, List<String>> get repetidas {
    final porMesa = <int, List<String>>{};
    for (final a in alumnos.values) {
      if (a.esBajaTemporal) continue;
      for (final n in MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)) {
        porMesa.putIfAbsent(n, () => []).add(a.id);
      }
    }
    return {
      for (final e in porMesa.entries)
        if (e.value.length > 1) e.key: e.value,
    };
  }
}

class _Subida {
  final String tabla;
  final String id;
  final void Function(_Nube) hacer;
  _Subida(this.tabla, this.id, this.hacer);
}

/// Una PC: su base, su cola de subida y su internet.
class _Pc implements PuertosDeLaMesaNueva {
  _Pc(this.nombre, this.nube, this.reloj);

  final String nombre;
  final _Nube nube;
  final _Reloj reloj;

  bool conInternet = true;

  /// En false, lo que se guarda queda en la cola hasta que la prueba diga
  /// [subir]: así dos PCs pueden hacer la cuenta antes de enterarse de la otra.
  bool subeSola = true;

  final alumnosLocal = <String, ContratoAlumno>{};
  final pagosLocal = <String, Map<String, dynamic>>{};
  final registrosLocal = <String, SorteoMesasRegistro>{};
  PlanoEvento? planoLocal;
  final cola = <_Subida>[];
  final puerta = <String>[];
  int _ids = 0;

  late final sola = MesaNuevaSola(this);

  bool _espera(String tabla, String id) =>
      cola.any((s) => s.tabla == tabla && s.id == id);

  /// Baja todo lo de la nube, menos lo que acá tiene un cambio sin subir.
  void bajar() {
    if (!conInternet) return;
    for (final a in nube.alumnos.values) {
      if (!_espera('contratos_alumnos', a.id)) alumnosLocal[a.id] = a;
    }
    pagosLocal.addAll(nube.pagos);
    registrosLocal.addAll(nube.registros);
    if (!_espera('planos_evento', _evento) && nube.plano != null) {
      planoLocal = nube.plano;
    }
  }

  /// Sube lo que está en la cola, en orden.
  void subir() {
    if (!conInternet) return;
    for (final s in cola) {
      s.hacer(nube);
    }
    cola.clear();
  }

  /// Un cobro en esta PC: queda en su base y en la cola.
  void cobrar(String alumnoId, String concepto, double monto) {
    final cuando = reloj.ahora().toIso8601String();
    final id = '$nombre-pago-${_ids++}';
    final pago = <String, dynamic>{
      'id': id,
      'contrato_alumno_id': alumnoId,
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': 0,
      'created_at': cuando,
      'fecha_pago': cuando,
    };
    pagosLocal[id] = pago;
    cola.add(_Subida('pagos', id, (n) => n.pagos[id] = pago));
    if (subeSola) subir();
  }

  // ── Lo que usa MesaNuevaSola ──

  @override
  Future<List<ContratoAlumno>> alumnos(String eventoId) async =>
      alumnosLocal.values.toList();

  @override
  Future<Map<String, List<Map<String, dynamic>>>> pagos(
    List<ContratoAlumno> alumnos,
  ) async {
    final r = <String, List<Map<String, dynamic>>>{};
    for (final p in pagosLocal.values) {
      r.putIfAbsent(p['contrato_alumno_id'] as String, () => []).add(p);
    }
    return r;
  }

  @override
  Future<List<SorteoMesasRegistro>> registros(String eventoId) async =>
      registrosLocal.values.toList();

  @override
  Future<PlanoEvento?> planoDeEstaPc(String eventoId) async => planoLocal;

  @override
  Future<int?> mesasDeOtraPcSinBajar(String eventoId) async {
    if (!conInternet) return null;
    var distintos = 0;
    for (final a in nube.alumnos.values) {
      final local = alumnosLocal[a.id];
      if (local == null || _espera('contratos_alumnos', a.id)) continue;
      if ((a.numeroMesa ?? '').trim() != (local.numeroMesa ?? '').trim()) {
        distintos++;
      }
    }
    return distintos;
  }

  @override
  Future<PlanoEvento?> planoDeLaNube(String eventoId) async {
    if (!conInternet) throw StateError('sin internet');
    return nube.plano;
  }

  @override
  Future<void> guardar({
    required Map<String, String> numeros,
    required SorteoMesasRegistro registro,
    required PlanoEvento plano,
  }) async {
    for (final e in numeros.entries) {
      final a = alumnosLocal[e.key]!.copyWith(numeroMesa: e.value);
      alumnosLocal[e.key] = a;
      cola.add(_Subida('contratos_alumnos', e.key, (n) {
        n.alumnos[e.key] = n.alumnos[e.key]!.copyWith(numeroMesa: e.value);
      }));
    }
    registrosLocal[registro.id] = registro;
    cola.add(_Subida(
      'sorteos_mesas',
      registro.id,
      (n) => n.registros[registro.id] = registro,
    ));
    planoLocal = plano;
    cola.add(_Subida('planos_evento', _evento, (n) => n.plano = plano));
    if (subeSola) subir();
  }

  @override
  Future<void> puertaAlDia(String eventoId, Iterable<String> alumnos) async =>
      puerta.addAll(alumnos);

  @override
  DateTime ahora() => reloj.ahora();

  @override
  String nuevoId() => '$nombre-renglon-${_ids++}';
}

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  List<int> mesas = const [],
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _evento,
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// La escuela del 10-nov, ya sorteada: 101 mesas, una familia en cada una menos
/// en la 52 (libre). Dos familias, [x] en la 9 e [y] en la 17, tienen una mesa
/// adicional cargada y **sin pagar**: salieron del sorteo con una sola. Y hay
/// una, `nopago`, que no pagó nada de su contrato: quedó sin mesa (el candado).
class _Oficina {
  final reloj = _Reloj();
  final nube = _Nube();
  late final a = _Pc('A', nube, reloj);
  late final b = _Pc('B', nube, reloj);
  late final Map<String, String> mesasDelSorteo;
  late final List<String> lugaresDelSalon;

  _Oficina({Map<int, MesaFijada> fijadas = const {}}) {
    final salon = ArmarAMedida.armar(
      const OpcionesAMedida(
        playon: PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8),
        cantidad: 101,
      ),
    ).armado;
    final ayer = DateTime.utc(2026, 11, 9, 15);
    final alumnos = [
      for (var n = 1; n <= 101; n++)
        if (n != 9 && n != 17 && n != 52) _familia('f$n', mesas: [n]),
      _familia('x', extras: 1, mesas: [9]),
      _familia('y', extras: 1, mesas: [17]),
      _familia('nopago'),
    ];
    for (final al in alumnos) {
      nube.alumnos[al.id] = al;
      if (al.id == 'nopago') continue;
      nube.pagos['base-${al.id}'] = {
        'id': 'base-${al.id}',
        'contrato_alumno_id': al.id,
        'concepto': 'Cuota Base (1/9)',
        'monto': 35000.0,
        'monto_gross': 35000.0,
        'anulado': 0,
        'created_at': ayer.toIso8601String(),
        'fecha_pago': ayer.toIso8601String(),
      };
    }
    mesasDelSorteo = {
      for (final al in alumnos)
        if (al.numeroMesa != null) al.id: al.numeroMesa!,
    };
    nube.registros['sorteo-del-jefe'] = SorteoMesasRegistro(
      id: 'sorteo-del-jefe',
      eventoId: _evento,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: mesasDelSorteo,
      hechoPor: 'Jefe',
      createdAt: reloj.ahora(),
    );
    final ahora = reloj.ahora();
    nube.plano = PlanoEvento.nuevo(
      eventoId: _evento,
      armado: salon,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.entera,
      ahora: ahora,
    ).copyWith(config: ConfigPlano(fijadas: fijadas), ahora: ahora);
    lugaresDelSalon = _lugares(nube.plano!);
    a.bajar();
    b.bajar();
  }

  /// Las dos PCs se ponen al día: suben lo suyo y bajan lo de la otra.
  void sincronizar() {
    a.subir();
    b.subir();
    a.bajar();
    b.bajar();
  }

  /// Nadie que ya tenía mesa cambió, y ninguna mesa del salón se movió.
  void nadieSeMovio({Set<String> salvo = const {'x', 'y'}}) {
    for (final e in mesasDelSorteo.entries) {
      if (salvo.contains(e.key)) continue;
      expect(nube.alumnos[e.key]!.numeroMesa, e.value, reason: e.key);
    }
    expect(
      _lugares(nube.plano!).take(101).toList(),
      lugaresDelSalon,
      reason: 'las 101 mesas del salón siguen donde estaban',
    );
    expect(EditarArmado.pisadas(nube.plano!.armado), isEmpty);
  }
}

List<String> _lugares(PlanoEvento p) => [
      for (final m in p.armado.mesas) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
    ];

void main() {
  group('una PC', () {
    test('paga la adicional después del sorteo: recibe la 102, sola', () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      final r = await o.a.sola.revisar(_evento);

      expect(r.estado, EstadoMesaNueva.dio);
      expect(r.dadas, {
        'x': [102],
      });
      expect(r.aviso, 'A X se le dio la mesa 102.');
      expect(o.nube.mesasDe('x'), [9, 102]);
      expect(o.nube.plano!.armado.existe(102), isTrue);
      expect(
        o.nube.plano!.config.fijadas[102]!.motivo,
        MesasNuevasAlFondo.motivo,
      );
      expect(o.a.puerta, ['x']);
      o.nadieSeMovio();

      // Queda anotado como automático, con lo que tenía antes.
      final renglon = o.nube.registros.values.singleWhere((r) => r.automatico);
      expect(renglon.resultado, {'x': '9, 102'});
      expect(renglon.antes, {'x': '9'});
      expect(renglon.nuevas, {'x': '102'});
      expect(renglon.hechoPor, 'El programa');

      // Y no se repite: mirar de nuevo no hace nada.
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect((await o.b.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect(o.nube.registros.values.where((r) => r.automatico), hasLength(1));
    });

    test('el renglón automático viaja y se lee igual', () {
      final r = SorteoMesasRegistro(
        id: 'r',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'x': '9, 102'},
        nuevas: const {'x': '102'},
        automatico: true,
        createdAt: DateTime.utc(2026, 11, 11),
      );
      final leido = SorteoMesasRegistro.fromMap(r.toMap());
      expect(leido.automatico, isTrue);
      expect(leido.nuevas, {'x': '102'});
      expect(leido.resultado, {'x': '9, 102'});
      // Un renglón de siempre no es automático.
      expect(
        SorteoMesasRegistro.fromMap(
          SorteoMesasRegistro(
            id: 's',
            eventoId: _evento,
            tipo: TipoRegistroSorteo.sorteo,
            resultado: const {'x': '9'},
            createdAt: DateTime.utc(2026, 11, 11),
          ).toMap(),
        ).automatico,
        isFalse,
      );
    });

    test('sin internet no se da: queda esperando, y se da al volver', () async {
      final o = _Oficina();
      o.a.conInternet = false;
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      final sinRed = await o.a.sola.revisar(_evento);
      expect(sinRed.estado, EstadoMesaNueva.sinInternet);
      expect(sinRed.aviso, contains('le falta el número de su mesa'));
      expect(o.a.alumnosLocal['x']!.numeroMesa, '9');
      expect(o.a.cola.map((s) => s.tabla), ['pagos'], reason: 'solo el cobro');
      expect(o.nube.mesasDe('x'), [9]);

      o.a.conInternet = true;
      o.sincronizar();
      final conRed = await o.a.sola.revisar(_evento);
      expect(conRed.estado, EstadoMesaNueva.dio);
      expect(o.nube.mesasDe('x'), [9, 102]);
      o.nadieSeMovio();
    });

    test('la adicional cargada y sin pagar sigue con candado', () async {
      final o = _Oficina();
      // Paga otra cuota de su contrato, pero nada de la mesa adicional.
      o.a.cobrar('x', 'Cuota Base (2/9)', 35000);
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect(o.nube.mesasDe('x'), [9]);
      expect(o.nube.plano!.armado.existe(102), isFalse);
    });

    test('quien no pagó nada no recibe mesa; cuando paga su primera cuota, sí',
        () async {
      final o = _Oficina();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      o.a.cobrar('nopago', 'Cuota Base (1/9)', 35000);
      final r = await o.a.sola.revisar(_evento);
      expect(r.estado, EstadoMesaNueva.dio);
      expect(o.nube.mesasDe('nopago'), [102]);
      o.nadieSeMovio();
    });

    test('quien tenía una mesa reservada por el jefe recibe esa, no una nueva',
        () async {
      final o = _Oficina(
        fijadas: {52: const MesaFijada(alumnoId: 'nopago', motivo: 'junior')},
      );
      o.a.cobrar('nopago', 'Cuota Base (1/9)', 35000);
      final r = await o.a.sola.revisar(_evento);
      expect(r.estado, EstadoMesaNueva.dio);
      expect(r.dadas, {
        'nopago': [52],
      });
      expect(o.nube.mesasDe('nopago'), [52]);
      expect(o.nube.plano!.armado.mesas, hasLength(101));
      expect(o.nube.registros.values.singleWhere((r) => r.automatico).nuevas,
          isNull);
    });

    test('una mesa libre del salón nunca se da sola: la 52 queda libre',
        () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      await o.a.sola.revisar(_evento);
      expect(o.nube.repetidas, isEmpty);
      expect(
        o.nube.alumnos.values.where(
          (a) => MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)
              .contains(52),
        ),
        isEmpty,
      );
    });
  });

  group('lo que el jefe deshace no vuelve solo', () {
    test('pagó antes del último sorteo y le falta mesa: no es "llegó después"',
        () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      // El jefe sortea (o deshace) después de ese pago: su renglón es más nuevo.
      final cuando = o.reloj.ahora();
      o.nube.registros['otro-del-jefe'] = SorteoMesasRegistro(
        id: 'otro-del-jefe',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.deshacer,
        resultado: const {},
        quedan: const {},
        hechoPor: 'Jefe',
        createdAt: cuando,
      );
      o.sincronizar();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect(o.nube.mesasDe('x'), [9]);
    });

    test('si el jefe deshace la mesa que se dio sola, no se la vuelve a dar',
        () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.dio);
      // DESHACER → solo los últimos sorteados: X vuelve a la 9, con su renglón.
      o.nube.alumnos['x'] = o.nube.alumnos['x']!.copyWith(numeroMesa: '9');
      o.nube.registros['deshacer'] = SorteoMesasRegistro(
        id: 'deshacer',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.deshacer,
        resultado: const {'x': '9, 102'},
        quedan: const {'x': '9'},
        hechoPor: 'Jefe',
        createdAt: o.reloj.ahora(),
      );
      o.sincronizar();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect((await o.b.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect(o.nube.mesasDe('x'), [9]);
    });

    test('con el sorteo deshecho entero no hace nada', () async {
      final o = _Oficina();
      for (final id in o.nube.alumnos.keys.toList()) {
        o.nube.alumnos[id] = _familia(
          id,
          extras: o.nube.alumnos[id]!.mesaExtraCantidad,
        );
      }
      o.sincronizar();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
    });

    test('una fiesta sin registro de sorteos: no se sabe quién llegó después',
        () async {
      final o = _Oficina();
      o.nube.registros.clear();
      o.a.registrosLocal.clear();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
    });
  });

  group('dos PCs', () {
    test('una después de la otra: 102 y 103, por orden de llegada', () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      expect((await o.a.sola.revisar(_evento)).dadas, {
        'x': [102],
      });
      o.sincronizar();
      o.b.cobrar('y', 'Mesa Extra (1/1)', 70000);
      expect((await o.b.sola.revisar(_evento)).dadas, {
        'y': [103],
      });
      o.sincronizar();
      expect(o.nube.mesasDe('x'), [9, 102]);
      expect(o.nube.mesasDe('y'), [17, 103]);
      expect(o.nube.repetidas, isEmpty);
      o.nadieSeMovio();
      expect(o.a.planoLocal!.armado.mesas, hasLength(103));
    });

    test('la otra PC todavía no bajó la mesa nueva: espera, no pisa', () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      await o.a.sola.revisar(_evento);
      // B cobra a otra familia sin haber bajado lo de A.
      o.b.cobrar('y', 'Mesa Extra (1/1)', 70000);
      final r = await o.b.sola.revisar(_evento);
      expect(r.estado, EstadoMesaNueva.esperar);
      expect(o.nube.mesasDe('y'), [17]);
      // Cuando baja, le toca la que sigue.
      o.sincronizar();
      expect((await o.b.sola.revisar(_evento)).dadas, {
        'y': [103],
      });
      expect(o.nube.repetidas, isEmpty);
      o.nadieSeMovio();
    });

    test('las dos miran a la misma familia a la vez: una sola 102', () async {
      final o = _Oficina();
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      o.sincronizar();
      // Las dos hacen la cuenta antes de que suba la de la otra.
      o.a.subeSola = false;
      o.b.subeSola = false;
      final ra = await o.a.sola.revisar(_evento);
      final rb = await o.b.sola.revisar(_evento);
      expect(ra.dadas, {
        'x': [102],
      });
      expect(rb.dadas, ra.dadas, reason: 'las dos dan lo mismo');
      o.sincronizar();

      expect(o.nube.mesasDe('x'), [9, 102]);
      expect(o.nube.plano!.armado.mesas, hasLength(102));
      expect(o.nube.repetidas, isEmpty);
      o.nadieSeMovio();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect((await o.b.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
    });

    for (final ganaElPlanoDe in ['A', 'B']) {
      test('la carrera: las dos cobran a familias distintas en el mismo '
          'momento (el plano de $ganaElPlanoDe sube último)', () async {
        final o = _Oficina();
        o.a.subeSola = false;
        o.b.subeSola = false;
        o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
        o.b.cobrar('y', 'Mesa Extra (1/1)', 70000);
        o.a.subir();
        o.b.subir();
        // Ninguna vio el cobro de la otra, y las dos le dan la 102 a la suya.
        expect((await o.a.sola.revisar(_evento)).dadas, {
          'x': [102],
        });
        expect((await o.b.sola.revisar(_evento)).dadas, {
          'y': [102],
        });
        if (ganaElPlanoDe == 'A') {
          o.b.subir();
          o.a.subir();
        } else {
          o.a.subir();
          o.b.subir();
        }
        expect(o.nube.repetidas.keys, [102], reason: 'la carrera, armada');

        // Bajan lo de la otra y vuelven a mirar: la que no figura en el plano
        // de la nube pasa a la que sigue.
        o.a.subeSola = true;
        o.b.subeSola = true;
        o.a.bajar();
        o.b.bajar();
        final duenia = ganaElPlanoDe == 'A' ? 'x' : 'y';
        final otra = duenia == 'x' ? 'y' : 'x';
        expect(o.nube.plano!.config.fijadas[102]!.alumnoId, duenia);

        final primera = await o.a.sola.revisar(_evento);
        expect(primera.estado, EstadoMesaNueva.dio);
        expect(primera.dadas, {
          otra: [103],
        });
        o.sincronizar();

        expect(o.nube.repetidas, isEmpty);
        expect(o.nube.mesasDe(duenia), [duenia == 'x' ? 9 : 17, 102]);
        expect(o.nube.mesasDe(otra), [otra == 'x' ? 9 : 17, 103]);
        expect(o.nube.plano!.config.fijadas[102]!.alumnoId, duenia);
        expect(o.nube.plano!.config.fijadas[103]!.alumnoId, otra);
        expect(o.nube.plano!.armado.mesas, hasLength(103));
        o.nadieSeMovio();

        // Y queda quieto: ninguna de las dos tiene nada más que hacer.
        expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
        expect((await o.b.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      });
    }

    test('la carrera, y las dos la arreglan a la vez: quedan igual', () async {
      final o = _Oficina();
      o.a.subeSola = false;
      o.b.subeSola = false;
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      o.b.cobrar('y', 'Mesa Extra (1/1)', 70000);
      await o.a.sola.revisar(_evento);
      await o.b.sola.revisar(_evento);
      o.sincronizar();
      expect(o.nube.repetidas.keys, [102]);

      // Las dos ven la mesa repetida y la arreglan sin enterarse de la otra.
      final ra = await o.a.sola.revisar(_evento);
      final rb = await o.b.sola.revisar(_evento);
      expect(ra.dadas, rb.dadas, reason: 'las dos mueven a la misma familia');
      o.sincronizar();

      expect(o.nube.repetidas, isEmpty);
      expect({...o.nube.mesasDe('x'), ...o.nube.mesasDe('y')},
          {9, 17, 102, 103});
      expect(o.nube.plano!.armado.mesas, hasLength(103));
      o.nadieSeMovio();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect((await o.b.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
    });

    test('una PC sin internet cobra, la otra da una mesa mientras tanto',
        () async {
      final o = _Oficina();
      o.a.conInternet = false;
      o.a.cobrar('x', 'Mesa Extra (1/1)', 70000);
      expect(
        (await o.a.sola.revisar(_evento)).estado,
        EstadoMesaNueva.sinInternet,
      );
      o.b.cobrar('y', 'Mesa Extra (1/1)', 70000);
      expect((await o.b.sola.revisar(_evento)).dadas, {
        'y': [102],
      });
      // Vuelve internet en A: sube su cobro, baja lo de B y recién ahí da.
      o.a.conInternet = true;
      o.sincronizar();
      expect((await o.a.sola.revisar(_evento)).dadas, {
        'x': [103],
      });
      o.sincronizar();
      expect(o.nube.repetidas, isEmpty);
      expect(o.nube.mesasDe('x'), [9, 103]);
      expect(o.nube.mesasDe('y'), [17, 102]);
      o.nadieSeMovio();
    });

    test('una mesa repetida a mano (no una mesa nueva) no se toca', () async {
      final o = _Oficina();
      // Alguien escribió la 30 en dos fichas: no es de esto, no se arregla solo.
      o.nube.alumnos['f31'] = o.nube.alumnos['f31']!.copyWith(numeroMesa: '30');
      o.sincronizar();
      expect((await o.a.sola.revisar(_evento)).estado, EstadoMesaNueva.nada);
      expect(o.nube.alumnos['f31']!.numeroMesa, '30');
      expect(o.nube.alumnos['f30']!.numeroMesa, '30');
    });
  });
}
