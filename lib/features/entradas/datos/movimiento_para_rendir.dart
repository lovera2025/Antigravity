import '../../../core/utils/uuid_utils.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/datos/lectura_de_filas.dart';
import 'venta_entradas.dart';

/// Qué dice un renglón de las entradas para rendir. La [clave] es lo que se
/// guarda en `entradas_para_rendir.que`.
enum QueParaRendir {
  /// El jefe le dio un bloque de entradas a alguien: con sus números, su precio
  /// (el de ese día, que queda fijo) y a quién.
  dio('dio'),

  /// Rindió plata por algunas: la venta está en `entradas_ventas` ([ventaId]).
  vendio('vendio'),

  /// Devolvió algunas sin vender, con sus números: esos quedan libres.
  devolvio('devolvio'),

  /// El jefe da por perdidas algunas (con motivo): no entra plata y esos
  /// números quedan anulados para siempre.
  noVolvieron('no_volvieron'),

  /// El jefe anuló otro renglón (con motivo): un bloque sin movimientos, un
  /// "devolvió" o un "no volvieron". Lo vendido se anula en VENTAS, no acá.
  anulo('anulo');

  final String clave;
  const QueParaRendir(this.clave);

  /// Null si la clave no es una de estas: una versión más nueva puede anotar
  /// algo que esta no conoce, y nunca se inventa qué fue (un renglón así se
  /// conserva y no cuenta).
  static QueParaRendir? deClave(String? clave) {
    for (final q in values) {
      if (q.clave == clave) return q;
    }
    return null;
  }
}

/// Un renglón de `entradas_para_rendir` (v82, 20-nov-2026): **las entradas que
/// se dan para rendir** (consignación). El jefe le da a alguien, alumno de la
/// fiesta o de afuera, un bloque numerado del talonario de las anticipadas; esa
/// persona las vende por su cuenta y después rinde la plata de las que vendió y
/// devuelve las que no (`docs/SPEC_entradas_para_rendir_2026-11-20.md`).
///
/// **Solo se agregan renglones: nunca se editan ni se borran.** Cada cosa que
/// pasa con un bloque es un renglón con el mismo [bloqueId] (el id del `dio`), y
/// anular es otro renglón (`anulo`). Así dos equipos, con o sin internet, nunca
/// se pisan: cada uno sube los suyos.
///
/// **La plata de una rendición no va acá:** es una venta común de
/// `entradas_ventas`, y el `vendio` solo la nombra. Por eso el cierre de la caja
/// que cobró la cuenta sin saber nada de esto.
///
/// **Lo que debe alguien de entradas para rendir no es deuda del contrato y no
/// frena nada:** ni el saldo, ni la mora, ni la entrega de lo sin cargo.
///
/// Los vínculos ([contratoAlumnoId], [ventaId], [cajaEntradasId], [anulaId]) van
/// en null cuando no hay, **nunca en `''`**: en la nube son uuid y un `''` traba
/// la fila en la cola.
class MovimientoParaRendir {
  final String id;
  final String eventoId;

  /// El `dio` al que pertenece. En el `dio`, su propio id.
  final String bloqueId;

  /// Como vino escrito; se lee con [que]. Uno que esta versión no conoce vuelve
  /// a la base igual que vino.
  final String queClave;

  /// Quién se las llevó, copiado en cada renglón para mostrarlo. En el `dio`,
  /// obligatorio: el nombre del alumno o el que se escribió.
  final String? personaNombre;

  /// `dio`: un teléfono o un DNI, si se anotó. Distingue a dos de afuera con el
  /// mismo nombre.
  final String? personaContacto;

  /// `dio`: si se las llevó un alumno de la fiesta. Solo para mostrar y
  /// agrupar: la venta de la rendición **nunca** va a su familia.
  final String? contratoAlumnoId;

  /// Cuántas: las que se llevó, vendió, devolvió o no volvieron (en un `anulo`,
  /// las del renglón que anula, para que quede escrito). **Toda cuenta mira
  /// [que] antes de sumar**: la cantidad de un `anulo` no es de nadie.
  final int cantidad;

  /// Los números, como `TramoTalonario.aTexto` ("1201-1220"). `dio`: el bloque;
  /// `devolvio`: los que volvieron; `no_volvieron`: si se saben. Null: sin
  /// números. **Un `anulo` no lleva** (20-nov-2026): los del renglón que anula
  /// se leen por [anulaId]. Si los copiara, quien juntara los números de todos
  /// los renglones de un bloque vería otro bloque con los mismos números.
  final String? numeros;

  /// `dio`: lo que vale cada una, **el precio del día en que se las llevó**.
  /// Queda fijo aunque venza la anticipada o el jefe cambie PRECIOS: se rinde a
  /// este precio, y nunca se vuelve a leer de `entradas_config`.
  final double? precio;

  /// `dio`: el nombre de ese precio ("Entrada anticipada" o el de la general),
  /// también fijo.
  final String? nombrePrecio;

  /// Si se llevó también las pulseras. **Siempre false por ahora**: la pulsera no
  /// se vende (el usuario, 20-nov-2026: solo entradas). La columna queda porque
  /// después no se puede sumar.
  final bool conPulseras;

  /// `vendio`: la venta de `entradas_ventas` con la plata.
  final String? ventaId;

  /// `vendio` y `devolvio`: la caja de quien lo recibió.
  final String? cajaEntradasId;

  /// `anulo`: el renglón que anula.
  final String? anulaId;

  /// `no_volvieron` y `anulo`: por qué. Obligatorio.
  final String? motivo;
  final String? nota;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const MovimientoParaRendir({
    required this.id,
    required this.eventoId,
    required this.bloqueId,
    required this.queClave,
    this.personaNombre,
    this.personaContacto,
    this.contratoAlumnoId,
    this.cantidad = 0,
    this.numeros,
    this.precio,
    this.nombrePrecio,
    this.conPulseras = false,
    this.ventaId,
    this.cajaEntradasId,
    this.anulaId,
    this.motivo,
    this.nota,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  QueParaRendir? get que => QueParaRendir.deClave(queClave);

  bool get esDio => que == QueParaRendir.dio;
  bool get esVendio => que == QueParaRendir.vendio;
  bool get esDevolvio => que == QueParaRendir.devolvio;
  bool get esNoVolvieron => que == QueParaRendir.noVolvieron;
  bool get esAnulo => que == QueParaRendir.anulo;

  /// Los números, leídos. Lo que no se entiende se descarta.
  List<TramoTalonario> get tramos => TramoTalonario.deTexto(numeros);

  // ── Los que se arman acá: cada uno valida y, si algo no cierra, tira
  //    `ArgumentError` y el renglón no se arma. ─────────────────────────────────

  static Never _no(String que, String por) =>
      throw ArgumentError('$que: $por');

  static String _sinEspaciosDeMas(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

  static int _suma(List<TramoTalonario> tramos) =>
      tramos.fold(0, (s, t) => s + t.cantidad);

  /// Los tramos tienen que ser números de verdad del talonario (del 1 en
  /// adelante, no al revés) y no pisarse entre ellos.
  static void _tramosSanos(String que, List<TramoTalonario> tramos) {
    for (final t in tramos) {
      if (t.desde < 1) _no(que, 'los números del talonario empiezan en 1');
      if (t.hasta < t.desde) _no(que, 'el tramo ${t.desde} al ${t.hasta} está al revés');
    }
    for (var i = 0; i < tramos.length; i++) {
      for (var j = i + 1; j < tramos.length; j++) {
        if (tramos[i].seCruzaCon(tramos[j])) {
          _no(que, 'los tramos ${tramos[i].texto} y ${tramos[j].texto} se pisan');
        }
      }
    }
  }

  /// Que cada número de [tramos] sea de los que se llevó en [bloque]: no se
  /// devuelve ni se pierde un número que nunca se le dio.
  static void _delBloque(
    String que,
    MovimientoParaRendir bloque,
    List<TramoTalonario> tramos,
  ) {
    final suyos = bloque.tramos;
    for (final t in tramos) {
      for (var n = t.desde; n <= t.hasta; n++) {
        if (!suyos.any((s) => s.desde <= n && n <= s.hasta)) {
          _no(que, 'el $n no es de las que se llevó');
        }
      }
    }
  }

  static void _esUnBloque(String que, MovimientoParaRendir bloque) {
    if (!bloque.esDio) _no(que, 'va sobre un bloque dado (un "dio")');
  }

  /// El jefe le da [cantidad] entradas para rendir a [personaNombre], con sus
  /// números ([tramos], **obligatorios**: la cantidad justa), al [precio] de
  /// hoy con su [nombrePrecio]. El id del bloque es el suyo.
  ///
  /// Que el nombre de alguien de afuera lleve nombre y apellido, que los
  /// números no pisen una venta ni otro bloque y que el precio sea el de hoy lo
  /// deciden las cuentas (`errorAlDar`): acá solo lo que el renglón necesita
  /// para tener sentido.
  factory MovimientoParaRendir.dio({
    required String eventoId,
    required String personaNombre,
    String? personaContacto,
    String? contratoAlumnoId,
    required int cantidad,
    required List<TramoTalonario> tramos,
    required double precio,
    required String nombrePrecio,
    String? nota,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    const que = 'no se puede dar';
    if (eventoId.trim().isEmpty) _no(que, 'falta la fiesta');
    final nombre = _sinEspaciosDeMas(personaNombre);
    if (nombre.isEmpty) _no(que, 'falta a quién se le dan');
    if (cantidad < 1) _no(que, 'la cantidad va de 1 en adelante');
    if (tramos.isEmpty) _no(que, 'faltan los números del talonario');
    _tramosSanos(que, tramos);
    final numeros = _suma(tramos);
    if (numeros != cantidad) {
      _no(que, 'son $numeros números y se le dan $cantidad');
    }
    if (precio.isNaN || precio <= 0) _no(que, 'la fiesta no tiene precio');
    final nombreDelPrecio = _sinEspaciosDeMas(nombrePrecio);
    if (nombreDelPrecio.isEmpty) _no(que, 'falta el nombre del precio');
    final id = UuidUtils.generate();
    final iso = isoDe(ahora);
    return MovimientoParaRendir(
      id: id,
      eventoId: eventoId.trim(),
      bloqueId: id,
      queClave: QueParaRendir.dio.clave,
      personaNombre: nombre,
      personaContacto: comoTextoONull(personaContacto),
      contratoAlumnoId: comoTextoONull(contratoAlumnoId),
      cantidad: cantidad,
      numeros: TramoTalonario.aTexto(tramos),
      precio: precio,
      nombrePrecio: nombreDelPrecio,
      nota: comoTextoONull(nota),
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Rindió la plata de [cantidad] de [bloque]: la venta [ventaId] la cobró la
  /// caja [cajaEntradasId]. Sin números: lo vendido son las que no devuelve.
  factory MovimientoParaRendir.vendio(
    MovimientoParaRendir bloque, {
    required int cantidad,
    required String ventaId,
    required String cajaEntradasId,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    const que = 'no se puede rendir';
    _esUnBloque(que, bloque);
    if (cantidad < 1) _no(que, 'lo vendido va de 1 en adelante');
    if (cantidad > bloque.cantidad) {
      _no(que, 'vendió $cantidad y se llevó ${bloque.cantidad}');
    }
    final venta = comoTextoONull(ventaId);
    if (venta == null) _no(que, 'falta la venta con la plata');
    final caja = comoTextoONull(cajaEntradasId);
    if (caja == null) _no(que, 'falta la caja que cobró');
    final iso = isoDe(ahora);
    return MovimientoParaRendir(
      id: UuidUtils.generate(),
      eventoId: bloque.eventoId,
      bloqueId: bloque.id,
      queClave: QueParaRendir.vendio.clave,
      personaNombre: bloque.personaNombre,
      cantidad: cantidad,
      ventaId: venta,
      cajaEntradasId: caja,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Devolvió sin vender las de [tramos] de [bloque] (**con sus números**: son
  /// los que quedan libres). [cajaEntradasId] es la caja de quien las recibió,
  /// si tenía una abierta: solo devolver no pide caja.
  factory MovimientoParaRendir.devolvio(
    MovimientoParaRendir bloque, {
    required List<TramoTalonario> tramos,
    String? cajaEntradasId,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    const que = 'no se puede devolver';
    _esUnBloque(que, bloque);
    if (tramos.isEmpty) _no(que, 'faltan los números de las que devuelve');
    _tramosSanos(que, tramos);
    final cantidad = _suma(tramos);
    if (cantidad > bloque.cantidad) {
      _no(que, 'devuelve $cantidad y se llevó ${bloque.cantidad}');
    }
    _delBloque(que, bloque, tramos);
    final iso = isoDe(ahora);
    return MovimientoParaRendir(
      id: UuidUtils.generate(),
      eventoId: bloque.eventoId,
      bloqueId: bloque.id,
      queClave: QueParaRendir.devolvio.clave,
      personaNombre: bloque.personaNombre,
      cantidad: cantidad,
      numeros: TramoTalonario.aTexto(tramos),
      cajaEntradasId: comoTextoONull(cajaEntradasId),
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// El jefe da por perdidas [cantidad] de [bloque], **con motivo**. Los números
  /// ([tramos]) son opcionales; si van, la cantidad justa y del bloque.
  factory MovimientoParaRendir.noVolvieron(
    MovimientoParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> tramos = const [],
    required String motivo,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    const que = 'no se puede dar por perdidas';
    _esUnBloque(que, bloque);
    final m = motivo.trim();
    if (m.isEmpty) _no(que, 'lleva motivo');
    if (cantidad < 1) _no(que, 'la cantidad va de 1 en adelante');
    if (cantidad > bloque.cantidad) {
      _no(que, 'son $cantidad y se llevó ${bloque.cantidad}');
    }
    if (tramos.isNotEmpty) {
      _tramosSanos(que, tramos);
      final numeros = _suma(tramos);
      if (numeros != cantidad) _no(que, 'son $numeros números y $cantidad entradas');
      _delBloque(que, bloque, tramos);
    }
    final iso = isoDe(ahora);
    return MovimientoParaRendir(
      id: UuidUtils.generate(),
      eventoId: bloque.eventoId,
      bloqueId: bloque.id,
      queClave: QueParaRendir.noVolvieron.clave,
      personaNombre: bloque.personaNombre,
      cantidad: cantidad,
      numeros: tramos.isEmpty ? null : TramoTalonario.aTexto(tramos),
      motivo: m,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// La anulación de [anulado], **con motivo**: un bloque (`dio`), un
  /// `devolvio` o un `no_volvieron`. **Un `vendio` no se anula acá**: se anula
  /// su venta en VENTAS, como cualquier venta. Tiene id fijo
  /// ([UuidUtils.entradasParaRendirAnulacionId]): dos equipos que anulan lo
  /// mismo dejan una sola fila.
  ///
  /// Que un bloque se anule solo sin movimientos vigentes lo revisa el
  /// repositorio, dentro de la transacción.
  factory MovimientoParaRendir.anulo(
    MovimientoParaRendir anulado, {
    required String motivo,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    const que = 'no se puede anular';
    final m = motivo.trim();
    if (m.isEmpty) _no(que, 'anular lleva motivo');
    switch (anulado.que) {
      case QueParaRendir.dio:
      case QueParaRendir.devolvio:
      case QueParaRendir.noVolvieron:
        break;
      case QueParaRendir.vendio:
        _no(que, 'lo vendido se anula en VENTAS, anulando su venta');
      case QueParaRendir.anulo:
        _no(que, 'una anulación no se anula');
      case null:
        _no(que, 'el renglón "${anulado.queClave}" no se conoce');
    }
    final iso = isoDe(ahora);
    return MovimientoParaRendir(
      id: UuidUtils.entradasParaRendirAnulacionId(anulado.id),
      eventoId: anulado.eventoId,
      bloqueId: anulado.bloqueId,
      queClave: QueParaRendir.anulo.clave,
      personaNombre: anulado.personaNombre,
      cantidad: anulado.cantidad,
      // Sin números: son los del renglón que anula ([anulaId]).
      anulaId: anulado.id,
      motivo: m,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  // ── Lo mínimo que el repositorio necesita para frenar ─────────────────────
  //    (la cuenta entera, con los avisos y los números, es `cuentas/`).

  /// Los ids de los renglones anulados en [movimientos].
  static Set<String> anuladosEn(Iterable<MovimientoParaRendir> movimientos) => {
        for (final m in movimientos)
          if (m.esAnulo && m.anulaId != null) m.anulaId!,
      };

  /// Lo que hoy cuenta de [bloque]: lo vendido cuya venta no está anulada
  /// ([ventasAnuladas]) y lo devuelto o perdido sin anular. **Un renglón que
  /// esta versión no conoce no cuenta** (no le cambia nada a nadie).
  static List<MovimientoParaRendir> vigentesDe(
    MovimientoParaRendir bloque,
    Iterable<MovimientoParaRendir> movimientos, {
    Set<String> ventasAnuladas = const {},
  }) {
    final todos = movimientos.toList();
    final anulados = anuladosEn(todos);
    return [
      for (final m in todos)
        if (m.bloqueId == bloque.id && m.id != bloque.id)
          if ((m.esVendio && !ventasAnuladas.contains(m.ventaId)) ||
              ((m.esDevolvio || m.esNoVolvieron) && !anulados.contains(m.id)))
            m,
    ];
  }

  /// Cuántas de [bloque] le quedan sin rendir: las que se llevó menos lo
  /// vendido, lo devuelto y lo que no volvió que siguen en pie. **Un bloque
  /// anulado no tiene nada que rendir**, y nunca da menos de 0.
  ///
  /// Es lo que el repositorio vuelve a contar dentro de la transacción antes de
  /// guardar una rendición: si la pantalla tenía la cuenta vieja (otro rindió
  /// en el medio), no se rinde de más.
  static int quedanSinRendir(
    MovimientoParaRendir bloque,
    Iterable<MovimientoParaRendir> movimientos, {
    Set<String> ventasAnuladas = const {},
  }) {
    if (!bloque.esDio) return 0;
    final todos = movimientos.toList();
    if (anuladosEn(todos).contains(bloque.id)) return 0;
    final usadas = vigentesDe(bloque, todos, ventasAnuladas: ventasAnuladas)
        .fold<int>(0, (s, m) => s + m.cantidad);
    final quedan = bloque.cantidad - usadas;
    return quedan < 0 ? 0 : quedan;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'bloque_id': bloqueId,
        'que': queClave,
        'persona_nombre': personaNombre,
        'persona_contacto': personaContacto,
        'contrato_alumno_id': contratoAlumnoId,
        'cantidad': cantidad,
        'numeros': numeros,
        'precio': precio,
        'nombre_precio': nombrePrecio,
        'con_pulseras': conPulseras ? 1 : 0,
        'venta_id': ventaId,
        'caja_entradas_id': cajaEntradasId,
        'anula_id': anulaId,
        'motivo': motivo,
        'nota': nota,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// **Nunca tira** (`lectura_de_filas`): una fila rara se muestra con ceros, no
  /// frena la lista. Un vínculo vacío se lee null.
  factory MovimientoParaRendir.fromMap(Map<String, dynamic> m) =>
      MovimientoParaRendir(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        bloqueId: comoTexto(m['bloque_id']),
        queClave: comoTexto(m['que']),
        personaNombre: comoTextoONull(m['persona_nombre']),
        personaContacto: comoTextoONull(m['persona_contacto']),
        contratoAlumnoId: comoTextoONull(m['contrato_alumno_id']),
        cantidad: comoInt(m['cantidad']),
        numeros: comoTextoONull(m['numeros']),
        precio: comoDoubleONull(m['precio']),
        nombrePrecio: comoTextoONull(m['nombre_precio']),
        conPulseras: comoBool(m['con_pulseras']),
        ventaId: comoTextoONull(m['venta_id']),
        cajaEntradasId: comoTextoONull(m['caja_entradas_id']),
        anulaId: comoTextoONull(m['anula_id']),
        motivo: comoTextoONull(m['motivo']),
        nota: comoTextoONull(m['nota']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}

/// Lo que guardó una rendición: la venta con la plata (si vendió algo) y los
/// renglones de lo vendido y lo devuelto. Todo junto, en una transacción.
class RendicionDeEntradas {
  final VentaEntradas? venta;
  final MovimientoParaRendir? vendio;
  final MovimientoParaRendir? devolvio;

  const RendicionDeEntradas({this.venta, this.vendio, this.devolvio});

  /// Los renglones de `entradas_para_rendir` que escribió, en orden.
  List<MovimientoParaRendir> get movimientos => [?vendio, ?devolvio];
}
