// El celular de la puerta (`ClienteCentral`) de mentira: la prueba le pone
// cada estado y mira lo que se le pidió. Lo usan `test/pantalla_puesto_test.dart`
// y `tool/celulares_muestra_test.dart`.
import 'dart:async';

import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';

import 'puerta_en_memoria.dart';

class _NadaGuardado implements GuardadoDelCelular {
  @override
  Future<String?> leer(String clave) async => null;

  @override
  Future<void> guardar(String clave, String? valor) async {}
}

/// El cliente, con el estado que pone la prueba y lo que se le pidió.
class ClienteDePrueba extends ClienteCentral {
  ClienteDePrueba()
      : super(
          servidor: Uri.parse('http://127.0.0.1:1/'),
          guardado: _NadaGuardado(),
        );

  EstadoDelPuesto e = EstadoDelPuesto.conectado;
  PuertaDelEvento? p;
  String? n = 'Juli';
  String? cod = '4821';
  String? tit = 'ESCUELA DE MUESTRA — Egresados (12/12) · masivo';
  List<PedidoPendiente> pend = [];
  int mandados = 0;
  Map<String, String> marcas = {};

  final ingresados = <String>[];
  final deshechos = <String>[];
  final datos = <(String, String?)>[];
  var reconexiones = 0;
  final avisosDePrueba = StreamController<String>.broadcast();

  void cambio() => notifyListeners();

  @override
  EstadoDelPuesto get estado => e;
  @override
  PuertaDelEvento? get puerta => p;
  @override
  String? get eventoId => p == null ? null : eventoMasivo;
  @override
  String? get nombre => n;
  @override
  String? get codigo => cod;
  @override
  String? get titulo => tit;
  @override
  List<PedidoPendiente> get pendientes => pend;
  @override
  int get seMandaron => mandados;
  @override
  Stream<String> get avisos => avisosDePrueba.stream;
  @override
  String? marca(String personaId) => marcas[personaId];

  @override
  Future<void> ingresar(PersonaPuerta persona) async =>
      ingresados.add(persona.id);
  @override
  Future<void> deshacer(PersonaPuerta persona) async =>
      deshechos.add(persona.id);
  @override
  Future<void> ponerDatos({required String nombre, String? codigo}) async =>
      datos.add((nombre, codigo));
  @override
  void reconectar() => reconexiones++;
}
