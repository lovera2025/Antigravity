import '../../../models/contrato_alumno.dart';
import '../../../models/evento.dart';
import '../../../models/invitado.dart';
import '../../../models/sillas_reparto.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/reparto_de_sillas.dart';
import '../../eventos/services/salon_mesas.dart';
import 'lista_puerta.dart';

/// Lo que se ve en Recepción de un evento: quiénes son, dónde se sientan y
/// quién ya entró.
///
/// **Un evento particular** es su lista de la puerta tal cual: nombre, DNI y
/// mesa, cargados a mano o por CSV.
///
/// **Un evento masivo** se arma desde los alumnos de la base de esta PC, no
/// desde la lista de la puerta: así salen con lo que está cargado en el momento
/// —antes y después del sorteo, y sin internet—, menos los dados de baja. De la
/// lista de la puerta se toma solo quién ya entró, cruzando por el id fijo de
/// cada lugar (`idInvitadoPuerta`). Sin sortear no hay mesa ni sillas; los
/// acompañantes y la música, solo si están cargados.
///
/// Sin pantalla ni base: la pantalla le pide la lista, la búsqueda y qué hacer
/// con Enter, y dibuja.
class PuertaDelEvento {
  final bool masivo;

  /// En un masivo, si algún alumno activo tiene mesa. Un particular cuenta
  /// siempre como sorteado: sus mesas se cargan a mano.
  final bool sorteado;

  /// Alumnos dados de baja que no aparecen.
  final int bajas;

  final List<GrupoPuerta> grupos;

  const PuertaDelEvento._({
    required this.masivo,
    required this.sorteado,
    required this.bajas,
    required this.grupos,
  });

  /// Un evento particular: una persona por fila de la lista de la puerta.
  factory PuertaDelEvento.particular(List<Invitado> invitados) {
    final grupos = [
      for (final i in invitados)
        GrupoPuerta._(titular: PersonaPuerta._deFila(i), cargadoAMano: true),
    ]..sort(_porNombre);
    return PuertaDelEvento._(
      masivo: false,
      sorteado: true,
      bajas: 0,
      grupos: grupos,
    );
  }

  /// Un evento masivo, desde sus alumnos.
  ///
  /// [repartos] es cómo eligió cada familia repartir sus sillas extra
  /// (`sillas_reparto`), por id de contrato. [invitados] es la lista de la
  /// puerta de esta PC: de ahí sale quién entró.
  ///
  /// Las filas de la lista que salieron de un alumno que ya no corresponde (una
  /// baja, un acompañante que se sacó) no se muestran. Las que se cargaron a
  /// mano en esa lista van al final, como en un particular: no se esconde a
  /// nadie que alguien haya agregado.
  factory PuertaDelEvento.masivo({
    required List<ContratoAlumno> alumnos,
    Map<String, SillasReparto> repartos = const {},
    required List<Invitado> invitados,
  }) {
    final filaPorId = {for (final i in invitados) i.id: i};
    final activos = alumnos.where((a) => !a.esBajaTemporal).toList();
    final sorteado = hayMesasSorteadas(activos);

    final filasPorAlumno = <String, List<FilaPuerta>>{};
    for (final f in filasPuertaDesdeAlumnos(activos)) {
      filasPorAlumno.putIfAbsent(f.contratoId, () => []).add(f);
    }

    final grupos = <GrupoPuerta>[];
    for (final a in activos) {
      final filas = filasPorAlumno[a.id];
      if (filas == null || filas.isEmpty) continue;
      final titular = filas.firstWhere((f) => f.esAlumno);
      final conNombre = filas.where((f) => !f.esAlumno).length;
      final musica = a.musicaElegida?.trim() ?? '';
      grupos.add(
        GrupoPuerta._(
          // Sin sortear nadie tiene mesa, así que tampoco sillas: no hace
          // falta preguntar si se sorteó para esconderlas.
          titular: PersonaPuerta._deAlumno(titular, filaPorId[titular.id]),
          acompanantes: [
            for (final f in filas.where((f) => !f.esAlumno))
              PersonaPuerta._deAlumno(
                f,
                filaPorId[f.id],
                acompanaA: titular.nombre,
              ),
          ],
          division: (a.cursoDivision?.trim().isNotEmpty ?? false)
              ? a.cursoDivision!.trim()
              : null,
          sinMesa: sorteado && !SalonMesas.tieneNumeros(a),
          sillas: textoSillasPuerta(a, repartos[a.id]),
          sillasAConfirmar:
              RepartoDeSillas.faltaElegirConMesas(a, repartos[a.id]),
          musica: musica.isEmpty ? null : musica,
          acompanantesSinNombre: a.cantidadAcompanantes > conNombre
              ? a.cantidadAcompanantes - conNombre
              : 0,
        ),
      );
    }
    grupos.sort(_porNombre);

    // Los ids que pudieron salir de algún alumno del evento, también de los de
    // baja: esas filas siguen a los alumnos y no son "cargadas a mano".
    final deAlumnos = {
      for (final a in alumnos)
        for (var lugar = 0; lugar < kMaxLugaresPorAlumno; lugar++)
          idInvitadoPuerta(a.id, lugar),
    };
    final aMano = [
      for (final i in invitados)
        if (!deAlumnos.contains(i.id))
          GrupoPuerta._(titular: PersonaPuerta._deFila(i), cargadoAMano: true),
    ]..sort(_porNombre);

    return PuertaDelEvento._(
      masivo: true,
      sorteado: sorteado,
      bajas: alumnos.length - activos.length,
      grupos: [...grupos, ...aMano],
    );
  }

  static int _porNombre(GrupoPuerta x, GrupoPuerta y) =>
      x.titular._buscable.compareTo(y.titular._buscable);

  Iterable<PersonaPuerta> get personas => grupos.expand((g) => g.personas);

  int get total => personas.length;
  int get adentro => personas.where((p) => p.ingresado).length;
  int get faltan => total - adentro;

  /// Cuántas personas muestra cada filtro, para los botones.
  int cuantos(FiltroPuerta filtro) => switch (filtro) {
        FiltroPuerta.todos => total,
        FiltroPuerta.faltan => faltan,
        FiltroPuerta.adentro => adentro,
      };

  /// Los grupos que se ven con esta búsqueda y este filtro.
  ///
  /// Se muestra el grupo entero —el alumno y sus acompañantes— si alguno de
  /// ellos coincide con la búsqueda y pasa el filtro: en la puerta llega la
  /// familia junta, y buscar a un acompañante tiene que mostrar con quién va.
  List<GrupoPuerta> buscar(String consulta, {FiltroPuerta filtro = FiltroPuerta.todos}) {
    final c = ConsultaPuerta(consulta);
    return [
      for (final g in grupos)
        if (g.personas.any((p) => c.coincide(p) && filtro.deja(p))) g,
    ];
  }

  /// Qué hace Enter con lo que está escrito.
  ///
  /// Ingresa solo si queda **una sola persona sin entrar** que coincida con la
  /// búsqueda (ella misma, no por ir con alguien que coincide). Si son varias,
  /// no hace nada y dice cuántas; si la única que coincide ya entró, dice a qué
  /// hora.
  ResultadoEnter alApretarEnter(
    String consulta, {
    FiltroPuerta filtro = FiltroPuerta.todos,
  }) {
    final c = ConsultaPuerta(consulta);
    if (c.vacia) return const ResultadoEnter._nada();
    final coinciden = [
      for (final p in personas)
        if (c.coincide(p) && filtro.deja(p)) p,
    ];
    final faltan = coinciden.where((p) => !p.ingresado).toList();
    if (faltan.length == 1) return ResultadoEnter._ingresar(faltan.single);
    if (faltan.length > 1) return ResultadoEnter._varios(faltan.length);
    if (coinciden.length == 1) return ResultadoEnter._yaAdentro(coinciden.single);
    if (coinciden.isEmpty) return const ResultadoEnter._nadie();
    return ResultadoEnter._todosAdentro(coinciden.length);
  }

  /// Las sillas de un alumno con mesa, como se ven en la puerta: cuántas le
  /// tocan en cada mesa, con el reparto que eligió la familia (o, mientras no
  /// eligió, el de siempre: la principal primero).
  ///
  /// "10 sillas (8 + 2 extra)" con una mesa; "12: 10 sillas · 13: 9 sillas"
  /// con varias. `null` si todavía no tiene mesa. Las cuentas son las de la
  /// planilla y el plano ([SalonMesas], [RepartoDeSillas]).
  static String? textoSillasPuerta(ContratoAlumno a, SillasReparto? guardado) {
    if (!SalonMesas.tieneNumeros(a)) return null;
    final numeros = [for (final t in SalonMesas.tramos(a)) ...t];
    final principal = RepartoDeSillas.vigente(a, guardado)?.principal;
    final extraPorMesa = {
      for (final (mesa, sillas)
          in SalonMesas.repartoSillas(a, sillasPrincipal: principal))
        mesa: sillas,
    };
    const base = SalonMesas.sillasPorMesa;
    if (numeros.length == 1) {
      final extra = extraPorMesa[numeros.single] ?? 0;
      return extra > 0
          ? '${base + extra} sillas ($base + $extra extra)'
          : '$base sillas';
    }
    return [
      for (final n in numeros) '$n: ${base + (extraPorMesa[n] ?? 0)} sillas',
    ].join(' · ');
  }
}

/// Cómo se nombra un evento en el selector de Recepción, con su tipo:
/// "ESCUELA NORMAL — Egresados (12/12) · masivo".
String etiquetaEventoRecepcion(Evento e) {
  final cliente = e.cliente?.nombreCompleto ?? 'Sin cliente';
  final f = e.fechaEvento;
  final tipo = e.modalidad == 'masivo' ? 'masivo' : 'particular';
  return '$cliente — ${e.tipoParaMostrar} (${f.day}/${f.month}) · $tipo';
}

/// Una familia en la puerta: el alumno y sus acompañantes con nombre. En un
/// particular, o en lo cargado a mano, es una sola persona.
class GrupoPuerta {
  final PersonaPuerta titular;
  final List<PersonaPuerta> acompanantes;
  final String? division;

  /// Masivo sorteado y este alumno sin mesa (por ejemplo, sin la base paga).
  final bool sinMesa;

  /// "10 sillas (8 + 2 extra)", o null si no tiene mesa.
  final String? sillas;

  /// La familia todavía no eligió cómo repartir sus sillas extra: se muestra
  /// el reparto de siempre, avisando.
  final bool sillasAConfirmar;

  final String? musica;

  /// Acompañantes que figuran en la cuenta pero sin nombre: no tienen fila ni
  /// botón propio.
  final int acompanantesSinNombre;

  /// Una fila de la lista de la puerta que no sale de un alumno: se puede
  /// eliminar desde Recepción.
  final bool cargadoAMano;

  const GrupoPuerta._({
    required this.titular,
    this.acompanantes = const [],
    this.division,
    this.sinMesa = false,
    this.sillas,
    this.sillasAConfirmar = false,
    this.musica,
    this.acompanantesSinNombre = 0,
    this.cargadoAMano = false,
  });

  List<PersonaPuerta> get personas => [titular, ...acompanantes];
}

/// Una persona que puede entrar.
class PersonaPuerta {
  /// El id de su fila en la lista de la puerta. En un masivo es fijo por alumno
  /// y lugar, exista o no la fila todavía.
  final String id;
  final String nombre;
  final String dni;

  /// "12", "12-14", "12-13 y 40". Null si no tiene, o si el masivo no se
  /// sorteó.
  final String? mesa;

  /// En un masivo, el alumno (no un acompañante).
  final bool esAlumno;

  /// En un masivo, a quién acompaña.
  final String? acompanaA;

  /// Su fila en la lista de la puerta de esta PC. En un masivo puede no
  /// existir todavía (antes del sorteo): se crea al ingresar.
  final Invitado? fila;

  final Set<int> _mesas;
  final String _buscable;

  PersonaPuerta._({
    required this.id,
    required this.nombre,
    required this.dni,
    required this.mesa,
    required this.esAlumno,
    required this.fila,
    this.acompanaA,
  })  : _mesas = MesasExtraUtils.numerosMesaDesdeTexto(mesa),
        _buscable = normalizarPuerta(nombre);

  factory PersonaPuerta._deFila(Invitado i) {
    final mesa = i.numeroMesa?.trim() ?? '';
    return PersonaPuerta._(
      id: i.id,
      nombre: i.nombreCompleto.trim(),
      dni: i.dni.trim(),
      mesa: mesa.isEmpty ? null : mesa,
      esAlumno: false,
      fila: i,
    );
  }

  factory PersonaPuerta._deAlumno(
    FilaPuerta f,
    Invitado? fila, {
    String? acompanaA,
  }) =>
      PersonaPuerta._(
        id: f.id,
        nombre: f.nombre,
        dni: '',
        mesa: f.mesa,
        esAlumno: f.esAlumno,
        fila: fila,
        acompanaA: acompanaA,
      );

  bool get ingresado => fila?.estadoIngreso == EstadoIngreso.ingresado;

  /// Cuándo entró: la última vez que se tocó su fila, que es al marcarla. Si
  /// después se corrigió su nombre o su mesa, cambia.
  DateTime? get horaIngreso => ingresado ? fila?.updatedAt?.toLocal() : null;

  /// "22:41", o null si no entró.
  String? get textoHora {
    final h = horaIngreso;
    if (h == null) return null;
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(h.hour)}:${dos(h.minute)}';
  }

  /// Las iniciales para el círculo: "PJ" de "PEREZ, JUAN".
  String get iniciales {
    final partes = _buscable.split(' ').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    final primera = partes.first[0];
    final segunda = partes.length > 1 ? partes[1][0] : '';
    return (primera + segunda).toUpperCase();
  }
}

enum FiltroPuerta {
  todos,
  faltan,
  adentro;

  String get nombre => switch (this) {
        FiltroPuerta.todos => 'Todos',
        FiltroPuerta.faltan => 'Faltan',
        FiltroPuerta.adentro => 'Adentro',
      };

  bool deja(PersonaPuerta p) => switch (this) {
        FiltroPuerta.todos => true,
        FiltroPuerta.faltan => !p.ingresado,
        FiltroPuerta.adentro => p.ingresado,
      };
}

/// Lo que se escribió en la búsqueda, ya partido.
///
/// Cada palabra tiene que aparecer en el nombre, en cualquier orden y sin
/// importar mayúsculas, acentos ni la coma: "juan perez" encuentra a
/// "PÉREZ, JUAN". Un número de hasta tres cifras es una mesa; uno más largo,
/// un DNI (o una mesa). Se pueden mezclar: "perez 12".
class ConsultaPuerta {
  final List<String> _palabras;

  ConsultaPuerta(String texto)
      : _palabras = normalizarPuerta(texto)
            .split(' ')
            .where((p) => p.isNotEmpty)
            .toList();

  bool get vacia => _palabras.isEmpty;

  bool coincide(PersonaPuerta p) {
    for (final palabra in _palabras) {
      if (!_coincidePalabra(p, palabra)) return false;
    }
    return true;
  }

  static final _soloCifras = RegExp(r'^\d+$');

  bool _coincidePalabra(PersonaPuerta p, String palabra) {
    if (!_soloCifras.hasMatch(palabra)) return p._buscable.contains(palabra);
    final numero = int.parse(palabra);
    if (p._mesas.contains(numero)) return true;
    if (palabra.length < 4) return false;
    return p.dni.replaceAll(RegExp(r'\D'), '').contains(palabra);
  }
}

/// Minúsculas, sin acentos, y todo lo que no es letra ni número pasa a ser un
/// espacio: "PÉREZ, JUAN" → "perez juan".
String normalizarPuerta(String texto) {
  final b = StringBuffer();
  for (final r in texto.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = _conAcento.indexOf(ch);
    if (i >= 0) {
      b.write(_sinAcento[i]);
    } else if (_letraOCifra.hasMatch(ch)) {
      b.write(ch);
    } else {
      b.write(' ');
    }
  }
  return b.toString().replaceAll(_espacios, ' ').trim();
}

const _conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _sinAcento = 'aaaaaeeeeiiiiooooouuuunc';
final _letraOCifra = RegExp(r'[a-z0-9]');
final _espacios = RegExp(r' +');

enum _QueHaceEnter { nada, ingresar, varios, yaAdentro, todosAdentro, nadie }

/// Qué pasa al apretar Enter en la búsqueda.
class ResultadoEnter {
  final _QueHaceEnter _que;

  /// A quién ingresar (si [ingresa]) o quién ya estaba adentro.
  final PersonaPuerta? persona;
  final int cantidad;

  const ResultadoEnter._nada()
      : _que = _QueHaceEnter.nada,
        persona = null,
        cantidad = 0;
  const ResultadoEnter._nadie()
      : _que = _QueHaceEnter.nadie,
        persona = null,
        cantidad = 0;
  const ResultadoEnter._ingresar(PersonaPuerta p)
      : _que = _QueHaceEnter.ingresar,
        persona = p,
        cantidad = 1;
  const ResultadoEnter._varios(int n)
      : _que = _QueHaceEnter.varios,
        persona = null,
        cantidad = n;
  const ResultadoEnter._yaAdentro(PersonaPuerta p)
      : _que = _QueHaceEnter.yaAdentro,
        persona = p,
        cantidad = 1;
  const ResultadoEnter._todosAdentro(int n)
      : _que = _QueHaceEnter.todosAdentro,
        persona = null,
        cantidad = n;

  bool get ingresa => _que == _QueHaceEnter.ingresar;

  /// Lo que se le dice al operador cuando Enter no ingresa a nadie. Null si
  /// ingresa o si no había nada escrito.
  String? get aviso => switch (_que) {
        _QueHaceEnter.nada || _QueHaceEnter.ingresar => null,
        _QueHaceEnter.varios =>
          'Hay $cantidad sin ingresar con esa búsqueda: tocá "Ingresar" en el que entra.',
        _QueHaceEnter.yaAdentro => persona!.textoHora == null
            ? '${persona!.nombre} ya ingresó.'
            : '${persona!.nombre} ya ingresó a las ${persona!.textoHora}.',
        _QueHaceEnter.todosAdentro =>
          'Los $cantidad que coinciden ya ingresaron.',
        _QueHaceEnter.nadie => 'No hay nadie con esa búsqueda.',
      };
}
