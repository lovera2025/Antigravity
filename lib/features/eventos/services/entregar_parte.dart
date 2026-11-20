import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import '../../../models/entrega_entradas.dart';
import 'entrega_por_partes.dart';
import 'retiro_entradas.dart';

/// Lo que quien atiende eligió entregar de **una parte**: lo que vio en el
/// diálogo y quién se lo lleva.
class DatosDeLaParte {
  final ParteEntrega parte;

  /// Cuántas mostró el diálogo. Si al guardar la cuenta dice otra cosa, no se
  /// guarda: se entregó lo que se vio.
  final int cantidad;

  /// Los números de las generales, si vienen numeradas. Opcionales. Las
  /// pulseras van sin número.
  final List<TramoTalonario> tramos;

  final int menores10;
  final ParentescoRetiro parentesco;
  final String nombre;

  /// Solo para "otra persona": por qué no viene un familiar directo.
  final String motivo;
  final bool autorizacionFirmada;
  final bool escribioEnPlanilla;

  const DatosDeLaParte({
    required this.parte,
    required this.cantidad,
    this.tramos = const [],
    this.menores10 = 0,
    required this.parentesco,
    required this.nombre,
    this.motivo = '',
    this.autorizacionFirmada = false,
    required this.escribioEnPlanilla,
  });
}

/// Cómo terminó una entrega. Las pantallas muestran los carteles: el servicio
/// no tiene `BuildContext`.
sealed class ResultadoDeLaEntrega {
  const ResultadoDeLaEntrega();
}

/// Quedó guardada. [subio]: llegó a la nube (si no, sube sola cuando vuelva la
/// conexión, y mientras tanto los otros equipos no la ven).
class Entregada extends ResultadoDeLaEntrega {
  final bool subio;
  final EntregaEntradas renglon;

  /// Con esta parte, la familia tiene todo.
  final bool todoEntregado;

  /// Se escribió también la fila completa de `entradas_retiro`.
  final bool conFilaCompleta;

  const Entregada({
    required this.subio,
    required this.renglon,
    required this.todoEntregado,
    required this.conFilaCompleta,
  });
}

/// Esa parte ya figura entregada (por otro equipo, o recién en este). No se
/// guardó nada. [texto] dice a quién y cuándo.
class YaEntregadaEnOtroEquipo extends ResultadoDeLaEntrega {
  final String texto;
  const YaEntregadaEnOtroEquipo(this.texto);
}

/// Mientras el diálogo estaba abierto cambió la cuenta, se anuló un cobro, o los
/// números ya tienen dueño. No se guardó nada: se vuelve a abrir con los datos
/// nuevos.
class CambioAlgo extends ResultadoDeLaEntrega {
  final String motivo;
  const CambioAlgo(this.motivo);
}

/// Sin internet, quien atiende eligió no seguir.
class Cancelada extends ResultadoDeLaEntrega {
  const Cancelada();
}

/// Cómo terminó una anulación.
sealed class ResultadoDeAnular {
  const ResultadoDeAnular();
}

class Anulada extends ResultadoDeAnular {
  final bool subio;
  final Set<ParteEntrega> partes;
  const Anulada({required this.subio, required this.partes});
}

/// No se anuló nada, y por qué.
class NoSeAnulo extends ResultadoDeAnular {
  final String motivo;
  const NoSeAnulo(this.motivo);
}

/// Lo que este equipo tiene de una fiesta: **todos** los alumnos (también los de
/// baja: sus números entregados siguen teniendo dueño), las filas de
/// `entradas_retiro` y los renglones de `entradas_entregas`.
class LoDeLaFiesta {
  final List<ContratoAlumno> alumnos;
  final Map<String, EntradasRetiro> retiros;
  final List<EntregaEntradas> renglones;

  const LoDeLaFiesta({
    required this.alumnos,
    required this.retiros,
    required this.renglones,
  });

  ContratoAlumno? alumno(String id) {
    for (final a in alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<EntregaEntradas> renglonesDe(String id) =>
      [for (final r in renglones) if (r.contratoAlumnoId == id) r]
        ..sort(EntregaEntradas.enOrden);

  /// Con lo que dijo la nube de un alumno: sus renglones se suman (un renglón
  /// nunca cambia) y la fila que vale es la más nueva.
  LoDeLaFiesta conLaNube(String id, LoDeLaNube? nube) {
    if (nube == null) return this;
    final ids = {for (final r in renglones) r.id};
    final retiro = retiros[id];
    final deLaNube = nube.retiro;
    final masNueva = deLaNube != null &&
            (retiro == null || deLaNube.updatedAt.isAfter(retiro.updatedAt))
        ? deLaNube
        : retiro;
    final conLaDeLaNube = Map.of(retiros);
    if (masNueva != null) conLaDeLaNube[id] = masNueva;
    return LoDeLaFiesta(
      alumnos: alumnos,
      retiros: conLaDeLaNube,
      renglones: [
        ...renglones,
        for (final r in nube.renglones)
          if (!ids.contains(r.id)) r,
      ],
    );
  }
}

/// Lo que dice la nube de la entrega de un alumno.
class LoDeLaNube {
  final EntradasRetiro? retiro;
  final List<EntregaEntradas> renglones;

  const LoDeLaNube({this.retiro, this.renglones = const []});
}

/// Lo que hace falta para la cuenta de un alumno, con la misma regla que el
/// cobro (`RetiroEntradas.deudaDe`).
class CuentaDelAlumno {
  final List<Map<String, dynamic>> pagos;
  final double moraCobradaHistorial;

  const CuentaDelAlumno({required this.pagos, required this.moraCobradaHistorial});
}

/// De dónde lee y dónde guarda [EntregarParte]. En la app, la base del equipo y
/// la nube (`entregar_parte_de_la_app.dart`); en las pruebas, la memoria.
abstract class PuertosDeLaEntrega {
  /// Lo que dice la conexión de este equipo.
  bool get hayInternet;

  /// La fila y los renglones del alumno en la nube. Lo que este equipo no
  /// tenía lo deja guardado, como la bajada. Tira sin red.
  Future<LoDeLaNube> deLaNube(String contratoAlumnoId);

  /// Todo lo de la fiesta, con lo que tiene este equipo.
  Future<LoDeLaFiesta> leer(String eventoId);

  /// Los pagos y la mora cobrada del alumno, para su cuenta.
  Future<CuentaDelAlumno> cuentaDe(ContratoAlumno alumno);

  /// Agrega los renglones y, si viene, guarda la fila de `entradas_retiro`:
  /// todo en una transacción, con su entrada en la cola.
  Future<void> guardar(List<EntregaEntradas> renglones, {EntradasRetiro? retiro});

  /// Sube ya lo guardado. True si llegó todo a la nube.
  Future<bool> subir({
    required List<String> renglones,
    String? retiro,
    required DateTime desde,
  });

  /// El id de este equipo.
  Future<String?> equipo();

  /// La hora, en UTC.
  DateTime ahora();
}

/// **El único camino para guardar una entrega por partes**: lo usan la entrega
/// de ENTRADAS y el bloque GRATIS de VENDER. Las pantallas solo muestran los
/// carteles.
///
/// Es el `_entregar` de siempre (`retiro_entradas_screen.dart`) para una parte:
/// con internet mira la nube por si otro equipo ya la entregó; sin internet
/// pregunta antes de seguir; relee todo; frena si cambió la cuenta o los
/// números; guarda; y sube ya.
///
/// Guarda **un renglón** de `entradas_entregas`. Si con ese renglón la familia
/// queda con las dos partes y `entradas_retiro` no está entregada, escribe
/// también la fila completa (`EntregaPorPartes.filaCompleta`), en la misma
/// transacción: así una PC con la 6.9.x, el plano y la planilla vieja la ven
/// "Retiró".
class EntregarParte {
  final PuertosDeLaEntrega _puertos;

  const EntregarParte(this._puertos);

  static const _volverAAbrir =
      'No se guardó nada: volvé a abrirlo con los datos nuevos.';

  /// Entrega [datos] a [contratoAlumnoId]. [quien] es quien lo anota
  /// (`quienOpera`). [seguirSinInternet] pregunta si seguir cuando no se puede
  /// mirar la nube.
  Future<ResultadoDeLaEntrega> entregar({
    required String eventoId,
    required String contratoAlumnoId,
    required DatosDeLaParte datos,
    required String quien,
    required Future<bool> Function() seguirSinInternet,
  }) async {
    // Otro equipo puede haberla entregado hace un minuto y todavía no bajó.
    LoDeLaNube? nube;
    var online = _puertos.hayInternet;
    if (online) {
      try {
        nube = await _puertos.deLaNube(contratoAlumnoId);
      } catch (_) {
        online = false;
      }
    }
    if (!online && !await seguirSinInternet()) return const Cancelada();

    // Con todo recién leído: si mientras el diálogo estaba abierto cambió la
    // cuenta, se anuló un cobro u otro equipo usó esos números, no se guarda.
    final fiesta =
        (await _puertos.leer(eventoId)).conLaNube(contratoAlumnoId, nube);
    final a = fiesta.alumno(contratoAlumnoId);
    if (a == null || a.esBajaTemporal) {
      return const CambioAlgo(
        'Este alumno ya no está en la lista de la fiesta. $_volverAAbrir',
      );
    }
    final retiro = fiesta.retiros[a.id];
    final propios = fiesta.renglonesDe(a.id);
    final entradas = RetiroEntradas.entradasDe(a);
    final estado = EstadoDeLaEntrega.de(
      retiro: retiro,
      renglones: propios,
      entradas: entradas,
    );
    final parte = estado.parte(datos.parte);
    if (parte.entregada) {
      final cuando = EntregaPorPartes.quienYCuando(
        parte,
        fecha: ArTime.formatFechaHora,
      );
      return YaEntregadaEnOtroEquipo(
        'Ya se le entregaron ${EntregaPorPartes.nombreDe(datos.parte)}'
        '${cuando.isEmpty ? '' : ': $cuando'}. No se guardó nada.',
      );
    }

    final cuenta = await _puertos.cuentaDe(a);
    final deuda = RetiroEntradas.deudaDe(
      a,
      pagos: cuenta.pagos,
      moraCobradaHistorial: cuenta.moraCobradaHistorial,
      ahoraAr: ArTime.toAr(_puertos.ahora()),
    );
    if (RetiroEntradas.bloqueo(a, deuda) != BloqueoRetiro.ninguno) {
      return const CambioAlgo(
        'La cuenta de este alumno cambió mientras el diálogo estaba abierto. '
        '$_volverAAbrir',
      );
    }
    if (parte.leToca <= 0) {
      return CambioAlgo(
        'No le corresponden ${EntregaPorPartes.nombreDe(datos.parte)}: no hay '
        'nada que entregar. $_volverAAbrir',
      );
    }
    if (datos.cantidad != parte.leToca) {
      return CambioAlgo(
        'Cambió la cuenta: hoy le corresponden ${parte.leToca} '
        '${datos.parte.nombre}, no ${datos.cantidad}. $_volverAAbrir',
      );
    }
    final errorNumeros = EntregaPorPartes.errorDeLosNumeros(
      parte: datos.parte,
      tramos: datos.tramos,
      cantidad: parte.leToca,
      deOtros: EntregaPorPartes.numerosDeOtros(
        fiesta.alumnos,
        fiesta.retiros,
        fiesta.renglones,
        salvo: a.id,
      ),
    );
    if (errorNumeros != null) return CambioAlgo('$errorNumeros $_volverAAbrir');
    final faltaQuien = RetiroEntradas.erroresQuienRetira(
      parentesco: datos.parentesco,
      nombre: datos.nombre,
      motivo: datos.motivo,
      autorizacionFirmada: datos.autorizacionFirmada,
      escribioEnPlanilla: datos.escribioEnPlanilla,
    );
    if (faltaQuien.isNotEmpty) {
      return CambioAlgo('${faltaQuien.values.first} No se guardó nada.');
    }

    final desde = DateTime.now().toUtc();
    final ahora = _puertos.ahora();
    final equipo = await _puertos.equipo();
    final nuevo = EntregaEntradas.entrega(
      contratoAlumnoId: a.id,
      eventoId: a.eventoId,
      parte: datos.parte,
      cantidad: parte.leToca,
      tramos: datos.tramos,
      menores10: datos.menores10,
      parentesco: datos.parentesco,
      nombre: datos.nombre,
      motivoOtraPersona: datos.motivo,
      autorizacionFirmada: datos.autorizacionFirmada,
      escribioEnPlanilla: datos.escribioEnPlanilla,
      hechoPor: quien,
      deviceId: equipo,
      ahora: ahora,
    );
    final despues = EstadoDeLaEntrega.de(
      retiro: retiro,
      renglones: [...propios, nuevo],
      entradas: entradas,
    );
    final (:renglones, :fila) = _conLaFilaSiCompleta(
      alumno: a,
      retiro: retiro,
      propios: propios,
      nuevos: [nuevo],
      despues: despues,
      entradas: entradas,
      equipo: equipo,
      ahora: ahora,
    );
    await _puertos.guardar(renglones, retiro: fila);
    final subio = await _puertos.subir(
      renglones: [for (final r in renglones) r.id],
      retiro: fila?.id,
      desde: desde,
    );
    return Entregada(
      subio: subio,
      renglon: nuevo,
      todoEntregado: despues.todoEntregado,
      conFilaCompleta: fila != null,
    );
  }

  /// Si con [nuevos] la familia queda con todo y `entradas_retiro` no está
  /// entregada: antes, las copias de lo que dependía de esa fila (si no, al
  /// reescribirla se perdería), y la fila completa. Si no, solo [nuevos].
  ({List<EntregaEntradas> renglones, EntradasRetiro? fila}) _conLaFilaSiCompleta({
    required ContratoAlumno alumno,
    required EntradasRetiro? retiro,
    required List<EntregaEntradas> propios,
    required List<EntregaEntradas> nuevos,
    required EstadoDeLaEntrega despues,
    required EntradasDeAlumno entradas,
    required String? equipo,
    required DateTime ahora,
  }) {
    if (!despues.todoEntregado || (retiro?.entregado ?? false)) {
      return (renglones: nuevos, fila: null);
    }
    final copias = EntregaPorPartes.copiasDeLaFila(
      alumno: alumno,
      retiro: retiro,
      estado: despues,
      deviceId: equipo,
      ahora: ahora,
    );
    final fila = EntregaPorPartes.filaCompleta(
      alumno: alumno,
      anterior: retiro,
      estado: EstadoDeLaEntrega.de(
        retiro: retiro,
        renglones: [...propios, ...copias, ...nuevos],
        entradas: entradas,
      ),
      ahora: ahora,
    );
    return (renglones: [...copias, ...nuevos], fila: fila);
  }

  /// La familia tiene las dos partes pero `entradas_retiro` no está entregada:
  /// pasa cuando cada parte la entregó un equipo distinto y ninguno vio las dos
  /// (uno sin internet). Escribe la fila completa, como si la hubiera escrito
  /// el que entregó la última parte, para que la 6.9.x, el plano y la planilla
  /// vieja la vean "Retiró".
  ///
  /// **Pide internet y mira la nube antes**: con lo de este equipo solo, podría
  /// volver a poner "entregado" sobre una anulación que todavía no bajó. Sin
  /// internet, o si no hace falta, no escribe nada. True si la escribió.
  Future<bool> completarLaFila({
    required String eventoId,
    required String contratoAlumnoId,
  }) async {
    if (!_puertos.hayInternet) return false;
    final LoDeLaNube nube;
    try {
      nube = await _puertos.deLaNube(contratoAlumnoId);
    } catch (_) {
      return false;
    }
    final fiesta =
        (await _puertos.leer(eventoId)).conLaNube(contratoAlumnoId, nube);
    final a = fiesta.alumno(contratoAlumnoId);
    if (a == null) return false;
    final retiro = fiesta.retiros[a.id];
    final propios = fiesta.renglonesDe(a.id);
    final entradas = RetiroEntradas.entradasDe(a);
    final estado = EstadoDeLaEntrega.de(
      retiro: retiro,
      renglones: propios,
      entradas: entradas,
    );
    final desde = DateTime.now().toUtc();
    final ahora = _puertos.ahora();
    final equipo = await _puertos.equipo();
    final (:renglones, :fila) = _conLaFilaSiCompleta(
      alumno: a,
      retiro: retiro,
      propios: propios,
      nuevos: const [],
      despues: estado,
      entradas: entradas,
      equipo: equipo,
      ahora: ahora,
    );
    if (fila == null) return false;
    await _puertos.guardar(renglones, retiro: fila);
    await _puertos.subir(
      renglones: [for (final r in renglones) r.id],
      retiro: fila.id,
      desde: desde,
    );
    return true;
  }

  /// Anula [partes] de la entrega de [contratoAlumnoId] (una o las dos), con
  /// [motivo]: **solo el jefe** ([esJefe]; sin él no hace nada). Agrega un
  /// renglón de anulación por cada parte entregada y, si `entradas_retiro`
  /// estaba entregada, la anula también (`RetiroEntradas.anular`), con la misma
  /// hora: así la 6.9.x deja de verla "Retiró" y esta versión sabe que es el
  /// reflejo de la anulación, no una de la 6.9.x.
  Future<ResultadoDeAnular> anularParte({
    required String eventoId,
    required String contratoAlumnoId,
    required Set<ParteEntrega> partes,
    required String motivo,
    required String quien,
    required bool esJefe,
  }) async {
    // Doble llave: el botón está apagado sin modo jefe, y acá tampoco pasa.
    if (!esJefe) return const NoSeAnulo('Anular una entrega es solo del jefe.');
    final m = motivo.trim();
    if (m.isEmpty) return const NoSeAnulo('Anular lleva motivo.');
    if (partes.isEmpty) return const NoSeAnulo('Elegí qué anular.');

    LoDeLaNube? nube;
    if (_puertos.hayInternet) {
      try {
        nube = await _puertos.deLaNube(contratoAlumnoId);
      } catch (_) {
        // Sin la nube se anula con lo de este equipo, como hasta ahora.
      }
    }
    final fiesta =
        (await _puertos.leer(eventoId)).conLaNube(contratoAlumnoId, nube);
    final a = fiesta.alumno(contratoAlumnoId);
    if (a == null) {
      return const NoSeAnulo('Este alumno ya no está en la lista de la fiesta.');
    }
    final retiro = fiesta.retiros[a.id];
    final propios = fiesta.renglonesDe(a.id);
    final estado = EstadoDeLaEntrega.deAlumno(a, retiro: retiro, renglones: propios);
    final aAnular = [
      for (final p in ParteEntrega.values)
        if (partes.contains(p) && estado.parte(p).entregada) p,
    ];
    if (aAnular.isEmpty) {
      return const NoSeAnulo('No hay nada entregado para anular.');
    }

    final desde = DateTime.now().toUtc();
    final ahora = _puertos.ahora();
    final equipo = await _puertos.equipo();
    final reescribe = retiro?.entregado ?? false;
    final copias = reescribe
        ? EntregaPorPartes.copiasDeLaFila(
            alumno: a,
            retiro: retiro,
            estado: estado,
            deviceId: equipo,
            ahora: ahora,
          )
        : const <EntregaEntradas>[];
    final anulaciones = [
      for (final p in aAnular)
        EntregaEntradas.anulacion(
          contratoAlumnoId: a.id,
          eventoId: a.eventoId,
          parte: p,
          cantidad: estado.parte(p).cantidad,
          tramos: estado.parte(p).tramos,
          motivo: m,
          hechoPor: quien,
          deviceId: equipo,
          ahora: ahora,
        ),
    ];
    // En la fila, que dice una sola cosa para las dos partes, se aclara cuál se
    // anuló: la 6.9.x muestra este motivo.
    final fila = reescribe
        ? RetiroEntradas.anular(
            retiro!,
            motivo: aAnular.length == ParteEntrega.values.length
                ? m
                : 'Solo ${EntregaPorPartes.nombreDe(aAnular.single)}: $m',
            quien: quien,
            ahora: ahora,
          )
        : null;
    final renglones = [...copias, ...anulaciones];
    await _puertos.guardar(renglones, retiro: fila);
    final subio = await _puertos.subir(
      renglones: [for (final r in renglones) r.id],
      retiro: fila?.id,
      desde: desde,
    );
    return Anulada(subio: subio, partes: aAnular.toSet());
  }
}
