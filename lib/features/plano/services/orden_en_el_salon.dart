import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/cumplimiento_de_cuotas.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import '../modelo/armado_salon.dart';
import 'familias_en_los_huecos.dart';
import 'mesas_del_paso.dart';
import 'mesas_juntas.dart';
import 'mesas_nuevas_al_fondo.dart';
import 'sorteo_con_plano.dart';

/// Lo que el sorteo necesita para repartir por cumplimiento: con qué sortear y
/// qué guardar. Si no se puede, [problema] dice por qué.
class OrdenParaElSorteo {
  final String? problema;

  /// El plano **para esta corrida del sorteo**: con cada mesa fijada para su
  /// familia. No se guarda.
  final ConfigPlano? configDelSorteo;

  /// El plano que se guarda con el sorteo: sin esas fijadas, con quién quedó
  /// dónde y por qué ([ConfigPlano.frente]).
  final ConfigPlano? configAGuardar;

  /// Los alumnos como los tiene que ver el sorteo: los que se ordenan, sin
  /// mesa. No se guardan.
  final List<ContratoAlumno> alumnosDelSorteo;

  /// Lo pagado como lo tiene que ver el sorteo: nadie pierde una mesa que ya
  /// tiene.
  final ExclusionSorteo exclusionDelSorteo;

  /// Alumno → sus mesas por orden (la principal primero).
  final Map<String, List<int>> lugares;

  /// Cuántas familias que hoy tienen mesa pasan a otra.
  final int cambian;

  const OrdenParaElSorteo._({
    this.problema,
    this.configDelSorteo,
    this.configAGuardar,
    this.alumnosDelSorteo = const [],
    this.exclusionDelSorteo = ExclusionSorteo.ninguna,
    this.lugares = const {},
    this.cambian = 0,
  });

  const OrdenParaElSorteo.noSePuede(String problema)
      : this._(problema: problema);

  bool get sePuede => problema == null;

  /// Cuántas familias quedan ubicadas.
  int get ubicadas => lugares.values.where((l) => l.isNotEmpty).length;
}

/// "Cumplimiento debido" (6.7.1, pedido del usuario el 12-nov-2026): las mesas
/// van de la familia que mejor cumplió con sus cuotas a la que peor, desde la
/// pasarela hacia afuera; la adicional, detrás de su principal.
///
/// **Se tilda en el cartel del SORTEO, no en el plano.** Antes de sortear el
/// plano se ve vacío, como siempre; al apretar SORTEAR se calcula el orden,
/// se le fija a cada familia su mesa **solo para esa corrida** y el motor de
/// siempre se las entrega ([paraElSorteo]). Esas fijadas no se guardan: lo que
/// queda es quién quedó dónde y por qué ([ConfigPlano.frente]).
///
/// Sirve con el salón vacío y con el sorteo ya hecho: ahí reacomoda a las
/// familias sin deshacer nada, y nadie pierde una mesa que ya tiene.
///
/// **No toca el motor del sorteo ni cambia el número de ninguna mesa.**
class OrdenEnElSalon {
  OrdenEnElSalon._();

  /// El motivo de una fijada puesta por el orden. Sin el puesto ni nada de
  /// cómo pagó: el motivo de una fijada lo ve cualquiera que abra el plano.
  static const motivo = MesaFijada.motivoPorOrden;

  static bool esPorOrden(MesaFijada f) => f.esPorOrden;

  /// Una fijada que no puso el jefe a mano: la del orden, o la de una mesa
  /// nueva al fondo (6.5.1). Esas familias se ordenan como las demás.
  static bool _noEsAMano(MesaFijada f) =>
      f.esPorOrden || f.motivo == MesasNuevasAlFondo.motivo;

  /// Una semilla que depende solo de la fiesta: los empates se sortean, y
  /// volver a calcular no los cambia.
  static int semillaDe(String eventoId) {
    var h = 17;
    for (final c in eventoId.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }

  /// El plano sin las fijadas que dejó el tilde de la 6.7.0 (ahí se fijaban
  /// antes de sortear, a la vista). Null si no tenía ninguna.
  static ConfigPlano? sinFijadasDelOrden(ConfigPlano config) {
    if (!config.fijadas.values.any(esPorOrden)) return null;
    return config.copyWith(
      fijadas: {
        for (final e in config.fijadas.entries)
          if (!esPorOrden(e.value)) e.key: e.value,
      },
    );
  }

  /// El plano con el orden apagado: un sorteo entero sin el tilde no deja
  /// escrito el porqué de otro. Null si no había nada que apagar.
  static ConfigPlano? apagado(ConfigPlano config) {
    final frente = config.frente;
    if (frente == null || (!frente.prendido && frente.lugares.isEmpty)) {
      return null;
    }
    return config.copyWith(
      frente: OrdenDelPlano(prendido: false, recorrido: frente.recorrido),
    );
  }

  /// Si el porqué guardado sigue valiendo: el orden está prendido y alguna
  /// familia sigue en una mesa que le dio. Después de deshacer el sorteo no
  /// vale; si se restaura, vuelve a valer.
  static bool vigente(ConfigPlano config, Iterable<ContratoAlumno> alumnos) {
    final frente = config.frente;
    if (frente == null || !frente.prendido || frente.lugares.isEmpty) {
      return false;
    }
    final deCada = {
      for (final a in alumnos)
        a.id: MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa),
    };
    return frente.lugares.any(
      (l) => l.mesas.any((n) => deCada[l.alumnoId]?.contains(n) ?? false),
    );
  }

  /// El lugar de cada familia de [orden], de la primera a la última.
  ///
  /// [mesasDe] dice cuántas mesas recibe cada una. [alFinal], cuántas de esas
  /// van después de las de todas las familias ("Las mesas adicionales: Al
  /// final"): primero se reparten las de adelante de todos y después esas, en
  /// el mismo orden. [noUsar] son las mesas que no se reparten. Una familia sin
  /// lugar queda con la lista vacía: el salón no tiene más mesas.
  ///
  /// Con [juntasEnLaFila] y el [armado], si con las tiras alguna familia con
  /// adicional quedaba partida (el salón justo), las que tienen adicional se
  /// ubican de nuevo con [FamiliasEnLosHuecos]: juntas, en mesas seguidas o
  /// una detrás de la otra, y en el orden del cumplimiento (16-nov-2026).
  static Map<String, List<int>> repartir({
    required MesasDelPaso paso,
    required List<PuestoDelOrden> orden,
    required Map<String, int> mesasDe,
    Map<String, int> alFinal = const {},
    Set<int> noUsar = const {},
    bool juntasEnLaFila = false,
    ArmadoSalon? armado,
  }) {
    final libres = [
      for (final n in paso.enOrden)
        if (!noUsar.contains(n)) n,
    ];
    // La que sigue de una familia: detrás de la anterior; si está tomada o no
    // existe, la libre más cercana de su lado; si no, la que sigue en el orden.
    int? laQueSigue(List<int> suyas) {
      if (libres.isEmpty) return null;
      final detras = paso.detras(suyas.last);
      final n = detras != null && libres.contains(detras)
          ? detras
          : paso.laMasCercana(suyas.first, libres) ?? libres.first;
      libres.remove(n);
      return n;
    }

    // Con "Primero las familias de una sola mesa" (16-nov-2026) las familias
    // con adicional arrancan a mitad de una fila, y la de varias mesas quedaba
    // partida en el borde. Con [juntasEnLaFila], las [cuantas] van en la
    // primera tira libre de su fila y su lado, una detrás de la otra; si no
    // hay ninguna, lo de siempre. Un hueco que deja una familia grande lo puede
    // tomar una más chica que viene después, como en el sorteo de siempre.
    List<int>? enUnaTira(int cuantas) {
      if (!juntasEnLaFila || cuantas < 2) return null;
      for (final p in libres) {
        final tira = [p];
        while (tira.length < cuantas) {
          final d = paso.detras(tira.last);
          if (d == null || !libres.contains(d) || tira.contains(d)) break;
          tira.add(d);
        }
        if (tira.length == cuantas) {
          libres.removeWhere(tira.contains);
          return tira;
        }
      }
      return null;
    }

    final r = <String, List<int>>{};
    final atrasDe = <String, int>{};
    // Desde qué familia van las que tienen adicional (con el tilde, van todas
    // juntas después de las de una sola mesa), y qué mesas quedaban ahí.
    int? desdeConAdicional;
    List<int>? libresParaLasConAdicional;
    for (final (k, p) in orden.indexed) {
      final id = p.alumno.id;
      final cuantas = max(1, mesasDe[id] ?? 1);
      // La principal queda siempre adelante.
      final atras = min(max(0, alFinal[id] ?? 0), cuantas - 1);
      atrasDe[id] = atras;
      if (desdeConAdicional == null && cuantas - atras > 1) {
        desdeConAdicional = k;
        libresParaLasConAdicional = [...libres];
      }
      final tira = enUnaTira(cuantas - atras);
      if (tira != null) {
        r[id] = tira;
        continue;
      }
      final suyas = <int>[];
      if (libres.isNotEmpty) {
        suyas.add(libres.removeAt(0));
        while (suyas.length < cuantas - atras) {
          final n = laQueSigue(suyas);
          if (n == null) break;
          suyas.add(n);
        }
      }
      r[id] = suyas;
    }
    // El salón justo (16-nov-2026): con las tiras y "lo de siempre", alguna
    // familia con adicional quedaba partida. Se ubican de nuevo, desde la
    // primera que tiene adicional, con [FamiliasEnLosHuecos]: cada una junta
    // (seguidas o una detrás de la otra), y la que mejor cumplió en el primer
    // lugar que se pueda. Si ni así, queda lo de antes.
    if (juntasEnLaFila &&
        armado != null &&
        desdeConAdicional != null &&
        libresParaLasConAdicional != null) {
      final resto = orden.sublist(desdeConAdicional);
      final partida = resto.any((p) {
        final suyas = r[p.alumno.id] ?? const <int>[];
        return suyas.length > 1 && !MesasJuntas.juntas(armado, suyas);
      });
      if (partida) {
        final acomodo = FamiliasEnLosHuecos.acomodar(
          armado: armado,
          libres: libresParaLasConAdicional,
          familias: [
            for (final p in resto)
              (
                id: p.alumno.id,
                mesas: max(1, mesasDe[p.alumno.id] ?? 1) -
                    (atrasDe[p.alumno.id] ?? 0),
              ),
          ],
        );
        if (acomodo != null) {
          for (final p in resto) {
            r[p.alumno.id] = [...?acomodo.mesas[p.alumno.id]];
          }
          final usadas = {for (final l in acomodo.mesas.values) ...l};
          libres
            ..clear()
            ..addAll([
              for (final n in libresParaLasConAdicional)
                if (!usadas.contains(n)) n,
            ]);
        }
      }
    }
    // Las del final van después de todas las de adelante: un hueco que dejó
    // una tira antes de la última de adelante queda vacío. Con el salón justo
    // no: si sin esos huecos no entran las del final, se usan.
    if (juntasEnLaFila && atrasDe.values.any((a) => a > 0)) {
      final puesto = {
        for (var i = 0; i < paso.enOrden.length; i++) paso.enOrden[i]: i,
      };
      final ultima = [
        for (final l in r.values) ...l,
      ].map((n) => puesto[n] ?? -1).fold<int>(-1, max);
      final despues = [
        for (final n in libres)
          if ((puesto[n] ?? -1) >= ultima) n,
      ];
      final hacenFalta = atrasDe.values.fold<int>(0, (s, a) => s + a);
      if (despues.length >= hacenFalta) {
        libres
          ..clear()
          ..addAll(despues);
      }
    }
    for (final p in orden) {
      final id = p.alumno.id;
      final atras = atrasDe[id] ?? 0;
      // Sin la principal no hay adicionales.
      if (atras == 0 || r[id]!.isEmpty || libres.isEmpty) continue;
      final tira = enUnaTira(atras);
      if (tira != null) {
        r[id]!.addAll(tira);
        continue;
      }
      final delFinal = <int>[libres.removeAt(0)];
      while (delFinal.length < atras) {
        final n = laQueSigue(delFinal);
        if (n == null) break;
        delFinal.add(n);
      }
      r[id]!.addAll(delFinal);
    }
    return r;
  }

  /// Lo que hace falta para sortear por cumplimiento, con los pagos de hoy.
  ///
  /// [exclusion] es lo pagado como lo dejó el cartel ("solo lo pagado", los
  /// tildados "sortear igual"): de ahí sale cuántas mesas le tocan a cada
  /// familia, igual que en el sorteo de siempre.
  ///
  /// **Con el sorteo ya hecho** reacomoda: cada familia que entra al orden deja
  /// sus mesas y recibe las que le tocan por orden, al menos tantas como
  /// tiene. Quien no entra (su mesa la fijó el jefe a mano, está de baja, o
  /// tiene más mesas de las pagas y menos que su contrato) se queda donde
  /// está, y sus mesas no se reparten.
  static OrdenParaElSorteo paraElSorteo({
    required String eventoId,
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required DateTime hoyAr,
    required DateTime ahora,
    ExclusionSorteo exclusion = ExclusionSorteo.ninguna,
    ModoSorteo modo = ModoSorteo.entera,
    RecorridoDelOrden recorrido = RecorridoDelOrden.columnas,
    bool usarPasto = false,
    bool adicionalesAlFinal = false,
    int juntasConLaPrincipal = 0,
    Set<String> dejarJuntas = const {},
    bool unaMesaPrimero = false,
    String? por,
  }) {
    List<int> mesasDeHoy(ContratoAlumno a) =>
        MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList()..sort();
    final hayConMesa =
        alumnos.any((a) => !a.esBajaTemporal && mesasDeHoy(a).isNotEmpty);
    // Por división cada familia va en el bloque de la suya, y este orden no
    // mira los bloques: dejaría familias fuera de su división.
    if (modo == ModoSorteo.bloques ||
        (hayConMesa && config.bloques.isNotEmpty)) {
      return const OrdenParaElSorteo.noSePuede(
        'Todavía no se puede con el sorteo por división.',
      );
    }
    final paso = MesasDelPaso.de(armado, recorrido: recorrido);
    if (paso == null) {
      return const OrdenParaElSorteo.noSePuede(
        'El salón no tiene pasarela ni escenario.',
      );
    }
    final aMano = {
      for (final e in config.fijadas.entries)
        if (!_noEsAMano(e.value)) e.key: e.value,
    };
    final conFijadaAMano = {for (final f in aMano.values) f.alumnoId};

    // Cuántas mesas le daría hoy el sorteo a cada uno, si nadie tuviera mesa.
    final sinNumeros = [
      for (final a in alumnos)
        mesasDeHoy(a).isEmpty ? a : a.copyWith(numeroMesa: ''),
    ];
    final leTocan = {
      for (final p in SorteoMesasMotor.pedidos(
        sinNumeros,
        sinMesa: exclusion.sinMesa,
        soloBase: exclusion.soloBase,
      ))
        p.alumnoId: p.mesas,
    };

    final metas = <String, int>{};
    final sinMesa = {...exclusion.sinMesa};
    final soloBase = {...exclusion.soloBase};
    for (final a in alumnos) {
      if (a.esBajaTemporal || conFijadaAMano.contains(a.id)) continue;
      final texto = a.numeroMesa?.trim() ?? '';
      final tiene = mesasDeHoy(a).length;
      // Un número escrito a mano que no se entiende no se toca.
      if (texto.isNotEmpty && tiene == 0) continue;
      final meta = max(tiene, leTocan[a.id] ?? 0);
      if (meta == 0) continue;
      final contrato = MesasExtraUtils.cantidadMesasFisicasSorteo(a);
      // Al sorteo solo se le puede pedir "la base" o "todas las del contrato".
      // Quien tiene más que las pagas y menos que las del contrato se queda
      // donde está: darle una de menos o una de más sería peor.
      if (meta != 1 && meta != contrato) continue;
      metas[a.id] = meta;
      sinMesa.remove(a.id);
      if (meta == 1 && contrato > 1) {
        soloBase.add(a.id);
      } else {
        soloBase.remove(a.id);
      }
    }
    final porCumplimiento = OrdenPorCumplimiento.de(
      alumnos: alumnos,
      pagos: pagos,
      corteAr: hoyAr,
      rng: Random(semillaDe(eventoId)),
      entran: metas.keys.toSet(),
    );
    final orden = unaMesaPrimero
        ? primeroUnaMesa(porCumplimiento)
        : porCumplimiento;
    if (orden.isEmpty) {
      return const OrdenParaElSorteo.noSePuede(
        'No hay ninguna familia para ubicar.',
      );
    }
    final entran = {for (final p in orden) p.alumno.id};
    final lugares = repartir(
      paso: paso,
      orden: orden,
      mesasDe: metas,
      alFinal: {
        if (adicionalesAlFinal)
          for (final id in entran)
            if (!dejarJuntas.contains(id) &&
                metas[id]! - 1 - juntasConLaPrincipal > 0)
              id: metas[id]! - 1 - juntasConLaPrincipal,
      },
      noUsar: {
        ...config.libres.keys,
        ...aMano.keys,
        if (!usarPasto) ...armado.pasto,
        // Las mesas de quien se queda donde está.
        for (final a in alumnos)
          if (!entran.contains(a.id)) ...mesasDeHoy(a),
      },
      juntasEnLaFila: unaMesaPrimero,
      armado: armado,
    );
    final fijadas = <int, MesaFijada>{...aMano};
    for (final p in orden) {
      for (final n in lugares[p.alumno.id] ?? const <int>[]) {
        fijadas[n] = MesaFijada(
          alumnoId: p.alumno.id,
          motivo: motivo,
          por: por,
          cuando: ahora,
        );
      }
    }
    final frente = OrdenDelPlano(
      prendido: true,
      el: ahora,
      por: por,
      recorrido: recorrido,
      unaMesaPrimero: unaMesaPrimero,
      lugares: [
        for (final p in orden)
          LugarPorOrden(
            alumnoId: p.alumno.id,
            puesto: p.puesto,
            grupo: p.grupo.numero,
            mesas: lugares[p.alumno.id] ?? const [],
            frase: unaMesaPrimero && !_deUnaMesa(p.alumno)
                ? '${p.frase} $fraseConAdicional'
                : p.frase,
          ),
      ],
    );
    var cambian = 0;
    for (final a in alumnos) {
      if (!entran.contains(a.id)) continue;
      final hoy = mesasDeHoy(a).toSet();
      if (hoy.isEmpty) continue;
      final nuevas = (lugares[a.id] ?? const <int>[]).toSet();
      if (hoy.length != nuevas.length || !hoy.containsAll(nuevas)) cambian++;
    }
    return OrdenParaElSorteo._(
      configDelSorteo: config.copyWith(fijadas: fijadas, frente: frente),
      configAGuardar: config.copyWith(fijadas: aMano, frente: frente),
      alumnosDelSorteo: [
        for (final a in alumnos)
          entran.contains(a.id) && mesasDeHoy(a).isNotEmpty
              ? a.copyWith(numeroMesa: '')
              : a,
      ],
      exclusionDelSorteo: ExclusionSorteo(sinMesa: sinMesa, soloBase: soloBase),
      lugares: lugares,
      cambian: cambian,
    );
  }

  /// Lo que se le suma a la oración de una familia con adicional cuando se
  /// sorteó con "Primero las familias de una sola mesa": por qué está detrás
  /// de familias que cumplieron peor.
  static const fraseConAdicional =
      'Tiene mesas adicionales: va después de las familias de una sola mesa.';

  /// Una sola mesa en el contrato: la misma cuenta que
  /// [SorteoConPlano.primerGrupo]. Quien contrató una adicional y no la pagó
  /// va con las que tienen adicional.
  static bool _deUnaMesa(ContratoAlumno a) =>
      MesasExtraUtils.cantidadMesasFisicasSorteo(a) <= 1;

  /// "Primero las familias de una sola mesa" con Cumplimiento debido
  /// (16-nov-2026): primero las de una sola mesa y después las que tienen
  /// adicional, **cada grupo en el orden por cumplimiento de [orden]**. El
  /// puntaje no cambia: solo se parte la lista y se vuelve a numerar el
  /// puesto, así el porqué se lee en el orden en que quedaron.
  static List<PuestoDelOrden> primeroUnaMesa(List<PuestoDelOrden> orden) {
    final partido = [
      for (final p in orden)
        if (_deUnaMesa(p.alumno)) p,
      for (final p in orden)
        if (!_deUnaMesa(p.alumno)) p,
    ];
    return [
      for (var i = 0; i < partido.length; i++)
        PuestoDelOrden(
          alumno: partido[i].alumno,
          puesto: i + 1,
          grupo: partido[i].grupo,
          cumplimiento: partido[i].cumplimiento,
          aMano: partido[i].aMano,
          inicioDelPlan: partido[i].inicioDelPlan,
          planDistinto: partido[i].planDistinto,
          empatadas: partido[i].empatadas,
          corte: partido[i].corte,
        ),
    ];
  }

  /// La entrada del sorteo de siempre con el orden puesto: toda la escuela
  /// junta, sin "hasta qué mesa" ni "lejos" (lo decide el orden).
  static EntradaSorteoPlano entrada(
    OrdenParaElSorteo o, {
    required ArmadoSalon armado,
    bool usarPasto = false,
  }) =>
      EntradaSorteoPlano(
        armado: armado,
        config: o.configDelSorteo!,
        alumnos: o.alumnosDelSorteo,
        exclusion: o.exclusionDelSorteo,
        usarPasto: usarPasto,
      );

  /// Null si el sorteo le dio a cada familia las mesas que le tocaban por
  /// orden. Si no, por qué: ahí no se guarda nada.
  static String? noCumple(OrdenParaElSorteo o, ResultadoSorteoPlano r) {
    for (final e in o.lugares.entries) {
      if (e.value.isEmpty) continue;
      final dadas = (r.asignaciones[e.key] ?? const <int>[]).toSet();
      if (dadas.length != e.value.length || !dadas.containsAll(e.value)) {
        return 'A una familia no le tocó la mesa que le correspondía por orden.';
      }
    }
    return null;
  }
}
