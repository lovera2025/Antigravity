// **La página del iPhone de la barra, para mirarla en un navegador** (28-nov-2026), sin
// base ni nube: una notebook de la barra en memoria, con su central de verdad en esta PC
// (127.0.0.1:8810), sirviendo `build/barra_pagina` (armada antes con
// `flutter build web --release -t lib/barra_pagina_main.dart --no-web-resources-cdn -o build/barra_pagina`).
//
//   flutter test tool/barra_pagina_servidor_test.dart --timeout=none --dart-define=minutos=40
//
// (o `preview_start` con `barra-pagina-prueba`). Entran: Romi 7777 (encargada), Nico 5555
// (repositor) y el jefe con 2026. Una tablet de mentira (Marta, Caja 1) vende sola cada
// 20 segundos, y a los 2 minutos pide cerrar su caja: el OK le llega a la encargada.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/pagina/catalogo_de_la_pagina.dart';

import '../test/helpers/barra_en_memoria.dart';

const _minutos = int.fromEnvironment('minutos', defaultValue: 30);
const _puerto = 8810;

void main() {
  test('la central de la barra sirve la página del iPhone', () async {
    final carpeta = Directory('build${Platform.pathSeparator}barra_pagina');
    if (!File('${carpeta.path}${Platform.pathSeparator}index.html').existsSync()) {
      fail('Falta build/barra_pagina: armala con flutter build web -t lib/barra_pagina_main.dart '
          '--no-web-resources-cdn -o build/barra_pagina');
    }
    final fiesta = fiestaDePrueba(BarraEnPrueba.id(1), 'TÉCNICA PINAROLI', DateTime.now().add(const Duration(hours: 1)));
    final personas = QuienEsQuienEnMemoria()
      ..persona('op-marta', 'Marta', pin: '1111', rol: RolEnLaBarra.cajera)
      ..persona('op-romi', 'Romi', pin: '7777', rol: RolEnLaBarra.encargada)
      ..persona('op-nico', 'Nico', pin: '5555', rol: RolEnLaBarra.repositor);

    final notebook = BarraEnMemoria()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    final speed = notebook.producto('Speed', categoria: 'Energizantes', orden: 0);
    final cerveza = notebook.producto('Cerveza lata', categoria: 'Cervezas', orden: 1);
    final fernet = notebook.producto('Fernet con coca', categoria: 'Tragos', orden: 2);
    notebook.precio(fiesta.id, speed, 5000, stock: 96, aviso: 10);
    notebook.precio(fiesta.id, cerveza, 3500, stock: 240, aviso: 24);
    notebook.precio(fiesta.id, fernet, 6000);
    for (final (p, n) in [(speed, 48), (cerveza, 120)]) {
      await notebook.guardarReparto(
        StockEnLaBarra.para(eventoId: fiesta.id, productoId: p.id, barra: 'Barra 1', arranque: n, aviso: 6, ahora: DateTime.now()),
        quien: 'Jefe',
      );
    }

    final central = CentralBarra(
      eventoId: fiesta.id,
      barra: notebook,
      quienEsQuien: personas,
      barraDelSalon: 'Barra 1',
      paginaDeLaBarra: carpeta,
      fiestaParaLaPagina: () async => fiestaParaLaPagina(fiesta),
      catalogoParaLaPagina: () => catalogoParaLaPagina(notebook, fiesta.id),
      alGuardarDeLaPagina: (tabla, id) => print('── la notebook sube $tabla $id'),
    );
    final puerto = await central.arrancar(desde: _puerto, en: InternetAddress.loopbackIPv4);
    print('── La página: http://127.0.0.1:$puerto/  (Romi 7777 · Nico 5555 · jefe 2026)');

    // La tablet de Marta, con su caja, que vende sola.
    final tablet = BarraEnMemoria()..equipo = 'tablet-marta';
    tablet.reloj = () => DateTime.now().toUtc();
    final cliente = ClienteDeLaCentral(
      credencial: () async => CredencialDeLaBarra.operador('op-marta', '1111'),
      eventoId: fiesta.id,
      equipo: 'tablet-marta',
      nombreCaja: 'Caja 1 · Marta',
      barra: tablet,
      barraDeLaCaja: 'Barra 1',
      aMano: DondeEstaLaCentral('127.0.0.1', puerto),
    );
    cliente.arrancar();
    final aviso = AvisoALaRed()..salida = cliente.mandar;
    final caja = BarraConLaRed(caja: tablet, jefe: tablet, red: tablet, aviso: aviso);
    while (!cliente.conectada) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final suya = await caja.abrirCaja(
        eventoId: fiesta.id, operadorId: 'op-marta', operadorNombre: 'Marta', numeroCaja: 1, sede: 'Barra 1');
    var n = 0;
    Future<void> vender() async {
      n++;
      final p = [speed, cerveza, fernet][n % 3];
      final precio = [5000.0, 3500.0, 6000.0][n % 3];
      await caja.vender(
        caja: suya,
        renglones: [RenglonVenta(productoId: p.id, nombre: p.nombre, precio: precio, cantidad: 1 + n % 2)],
        medio: n % 4 == 0 ? MedioBarra.transferencia : MedioBarra.efectivo,
        efectivo: n % 4 == 0 ? 0 : precio * (1 + n % 2),
        transferencia: n % 4 == 0 ? precio * (1 + n % 2) : 0,
        quien: 'Marta',
      );
    }

    for (var i = 0; i < 6; i++) {
      await vender();
    }
    final fin = DateTime.now().add(const Duration(minutes: _minutos));
    var pidio = false;
    final arranco = DateTime.now();
    while (DateTime.now().isBefore(fin)) {
      await Future<void>.delayed(const Duration(seconds: 20));
      if (!pidio && DateTime.now().difference(arranco) > const Duration(minutes: 2)) {
        pidio = true;
        await caja.anotarPasoDelCierre(PasoDelCierre.pedir(
          caja: (await tablet.cajas(fiesta.id)).firstWhere((c) => c.id == suya.id),
          efectivoContado: 20000,
          hechoPor: 'Marta',
          ahora: DateTime.now(),
        ));
        print('── Marta pidió cerrar su caja');
      } else if (!pidio) {
        await vender();
      }
    }
    cliente.dispose();
    await central.cerrar();
  }, timeout: Timeout.none);
}
