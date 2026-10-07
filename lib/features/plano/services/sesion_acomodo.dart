import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import 'armar_a_medida.dart';
import 'editar_armado.dart';
import 'medir_salon.dart';

/// Una sesión de Personalizar → Acomodar: el salón como estaba al empezar
/// ([base]), cómo va quedando, y lo que se puede deshacer.
///
/// **Nada se guarda hasta tocar GUARDAR**: todo lo que pasa acá vive en la
/// pantalla. No lee ni escribe nada; las cuentas son las de [EditarArmado].
class SesionAcomodo {
  /// El salón guardado, del que se parte.
  final ArmadoSalon base;
  final MedidasPlano medidas;

  /// Mesa → por qué no se puede sacar (tiene familia, está fijada). Se pone
  /// al día con [ponerAlDia] si la otra PC cambia algo mientras se acomoda.
  Map<int, String> enUso;

  /// Las mesas en uso **como estaban al abrir la sesión**. Si dejan de ser
  /// las mismas, lo acomodado no se guarda: se pensó con otro salón.
  final Map<int, String> enUsoAlEmpezar;

  /// Las familias con sus mesas, para avisar si alguna queda separada.
  List<OcupantePlano> ocupantes;

  /// Ya hay familias con mesa (también de baja): los números no cambian y no
  /// se vuelve al armado original.
  bool haySorteo;

  SesionAcomodo({
    required this.base,
    this.medidas = const MedidasPlano(),
    this.enUso = const {},
    this.ocupantes = const [],
    this.haySorteo = false,
  })  : _actual = base,
        enUsoAlEmpezar = Map.unmodifiable(enUso);

  /// Lo que bajó de la otra PC mientras se acomodaba: quién tiene cada mesa.
  /// Lo acomodado queda; los avisos y lo que se puede sacar pasan a salir de
  /// lo que hay de verdad.
  void ponerAlDia({
    required Map<int, String> enUso,
    required List<OcupantePlano> ocupantes,
    required bool haySorteo,
  }) {
    this.enUso = enUso;
    this.ocupantes = ocupantes;
    this.haySorteo = haySorteo;
  }

  /// ¿Cambiaron las mesas de las familias desde que se abrió la sesión?
  bool get cambioElUso => !EditarArmado.mismoUso(enUsoAlEmpezar, enUso);

  static const int _maximoDeshacer = 60;

  ArmadoSalon _actual;
  final List<ArmadoSalon> _pila = [];
  ArmadoSalon? _antesDeArrastrar;
  VistaPreviaSeparar? _previa;

  late final String _firmaBase = EditarArmado.firma(base);
  ArmadoSalon? _firmado;
  bool _igualALaBase = true;

  /// Cómo va quedando el salón (sin la vista previa de separar).
  ArmadoSalon get actual => _actual;

  /// Lo que se dibuja: la vista previa de separar o juntar, si hay una
  /// abierta; si no, lo acomodado.
  ArmadoSalon get visto => _previa?.armado ?? _actual;

  VistaPreviaSeparar? get previa => _previa;

  bool get arrastrando => _antesDeArrastrar != null;

  bool get puedeDeshacer => _pila.isNotEmpty;

  /// ¿El salón quedó distinto del guardado? Deshacer hasta el principio, o
  /// volver una mesa a su lugar, es no haber cambiado nada.
  bool get hayCambios {
    if (identical(_actual, base)) return false;
    if (!identical(_firmado, _actual)) {
      _firmado = _actual;
      _igualALaBase = EditarArmado.firma(_actual) == _firmaBase;
    }
    return !_igualALaBase;
  }

  /// Lo que no deja guardar así, con las mesas de las que habla.
  List<AvisoAcomodo> get bloqueosConMesas => [
        for (final (x, y) in EditarArmado.pisadas(_actual))
          AvisoAcomodo('Las mesas $x y $y se pisan.', [x, y]),
        if (_actual.mesas.isEmpty) const AvisoAcomodo('El salón quedó sin mesas.'),
        if (hayCambios && cambioElUso)
          const AvisoAcomodo(
            'Mientras acomodabas cambiaron las mesas de las familias. Tocá '
            'DESCARTAR para ver cómo quedó y acomodá de nuevo.',
          ),
      ];

  /// Lo que no deja guardar así, en palabras.
  List<String> get bloqueos => [for (final b in bloqueosConMesas) b.texto];

  bool get puedeGuardar =>
      hayCambios && bloqueos.isEmpty && !arrastrando && _previa == null;

  void _poner(ArmadoSalon armado) {
    _previa = null;
    // La hoja vuelve al tamaño que le hace falta: no queda agrandada por algo
    // que ya se trajo de vuelta.
    final nuevo = EditarArmado.ajustarCajas(armado, base);
    if (identical(nuevo, _actual)) return;
    _pila.add(_actual);
    if (_pila.length > _maximoDeshacer) _pila.removeAt(0);
    _actual = nuevo;
  }

  // ── Arrastrar ───────────────────────────────────────────────────────────

  /// Un arrastre entero (desde que se aprieta hasta que se suelta) es un solo
  /// paso para Deshacer.
  void empezarArrastre() {
    _previa = null;
    _antesDeArrastrar ??= _actual;
  }

  /// Lleva la mesa hacia ([x], [y]): se corre de a un cuarto de metro
  /// contando desde donde estaba al empezar a arrastrarla.
  void arrastrarMesa(int numero, double x, double y) {
    final antes = _antesDeArrastrar?.mesa(numero);
    if (antes == null) return;
    _actual = EditarArmado.mover(
      _actual,
      numero,
      x,
      y,
      desde: (x: antes.x, y: antes.y),
    );
  }

  void arrastrarSector(int indice, double x, double y) {
    final antes = _antesDeArrastrar;
    if (antes == null || indice < 0 || indice >= antes.sectores.length) return;
    final caja = antes.sectores[indice].caja;
    _actual = EditarArmado.moverSector(
      _actual,
      indice,
      x,
      y,
      desde: (x: caja.x, y: caja.y),
    );
  }

  void terminarArrastre() {
    final antes = _antesDeArrastrar;
    _antesDeArrastrar = null;
    if (antes == null || identical(antes, _actual)) return;
    // Mientras se arrastraba la hoja solo crecía, para que el dibujo no
    // saltara. Al soltar queda del tamaño que hace falta.
    _actual = EditarArmado.ajustarCajas(_actual, base);
    // Llevarla y traerla de vuelta en el mismo arrastre es no haberla movido:
    // no queda un paso de Deshacer que no hace nada.
    if (EditarArmado.firma(antes) == EditarArmado.firma(_actual)) {
      _actual = antes;
      return;
    }
    _pila.add(antes);
    if (_pila.length > _maximoDeshacer) _pila.removeAt(0);
  }

  // ── Mesas ───────────────────────────────────────────────────────────────

  /// Agrega una mesa en [hoja], cerca de [cerca] si se puede, y devuelve su
  /// número: el que sigue al más alto, sin reusar el de una mesa que está en
  /// uso ni el de una que se sacó en esta sesión.
  int agregar(String hoja, {int? cerca}) {
    final numero = EditarArmado.proximoNumero(
      _actual,
      [...base.numeros, ...enUso.keys],
    );
    // Varias mesas nuevas seguidas quedan una al lado de la otra: a la
    // familia que llega tarde con dos mesas le tienen que tocar juntas.
    final anterior = numero - 1;
    final sigueALaAnterior = cerca == null &&
        !base.existe(anterior) &&
        _actual.mesa(anterior)?.hoja == hoja;
    final lugar = EditarArmado.lugarLibre(
      _actual,
      hoja,
      cerca: sigueALaAnterior ? anterior : cerca,
      lugarM: medidas.lugarMesaM,
      fueraDelPasillo: sigueALaAnterior,
    );
    _poner(EditarArmado.agregar(
      _actual,
      numero: numero,
      hoja: hoja,
      x: lugar.x,
      y: lugar.y,
    ));
    return numero;
  }

  /// Por qué no se puede sacar una mesa, o null si se puede.
  String? motivoParaNoSacar(int numero) {
    final porque = enUso[numero];
    return porque == null
        ? null
        : 'La mesa $numero no se saca: $porque. Se puede correr.';
  }

  /// Saca la mesa. Devuelve por qué no se pudo, o null si se sacó.
  String? sacar(int numero) {
    final motivo = motivoParaNoSacar(numero);
    if (motivo != null) return motivo;
    _poner(EditarArmado.sacar(_actual, numero));
    return null;
  }

  void cambiarPasto(int numero) {
    final m = _actual.mesa(numero);
    if (m == null) return;
    _poner(EditarArmado.marcarPasto(_actual, numero, !m.pasto));
  }

  // ── Sectores ────────────────────────────────────────────────────────────

  /// Agrega un sector y devuelve su lugar en la lista.
  int agregarSector(String hoja, TipoSector tipo, {String texto = ''}) {
    _poner(EditarArmado.agregarSector(
      _actual,
      hoja: hoja,
      tipo: tipo,
      texto: texto,
    ));
    return _actual.sectores.length - 1;
  }

  void sacarSector(int indice) =>
      _poner(EditarArmado.sacarSector(_actual, indice));

  void tamanoSector(int indice, {required double anchoM, required double altoM}) =>
      _poner(EditarArmado.tamanoSector(
        _actual,
        indice,
        anchoM: anchoM,
        altoM: altoM,
      ));

  // ── Separar o juntar ────────────────────────────────────────────────────

  /// Muestra cómo quedaría, sin cambiar nada todavía. Lo que entra y lo que
  /// queda apretado se mide como en [avisos]: con las medidas de la fiesta y
  /// las sillas extra de cada mesa.
  void probarSeparar(
    Set<int> numeros,
    double pasoM, {
    int Function(int numero)? sillasExtraDe,
  }) {
    _previa = EditarArmado.separar(
      _actual,
      numeros,
      pasoM,
      medidas: medidas,
      sillasExtraDe: sillasExtraDe,
    );
  }

  /// Aplica lo que se está viendo. Si a esa distancia no se puede (la vista
  /// previa dice por qué), no cambia nada.
  void aplicarSeparar() {
    final previa = _previa;
    if (previa == null || !previa.sePuede) return;
    _poner(previa.armado);
  }

  void cancelarSeparar() => _previa = null;

  // ── Deshacer, descartar, volver al original ─────────────────────────────

  void deshacer() {
    _previa = null;
    if (_pila.isEmpty) return;
    _actual = _pila.removeLast();
  }

  /// Vuelve al salón guardado. Es un paso más: Deshacer trae de vuelta lo
  /// que se había acomodado.
  void descartar() {
    _antesDeArrastrar = null;
    _poner(base);
  }

  /// Por qué no se puede volver al armado original, o null si se puede.
  String? get motivoSinOriginal {
    if (haySorteo) {
      return 'Ya hay familias con mesa: deshacé el sorteo para volver al '
          'armado original.';
    }
    final original = EditarArmado.original(_actual);
    if (original == null) {
      return 'No se sabe de qué armado salió este salón.';
    }
    for (final n in enUso.keys.toList()..sort()) {
      if (!original.existe(n)) {
        return 'La mesa $n ${enUso[n]} y el armado original no la tiene.';
      }
    }
    // A medida se arma de nuevo con las mesas que hay: si se agregaron más de
    // las que entran en el hormigón, volver al original se llevaría algunas.
    final hay = _actual.cantidadComunes;
    final entran = original.cantidadComunes;
    if (ArmarAMedida.lugarDe(_actual) != null && entran < hay) {
      return 'El salón tiene $hay mesas y armado de nuevo entran $entran: '
          'sacá las que sobran o marcalas de pasto.';
    }
    return null;
  }

  /// Vuelve al armado como venía de fábrica (se puede deshacer). Devuelve por
  /// qué no se pudo, o null si se hizo.
  String? volverAlOriginal() {
    final motivo = motivoSinOriginal;
    if (motivo != null) return motivo;
    _poner(EditarArmado.original(_actual)!);
    return null;
  }

  // ── Lo que conviene saber antes de guardar ──────────────────────────────

  /// Avisos que no frenan el guardado: familias que quedaron con sus mesas
  /// separadas, mesas apretadas, mesas fuera del hormigón y mesas tapadas por
  /// un sector. Cada uno trae sus mesas: en la pantalla se toca y lleva a
  /// ellas ("5 mesas quedan apretadas" solo no dice cuáles).
  List<AvisoAcomodo> avisosConMesas(int Function(int numero) sillasExtraDe) {
    final r = <AvisoAcomodo>[];
    // Lo mismo que el plano marca como grave una vez guardado: mejor verlo
    // antes de guardar.
    for (final p in _actual.problemas()) {
      if (!p.contains('tapa la mesa')) continue;
      r.add(AvisoAcomodo(p, [
        for (final m in RegExp(r'mesa (\d+)').allMatches(p))
          int.parse(m.group(1)!),
      ]));
    }
    for (final o in EditarArmado.familiasPartidas(base, _actual, ocupantes)) {
      final mesas = o.numeros.toList()..sort();
      r.add(AvisoAcomodo(
        '${o.apellido} quedó con sus mesas ${mesas.join(' y ')} separadas.',
        mesas,
      ));
    }
    final lugar = MedirSalon.revisar(_actual, medidas, sillasExtraDe);
    final apretadas = <int>{for (final p in lugar.apretadas) ...p.sinLugar}
        .toList()
      ..sort();
    if (apretadas.isNotEmpty) {
      r.add(AvisoAcomodo(
        apretadas.length == 1
            ? 'La mesa ${apretadas.single} queda apretada.'
            : '${apretadas.length} mesas quedan apretadas: '
                '${AvisoAcomodo.enLista(apretadas)}.',
        apretadas,
      ));
    }
    final afuera = lugar.fueraDelHormigon.toList()..sort();
    if (afuera.isNotEmpty) {
      r.add(AvisoAcomodo(
        afuera.length == 1
            ? 'La mesa ${afuera.single} no entra en el hormigón: correla o '
                'marcala de pasto.'
            : '${afuera.length} mesas no entran en el hormigón: '
                '${AvisoAcomodo.enLista(afuera)}. Correlas o marcalas de '
                'pasto.',
        afuera,
      ));
    }
    return r;
  }

  /// Los mismos avisos, solo en palabras.
  List<String> avisos(int Function(int numero) sillasExtraDe) =>
      [for (final a in avisosConMesas(sillasExtraDe)) a.texto];
}

/// Algo para mirar antes de guardar el salón, con las mesas de las que habla.
/// En la pantalla se toca y lleva a ellas, de a una.
class AvisoAcomodo {
  final String texto;
  final List<int> mesas;

  const AvisoAcomodo(this.texto, [this.mesas = const []]);

  /// "la 40, la 44 y la 50". Con más de [maximo], las primeras y cuántas más:
  /// un renglón con treinta números no se lee.
  static String enLista(List<int> mesas, {int maximo = 8}) {
    if (mesas.isEmpty) return '';
    final cortadas = mesas.length > maximo;
    final partes = [
      for (final n in cortadas ? mesas.take(maximo) : mesas) 'la $n',
    ];
    if (cortadas) return '${partes.join(', ')} y ${mesas.length - maximo} más';
    if (partes.length == 1) return partes.single;
    return '${partes.sublist(0, partes.length - 1).join(', ')} y ${partes.last}';
  }
}
