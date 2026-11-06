import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/silla_puerta.dart';
import '../../../models/sillas_reparto.dart';
import '../../eventos/services/reparto_de_sillas.dart';
import '../../eventos/services/salon_mesas.dart';

/// Las sillas que se suman la noche de la fiesta, en la puerta (6.4.0).
///
/// Desde que empiezan los sorteos una silla extra se pide solo esa noche, ya
/// sentados: la recepcionista ve si la familia puede agregar, la manda a la caja
/// de la barra (que la cobra y le da un vale) y anota la silla con el número del
/// vale (`SillaPuerta`). Esa noche no se piden mesas: la silla va siempre a una
/// mesa que la familia ya tiene.
///
/// Sin pantalla ni base. **Las sumadas no entran en `SalonMesas.sillasExtra` ni en
/// `RepartoDeSillas`**: el sorteo, la planilla, el retiro de entradas y el plano
/// siguen con lo del contrato.

/// Cómo está una mesa de la familia esa noche.
enum EstadoMesaPuerta {
  /// Todavía entra alguna silla más.
  conLugar,

  /// Ya tiene las 2 extra.
  llena,

  /// Tiene más de las que entran (dos notebooks sumaron a la vez, o una silla
  /// quedó en una mesa que ya no es de la familia): hay que mirarla.
  revisar,
}

/// Una mesa de la familia, con sus sillas del contrato y las sumadas esa noche.
class SillasDeUnaMesa {
  final int numero;

  /// La primera de la familia: la de la base. Las demás son adicionales.
  final bool esPrincipal;

  /// Las extra que le tocan del contrato, con el reparto que eligió la familia.
  final int extraDelContrato;

  /// Las vigentes que se sumaron esa noche en la puerta.
  final int sumadas;

  /// Una silla sumada a una mesa que ya no es de la familia (se la cambió de
  /// mesa después de anotarla).
  final bool fueraDeSusMesas;

  const SillasDeUnaMesa({
    required this.numero,
    required this.esPrincipal,
    required this.extraDelContrato,
    required this.sumadas,
    this.fueraDeSusMesas = false,
  });

  static const int tope = SalonMesas.maxSillasExtraPorMesa;

  int get extra => extraDelContrato + sumadas;

  /// Cuántas más entran en esta mesa.
  int get lugar => fueraDeSusMesas ? 0 : max(0, tope - extra);

  bool get puedeAgregar => lugar > 0;

  int get deMas => max(0, extra - tope);

  EstadoMesaPuerta get estado {
    if (fueraDeSusMesas || deMas > 0) return EstadoMesaPuerta.revisar;
    return puedeAgregar ? EstadoMesaPuerta.conLugar : EstadoMesaPuerta.llena;
  }

  /// "Mesa 12: 8 sillas + 1 extra · puede agregar 1 más · se cobran en la barra"
  /// · "Mesa adicional 13: 8 sillas · puede agregar hasta 2 · se cobran en la
  /// barra" · "Mesa 12: 8 sillas + 2 extra (1 esta noche) · ya no puede agregar"
  /// · "Mesa 12: 8 sillas + 3 extra (2 esta noche) · 1 de más: revisar".
  String get texto {
    if (fueraDeSusMesas) {
      return 'Mesa $numero: ${_sillas(sumadas)} sumada${sumadas == 1 ? '' : 's'} '
          'esta noche, pero ya no es de la familia: revisar';
    }
    final b = StringBuffer(esPrincipal ? 'Mesa $numero' : 'Mesa adicional $numero')
      ..write(': ${SalonMesas.sillasPorMesa} sillas');
    if (extra > 0) b.write(' + $extra extra');
    if (sumadas > 0) b.write(' ($sumadas esta noche)');
    if (deMas > 0) {
      b.write(' · $deMas de más: revisar');
    } else if (!puedeAgregar) {
      b.write(' · ya no puede agregar');
    } else if (extra == 0) {
      b.write(' · puede agregar hasta $lugar · se cobran en la barra');
    } else {
      b.write(' · puede agregar $lugar más · se cobran en la barra');
    }
    return b.toString();
  }

  static String _sillas(int n) => n == 1 ? '1 silla' : '$n sillas';

  Map<String, Object?> toJson() => {
        'numero': numero,
        'principal': esPrincipal,
        'contrato': extraDelContrato,
        'sumadas': sumadas,
        if (fueraDeSusMesas) 'fuera': true,
      };

  static SillasDeUnaMesa? fromJson(Object? json) {
    if (json is! Map) return null;
    final numero = json['numero'];
    if (numero is! int) return null;
    int entero(Object? v) => v is int ? v : 0;
    return SillasDeUnaMesa(
      numero: numero,
      esPrincipal: json['principal'] == true,
      extraDelContrato: entero(json['contrato']),
      sumadas: entero(json['sumadas']),
      fueraDeSusMesas: json['fuera'] == true,
    );
  }
}

/// Las mesas de una familia esa noche.
class SillasDeLaFamilia {
  final List<SillasDeUnaMesa> mesas;

  const SillasDeLaFamilia(this.mesas);

  static const nada = SillasDeLaFamilia([]);

  /// Las de [a] (sus mesas sorteadas), con el reparto del contrato como lo eligió
  /// la familia ([guardado], o el de siempre mientras no eligió) y cada silla de
  /// [sumadasVigentes] en la mesa que dice su fila. Sin mesa, ninguna.
  factory SillasDeLaFamilia.de(
    ContratoAlumno a,
    SillasReparto? guardado,
    Iterable<SillaPuerta> sumadasVigentes,
  ) {
    final numeros = SalonMesas.tieneNumeros(a)
        ? [for (final t in SalonMesas.tramos(a)) ...t]
        : const <int>[];
    final principal = RepartoDeSillas.vigente(a, guardado)?.principal;
    final delContrato = {
      for (final (mesa, sillas)
          in SalonMesas.repartoSillas(a, sillasPrincipal: principal))
        mesa: sillas,
    };
    final sumadas = <int, int>{};
    for (final s in sumadasVigentes) {
      if (!s.vigente || s.contratoAlumnoId != a.id) continue;
      sumadas[s.mesa] = (sumadas[s.mesa] ?? 0) + s.cantidad;
    }
    return SillasDeLaFamilia([
      for (var i = 0; i < numeros.length; i++)
        SillasDeUnaMesa(
          numero: numeros[i],
          esPrincipal: i == 0,
          extraDelContrato: delContrato[numeros[i]] ?? 0,
          sumadas: sumadas[numeros[i]] ?? 0,
        ),
      for (final e in sumadas.entries)
        if (!numeros.contains(e.key))
          SillasDeUnaMesa(
            numero: e.key,
            esPrincipal: false,
            extraDelContrato: 0,
            sumadas: e.value,
            fueraDeSusMesas: true,
          ),
    ]);
  }

  bool get vacia => mesas.isEmpty;

  /// Si entra alguna silla más en alguna de sus mesas.
  bool get puedeAgregar => mesas.any((m) => m.puedeAgregar);

  /// Cuántas más entran entre todas sus mesas.
  int get lugar => mesas.fold(0, (s, m) => s + m.lugar);

  /// Dónde va la próxima: [preferida] si tiene lugar, si no la primera con lugar
  /// (la principal antes). Null si no entra ninguna más.
  SillasDeUnaMesa? mesaConLugar({int? preferida}) {
    final elegida =
        mesas.where((m) => m.numero == preferida && m.puedeAgregar).firstOrNull;
    return elegida ?? mesas.where((m) => m.puedeAgregar).firstOrNull;
  }

  SillasDeUnaMesa? mesa(int numero) =>
      mesas.where((m) => m.numero == numero && !m.fueraDeSusMesas).firstOrNull;
}

/// Lo que se sumó esa noche en todo el evento: lo que se compara con las "Silla
/// extra" vendidas en la barra. Las quitadas no cuentan, pero se dicen aparte.
class ConteoDeLaNoche {
  final int sumadas;

  /// Los vales de las vigentes, en el orden en que se anotaron.
  final List<String> vales;
  final int quitadas;

  const ConteoDeLaNoche({
    required this.sumadas,
    required this.vales,
    required this.quitadas,
  });

  factory ConteoDeLaNoche.de(Iterable<SillaPuerta> todas) {
    final ordenadas = [...todas]
      ..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    final vigentes = ordenadas.where((s) => s.vigente);
    return ConteoDeLaNoche(
      sumadas: vigentes.fold(0, (s, x) => s + x.cantidad),
      vales: [for (final s in vigentes) s.vale],
      quitadas: ordenadas.where((s) => !s.vigente).length,
    );
  }

  bool get vacio => sumadas == 0 && quitadas == 0;

  /// "Esta noche: 4 sillas sumadas · vales 0012, 0015, 0021, 0030 · 1 quitada".
  /// Null si no hubo nada.
  String? get texto {
    if (vacio) return null;
    final partes = <String>[
      switch (sumadas) {
        0 => 'ninguna silla sumada',
        1 => '1 silla sumada',
        _ => '$sumadas sillas sumadas',
      },
      if (vales.length == 1) 'vale ${vales.single}',
      if (vales.length > 1) 'vales ${vales.join(', ')}',
      if (quitadas == 1) '1 quitada',
      if (quitadas > 1) '$quitadas quitadas',
    ];
    return 'Esta noche: ${partes.join(' · ')}';
  }

  Map<String, Object?> toJson() =>
      {'sumadas': sumadas, 'vales': vales, 'quitadas': quitadas};

  static ConteoDeLaNoche? fromJson(Object? json) {
    if (json is! Map) return null;
    final vales = json['vales'];
    return ConteoDeLaNoche(
      sumadas: json['sumadas'] is int ? json['sumadas'] as int : 0,
      vales: vales is List ? [for (final v in vales) '$v'] : const [],
      quitadas: json['quitadas'] is int ? json['quitadas'] as int : 0,
    );
  }
}

/// "+1 silla · mesa 12 · vale 0012 · Pato 23:05".
String textoSillaSumada(SillaPuerta s) {
  final partes = [
    s.cantidad == 1 ? '+1 silla' : '+${s.cantidad} sillas',
    'mesa ${s.mesa}',
    'vale ${s.vale}',
    [
      if (s.anotadoPor != null) s.anotadoPor!,
      _hora(s.createdAt),
    ].join(' '),
    if (s.nota != null) s.nota!,
  ];
  return partes.join(' · ');
}

/// "quitada por Pato 23:20: devolvieron el vale". Null si sigue vigente.
String? textoSillaQuitada(SillaPuerta s) {
  final cuando = s.quitadaAt;
  if (cuando == null) return null;
  final quien = s.quitadaPor == null ? '' : ' por ${s.quitadaPor}';
  final motivo = s.quitadaMotivo == null ? '' : ': ${s.quitadaMotivo}';
  return 'quitada$quien ${_hora(cuando)}$motivo';
}

/// "23:05", en la hora de esta PC.
String _hora(DateTime t) {
  final h = t.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(h.hour)}:${dos(h.minute)}';
}
