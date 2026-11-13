import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pc_despierta_stub.dart'
    if (dart.library.ffi) 'pc_despierta_windows.dart' as sistema;

/// Cada cuánto se le avisa a Windows que la PC está en uso. Menos que el
/// minuto, que es lo más corto que Windows deja poner para apagar la pantalla.
const kCadaCuantoSeAvisa = Duration(seconds: 30);

/// Le dice al sistema "hay uso". Solo hace algo en Windows; las pruebas lo
/// reemplazan.
final avisarUsoAlSistemaProvider =
    Provider<void Function()>((ref) => sistema.avisarUsoAlSistema);

/// Que la notebook no apague la pantalla ni se suspenda mientras trabaja sola.
///
/// La noche de la fiesta nadie toca la notebook del salón: se marca desde los
/// celulares y la tele solo muestra. Windows la toma por abandonada, apaga la
/// pantalla (la tele queda en negro) y después la suspende (la central deja de
/// contestarles a los celulares y nada sube). Hasta la 6.8.0 no había nada que
/// lo impidiera (revisión del 13-nov).
///
/// Mientras está [prendida], cada [cada] se le avisa a Windows que hay uso
/// (`SetThreadExecutionState`, sin `ES_CONTINUOUS`): eso solo vuelve a cero sus
/// relojes de inactividad. **No deja nada prendido que haya que soltar**: si el
/// programa se cierra o se cuelga, a los pocos minutos la PC vuelve a su plan
/// de energía de siempre.
///
/// La usan la ventana del tótem mientras está a la vista y las dos centrales
/// (la de la puerta y la de la barra) mientras están prendidas. No alcanza si
/// se cierra la tapa o se aprieta el botón de apagado: eso se configura en
/// Windows.
class PcDespierta {
  PcDespierta({required this.avisar, this.cada = kCadaCuantoSeAvisa});

  final void Function() avisar;
  final Duration cada;
  Timer? _reloj;

  bool get prendida => _reloj != null;

  void mantener(bool si) {
    if (si == prendida) return;
    _reloj?.cancel();
    _reloj = null;
    if (!si) return;
    avisar();
    _reloj = Timer.periodic(cada, (_) => avisar());
  }
}
