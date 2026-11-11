import '../../../models/contrato_alumno.dart';
import '../../../models/movimiento_mesas.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/salon_mesas.dart';
import '../modelo/armado_salon.dart';
import 'divisiones.dart';
import 'sorteo_con_plano.dart';

/// Un cambio en lo que se configura del plano (fijar una mesa, dejarla libre),
/// ya calculado. Si no se puede, [problema] dice por qué en palabras y [config]
/// es null.
class CambioDeConfig {
  final ConfigPlano? config;
  final String? problema;

  /// Las mesas que tocó.
  final List<int> mesas;

  /// El armado, si el cambio también lo toca (se acomodó el salón, o se
  /// redibujó el borde del hormigón). Null: queda el que está.
  final ArmadoSalon? armado;

  const CambioDeConfig.ok(ConfigPlano this.config, this.mesas, {this.armado})
      : problema = null;
  const CambioDeConfig.noSePuede(String this.problema)
      : config = null,
        mesas = const [],
        armado = null;

  bool get sePuede => problema == null;
}

/// Un cambio en los números de mesa de una o dos familias, ya calculado.
class CambioDeMesas {
  final TipoMovimientoMesas tipo;

  /// Alumno → sus números antes y después ("12, 13").
  final Map<String, String?> antes;
  final Map<String, String?> despues;

  /// Lo que conviene saber antes de confirmar. Queda escrito en el renglón.
  final List<String> avisos;

  /// Alguna de las familias ya retiró sus entradas: hay que avisarle.
  final bool hayQueAvisarALaFamilia;

  /// La configuración del plano si el cambio la toca (una mesa fijada que la
  /// familia deja). Null: no cambia.
  final ConfigPlano? config;

  /// El renglón que se deshace, si es un deshacer.
  final String? deshaceId;
  final String? problema;

  const CambioDeMesas._({
    required this.tipo,
    this.antes = const {},
    this.despues = const {},
    this.avisos = const [],
    this.hayQueAvisarALaFamilia = false,
    this.config,
    this.deshaceId,
    this.problema,
  });

  const CambioDeMesas.noSePuede(TipoMovimientoMesas tipo, String problema)
      : this._(tipo: tipo, problema: problema);

  bool get sePuede => problema == null;

  /// Es el mismo cambio que [otro]: las mismas familias, de las mismas mesas a
  /// las mismas mesas, y sin un "hay que avisarle a la familia" nuevo.
  ///
  /// Entre que se muestra un cambio y se guarda, la otra PC puede haber movido
  /// a una de las familias. Si lo que se va a guardar ya no es lo que se
  /// mostró, no se guarda: se vuelve a mostrar.
  bool esElMismoQue(CambioDeMesas otro) {
    bool iguales(Map<String, String?> a, Map<String, String?> b) =>
        a.length == b.length &&
        a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
    return tipo == otro.tipo &&
        iguales(antes, otro.antes) &&
        iguales(despues, otro.despues) &&
        hayQueAvisarALaFamilia == otro.hayQueAvisarALaFamilia;
  }

  /// "GÓMEZ: 12, 13 → 40, 41", un renglón por familia.
  List<String> renglones(String Function(String alumnoId) apellidoDe) => [
        for (final id in despues.keys)
          '${apellidoDe(id)}: ${_oSinMesa(antes[id])} → '
              '${_oSinMesa(despues[id])}',
      ];

  static String _oSinMesa(String? texto) {
    final t = texto?.trim() ?? '';
    return t.isEmpty ? 'sin mesa' : t;
  }

  /// La mesa que una familia dejó y la que tomó, si cambió **una sola** de
  /// varias. Null: se movió entera, o tiene una sola mesa.
  ({int deja, int toma})? _unaSolaDe(String id) {
    final a = MesasExtraUtils.numerosMesaDesdeTexto(antes[id]);
    final d = MesasExtraUtils.numerosMesaDesdeTexto(despues[id]);
    final salen = a.difference(d);
    final entran = d.difference(a);
    if (salen.length != 1 || entran.length != 1) return null;
    return (deja: salen.single, toma: entran.single);
  }

  bool _tieneVarias(String id) =>
      MesasExtraUtils.numerosMesaDesdeTexto(antes[id]).length > 1;

  /// Lo que se dice cuando el cambio ya quedó guardado.
  String textoHecho(String Function(String alumnoId) apellidoDe) {
    final ids = despues.keys.toList();
    switch (tipo) {
      case TipoMovimientoMesas.intercambio:
        // Cambiaron una sola mesa, y alguna de las dos conserva otras: se
        // dice cuál, porque "cambiaron de lugar" sonaría a la familia entera.
        final una = _unaSolaDe(ids.first);
        if (una != null && ids.any(_tieneVarias)) {
          return '${ids.map(apellidoDe).join(' y ')} cambiaron la '
              '${una.deja} por la ${una.toma}.';
        }
        return '${ids.map(apellidoDe).join(' y ')} cambiaron de lugar.';
      case TipoMovimientoMesas.mover:
        final una = _unaSolaDe(ids.first);
        if (una != null && _tieneVarias(ids.first)) {
          return '${apellidoDe(ids.first)} pasó la ${una.deja} a la '
              '${una.toma}.';
        }
        final mesas = MesasExtraUtils.numerosMesaDesdeTexto(despues[ids.first])
            .toList()
          ..sort();
        return '${apellidoDe(ids.first)} pasó a '
            '${CambiosDeMesa.textoMesas(mesas)}.';
      case TipoMovimientoMesas.deshacer:
        return 'El cambio se deshizo.';
    }
  }

  /// El renglón de `mesas_movimientos` de este cambio.
  MovimientoMesas movimiento({
    required String id,
    required String eventoId,
    required String motivo,
    required String? hechoPor,
    required DateTime ahora,
  }) =>
      MovimientoMesas(
        id: id,
        eventoId: eventoId,
        tipo: tipo,
        antes: antes,
        despues: despues,
        motivo: motivo.trim(),
        deshaceId: deshaceId,
        avisos: avisos,
        hechoPor: hechoPor,
        createdAt: ahora,
      );
}

/// Las reglas para tocar las mesas a mano: fijar y dejar libres antes del
/// sorteo, y cambiar o mover familias después. Todo es cuenta pura: recibe
/// cómo están las cosas y devuelve cómo quedarían, o por qué no se puede.
///
/// Se mueve **la familia entera**, con todas sus mesas juntas ([mover],
/// [intercambiar]), salvo que el jefe elija **una sola de sus mesas**
/// ([moverUna], [intercambiarUna]): un arreglo puntual después del sorteo, como
/// juntar la mesa del sorteo con la que la familia recibió al fondo.
class CambiosDeMesa {
  CambiosDeMesa._();

  /// "GÓMEZ" de "GÓMEZ, SOFÍA".
  static String apellido(ContratoAlumno a) {
    final nombre = a.nombreAlumno.replaceFirst('[BAJA]', '').trim();
    final i = nombre.indexOf(',');
    return (i < 0 ? nombre : nombre.substring(0, i)).trim();
  }

  static List<int> numerosDe(ContratoAlumno a) =>
      MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList()..sort();

  static List<int> _numerosDeTexto(String? texto) =>
      MesasExtraUtils.numerosMesaDesdeTexto(texto).toList()..sort();

  static ContratoAlumno? _alumno(List<ContratoAlumno> alumnos, String id) {
    for (final a in alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Mesa → la familia que la tiene hoy. **También las de baja**, que
  /// conservan su lugar: es la misma regla que usa el sorteo
  /// (`sorteo_con_plano.dart`). Si acá no contaran, se podría fijar o mover a
  /// alguien a una mesa que el sorteo después no da, o dejar dos familias en
  /// la misma mesa cuando la baja se levanta.
  static Map<int, ContratoAlumno> duenios(List<ContratoAlumno> alumnos) {
    final r = <int, ContratoAlumno>{};
    for (final a in alumnos) {
      for (final n in numerosDe(a)) {
        r.putIfAbsent(n, () => a);
      }
    }
    return r;
  }

  /// "La mesa 12 ya la tiene SOSA", o que la conserva alguien de baja.
  static String _ocupadaPor(int mesa, ContratoAlumno otro) => otro.esBajaTemporal
      ? 'La mesa $mesa la conserva ${apellido(otro)}, que está de baja. Si no '
          'vuelve, sacale la mesa en Editar alumno.'
      : 'La mesa $mesa ya la tiene ${apellido(otro)}.';

  /// "la 12", "la 12 y la 13", "la 12, la 13 y la 14".
  static String textoMesas(List<int> mesas) {
    final partes = [for (final n in mesas) 'la $n'];
    if (partes.length <= 1) return partes.join();
    return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
  }

  /// [cantidad] mesas seguidas y pegadas desde [desde], o por qué no las hay.
  static ({List<int>? mesas, String? problema}) tramoDesde(
    ArmadoSalon armado,
    int desde,
    int cantidad,
  ) {
    if (!armado.existe(desde)) {
      return (mesas: null, problema: 'La mesa $desde no está en este armado.');
    }
    final mesas = [for (var i = 0; i < cantidad; i++) desde + i];
    for (var i = 1; i < mesas.length; i++) {
      final n = mesas[i];
      if (!armado.existe(n)) {
        return (
          mesas: null,
          problema: 'Después de la ${n - 1} no hay más mesas: hacen falta '
              '$cantidad seguidas. Elegí otra.',
        );
      }
      if (!armado.pegadas(n - 1, n)) {
        return (
          mesas: null,
          problema: cantidad == 2
              ? 'Desde la $desde no hay 2 mesas pegadas: la ${n - 1} y la $n '
                  'no están juntas. Elegí otra.'
              : 'Desde la $desde no hay $cantidad mesas pegadas: la ${n - 1} '
                  'y la $n no están juntas. Elegí otra.',
        );
      }
    }
    return (mesas: mesas, problema: null);
  }

  // ── Antes del sorteo: fijar y dejar libres ──────────────────────────────

  /// Fija para una familia todas sus mesas, juntas, desde [desdeMesa]. Si ya
  /// tenía otras fijadas, pasan a ser estas.
  static CambioDeConfig fijar({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required String alumnoId,
    required int desdeMesa,
    required String motivo,
    required String? por,
    required DateTime ahora,
  }) {
    final a = _alumno(alumnos, alumnoId);
    if (a == null || a.esBajaTemporal) {
      return const CambioDeConfig.noSePuede(
        'Esa familia ya no está en la fiesta.',
      );
    }
    if (motivo.trim().isEmpty) {
      return const CambioDeConfig.noSePuede(
        'Escribí por qué se le fija la mesa.',
      );
    }
    // Con algo escrito en su mesa, aunque no se entienda, ya tiene: el sorteo
    // no la toca, y fijarle otra dejaría una mesa reservada para nadie.
    if ((a.numeroMesa ?? '').trim().isNotEmpty) {
      return CambioDeConfig.noSePuede(
        numerosDe(a).isEmpty
            ? '${apellido(a)} tiene escrito "${a.numeroMesa!.trim()}" en su '
                'mesa. Corregilo en Editar alumno antes de fijarle una.'
            : '${apellido(a)} ya tiene mesa. Para cambiarla de lugar usá Mover.',
      );
    }
    final tramo = tramoDesde(armado, desdeMesa, SalonMesas.mesas(a));
    final mesas = tramo.mesas;
    if (mesas == null) return CambioDeConfig.noSePuede(tramo.problema!);

    final duenio = duenios(alumnos);
    for (final n in mesas) {
      final otro = duenio[n];
      if (otro != null) {
        return CambioDeConfig.noSePuede(_ocupadaPor(n, otro));
      }
      if (config.libres.containsKey(n)) {
        return CambioDeConfig.noSePuede(
          'La mesa $n se dejó libre a propósito. Volvé a usarla primero.',
        );
      }
      final fijada = config.fijadas[n];
      if (fijada != null && fijada.alumnoId != alumnoId) {
        final para = _alumno(alumnos, fijada.alumnoId);
        return CambioDeConfig.noSePuede(
          'La mesa $n ya está fijada para '
          '${para == null ? 'otra familia' : apellido(para)}.',
        );
      }
    }
    final fijadas = {
      for (final e in config.fijadas.entries)
        if (e.value.alumnoId != alumnoId) e.key: e.value,
      for (final n in mesas)
        n: MesaFijada(
          alumnoId: alumnoId,
          motivo: motivo.trim(),
          por: por,
          cuando: ahora,
        ),
    };
    return CambioDeConfig.ok(config.copyWith(fijadas: fijadas), mesas);
  }

  /// Saca todas las mesas fijadas de una familia.
  static CambioDeConfig quitarFijadas(ConfigPlano config, String alumnoId) {
    final suyas = config.fijadasPorAlumno[alumnoId] ?? const <int>[];
    if (suyas.isEmpty) {
      return const CambioDeConfig.noSePuede(
        'Esa familia ya no tiene mesas fijadas.',
      );
    }
    return CambioDeConfig.ok(
      config.copyWith(fijadas: {
        for (final e in config.fijadas.entries)
          if (e.value.alumnoId != alumnoId) e.key: e.value,
      }),
      suyas,
    );
  }

  /// Saca la fijada de una sola mesa: sirve cuando la familia para la que era
  /// ya no está en la fiesta.
  static CambioDeConfig quitarFijadaDeMesa(ConfigPlano config, int mesa) {
    if (!config.fijadas.containsKey(mesa)) {
      return CambioDeConfig.noSePuede('La mesa $mesa ya no está fijada.');
    }
    return CambioDeConfig.ok(
      config.copyWith(fijadas: {
        for (final e in config.fijadas.entries)
          if (e.key != mesa) e.key: e.value,
      }),
      [mesa],
    );
  }

  /// Deja una mesa sin usar: el sorteo no la da. Solo una mesa vacía y sin
  /// fijar.
  static CambioDeConfig dejarLibre({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required int mesa,
    required String? motivo,
    required String? por,
    required DateTime ahora,
  }) {
    if (!armado.existe(mesa)) {
      return CambioDeConfig.noSePuede('La mesa $mesa no está en este armado.');
    }
    if (config.libres.containsKey(mesa)) {
      return CambioDeConfig.noSePuede('La mesa $mesa ya está libre.');
    }
    final duenio = duenios(alumnos)[mesa];
    if (duenio != null) {
      return CambioDeConfig.noSePuede(
        duenio.esBajaTemporal
            ? _ocupadaPor(mesa, duenio)
            : 'La mesa $mesa la tiene ${apellido(duenio)}. Movela primero a '
                'otra.',
      );
    }
    if (config.fijadas.containsKey(mesa)) {
      return CambioDeConfig.noSePuede(
        'La mesa $mesa está fijada para una familia. Quitá la fijada primero.',
      );
    }
    final texto = motivo?.trim() ?? '';
    return CambioDeConfig.ok(
      config.copyWith(libres: {
        ...config.libres,
        mesa: MesaLibre(
          motivo: texto.isEmpty ? null : texto,
          por: por,
          cuando: ahora,
        ),
      }),
      [mesa],
    );
  }

  /// Cambia por qué está libre una mesa que ya lo está: para quién se reservó
  /// y quiénes se sientan (`ReservaDeMesa`, 6.5.0), o el motivo de que no se
  /// use. Sigue libre: el sorteo no la da.
  static CambioDeConfig cambiarMotivoDeLibre({
    required ConfigPlano config,
    required int mesa,
    required String? motivo,
    required String? por,
    required DateTime ahora,
  }) {
    if (!config.libres.containsKey(mesa)) {
      return CambioDeConfig.noSePuede('La mesa $mesa ya no está libre.');
    }
    final texto = motivo?.trim() ?? '';
    return CambioDeConfig.ok(
      config.copyWith(libres: {
        for (final e in config.libres.entries)
          if (e.key != mesa) e.key: e.value,
        mesa: MesaLibre(
          motivo: texto.isEmpty ? null : texto,
          por: por,
          cuando: ahora,
        ),
      }),
      [mesa],
    );
  }

  /// La mesa vuelve a entrar en el sorteo.
  static CambioDeConfig volverAUsar(ConfigPlano config, int mesa) {
    if (!config.libres.containsKey(mesa)) {
      return CambioDeConfig.noSePuede('La mesa $mesa no estaba libre.');
    }
    return CambioDeConfig.ok(
      config.copyWith(libres: {
        for (final e in config.libres.entries)
          if (e.key != mesa) e.key: e.value,
      }),
      [mesa],
    );
  }

  // ── Después del sorteo: cambiar y mover familias ────────────────────────

  static String _division(ContratoAlumno a) {
    final t = (a.cursoDivision ?? '').trim();
    return t.isEmpty ? Divisiones.sinDivision : t;
  }

  /// Lo que hay que saber de una familia que pasa a [nuevas].
  static List<String> _avisosDe({
    required ContratoAlumno a,
    required List<int> viejas,
    required List<int> nuevas,
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Set<String> yaRetiraron,
  }) {
    final nombre = apellido(a);
    final avisos = <String>[];
    final pasto = armado.pasto;
    if (nuevas.any(pasto.contains) && !viejas.any(pasto.contains)) {
      avisos.add('$nombre pasa a mesas del pasto.');
    }
    final clave = Divisiones.clave(a.cursoDivision);
    for (final b in config.bloques) {
      if (b.division != clave) continue;
      if (nuevas.any((n) => !b.contiene(n))) {
        avisos.add(
          '$nombre queda fuera del bloque de ${_division(a)} (mesas '
          '${b.texto(a: ' a ')}).',
        );
      }
    }
    if (yaRetiraron.contains(a.id)) {
      avisos.add(
        '$nombre ya retiró sus entradas: hay que avisarle y reimprimir la '
        'planilla de entrega.',
      );
    }
    if (SalonMesas.sillasExtra(a) > 0) {
      avisos.add('Las sillas extra de $nombre van a sus mesas nuevas.');
    }
    if (config.fijadasPorAlumno.containsKey(a.id)) {
      avisos.add(
        '$nombre tenía mesas fijadas: pasan a ser las nuevas, con el mismo '
        'motivo.',
      );
    }
    return avisos;
  }

  /// La configuración con las fijadas de cada familia pasadas a sus mesas
  /// nuevas ([nuevas]: alumno → mesas), con el mismo motivo, quién y cuándo.
  /// Null si ninguna tenía fijadas.
  ///
  /// La fijada existe para que un sorteo nuevo le vuelva a dar su lugar a la
  /// familia. Si se la mueve con motivo, su lugar pasa a ser el nuevo; y si el
  /// cambio se deshace, vuelve al de antes. Sacarla sin más hacía que, después
  /// de mover y deshacer, la familia quedara sin su fijada.
  static ConfigPlano? _fijadasQueSiguen(
    ConfigPlano config,
    Map<String, List<int>> nuevas,
  ) {
    final porFamilia = config.fijadasPorAlumno;
    if (!nuevas.keys.any(porFamilia.containsKey)) return null;
    final fijadas = {
      for (final e in config.fijadas.entries)
        if (!nuevas.containsKey(e.value.alumnoId)) e.key: e.value,
    };
    for (final e in nuevas.entries) {
      final viejas = porFamilia[e.key];
      if (viejas == null || viejas.isEmpty) continue;
      final dato = config.fijadas[viejas.first]!;
      for (final n in e.value) {
        // Una mesa que ya es fijada de otra familia no se pisa.
        fijadas.putIfAbsent(n, () => dato);
      }
    }
    return config.copyWith(fijadas: fijadas);
  }

  /// Dos familias con la misma cantidad de mesas cambian de lugar.
  static CambioDeMesas intercambiar({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required String alumnoId,
    required String otroId,
    Set<String> yaRetiraron = const {},
  }) {
    const tipo = TipoMovimientoMesas.intercambio;
    final a = _alumno(alumnos, alumnoId);
    final b = _alumno(alumnos, otroId);
    if (a == null || b == null) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Una de las familias ya no está en la fiesta.',
      );
    }
    if (a.esBajaTemporal || b.esBajaTemporal) {
      final baja = a.esBajaTemporal ? a : b;
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(baja)} está de baja: no se la cambia de lugar. Si no '
        'vuelve, sacale la mesa en Editar alumno.',
      );
    }
    if (a.id == b.id) {
      return const CambioDeMesas.noSePuede(tipo, 'Elegí otra familia.');
    }
    final deA = numerosDe(a);
    final deB = numerosDe(b);
    if (deA.isEmpty || deB.isEmpty) {
      final sin = deA.isEmpty ? a : b;
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(sin)} todavía no tiene mesa.',
      );
    }
    if (deA.length != deB.length) {
      String cuantas(List<int> l) => l.length == 1 ? '1 mesa' : '${l.length} mesas';
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(a)} tiene ${cuantas(deA)} y ${apellido(b)} tiene '
        '${cuantas(deB)}: para cambiar tienen que tener la misma cantidad. '
        'Usá Mover.',
      );
    }
    final avisos = <String>[
      if (Divisiones.clave(a.cursoDivision) != Divisiones.clave(b.cursoDivision))
        'Son de divisiones distintas: ${_division(a)} y ${_division(b)}.',
      ..._avisosDe(
        a: a,
        viejas: deA,
        nuevas: deB,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
      ..._avisosDe(
        a: b,
        viejas: deB,
        nuevas: deA,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
    ];
    return CambioDeMesas._(
      tipo: tipo,
      antes: {
        a.id: MesasExtraUtils.formatearAsignacionMesas(deA),
        b.id: MesasExtraUtils.formatearAsignacionMesas(deB),
      },
      despues: {
        a.id: MesasExtraUtils.formatearAsignacionMesas(deB),
        b.id: MesasExtraUtils.formatearAsignacionMesas(deA),
      },
      avisos: avisos,
      hayQueAvisarALaFamilia:
          yaRetiraron.contains(a.id) || yaRetiraron.contains(b.id),
      config: _fijadasQueSiguen(config, {a.id: deB, b.id: deA}),
    );
  }

  /// Una familia pasa, con todas sus mesas, a mesas libres seguidas desde
  /// [desdeMesa].
  static CambioDeMesas mover({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required String alumnoId,
    required int desdeMesa,
    Set<String> yaRetiraron = const {},
  }) {
    const tipo = TipoMovimientoMesas.mover;
    final a = _alumno(alumnos, alumnoId);
    if (a == null || a.esBajaTemporal) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Esa familia ya no está en la fiesta.',
      );
    }
    final viejas = numerosDe(a);
    if (viejas.isEmpty) {
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(a)} todavía no tiene mesa.',
      );
    }
    final tramo = tramoDesde(armado, desdeMesa, viejas.length);
    final nuevas = tramo.mesas;
    if (nuevas == null) return CambioDeMesas.noSePuede(tipo, tramo.problema!);
    if (nuevas.length == viejas.length &&
        nuevas.toSet().containsAll(viejas)) {
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(a)} ya está en ${viejas.length == 1 ? 'esa mesa' : 'esas mesas'}.',
      );
    }
    final duenio = duenios(alumnos);
    for (final n in nuevas) {
      final otro = duenio[n];
      if (otro != null && otro.id != a.id) {
        return CambioDeMesas.noSePuede(
          tipo,
          otro.esBajaTemporal
              ? _ocupadaPor(n, otro)
              : 'La mesa $n es de ${apellido(otro)}. Para cambiar de lugar '
                  'con esa familia usá Cambiar.',
        );
      }
      if (config.libres.containsKey(n)) {
        return CambioDeMesas.noSePuede(
          tipo,
          'La mesa $n se dejó libre a propósito. Volvé a usarla primero.',
        );
      }
      final fijada = config.fijadas[n];
      if (fijada != null && fijada.alumnoId != a.id) {
        final para = _alumno(alumnos, fijada.alumnoId);
        return CambioDeMesas.noSePuede(
          tipo,
          'La mesa $n está fijada para '
          '${para == null ? 'otra familia' : apellido(para)}.',
        );
      }
    }
    return CambioDeMesas._(
      tipo: tipo,
      antes: {a.id: MesasExtraUtils.formatearAsignacionMesas(viejas)},
      despues: {a.id: MesasExtraUtils.formatearAsignacionMesas(nuevas)},
      avisos: _avisosDe(
        a: a,
        viejas: viejas,
        nuevas: nuevas,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
      hayQueAvisarALaFamilia: yaRetiraron.contains(a.id),
      config: _fijadasQueSiguen(config, {a.id: nuevas}),
    );
  }

  // ── Una sola mesa de la familia ─────────────────────────────────────────

  /// Las mesas forman un solo grupo en el salón: de cualquiera se llega a
  /// cualquier otra pasando por mesas pegadas de la misma familia. Dos mesas
  /// pueden tocarse sin tener números seguidos (una en cada fila).
  static bool _unidasEnElSalon(ArmadoSalon armado, List<int> mesas) {
    if (mesas.length < 2) return true;
    final vistas = <int>{mesas.first};
    final cola = [mesas.first];
    while (cola.isNotEmpty) {
      final n = cola.removeLast();
      for (final m in mesas) {
        if (!vistas.contains(m) && armado.pegadas(n, m)) {
          vistas.add(m);
          cola.add(m);
        }
      }
    }
    return vistas.length == mesas.length;
  }

  /// Lo que hay que saber de una familia que cambia **una sola** de sus
  /// mesas: deja [deja] y toma [toma]. Las demás quedan donde están.
  static List<String> _avisosDeUna({
    required ContratoAlumno a,
    required List<int> viejas,
    required List<int> nuevas,
    required int deja,
    required int toma,
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Set<String> yaRetiraron,
  }) {
    final nombre = apellido(a);
    final avisos = <String>[];
    final pasto = armado.pasto;
    if (pasto.contains(toma) && !pasto.contains(deja)) {
      avisos.add('La $toma es una mesa del pasto.');
    }
    final clave = Divisiones.clave(a.cursoDivision);
    for (final b in config.bloques) {
      if (b.division != clave) continue;
      if (!b.contiene(toma)) {
        avisos.add(
          'La $toma queda fuera del bloque de ${_division(a)} (mesas '
          '${b.texto(a: ' a ')}).',
        );
      }
    }
    if (yaRetiraron.contains(a.id)) {
      avisos.add(
        '$nombre ya retiró sus entradas: hay que avisarle y reimprimir la '
        'planilla de entrega.',
      );
    }
    if (SalonMesas.sillasExtra(a) > 0) {
      avisos.add(
        'Las sillas extra de $nombre siguen a sus mesas: mirá cómo queda el '
        'reparto.',
      );
    }
    if (config.fijadas[deja]?.alumnoId == a.id) {
      avisos.add(
        'La $deja estaba fijada para $nombre: la fijada pasa a la $toma, con '
        'el mismo motivo.',
      );
    }
    // Juntas o separadas, medido como lo dibuja el plano (`tramosPegados`).
    if (nuevas.length > 1) {
      final juntas = SorteoConPlano.tramosPegados(armado, nuevas).length == 1;
      final antes = SorteoConPlano.tramosPegados(armado, viejas).length == 1;
      if (juntas) {
        if (!antes) avisos.add('$nombre queda con sus mesas juntas.');
      } else if (_unidasEnElSalon(armado, nuevas)) {
        avisos.add(
          '$nombre queda con sus mesas pegadas en el salón '
          '(${textoMesas(nuevas)}), aunque los números no son seguidos.',
        );
      } else {
        avisos.add(
          '$nombre ${antes ? 'queda' : 'sigue'} con sus mesas separadas: '
          '${textoMesas(nuevas)}.',
        );
      }
    }
    return avisos;
  }

  /// La configuración con las fijadas pasadas **mesa por mesa**: [cambios]
  /// dice, para cada familia, qué mesa deja y a cuál pasa. Solo se mueve la
  /// fijada de una mesa que era de esa familia; las demás quedan donde están.
  /// Null si ninguna de las mesas que se dejan estaba fijada.
  static ConfigPlano? _fijadasMesaPorMesa(
    ConfigPlano config,
    Map<String, Map<int, int>> cambios,
  ) {
    final quitar = <int>{};
    final poner = <int, MesaFijada>{};
    for (final familia in cambios.entries) {
      for (final c in familia.value.entries) {
        final dato = config.fijadas[c.key];
        if (dato == null || dato.alumnoId != familia.key) continue;
        quitar.add(c.key);
        poner[c.value] = dato;
      }
    }
    if (quitar.isEmpty) return null;
    final fijadas = {
      for (final e in config.fijadas.entries)
        if (!quitar.contains(e.key)) e.key: e.value,
    };
    for (final e in poner.entries) {
      // Una mesa que sigue siendo fijada de otra familia no se pisa.
      fijadas.putIfAbsent(e.key, () => e.value);
    }
    return config.copyWith(fijadas: fijadas);
  }

  /// Una familia pasa **una sola de sus mesas** ([mesa]) a una mesa vacía
  /// ([aMesa]). Las otras quedan donde están: sirve para juntarla con la que
  /// recibió después del sorteo, o para correr una sola.
  static CambioDeMesas moverUna({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required String alumnoId,
    required int mesa,
    required int aMesa,
    Set<String> yaRetiraron = const {},
  }) {
    const tipo = TipoMovimientoMesas.mover;
    final a = _alumno(alumnos, alumnoId);
    if (a == null || a.esBajaTemporal) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Esa familia ya no está en la fiesta.',
      );
    }
    final viejas = numerosDe(a);
    if (!viejas.contains(mesa)) {
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(a)} ya no tiene la mesa $mesa.',
      );
    }
    if (!armado.existe(aMesa)) {
      return CambioDeMesas.noSePuede(
        tipo,
        'La mesa $aMesa no está en este armado.',
      );
    }
    if (viejas.contains(aMesa)) {
      return CambioDeMesas.noSePuede(
        tipo,
        'La mesa $aMesa ya es de ${apellido(a)}: tocá otra.',
      );
    }
    final otro = duenios(alumnos)[aMesa];
    if (otro != null) {
      return CambioDeMesas.noSePuede(
        tipo,
        otro.esBajaTemporal
            ? _ocupadaPor(aMesa, otro)
            : 'La mesa $aMesa es de ${apellido(otro)}.',
      );
    }
    if (config.libres.containsKey(aMesa)) {
      return CambioDeMesas.noSePuede(
        tipo,
        'La mesa $aMesa se dejó libre a propósito. Volvé a usarla primero.',
      );
    }
    final fijada = config.fijadas[aMesa];
    if (fijada != null && fijada.alumnoId != a.id) {
      final para = _alumno(alumnos, fijada.alumnoId);
      return CambioDeMesas.noSePuede(
        tipo,
        'La mesa $aMesa está fijada para '
        '${para == null ? 'otra familia' : apellido(para)}.',
      );
    }
    final nuevas = [
      for (final n in viejas)
        if (n != mesa) n,
      aMesa,
    ]..sort();
    return CambioDeMesas._(
      tipo: tipo,
      antes: {a.id: MesasExtraUtils.formatearAsignacionMesas(viejas)},
      despues: {a.id: MesasExtraUtils.formatearAsignacionMesas(nuevas)},
      avisos: _avisosDeUna(
        a: a,
        viejas: viejas,
        nuevas: nuevas,
        deja: mesa,
        toma: aMesa,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
      hayQueAvisarALaFamilia: yaRetiraron.contains(a.id),
      config: _fijadasMesaPorMesa(config, {
        a.id: {mesa: aMesa},
      }),
    );
  }

  /// Dos familias cambian **una mesa por otra**: la [mesa] de una por
  /// [otraMesa], que es de otra familia. Cada una conserva las demás, así que
  /// no hace falta que tengan la misma cantidad.
  static CambioDeMesas intercambiarUna({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required List<ContratoAlumno> alumnos,
    required String alumnoId,
    required int mesa,
    required int otraMesa,
    Set<String> yaRetiraron = const {},
  }) {
    const tipo = TipoMovimientoMesas.intercambio;
    final a = _alumno(alumnos, alumnoId);
    if (a == null) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Una de las familias ya no está en la fiesta.',
      );
    }
    final deA = numerosDe(a);
    if (!deA.contains(mesa)) {
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(a)} ya no tiene la mesa $mesa.',
      );
    }
    final b = duenios(alumnos)[otraMesa];
    if (b == null) {
      return CambioDeMesas.noSePuede(
        tipo,
        'En la mesa $otraMesa no hay ninguna familia.',
      );
    }
    if (b.id == a.id) {
      return CambioDeMesas.noSePuede(
        tipo,
        'La mesa $otraMesa también es de ${apellido(a)}: tocá la de otra '
        'familia.',
      );
    }
    if (a.esBajaTemporal || b.esBajaTemporal) {
      final baja = a.esBajaTemporal ? a : b;
      return CambioDeMesas.noSePuede(
        tipo,
        '${apellido(baja)} está de baja: no se la cambia de lugar. Si no '
        'vuelve, sacale la mesa en Editar alumno.',
      );
    }
    final deB = numerosDe(b);
    final nuevasA = [
      for (final n in deA)
        if (n != mesa) n,
      otraMesa,
    ]..sort();
    final nuevasB = [
      for (final n in deB)
        if (n != otraMesa) n,
      mesa,
    ]..sort();
    final avisos = <String>[
      if (Divisiones.clave(a.cursoDivision) != Divisiones.clave(b.cursoDivision))
        'Son de divisiones distintas: ${_division(a)} y ${_division(b)}.',
      ..._avisosDeUna(
        a: a,
        viejas: deA,
        nuevas: nuevasA,
        deja: mesa,
        toma: otraMesa,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
      ..._avisosDeUna(
        a: b,
        viejas: deB,
        nuevas: nuevasB,
        deja: otraMesa,
        toma: mesa,
        armado: armado,
        config: config,
        yaRetiraron: yaRetiraron,
      ),
    ];
    return CambioDeMesas._(
      tipo: tipo,
      antes: {
        a.id: MesasExtraUtils.formatearAsignacionMesas(deA),
        b.id: MesasExtraUtils.formatearAsignacionMesas(deB),
      },
      despues: {
        a.id: MesasExtraUtils.formatearAsignacionMesas(nuevasA),
        b.id: MesasExtraUtils.formatearAsignacionMesas(nuevasB),
      },
      avisos: avisos,
      hayQueAvisarALaFamilia:
          yaRetiraron.contains(a.id) || yaRetiraron.contains(b.id),
      config: _fijadasMesaPorMesa(config, {
        a.id: {mesa: otraMesa},
        b.id: {otraMesa: mesa},
      }),
    );
  }

  /// Vuelve atrás un cambio, solo si nada cambió después: las familias siguen
  /// donde las dejó, y las mesas a las que vuelven no las tomó otra.
  static CambioDeMesas deshacer({
    required MovimientoMesas movimiento,
    required List<MovimientoMesas> movimientos,
    required List<ContratoAlumno> alumnos,
    ConfigPlano config = ConfigPlano.vacia,
    Set<String> yaRetiraron = const {},
  }) {
    const tipo = TipoMovimientoMesas.deshacer;
    if (movimiento.tipo == TipoMovimientoMesas.deshacer) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Esto ya es un deshacer. Si hace falta, hacé el cambio de nuevo.',
      );
    }
    if (movimientos.any((m) => m.deshaceId == movimiento.id)) {
      return const CambioDeMesas.noSePuede(tipo, 'Este cambio ya se deshizo.');
    }
    final involucrados = movimiento.despues.keys.toSet();
    // Un renglón que no dice a dónde fue cada familia, o que no nombra a las
    // mismas antes y después, no se puede volver atrás a ciegas.
    if (involucrados.isEmpty ||
        involucrados.length != movimiento.antes.length ||
        !involucrados.containsAll(movimiento.antes.keys)) {
      return const CambioDeMesas.noSePuede(
        tipo,
        'Este renglón no se puede leer entero: no se deshace.',
      );
    }
    for (final e in movimiento.despues.entries) {
      final a = _alumno(alumnos, e.key);
      if (a == null || a.esBajaTemporal) {
        return const CambioDeMesas.noSePuede(
          tipo,
          'Una de las familias ya no está en la fiesta.',
        );
      }
      final hoy = numerosDe(a);
      final dejo = _numerosDeTexto(e.value);
      if (hoy.length != dejo.length || !hoy.toSet().containsAll(dejo)) {
        return CambioDeMesas.noSePuede(
          tipo,
          'Las mesas de ${apellido(a)} cambiaron después de este cambio: ya '
          'no se puede deshacer.',
        );
      }
    }
    final duenio = duenios(alumnos);
    for (final e in movimiento.antes.entries) {
      for (final n in _numerosDeTexto(e.value)) {
        final otro = duenio[n];
        if (otro != null && !involucrados.contains(otro.id)) {
          return CambioDeMesas.noSePuede(
            tipo,
            'La mesa $n ahora es de ${apellido(otro)}: ya no se puede '
            'deshacer.',
          );
        }
        // Lo mismo que no deja hacer Mover: una mesa que después se dejó
        // libre, o que se fijó para otra familia.
        if (config.libres.containsKey(n)) {
          return CambioDeMesas.noSePuede(
            tipo,
            'La mesa $n se dejó libre después de este cambio: ya no se puede '
            'deshacer.',
          );
        }
        final fijada = config.fijadas[n];
        if (fijada != null && !involucrados.contains(fijada.alumnoId)) {
          return CambioDeMesas.noSePuede(
            tipo,
            'La mesa $n se fijó para otra familia después de este cambio: ya '
            'no se puede deshacer.',
          );
        }
      }
    }
    final avisos = <String>[
      for (final id in involucrados)
        if (yaRetiraron.contains(id))
          '${apellido(_alumno(alumnos, id)!)} ya retiró sus entradas: hay que '
              'avisarle y reimprimir la planilla de entrega.',
    ];
    // Si alguna familia conservó una mesa, el cambio fue de una sola: sus
    // fijadas vuelven mesa por mesa. Pasarlas todas a todas dejaría fijada
    // una mesa que nunca lo fue (la del sorteo, al lado de la del fondo).
    var deUnaSola = false;
    final vuelven = <String, Map<int, int>>{};
    for (final e in movimiento.antes.entries) {
      final antes = _numerosDeTexto(e.value).toSet();
      final hoy = _numerosDeTexto(movimiento.despues[e.key]).toSet();
      if (antes.intersection(hoy).isNotEmpty) deUnaSola = true;
      final salen = hoy.difference(antes).toList()..sort();
      final entran = antes.difference(hoy).toList()..sort();
      vuelven[e.key] = {
        for (var i = 0; i < salen.length && i < entran.length; i++)
          salen[i]: entran[i],
      };
    }
    return CambioDeMesas._(
      tipo: tipo,
      antes: movimiento.despues,
      despues: movimiento.antes,
      avisos: avisos,
      hayQueAvisarALaFamilia: avisos.isNotEmpty,
      // Las fijadas que siguieron a la familia vuelven con ella.
      config: deUnaSola
          ? _fijadasMesaPorMesa(config, vuelven)
          : _fijadasQueSiguen(config, {
              for (final e in movimiento.antes.entries)
                e.key: _numerosDeTexto(e.value),
            }),
      deshaceId: movimiento.id,
    );
  }
}
