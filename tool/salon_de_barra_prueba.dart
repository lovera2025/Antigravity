// Lo que comparten las ventanas de prueba de la barra en red: un equipo (tablet o
// notebook) con su barra en memoria, sus operadores y la central de verdad. Sin base y
// sin nube. Lo usan `central_barra_prueba.dart` (las dos tablets y la notebook en esta PC)
// y `tablet_barra_prueba.dart` (el celular o la tablet, por el wifi de verdad).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/services/barras_del_salon.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/operador_caja.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/dashboard/widgets/actualizar_app.dart';
import 'package:arguello_events/models/evento.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

final idPuertoViejo = BarraEnPrueba.id(1);

/// La fiesta de la prueba: PUERTO VIEJO, hoy.
List<Evento> fiestasDePrueba() => [fiestaDePrueba(idPuertoViejo, 'PUERTO VIEJO', DateTime.now())];

/// El catálogo y los precios de PUERTO VIEJO, los mismos en todos los equipos (como si
/// los hubieran bajado de la nube antes de la fiesta).
BarraEnMemoria catalogoDePrueba() {
  final catalogo = BarraEnMemoria();
  var orden = 0;
  for (final (nombre, categoria, precio, stock) in [
    ('Cerveza lata', 'Cervezas', 3500.0, 24),
    ('Fernet con coca', 'Tragos', 6000.0, null),
    ('Gin tonic', 'Tragos', 7000.0, null),
    ('Speed con vodka', 'Tragos', 8000.0, 6),
    ('Agua sin gas', 'Sin alcohol', 1000.0, 4),
    ('Silla extra', 'Sillas', 8000.0, null),
  ]) {
    final p = catalogo.producto(nombre, categoria: categoria, orden: orden);
    catalogo.precio(idPuertoViejo, p, precio, orden: orden, stock: stock, aviso: stock == null ? null : 2);
    orden++;
  }
  return catalogo;
}

/// Lo guardado en el equipo, en memoria: cada lado tiene el suyo (y sobrevive a
/// "reiniciar la notebook" en la ventana de prueba).
class GuardadoDePrueba extends GuardadoDeLaCentral {
  CentralGuardada? central;
  DondeEstaLaCentral? donde;

  String? get fiesta => central?.eventoId;

  @override
  Future<CentralGuardada?> prendida() async => central;

  @override
  Future<void> anotarPrendida(String? eventoId, {String? barra, DateTime? ahora}) async => central =
      eventoId == null ? null : CentralGuardada(eventoId: eventoId, desde: ahora ?? DateTime.now(), barra: barra);

  @override
  Future<DondeEstaLaCentral?> aMano() async => donde;

  @override
  Future<void> anotarAMano(DondeEstaLaCentral? d) async => donde = d;
}

/// La barra recordada de un equipo de la prueba (Barra 1 · Barra 2), en memoria.
class BarraDelEquipoEnMemoria extends BarraDelEquipo {
  BarraDelEquipoEnMemoria([this.barra]);

  String? barra;

  @override
  Future<String?> leer() async => barraDe(barra);

  @override
  Future<void> guardar(String? b) async {
    if (barraDe(b) != null) barra = barraDe(b);
  }
}

/// Por dónde habla un equipo de la prueba con los demás. Lo que queda en null es lo de
/// la app: escuchar en todas las direcciones, los puertos de siempre (8797 y 8777) y
/// buscar por toda la red.
class RedDePrueba {
  const RedDePrueba({
    this.escucha,
    this.puertoCentral,
    this.puertoBusqueda,
    this.destinos,
    this.direcciones,
    this.puertosQuePregunta,
  });

  /// Todo dentro de esta PC: sin cartel del cortafuegos y sin salir a la red.
  RedDePrueba.enEstaPc({required int puertoBusqueda})
      : this(
          escucha: InternetAddress.loopbackIPv4,
          puertoCentral: 0,
          puertoBusqueda: puertoBusqueda,
          destinos: () async => [InternetAddress.loopbackIPv4],
          direcciones: () async => ['127.0.0.1'],
        );

  /// La de la app, por el wifi de verdad.
  static const delSalon = RedDePrueba();

  /// Una tablet en esta PC que busca la central de verdad de esta misma PC.
  static final tabletEnLaPc = RedDePrueba(destinos: () async => [InternetAddress.loopbackIPv4]);

  final InternetAddress? escucha;
  final int? puertoCentral;
  final int? puertoBusqueda;
  final Future<List<InternetAddress>> Function()? destinos;
  final Future<List<String>> Function()? direcciones;

  /// A qué puertos pregunta por las centrales (25-nov-2026: con las dos barras en esta PC,
  /// cada central contesta en el suyo). La lista se puede cambiar con la ventana abierta:
  /// así se "juntan" y se "separan" las redes de las dos barras.
  final List<int>? puertosQuePregunta;

  List<Override> get reemplazos => [
        if (escucha != null) escuchaCentralBarraProvider.overrideWithValue(escucha!),
        if (puertoCentral != null) puertoCentralBarraProvider.overrideWithValue(puertoCentral!),
        if (puertoBusqueda != null) puertoBusquedaBarraProvider.overrideWithValue(puertoBusqueda!),
        if (destinos != null) destinosBusquedaBarraProvider.overrideWithValue(destinos!),
        if (direcciones != null) direccionesCentralBarraProvider.overrideWithValue(direcciones!),
        if (puertosQuePregunta != null) puertosQuePreguntaBarraProvider.overrideWithValue(puertosQuePregunta!),
      ];
}

/// Un equipo de la prueba: sus providers y su barra.
class EquipoDePrueba {
  EquipoDePrueba(this.nombre, this.container, this.barra, this.conexion, {this.operador});

  final String nombre;
  final ProviderContainer container;
  final BarraEnMemoria barra;
  final ConexionFija conexion;

  /// La cajera (o la encargada) de este equipo, si tiene.
  final OperadorCaja? operador;
}

/// Un equipo con su barra en memoria (con el [catalogo]), su cajera si la tiene, y la
/// central por la [red]. [papel] null es la impresora de verdad (la que se elige con el
/// ícono de VENDER); si no, los papeles quedan en memoria.
EquipoDePrueba armarEquipo({
  required String id,
  required String nombre,
  required BarraEnMemoria catalogo,
  required List<Evento> eventos,
  required RedDePrueba red,
  String? cajera,
  String? pin,
  bool jefe = false,
  bool encargada = false,
  String? barraDelEquipo,
  PapelEnMemoria? papel,
  DateTime Function()? reloj,
  BarraEnMemoria? deAntes,
  GuardadoDePrueba? guardado,
}) {
  // [deAntes]: la misma barra de un equipo que se "reinicia" (la base queda).
  final barra = deAntes ??
      (BarraEnMemoria()
        ..equipo = id
        ..reloj = (() => (reloj ?? DateTime.now)().toUtc()));
  if (deAntes == null) {
    barra.productosGuardados.addAll(catalogo.productosGuardados);
    barra.preciosGuardados.addAll(catalogo.preciosGuardados);
  }
  final operadores = OperadoresEnPrueba();
  if (cajera != null) {
    final opId = 'a0000000-0000-4000-8000-${(cajera.hashCode & 0xffffff).toString().padLeft(12, '0')}';
    operadores.operadores.lista.add(operadorDePrueba(opId, cajera, pin!));
    operadores.permisos.poner(opId, PermisosEfectivos(barra: true, encargadaBarra: encargada));
  }
  final aviso = AvisoALaRed();
  final conLaRed = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
  var alDia = DateTime.now();
  final overrides = <Override>[
    ...operadores.reemplazos,
    avisoALaRedProvider.overrideWithValue(aviso),
    barraDeEsteEquipoProvider.overrideWithValue(conLaRed),
    barraDeLaRedProvider.overrideWithValue(barra),
    eventosDeLaBarraProvider.overrideWith((ref) async => eventos),
    if (papel != null) papelDeLaBarraProvider.overrideWithValue(papel),
    subirVentaProvider.overrideWithValue((v) async {}),
    subirDeLaBarraProvider.overrideWithValue((tabla, id) async {}),
    // Ni la nube ni la carpeta del programa (6.9.0, etapa 7): el pedido del cierre no
    // pregunta a ningún lado (cruza por la red del salón) y los PDF no se guardan.
    bajarCierresDeLaBarraProvider.overrideWithValue(() async {}),
    guardarPdfDeLaBarraProvider.overrideWithValue((lineas, {required titulo, required nombre, context}) async {}),
    accesosBarraProvider.overrideWithValue(AccesosBarra(
      bajar: () async => operadores.conexion.currentStatus == AppConnectivity.online,
      contarFiestas: () async => (await barra.fiestasConPrecio()).length,
      contarSinSubir: barra.ventasSinSubir,
      contarPendientes: barra.pendientesDeLaBarra,
      leerAlDia: () async => alDia,
      anotarAlDia: (c) async => alDia = c,
    )),
    ...red.reemplazos,
    equipoDeLaBarraProvider.overrideWithValue(() async => id),
    guardadoDeLaCentralProvider.overrideWithValue(guardado ?? GuardadoDePrueba()),
    // La barra de cada equipo, en memoria: en la ventana todos comparten las preferencias.
    barraDelEquipoProvider.overrideWithValue(BarraDelEquipoEnMemoria(barraDelEquipo)),
    if (reloj != null) relojDeLaBarraProvider.overrideWithValue(reloj),
    if (jefe) esRolJefeProvider.overrideWithValue(true),
    if (jefe) relojDelJefeProvider.overrideWithValue(reloj ?? DateTime.now),
    // Nada de salir a GitHub a buscar versiones desde una prueba.
    versionNuevaEnLaTabletProvider.overrideWith((ref) async => null),
  ];
  return EquipoDePrueba(
    nombre,
    ProviderContainer(overrides: overrides),
    barra,
    operadores.conexion,
    operador: operadores.operadores.lista.firstOrNull,
  );
}

/// La cajera: el PIN y, adentro, la barra.
class CajeraDePrueba extends ConsumerWidget {
  const CajeraDePrueba({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    return switch (destinoDeEntrada(app)) {
      DestinoDeEntrada.barra => const BarraHomeScreen(),
      _ => const RoleGateScreen(),
    };
  }
}
