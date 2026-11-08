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
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
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

/// Lo guardado en el equipo, en memoria: cada lado tiene el suyo.
class GuardadoDePrueba extends GuardadoDeLaCentral {
  String? fiesta;
  DondeEstaLaCentral? donde;

  @override
  Future<String?> prendida({DateTime? ahora}) async => fiesta;

  @override
  Future<void> anotarPrendida(String? eventoId, {DateTime? ahora}) async => fiesta = eventoId;

  @override
  Future<DondeEstaLaCentral?> aMano() async => donde;

  @override
  Future<void> anotarAMano(DondeEstaLaCentral? d) async => donde = d;
}

/// Por dónde habla un equipo de la prueba con los demás. Lo que queda en null es lo de
/// la app: escuchar en todas las direcciones, los puertos de siempre (8797 y 8777) y
/// buscar por toda la red.
class RedDePrueba {
  const RedDePrueba({this.escucha, this.puertoCentral, this.puertoBusqueda, this.destinos, this.direcciones});

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

  List<Override> get reemplazos => [
        if (escucha != null) escuchaCentralBarraProvider.overrideWithValue(escucha!),
        if (puertoCentral != null) puertoCentralBarraProvider.overrideWithValue(puertoCentral!),
        if (puertoBusqueda != null) puertoBusquedaBarraProvider.overrideWithValue(puertoBusqueda!),
        if (destinos != null) destinosBusquedaBarraProvider.overrideWithValue(destinos!),
        if (direcciones != null) direccionesCentralBarraProvider.overrideWithValue(direcciones!),
      ];
}

/// Un equipo de la prueba: sus providers y su barra.
class EquipoDePrueba {
  EquipoDePrueba(this.nombre, this.container, this.barra, this.conexion);

  final String nombre;
  final ProviderContainer container;
  final BarraEnMemoria barra;
  final ConexionFija conexion;
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
  PapelEnMemoria? papel,
}) {
  final barra = BarraEnMemoria()
    ..equipo = id
    ..reloj = (() => DateTime.now().toUtc());
  barra.productosGuardados.addAll(catalogo.productosGuardados);
  barra.preciosGuardados.addAll(catalogo.preciosGuardados);
  final operadores = OperadoresEnPrueba();
  if (cajera != null) {
    final opId = 'a0000000-0000-4000-8000-${(cajera.hashCode & 0xffffff).toString().padLeft(12, '0')}';
    operadores.operadores.lista.add(operadorDePrueba(opId, cajera, pin!));
    operadores.permisos.poner(opId, const PermisosEfectivos(barra: true));
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
    guardadoDeLaCentralProvider.overrideWithValue(GuardadoDePrueba()),
    if (jefe) esRolJefeProvider.overrideWithValue(true),
    if (jefe) relojDelJefeProvider.overrideWithValue(DateTime.now),
    // Nada de salir a GitHub a buscar versiones desde una prueba.
    versionNuevaEnLaTabletProvider.overrideWith((ref) async => null),
  ];
  return EquipoDePrueba(nombre, ProviderContainer(overrides: overrides), barra, operadores.conexion);
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
