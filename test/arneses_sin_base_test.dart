// Las ventanas de prueba (`tool/*_prueba.dart`) no tocan nada de verdad de la PC
// (6.9.0, etapa 7). Mirando los arneses aparecieron cinco que, con un clic,
// abrían la base de la PC (y la migraban), o escribían las preferencias del
// programa instalado o la carpeta de sus PDF. Este test lee el texto de las
// ventanas y de lo que reemplazan, y falla si vuelve a pasar:
// - toda ventana cierra la base al arrancar (`LocalDatabase.cerrarParaLaPrueba`):
//   si algún camino se escapa, falla en vez de abrir la de verdad;
// - toda ventana con providers usa preferencias en memoria;
// - las de la venta de entradas y el cierre de caja ponen la venta en memoria;
// - las de la barra reemplazan la central, el pedido del cierre y los PDF;
// - la lista de la puerta en memoria reemplaza todo lo que abre la base.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _leer(String ruta) =>
    File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

String _nombre(String ruta) => ruta.replaceAll('\\', '/').split('/').last;

/// Las ventanas: todo `tool/*_prueba.dart` y `tool/barra_prueba_web.dart`.
/// `salon_de_barra_prueba.dart` no es una ventana: la usan otras dos.
List<String> _ventanas() {
  final todas = Directory('tool')
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) {
    final n = _nombre(p);
    return (n.endsWith('_prueba.dart') || n == 'barra_prueba_web.dart') &&
        n != 'salon_de_barra_prueba.dart';
  }).toList()
    ..sort();
  return todas;
}

/// Las que no usan preferencias en memoria, con su motivo.
const _conLasPreferenciasDeVerdad = {
  // La ventana del tótem no escribe el archivo de preferencias (P8): el arnés
  // lo comprueba con el archivo de verdad, y no lo escribe.
  'kiosco_prueba.dart',
  // Solo para el navegador: ahí las preferencias son del navegador.
  'link_delegado_prueba.dart',
};

/// Las de la barra que corren en el navegador (`enLaWebProvider` en true): ahí no
/// hay base, ni central, ni pedido del cierre a la base.
const _barraEnLaWeb = {'barra_web_prueba.dart', 'encargada_web_prueba.dart'};

void main() {
  final ventanas = _ventanas();

  test('hay ventanas de prueba para mirar', () {
    expect(ventanas.length, greaterThan(10));
  });

  test('toda ventana cierra la base de la PC antes de arrancar', () {
    final sinCerrar = <String>[];
    for (final ruta in ventanas) {
      final s = _leer(ruta);
      final cierra = s.indexOf('LocalDatabase.cerrarParaLaPrueba();');
      final arranca = s.indexOf('runApp(');
      if (cierra < 0 || (arranca >= 0 && cierra > arranca)) {
        sinCerrar.add(_nombre(ruta));
      }
    }
    expect(sinCerrar, isEmpty,
        reason: 'Estas ventanas pueden abrir la base de la PC: $sinCerrar');
  });

  test('toda ventana con providers usa preferencias en memoria', () {
    final conLasDeVerdad = <String>[];
    for (final ruta in ventanas) {
      final n = _nombre(ruta);
      if (_conLasPreferenciasDeVerdad.contains(n)) continue;
      final s = _leer(ruta);
      final usaProviders = [
        'ProviderScope(',
        'ProviderContainer(',
        'armarLados(',
        '.recepcion(',
      ].any(s.contains);
      if (usaProviders && !s.contains('setMockInitialValues')) {
        conLasDeVerdad.add(n);
      }
    }
    expect(conLasDeVerdad, isEmpty,
        reason: 'Estas ventanas escriben las preferencias del programa '
            'instalado: $conLasDeVerdad');
  });

  test('la venta de entradas y el cierre de caja van en memoria', () {
    final conLaBase = <String>[];
    for (final ruta in ventanas) {
      final s = _leer(ruta);
      final muestra = [
        'EntradasHomeScreen(',
        'RetiroEntradasScreen',
        'VenderEntradasScreen',
        'CierreCajaScreen(',
      ].any(s.contains);
      final enMemoria =
          s.contains('EntradasEnMemoria') || s.contains('reemplazosDelCierre(');
      if (muestra && !enMemoria) conLaBase.add(_nombre(ruta));
    }
    expect(conLaBase, isEmpty,
        reason: 'Estas ventanas leen la venta de entradas de la base: $conLaBase');
  });

  test('la barra no va a la base, a la nube ni a la carpeta del programa', () {
    const hacenFalta = [
      'barraDeLaRedProvider',
      'bajarCierresDeLaBarraProvider',
      'guardarPdfDeLaBarraProvider',
    ];
    final faltan = <String>[];
    for (final ruta in [...ventanas, 'tool/salon_de_barra_prueba.dart']) {
      final n = _nombre(ruta);
      if (_barraEnLaWeb.contains(n)) continue;
      final s = _leer(ruta);
      if (!s.contains('BarraHomeScreen') && !s.contains('BarraJefeScreen')) {
        continue;
      }
      // Sus equipos salen de `salon_de_barra_prueba.dart`, que se mira acá mismo.
      if (s.contains("import 'salon_de_barra_prueba.dart';") &&
          !s.contains('ProviderContainer(')) {
        continue;
      }
      for (final p in hacenFalta) {
        if (!s.contains('$p.overrideWith')) faltan.add('$n: $p');
      }
    }
    expect(faltan, isEmpty, reason: 'Sin reemplazar: $faltan');
  });

  test('las de la barra en el navegador son del navegador', () {
    for (final n in _barraEnLaWeb) {
      expect(_leer('tool/$n'), contains('enLaWebProvider.overrideWithValue(true)'),
          reason: '$n está en la lista de la web y no lo es');
    }
  });

  test('la lista de la puerta en memoria no abre la base', () {
    final repo =
        _leer('lib/features/recepcion/repositories/invitados_repository.dart');
    final memoria = _leer('test/helpers/puerta_en_memoria.dart');
    final inicio = memoria.indexOf('class InvitadosEnMemoria');
    final fin = memoria.indexOf('\nclass ', inicio + 1);
    final clase = memoria.substring(inicio, fin < 0 ? memoria.length : fin);

    // Cada método público del repositorio, con su cuerpo hasta el siguiente.
    final metodo = RegExp(
      r'^  (?:Future|Stream)<[^\n]*?> (\w+)\(',
      multiLine: true,
    );
    final todos = metodo.allMatches(repo).toList();
    final abrenLaBase = <String>[];
    for (var i = 0; i < todos.length; i++) {
      final nombre = todos[i].group(1)!;
      if (nombre.startsWith('_')) continue;
      final hasta = i + 1 < todos.length ? todos[i + 1].start : repo.length;
      if (repo.substring(todos[i].start, hasta).contains('LocalDatabase.instance')) {
        abrenLaBase.add(nombre);
      }
    }
    expect(abrenLaBase, contains('forceRefresh'));

    final sinReemplazar = [
      for (final n in abrenLaBase)
        if (!RegExp('@override\\s+(?:Future|Stream)<[^\\n]*?> $n\\(')
            .hasMatch(clase))
          n,
    ];
    expect(sinReemplazar, isEmpty,
        reason: 'InvitadosEnMemoria no reemplaza estos, que abren la base: '
            '$sinReemplazar');
  });
}
