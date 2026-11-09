import 'dart:async';
import 'dart:typed_data';

import 'canal_ble.dart';
import 'impresora_recordada.dart';

export 'impresora_recordada.dart';

/// Por dónde le escriben las impresoras térmicas, en orden de preferencia. Los tres
/// primeros son los que trae la TP-POS58.
const _preferidas = [
  // UART de ISSC/Microchip.
  '49535343-8841-43f4-a8d4-ecbe34729bb3',
  // El servicio FF00 de las impresoras chinas: FF02 es la escritura.
  '0000ff02-0000-1000-8000-00805f9b34fb',
  // El servicio E7810A71 de las térmicas portátiles.
  'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
];

/// Los servicios que trae todo aparato Bluetooth y no son para imprimir: nombre,
/// batería, datos del fabricante.
const _deSistema = [
  '00001800-0000-1000-8000-00805f9b34fb',
  '00001801-0000-1000-8000-00805f9b34fb',
  '0000180a-0000-1000-8000-00805f9b34fb',
  '0000180f-0000-1000-8000-00805f9b34fb',
];

/// Por cuál característica se le manda el ticket: una conocida si está y, si no, la
/// primera de un servicio que no sea del sistema. Así anda con "lo que se detecte",
/// no solo con este modelo. Null si no hay por dónde escribirle.
CaracteristicaBle? elegirCaracteristica(Iterable<CaracteristicaBle> todas) {
  final utiles = [
    for (final c in todas)
      if ((c.escribe || c.escribeSinRespuesta) &&
          !_deSistema.contains(c.servicio.toLowerCase()))
        c,
  ];
  for (final uuid in _preferidas) {
    for (final c in utiles) {
      if (c.uuid.toLowerCase() == uuid) return c;
    }
  }
  return utiles.isEmpty ? null : utiles.first;
}

/// De a cuánto se manda, según lo negociado: tres bytes son del protocolo, y las
/// térmicas no aguantan trozos muy grandes. Sin saberlo, los 20 que anda siempre.
int tamanoDeTrozo(int? mtu) {
  if (mtu == null) return 20;
  final util = mtu - 3;
  if (util < 20) return 20;
  return util > 180 ? 180 : util;
}

/// Los bytes en trozos, en orden y sin perder ninguno.
List<Uint8List> partirEnTrozos(List<int> bytes, int tamano) {
  final datos = Uint8List.fromList(bytes);
  return [
    for (var i = 0; i < datos.length; i += tamano)
      Uint8List.sublistView(
        datos,
        i,
        i + tamano > datos.length ? datos.length : i + tamano,
      ),
  ];
}

/// Qué le pareció de impresora a este nombre, para ponerla primera en la lista.
bool pareceImpresora(String nombre) => RegExp(
      r'POS|PRINT|PT-?\d|MTP|RPP|TP-|TERMAL|THERMAL|58',
      caseSensitive: false,
    ).hasMatch(nombre);

enum ResultadoImpresion {
  impreso,

  /// En este equipo nunca se eligió una impresora.
  sinImpresoraElegida,

  /// Hay una elegida, pero no contesta: apagada, lejos o sin batería.
  noConectada,

  /// Se cortó mandando, y también al volver a probar.
  fallo,

  /// La impresora dijo que no tiene papel: no se mandó nada.
  sinPapel,
}

/// Lo que la impresora dice del rollo.
enum EstadoDelPapel {
  hay,

  /// El sensor de "queda poco" (no todas lo tienen).
  poco,
  noHay,

  /// No contestó, o contestó algo que no es la respuesta del papel. Se imprime
  /// igual, como siempre: no saber nunca frena un vale.
  noSeSabe,
}

/// La pregunta por el papel de ESC/POS: `DLE EOT 4`. Es de las de tiempo real:
/// la impresora la contesta aunque esté ocupada y no la imprime.
const consultaDelPapel = [0x10, 0x04, 0x04];

/// Qué dice el byte que contesta la impresora a [consultaDelPapel]. Los bits 1
/// y 4 van siempre prendidos y el 0 y el 7 apagados: si no, no es la respuesta
/// del papel. Los bits 2 y 3 son "queda poco"; el 5 y el 6, "no hay".
EstadoDelPapel estadoDelPapel(List<int> respuesta) {
  if (respuesta.isEmpty) return EstadoDelPapel.noSeSabe;
  final b = respuesta.last;
  if (b & 0x93 != 0x12) return EstadoDelPapel.noSeSabe;
  if (b & 0x60 != 0) return EstadoDelPapel.noHay;
  if (b & 0x0c != 0) return EstadoDelPapel.poco;
  return EstadoDelPapel.hay;
}

/// Por dónde puede contestar: las que avisan, fuera de los servicios del sistema.
/// Primero las del mismo servicio que la de escribir: la TP-POS58 contesta por el
/// UART de ISSC (`49535343-1e4d-…`).
List<CaracteristicaBle> caracteristicasQueContestan(
  Iterable<CaracteristicaBle> todas, {
  CaracteristicaBle? escritura,
}) {
  final utiles = [
    for (final c in todas)
      if ((c.avisa || c.indica) && !_deSistema.contains(c.servicio.toLowerCase())) c,
  ];
  final mismo = escritura?.servicio.toLowerCase();
  return [
    for (final c in utiles)
      if (c.servicio.toLowerCase() == mismo) c,
    for (final c in utiles)
      if (c.servicio.toLowerCase() != mismo) c,
  ];
}

/// Cómo quedó la impresora después de [ImpresoraBluetooth.reconectar].
enum EstadoImpresora { lista, sinElegir, noContesta }

/// La impresora de la barra: conectarse y mandarle bytes. Lo que dice el ticket lo
/// arma `TicketEscPos`; acá no se sabe qué se imprime.
///
/// Se elige una vez por equipo ([conectar]) y después se conecta sola: antes de cada
/// ticket mira si sigue conectada y, si no, vuelve a la que quedó recordada.
class ImpresoraBluetooth {
  final CanalBle canal;

  /// Entre trozo y trozo: sin esto, a la impresora se le llena el búfer y pierde
  /// renglones sin avisar.
  final Duration pausa;

  /// Dónde queda guardada la impresora de este equipo. Null: solo se recuerda mientras
  /// la pantalla está abierta.
  final ImpresoraRecordada? recordada;

  /// Cuánto se espera la respuesta del papel. Una que contesta lo hace en unas
  /// decenas de milisegundos.
  final Duration esperaDelPapel;

  String? _id;
  CaracteristicaBle? _caracteristica;
  List<CaracteristicaBle> _contestan = const [];
  int _tamano = tamanoDeTrozo(null);
  Future<void> _ultimo = Future<void>.value();
  ImpresoraElegida? _elegida;
  bool _leyoLaRecordada = false;

  /// Si esta impresora contesta por el papel: null mientras no se le preguntó.
  /// Solo con `true` se pregunta antes de cada papel; una que no contesta
  /// imprime como siempre, sin esperar nada.
  bool? _contestaElPapel;

  ImpresoraBluetooth(
    this.canal, {
    this.pausa = const Duration(milliseconds: 20),
    this.recordada,
    this.esperaDelPapel = const Duration(milliseconds: 800),
  });

  String? get conectadaA => _id;
  CaracteristicaBle? get caracteristica => _caracteristica;
  int get tamano => _tamano;

  /// Por dónde puede contestar la impresora conectada.
  List<CaracteristicaBle> get contestan => _contestan;

  /// Si contestó por el papel alguna vez (null: todavía no se le preguntó).
  bool? get contestaElPapel => _contestaElPapel;

  final _apodos = <String, String>{};
  bool _leyoApodos = false;

  /// El nombre que se le puso a cada impresora en este equipo, por id (6.4.0).
  Future<Map<String, String>> apodos() async {
    if (!_leyoApodos) {
      _apodos.addAll(await recordada?.apodos() ?? const {});
      _leyoApodos = true;
    }
    return Map.unmodifiable(_apodos);
  }

  /// Le pone nombre a la impresora [id] ("Impresora caja 1"); vacío se lo saca.
  Future<void> ponerApodo(String id, String apodo) async {
    await apodos();
    final a = apodo.trim();
    if (a.isEmpty) {
      _apodos.remove(id);
    } else {
      _apodos[id] = a;
    }
    await recordada?.guardarApodos(Map.of(_apodos));
  }

  /// Cómo se la llama: el nombre que le pusieron o, si no, el suyo ("TP-POS58").
  Future<String> nombreDe(ImpresoraElegida impresora) async {
    final apodo = (await apodos())[impresora.id];
    if (apodo != null) return apodo;
    return impresora.nombre.isEmpty ? 'La impresora de este equipo' : impresora.nombre;
  }

  /// La impresora de este equipo, la conectada o la recordada. Null si nunca se eligió.
  Future<ImpresoraElegida?> elegida() async {
    if (!_leyoLaRecordada) {
      _elegida ??= await recordada?.leer();
      _leyoLaRecordada = true;
    }
    return _elegida;
  }

  /// Se conecta, busca por dónde escribirle y la deja como la impresora de este
  /// equipo. False si no tiene por dónde: ese aparato no queda elegido.
  Future<bool> conectar(String id, {String nombre = ''}) async {
    if (_id != null && _id != id) await desconectar();
    await canal.conectar(id);
    final todas = await canal.caracteristicas(id);
    final elegida = elegirCaracteristica(todas);
    if (elegida == null) {
      await canal.desconectar(id);
      return false;
    }
    // Otra impresora: lo que se sabía del papel era de la anterior.
    if (_elegida?.id != id) _contestaElPapel = null;
    _contestan = caracteristicasQueContestan(todas, escritura: elegida);
    int? mtu;
    try {
      mtu = await canal.pedirMtu(id, 512);
    } catch (_) {
      // Windows lo negocia solo y puede no dejar pedirlo: se manda de a 20.
    }
    _id = id;
    _caracteristica = elegida;
    _tamano = tamanoDeTrozo(mtu);
    await _recordar(id, nombre);
    return true;
  }

  Future<void> _recordar(String id, String nombre) async {
    final antes = _elegida;
    final ahora = ImpresoraElegida(
      id: id,
      nombre: nombre.isEmpty && antes?.id == id ? antes!.nombre : nombre,
    );
    _elegida = ahora;
    _leyoLaRecordada = true;
    if (antes == null || !antes.esLaMisma(ahora)) await recordada?.guardar(ahora);
  }

  /// La deja lista para imprimir: si sigue conectada no hace nada y, si no, se conecta
  /// a la de este equipo. Para llamarla al abrir VENDER, al volver del segundo plano y
  /// antes de cada ticket. Nunca tira.
  Future<EstadoImpresora> reconectar() async {
    final id = _id;
    if (id != null && await _sigueConectada(id)) return EstadoImpresora.lista;
    final destino = await elegida();
    if (destino == null) return EstadoImpresora.sinElegir;
    try {
      final ok = await conectar(destino.id, nombre: destino.nombre);
      return ok ? EstadoImpresora.lista : EstadoImpresora.noContesta;
    } catch (_) {
      _id = null;
      _caracteristica = null;
      return EstadoImpresora.noContesta;
    }
  }

  Future<bool> _sigueConectada(String id) async {
    try {
      return await canal.estaConectado(id);
    } catch (_) {
      return false;
    }
  }

  /// Corta la conexión, pero la impresora sigue siendo la de este equipo.
  Future<void> desconectar() async {
    final id = _id;
    _id = null;
    _caracteristica = null;
    _contestan = const [];
    if (id == null) return;
    try {
      await canal.desconectar(id);
    } catch (_) {}
  }

  /// Este equipo deja de tener impresora: hasta elegir otra, no imprime.
  Future<void> olvidar() async {
    await desconectar();
    _contestaElPapel = null;
    _elegida = null;
    _leyoLaRecordada = true;
    await recordada?.olvidar();
  }

  /// Manda [bytes] entero. **De a un ticket por vez:** dos a la vez saldrían
  /// mezclados en el papel. Nunca tira: dice cómo le fue.
  Future<ResultadoImpresion> imprimir(List<int> bytes) {
    final resultado = _ultimo.then((_) => _mandar(bytes));
    _ultimo = resultado.then<void>((_) {});
    return resultado;
  }

  /// Le pregunta a la impresora por el papel. **De a uno, con los papeles**: si
  /// hay un ticket saliendo, espera a que termine. Nunca tira. Para el arnés y
  /// para saber, al abrir VENDER, si esta impresora contesta; [crudo] recibe lo
  /// que volvió, byte por byte.
  Future<EstadoDelPapel> consultarPapel({void Function(List<int> crudo)? crudo}) {
    final resultado = _ultimo.then((_) async {
      if (await reconectar() != EstadoImpresora.lista) return EstadoDelPapel.noSeSabe;
      return _preguntarPorElPapel(crudo: crudo);
    });
    _ultimo = resultado.then<void>((_) {});
    return resultado;
  }

  /// Ya conectada: escucha por todas las que contestan, manda la pregunta y
  /// espera la primera respuesta, hasta [esperaDelPapel]. Nunca tira.
  Future<EstadoDelPapel> _preguntarPorElPapel({
    void Function(List<int> crudo)? crudo,
  }) async {
    final id = _id;
    final c = _caracteristica;
    if (id == null || c == null || _contestan.isEmpty) {
      _contestaElPapel ??= false;
      return EstadoDelPapel.noSeSabe;
    }
    final respuesta = Completer<List<int>>();
    final subs = <StreamSubscription<Uint8List>>[];
    try {
      for (final cc in _contestan) {
        subs.add(canal.escuchar(id, cc).listen(
          (bytes) {
            if (bytes.isNotEmpty && !respuesta.isCompleted) respuesta.complete(bytes);
          },
          onError: (Object _) {},
        ));
      }
      // Que la suscripción llegue antes de preguntar.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await canal.escribir(id, c, Uint8List.fromList(consultaDelPapel));
      final bytes = await respuesta.future.timeout(esperaDelPapel);
      crudo?.call(bytes);
      final estado = estadoDelPapel(bytes);
      if (estado != EstadoDelPapel.noSeSabe) {
        _contestaElPapel = true;
      } else {
        _contestaElPapel ??= false;
      }
      return estado;
    } on TimeoutException {
      // Una que ya contestó y ahora no: no se decide nada por una vez.
      _contestaElPapel ??= false;
      return EstadoDelPapel.noSeSabe;
    } catch (_) {
      return EstadoDelPapel.noSeSabe;
    } finally {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    }
  }

  Future<ResultadoImpresion> _mandar(List<int> bytes) async {
    switch (await reconectar()) {
      case EstadoImpresora.sinElegir:
        return ResultadoImpresion.sinImpresoraElegida;
      case EstadoImpresora.noContesta:
        return ResultadoImpresion.noConectada;
      case EstadoImpresora.lista:
        break;
    }
    // Sin papel, el vale "sale" igual (la escritura no tiene respuesta) y queda
    // anotado como impreso. Si esta impresora contesta, se le pregunta antes.
    if (_contestaElPapel == true &&
        await _preguntarPorElPapel() == EstadoDelPapel.noHay) {
      return ResultadoImpresion.sinPapel;
    }
    if (await _escribir(bytes)) return ResultadoImpresion.impreso;
    // Se cortó a la mitad. La conexión puede haber quedado colgada: se suelta, se
    // vuelve a conectar y se manda el ticket entero otra vez, una sola vez. Mejor un
    // pedazo repetido en el papel que un ticket que no sale.
    await desconectar();
    if (await reconectar() != EstadoImpresora.lista) return ResultadoImpresion.fallo;
    return await _escribir(bytes)
        ? ResultadoImpresion.impreso
        : ResultadoImpresion.fallo;
  }

  Future<bool> _escribir(List<int> bytes) async {
    final id = _id;
    final c = _caracteristica;
    if (id == null || c == null) return false;
    try {
      for (final trozo in partirEnTrozos(bytes, _tamano)) {
        await canal.escribir(id, c, trozo);
        if (pausa > Duration.zero) await Future<void>.delayed(pausa);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
