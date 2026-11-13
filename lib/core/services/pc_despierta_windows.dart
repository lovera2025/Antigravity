import 'dart:ffi';
import 'dart:io';

typedef _Nativa = Uint32 Function(Uint32);
typedef _EnDart = int Function(int);

/// `ES_SYSTEM_REQUIRED`: vuelve a cero el reloj de suspender.
const _sistemaEnUso = 0x00000001;

/// `ES_DISPLAY_REQUIRED`: vuelve a cero el reloj de apagar la pantalla.
const _pantallaEnUso = 0x00000002;

_EnDart? _funcion;
bool _noSePuede = false;

/// Le avisa a Windows que la PC está en uso: vuelve a cero sus relojes de
/// apagar la pantalla y de suspender. Devuelve si Windows lo tomó.
///
/// Sin `ES_CONTINUOUS` a propósito: no queda ningún pedido en pie, hay que
/// repetirlo cada tanto (`PcDespierta`). En Android no hace nada (la tablet
/// usa `PantallaDespierta`), y en las pruebas tampoco.
bool avisarUsoAlSistema() {
  if (_noSePuede || !Platform.isWindows) return false;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  try {
    final f = _funcion ??= DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_Nativa, _EnDart>('SetThreadExecutionState');
    return f(_sistemaEnUso | _pantallaEnUso) != 0;
  } catch (_) {
    // Si esta PC no lo tiene, no se insiste: queda su plan de energía.
    _noSePuede = true;
    return false;
  }
}
