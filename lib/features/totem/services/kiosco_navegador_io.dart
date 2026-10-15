import 'kiosco.dart';

/// Fuera del navegador no hay pantalla completa del navegador: nunca se usa,
/// existe para que compile el escritorio (ver `kiosco_navegador.dart`).
class KioscoNavegador implements Kiosco {
  const KioscoNavegador();

  @override
  Future<bool> entrar() async => false;

  @override
  Future<bool> salir() async => true;

  @override
  bool? get activo => null;
}
