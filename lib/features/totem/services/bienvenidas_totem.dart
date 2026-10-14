import '../../../models/invitado.dart';

// A quién saluda el tótem. Sin pantalla ni nube: recibe lo que se leyó y lo
// que el tótem ya sabe, y contesta qué hacer.
//
// Las reglas, que son las que el usuario pidió con "que no salude tarde":
// - la primera lectura va en silencio: los que ya habían entrado aparecen en
//   la lista sin bienvenida;
// - la primera lectura después de un corte largo ([kCorteLargoTotem]) también:
//   los que entraron por otra PC mientras tanto ya pasaron de largo;
// - un corte corto no se come ningún saludo;
// - lo que avisó esta PC por el puente entre ventanas no lo deshace una
//   lectura atrasada de la nube. Sin internet el ingreso llega al tótem por el
//   puente, pero a la nube sube después: al volver la conexión el tótem leía
//   primero, lo sacaba de la lista y, cuando subía, lo saludaba de nuevo.

/// Cuánto tiene que durar un corte para que lo que entró mientras tanto vaya a
/// la lista sin bienvenida. Es la misma vara que la relectura de cada minuto:
/// con la conexión muda, el tótem ya saluda hasta un minuto tarde.
const kCorteLargoTotem = Duration(minutes: 1);

/// Si la lectura que acaba de llegar va en silencio.
///
/// [corte] es cuánto hace que el tótem no podía leer, medido con el reloj de
/// esa misma PC; `null` si no había ningún corte.
bool lecturaEnSilencio({required bool primera, Duration? corte}) =>
    primera || (corte != null && corte >= kCorteLargoTotem);

/// Cuánto esperar antes de volver a intentar conectarse: 2, 4, 8, 16 y 32
/// segundos, y de ahí no pasa.
Duration esperaDeReintento(int intentos) {
  final n = intentos < 0 ? 0 : (intentos > 4 ? 4 : intentos);
  return Duration(seconds: 2 << n);
}

// La cola que se acorta (pedido del usuario el 14-oct): una bienvenida dura
// 7 s si nadie espera; si hay gente esperando, 3 s. Con 7 s fijos, una puerta
// que marca una familia cada 5 s atrasa el tótem sin vuelta.

/// Lo que dura una bienvenida cuando nadie espera.
const kBienvenidaSola = Duration(seconds: 7);

/// Lo que dura cuando hay gente esperando, también la que ya estaba en
/// pantalla cuando llegó alguien.
const kBienvenidaConCola = Duration(seconds: 3);

/// Lo que se queda la tarjeta, como mínimo, cuando se le suma alguien de la
/// familia: que se alcance a leer su nombre.
const kSumarseALaTarjeta = Duration(seconds: 3);

/// Cuándo termina la bienvenida que está en pantalla.
///
/// [empezo] es cuando apareció; [hayCola], si alguien espera la suya ahora;
/// [seSumo], la última vez que se le sumó alguien de la familia. Si ya pasó,
/// la pantalla la termina enseguida.
DateTime finDeBienvenida({
  required DateTime empezo,
  required bool hayCola,
  DateTime? seSumo,
}) {
  final fin = empezo.add(hayCola ? kBienvenidaConCola : kBienvenidaSola);
  if (seSumo == null) return fin;
  final minimo = seSumo.add(kSumarseALaTarjeta);
  return minimo.isAfter(fin) ? minimo : fin;
}

/// Cada persona es su propia familia: un particular, o sin la ficha del evento.
String cadaUnoSuFamilia(Invitado i) => i.id;

/// La bienvenida que está en pantalla: una persona, o una familia que entró
/// junta.
class BienvenidaTotem {
  /// El id del alumno, en un masivo; el de la persona, si no.
  final String familia;

  /// En el orden en que llegaron.
  final List<Invitado> personas;

  final DateTime empezo;

  /// La última vez que se le sumó alguien de la familia.
  DateTime? seSumo;

  BienvenidaTotem({
    required this.familia,
    required List<Invitado> personas,
    required this.empezo,
  }) : personas = [...personas];

  bool tiene(String id) => personas.any((p) => p.id == id);
}

/// Lo que hay que hacer con una lectura de la nube.
class LecturaResuelta {
  /// Ingresos nuevos que llevan bienvenida, en el orden en que vinieron.
  final List<Invitado> saludar;

  /// Ingresos que el tótem no tenía y que van a la lista sin bienvenida.
  final List<Invitado> sinSaludo;

  /// Los que el tótem tenía como ingresados y ya no lo están.
  final Set<String> sacar;

  /// Avisos del puente que la nube ya tiene: dejan de necesitar protección.
  final Set<String> confirmados;

  const LecturaResuelta({
    this.saludar = const [],
    this.sinSaludo = const [],
    this.sacar = const {},
    this.confirmados = const {},
  });
}

/// Resuelve una lectura completa de los invitados del evento.
///
/// - [vistos]: los ingresados que el tótem ya saludó o ya puso en la lista.
/// - [delPuente]: los que avisó esta PC por el puente y la nube todavía no
///   mostró como ingresados. No se sacan aunque la lectura no los traiga.
/// - [enCurso]: el que está en pantalla y los que esperan en la cola. No se
///   vuelven a encolar.
/// - [enSilencio]: ver [lecturaEnSilencio].
LecturaResuelta resolverLectura({
  required List<Invitado> lectura,
  required Set<String> vistos,
  required Set<String> delPuente,
  required bool enSilencio,
  Set<String> enCurso = const {},
}) {
  final ingresados = [
    for (final i in lectura)
      if (i.estadoIngreso == EstadoIngreso.ingresado) i,
  ];
  final idsIngresados = {for (final i in ingresados) i.id};

  final nuevos = <Invitado>[];
  // Los que una lectura atrasada había sacado mientras se los saludaba o
  // esperaban su turno. Vuelven a la lista, sin otra bienvenida: salteándolos
  // quedaban afuera, y la lectura siguiente los saludaba de nuevo.
  final deVuelta = <Invitado>[];
  final yaTomados = <String>{};
  for (final i in ingresados) {
    if (vistos.contains(i.id) || !yaTomados.add(i.id)) continue;
    (enCurso.contains(i.id) ? deVuelta : nuevos).add(i);
  }

  return LecturaResuelta(
    saludar: enSilencio ? const [] : nuevos,
    sinSaludo: enSilencio ? [...deVuelta, ...nuevos] : deVuelta,
    sacar: {
      for (final id in vistos)
        if (!idsIngresados.contains(id) && !delPuente.contains(id)) id,
    },
    confirmados: {
      for (final id in delPuente)
        if (idsIngresados.contains(id)) id,
    },
  );
}

/// Lo que el tótem sabe de los ingresos de la fiesta que está mostrando: la
/// lista, la cola de bienvenidas, la bienvenida en pantalla y si viene
/// pudiendo leer la nube.
///
/// No dibuja ni habla con la nube: la pantalla le cuenta lo que pasó (leyó, no
/// pudo leer, llegó un aviso, terminó una bienvenida) y dibuja lo que queda
/// acá. Así el recorrido entero —un corte, lo que se marca mientras tanto, la
/// vuelta, una familia que entra de a uno— se prueba sin montar la pantalla.
class IngresosTotem {
  /// Los que ya llegaron, los más recientes primero.
  final List<Invitado> ingresados = [];

  /// Los que esperan su bienvenida, en orden.
  final List<Invitado> cola = [];

  /// De qué familia es cada uno. En un masivo la da la ficha del evento: el
  /// alumno y sus acompañantes se saludan juntos.
  String Function(Invitado) familiaDe = cadaUnoSuFamilia;

  /// La bienvenida que está en pantalla. Null mientras no se saluda a nadie,
  /// y también mientras la tarjeta se va: lo que llega en ese momento espera
  /// la suya.
  BienvenidaTotem? enPantalla;

  /// Cuándo termina la bienvenida en pantalla ([finDeBienvenida]).
  DateTime? get fin {
    final b = enPantalla;
    if (b == null) return null;
    return finDeBienvenida(
      empezo: b.empezo,
      hayCola: cola.isNotEmpty,
      seSumo: b.seSumo,
    );
  }

  /// Cuántos esperan su bienvenida: "N más en camino".
  int get enCamino => cola.length;

  /// Pone en pantalla al primero de la cola y a los de su familia que
  /// esperaban. Null si no espera nadie.
  BienvenidaTotem? siguiente(DateTime ahora) {
    if (cola.isEmpty) return null;
    final familia = familiaDe(cola.first);
    final juntos = [
      for (final i in cola)
        if (familiaDe(i) == familia) i,
    ];
    cola.removeWhere((i) => familiaDe(i) == familia);
    return enPantalla = BienvenidaTotem(
      familia: familia,
      personas: juntos,
      empezo: ahora,
    );
  }

  /// La tarjeta empezó a irse.
  void termino() => enPantalla = null;

  /// Alguien que lleva bienvenida: a la tarjeta, si es de la familia que se
  /// está saludando; si no, a la cola.
  void _llega(Invitado i, DateTime ahora) {
    final b = enPantalla;
    if (b != null && familiaDe(i) == b.familia) {
      if (!b.tiene(i.id)) b.personas.add(i);
      b.seSumo = ahora;
      return;
    }
    cola.add(i);
  }

  /// Los ingresados que ya se saludaron o ya están en la lista.
  final _vistos = <String>{};

  /// Los que avisó esta PC por el puente y la nube todavía no mostró.
  final _delPuente = <String>{};

  bool _leyoAlgunaVez = false;

  /// Desde cuándo no se puede leer la nube, con el reloj de esta PC.
  DateTime? _cortadoDesde;

  /// Si la última vez que quiso leer la nube, pudo.
  bool get conectado => _cortadoDesde == null;

  /// Llegó una lectura completa de los invitados, del stream o de la
  /// relectura.
  void leyo(List<Invitado> lectura, {required DateTime ahora}) {
    final desde = _cortadoDesde;
    final r = resolverLectura(
      lectura: lectura,
      vistos: _vistos,
      delPuente: _delPuente,
      enCurso: {
        ...?enPantalla?.personas.map((i) => i.id),
        for (final i in cola) i.id,
      },
      enSilencio: lecturaEnSilencio(
        primera: !_leyoAlgunaVez,
        corte: desde == null ? null : ahora.difference(desde),
      ),
    );

    _leyoAlgunaVez = true;
    // Leyó: recién acá se da por conectado, no al intentarlo.
    _cortadoDesde = null;

    _delPuente.removeAll(r.confirmados);
    _vistos.removeAll(r.sacar);
    ingresados.removeWhere((i) => r.sacar.contains(i.id));

    // Los nuevos van arriba de la lista, lleven bienvenida o no. Los que ya
    // estaban no se mueven: después de un corte la lista no se rearma.
    final nuevos = [...r.sinSaludo, ...r.saludar];
    for (final i in nuevos) {
      _vistos.add(i.id);
    }
    ingresados.insertAll(0, nuevos.reversed);
    for (final i in r.saludar) {
      _llega(i, ahora);
    }
  }

  /// No se pudo leer la nube. El corte se cuenta desde el primer fallo.
  void noPudoLeer(DateTime ahora) => _cortadoDesde ??= ahora;

  /// Llegó un aviso de ingreso, sin esperar a la nube: por el puente entre
  /// ventanas ([porElPuente], lo marcó esta misma PC) o por el canal de avisos
  /// (lo marcó otra PC o un celular). Devuelve si era nuevo: si va a la
  /// tarjeta de su familia o a la cola, lo dice [enPantalla].
  bool aviso(
    Invitado invitado, {
    bool porElPuente = false,
    DateTime? ahora,
  }) {
    // Aunque ya esté saludado: lo que marcó esta PC puede no haber subido.
    if (porElPuente) _delPuente.add(invitado.id);
    if (!_vistos.add(invitado.id)) return false;
    _llega(invitado, ahora ?? DateTime.now());
    ingresados.insert(0, invitado);
    return true;
  }

  /// Se borró a alguien o se deshizo su ingreso. Si lo vuelven a marcar, se lo
  /// saluda de nuevo. Si era el único de la tarjeta, la tarjeta se va.
  void baja(String id) {
    ingresados.removeWhere((i) => i.id == id);
    cola.removeWhere((i) => i.id == id);
    _vistos.remove(id);
    _delPuente.remove(id);
    final b = enPantalla;
    if (b != null) {
      b.personas.removeWhere((i) => i.id == id);
      if (b.personas.isEmpty) enPantalla = null;
    }
  }

  /// Se vació la lista o se deshicieron todos los ingresos.
  void vaciar() {
    ingresados.clear();
    cola.clear();
    enPantalla = null;
    _vistos.clear();
    _delPuente.clear();
  }

  /// Como recién abierto: otro evento, o la ventana que vuelve de estar
  /// escondida. La próxima lectura va en silencio.
  void reiniciar() {
    vaciar();
    _leyoAlgunaVez = false;
    _cortadoDesde = null;
  }

  /// La ventana se esconde: nadie queda esperando su bienvenida.
  void pausar() {
    cola.clear();
    enPantalla = null;
    _cortadoDesde = null;
  }
}
