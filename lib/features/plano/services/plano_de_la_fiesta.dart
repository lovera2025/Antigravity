import 'dart:math' as math;

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sillas_reparto.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/reparto_de_sillas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import 'armar_a_medida.dart';
import 'divisiones.dart';
import 'medir_salon.dart';

/// Algo del plano que conviene mirar, dicho en palabras, con la mesa a la que
/// lleva al tocarlo.
class AvisoPlano {
  final String texto;
  final int? mesa;

  /// Hay que resolverlo antes de sortear o de la fiesta. Lo que no es grave
  /// es para tener en cuenta (una mesa con sillas extra que quedó apretada).
  final bool grave;

  const AvisoPlano(this.texto, {this.mesa, this.grave = false});
}

/// Cómo está el salón en una palabra, para el encabezado.
enum SemaforoPlano { entran, revisar, faltan }

/// Todo lo que muestra la pantalla del plano de una fiesta, calculado con los
/// datos del momento: las familias con sus mesas y sillas, lo que mide y lo
/// que no cierra. Nada de esto se guarda.
class PlanoDeLaFiesta {
  final ArmadoSalon armado;
  final ConfigPlano config;
  final EstadoPlano estado;
  final MedidasPlano medidas;

  /// Las mesas que tienen cargadas las familias (la del contrato más las
  /// agregadas), sin las bajas.
  final int mesasNecesarias;

  /// Cuántas entran como mucho en el playón, a la distancia de la fiesta.
  final int capacidadPlayon;
  final SinLugar sinLugar;
  final List<OcupaHoja> ocupa;
  final List<AvisoPlano> avisos;

  const PlanoDeLaFiesta._({
    required this.armado,
    required this.config,
    required this.estado,
    required this.medidas,
    required this.mesasNecesarias,
    required this.capacidadPlayon,
    required this.sinLugar,
    required this.ocupa,
    required this.avisos,
  });

  int get mesasComunes => armado.cantidadComunes;
  int get mesasPasto => armado.cantidadPasto;

  /// Las que faltan aun usando el pasto.
  int get faltan =>
      math.max(0, mesasNecesarias - mesasComunes - mesasPasto);

  /// Entran, pero usando mesas del pasto.
  bool get usaPasto => faltan == 0 && mesasNecesarias > mesasComunes;

  SemaforoPlano get semaforo => faltan > 0
      ? SemaforoPlano.faltan
      : avisos.any((a) => a.grave)
          ? SemaforoPlano.revisar
          : SemaforoPlano.entran;

  /// "Entran las 132", "Faltan 6 mesas", "Hay 2 cosas para revisar".
  String get titular {
    switch (semaforo) {
      case SemaforoPlano.faltan:
        return faltan == 1 ? 'Falta 1 mesa' : 'Faltan $faltan mesas';
      case SemaforoPlano.revisar:
        final n = avisos.where((a) => a.grave).length;
        return n == 1 ? 'Hay 1 cosa para revisar' : 'Hay $n cosas para revisar';
      case SemaforoPlano.entran:
        if (mesasNecesarias == 0) return 'Salón listo';
        return mesasNecesarias == 1
            ? 'Entra la mesa'
            : 'Entran las $mesasNecesarias';
    }
  }

  /// "100 mesas y 20 de pasto · ocupa 31 × 19 m · en el playón entran hasta
  /// 284".
  String get detalle {
    final mesas = mesasPasto > 0
        ? '$mesasComunes mesas y $mesasPasto de pasto'
        : mesasComunes == 1
            ? '1 mesa'
            : '$mesasComunes mesas';
    return [
      mesas,
      if (ocupa.isNotEmpty) 'ocupa ${textoOcupa(ocupa)}',
      'en el playón entran hasta $capacidadPlayon',
    ].join(' · ');
  }

  /// "31 × 19 m", o "31 × 19 m y 31 × 6 m" si son dos hojas.
  static String textoOcupa(List<OcupaHoja> ocupa) => [
        for (final o in ocupa) '${o.anchoM.round()} × ${o.altoM.round()} m',
      ].join(' y ');

  /// Las mesas que la fiesta necesita: las cargadas de cada familia, sin las
  /// bajas. Es para armar el salón, así que no mira lo pagado: una mesa que
  /// hoy está sin pagar puede pagarse antes del sorteo.
  static int mesasQueNecesita(Iterable<ContratoAlumno> alumnos) => alumnos
      .where((a) => !a.esBajaTemporal)
      .fold(0, (s, a) => s + SalonMesas.mesas(a));

  /// Una familia como ocupante del plano: sus mesas y las sillas extra que
  /// van en cada una, según el reparto que rige hoy.
  static OcupantePlano ocupanteDe(ContratoAlumno a, SillasReparto? reparto) {
    final vigente = RepartoDeSillas.vigente(a, reparto);
    return OcupantePlano(
      id: a.id,
      nombre: a.nombreAlumno,
      numeros: MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList()
        ..sort(),
      division: a.cursoDivision,
      sillasExtraPorMesa: {
        for (final (mesa, sillas)
            in SalonMesas.repartoSillas(a, sillasPrincipal: vigente?.principal))
          mesa: sillas,
      },
    );
  }

  /// Las familias que ya tienen mesa. **También las de baja**, que conservan
  /// su lugar: el sorteo no da esa mesa a nadie, así que el plano tiene que
  /// mostrarla ocupada (y avisa para que se libere si no vuelven).
  static List<OcupantePlano> ocupantes(
    Iterable<ContratoAlumno> alumnos,
    Map<String, SillasReparto> repartos,
  ) =>
      [
        for (final a in alumnos)
          if (SalonMesas.tieneNumeros(a)) ocupanteDe(a, repartos[a.id]),
      ];

  factory PlanoDeLaFiesta.desde({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    Map<String, SillasReparto> repartos = const {},
  }) {
    final porId = {for (final a in alumnos) a.id: a};
    final avisos = <AvisoPlano>[];

    // Las fijadas, con la familia para la que son. Una fijada para alguien que
    // ya no está en la fiesta (o está de baja) no se dibuja: se avisa.
    final fijadas = <int, OcupantePlano>{};
    final fijadasSinFamilia = <int>[];
    for (final e in config.fijadas.entries) {
      final a = porId[e.value.alumnoId];
      if (a == null || a.esBajaTemporal) {
        fijadasSinFamilia.add(e.key);
      } else {
        fijadas[e.key] = ocupanteDe(a, repartos[a.id]);
      }
    }

    final estado = EstadoPlano.desde(
      armado: armado,
      ocupantes: ocupantes(alumnos, repartos),
      libres: config.libres.keys.toSet(),
      fijadas: fijadas,
      ordenDivisiones:
          config.ordenDivisiones.isEmpty ? null : config.ordenDivisiones,
    );

    final medidas = config.medidas;
    final necesarias = mesasQueNecesita(alumnos);
    final sinLugar = MedirSalon.revisar(
      armado,
      medidas,
      (n) => estado.info(n).sillasExtra,
    );

    final tiene = armado.mesas.length;
    if (necesarias > tiene) {
      final n = necesarias - tiene;
      avisos.add(AvisoPlano(
        '${n == 1 ? 'Falta 1 mesa' : 'Faltan $n mesas'}: la fiesta necesita '
        '$necesarias y este armado tiene $tiene.',
        grave: true,
      ));
    }

    for (final i in estado.mesas) {
      if (i.estado != EstadoMesa.conflicto) continue;
      final nombres = [for (final o in i.ocupantes) o.apellido];
      final String texto;
      if (nombres.length > 1) {
        texto = 'La mesa ${i.numero} la tienen ${nombres.length} familias: '
            '${nombres.join(', ')}.';
      } else if (i.libre) {
        texto = nombres.isEmpty
            ? 'La mesa ${i.numero} está libre y también fijada para '
                '${i.fijadaPara?.apellido}.'
            : 'La mesa ${i.numero} se dejó libre y la tiene ${nombres.first}.';
      } else {
        texto = 'La mesa ${i.numero} está fijada para '
            '${i.fijadaPara?.apellido} y la tiene ${nombres.first}.';
      }
      avisos.add(AvisoPlano(texto, mesa: i.numero, grave: true));
    }

    for (final f in estado.fueraDelPlano) {
      avisos.add(AvisoPlano(
        '${f.ocupante.apellido} tiene la mesa ${f.numero}, que no está en '
        'este armado.',
        grave: true,
      ));
    }
    for (final f in estado.fijadasFueraDelPlano) {
      avisos.add(AvisoPlano(
        'La mesa ${f.numero} está fijada para ${f.para.apellido}, pero este '
        'armado no la tiene.',
        grave: true,
      ));
    }
    for (final n in fijadasSinFamilia..sort()) {
      avisos.add(AvisoPlano(
        'La mesa $n está fijada para una familia que ya no está en la fiesta.',
        mesa: armado.existe(n) ? n : null,
        grave: true,
      ));
    }
    for (final n in estado.libresFueraDelPlano) {
      avisos.add(AvisoPlano(
        'La mesa $n está marcada como libre, pero este armado no la tiene.',
      ));
    }

    for (final a in alumnos) {
      if (!a.esBajaTemporal || !SalonMesas.tieneNumeros(a)) continue;
      final mesas = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList()
        ..sort();
      avisos.add(AvisoPlano(
        '${a.nombreAlumno.replaceFirst('[BAJA]', '').trim()} está de baja y '
        'conserva ${mesas.length == 1 ? 'la mesa ${mesas.single}' : 'las mesas ${mesas.join(', ')}'}: '
        'si no vuelve, sacásela en Editar alumno.',
        mesa: armado.existe(mesas.first) ? mesas.first : null,
      ));
    }

    for (final problema in armado.problemas()) {
      avisos.add(AvisoPlano(problema, grave: true));
    }

    for (final n in sinLugar.fueraDelHormigon) {
      // Con el círculo de la mesa afuera ya lo dijo `problemas()`.
      if (avisos.any((a) => a.texto.startsWith('La mesa $n queda fuera'))) {
        continue;
      }
      avisos.add(AvisoPlano(
        'La mesa $n queda muy contra el borde del hormigón.',
        mesa: n,
      ));
    }
    // Una mesa con sillas extra aprieta contra todas sus vecinas: es un solo
    // aviso, el de esa mesa, y no uno por vecina.
    final porMesa = <int, List<ParApretado>>{};
    for (final p in sinLugar.apretadas) {
      final sinLugarDelPar = p.sinLugar;
      if (sinLugarDelPar.length == 2) {
        avisos.add(AvisoPlano(
          'Las mesas ${p.a} y ${p.b} están muy juntas: faltan '
          '${_centimetros(p.faltaM)}.',
          mesa: p.a,
        ));
      } else {
        porMesa.putIfAbsent(sinLugarDelPar.single, () => []).add(p);
      }
    }
    for (final mesa in porMesa.keys.toList()..sort()) {
      avisos.add(AvisoPlano(
        _textoApretada(mesa, porMesa[mesa]!, estado),
        mesa: mesa,
      ));
    }

    for (final (a, b) in Divisiones.parecidas(estado.divisiones)) {
      avisos.add(AvisoPlano(
        'Las divisiones "${estado.nombresDivision[a] ?? a}" y '
        '"${estado.nombresDivision[b] ?? b}" se parecen: si son la misma, '
        'corregila en Editar alumno.',
      ));
    }

    return PlanoDeLaFiesta._(
      armado: armado,
      config: config,
      estado: estado,
      medidas: medidas,
      mesasNecesarias: necesarias,
      capacidadPlayon: ArmarAMedida.capacidad(OpcionesAMedida(
        playon: medidas.playon,
        cantidad: 1,
        lugarM: medidas.lugarMesaM,
      )),
      sinLugar: sinLugar,
      ocupa: MedirSalon.ocupa(armado, lugarM: medidas.lugarMesaM),
      avisos: avisos,
    );
  }

  static String _centimetros(double metros) =>
      '${math.max(1, (metros * 100).round())} cm';

  /// "La mesa 12 lleva 10 sillas y queda apretada: le faltan 15 cm." Lo que
  /// falta es contra la vecina que más aprieta; al tocar el aviso se ve cuál.
  static String _textoApretada(
    int mesa,
    List<ParApretado> pares,
    EstadoPlano estado,
  ) {
    final falta = pares.map((p) => p.faltaM).reduce(math.max);
    final sillas = SalonMesas.sillasPorMesa + estado.info(mesa).sillasExtra;
    return 'La mesa $mesa lleva $sillas sillas y queda apretada: le faltan '
        '${_centimetros(falta)}.';
  }
}
