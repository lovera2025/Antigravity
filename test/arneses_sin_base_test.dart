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
// - las que llegan a PARA RENDIR reemplazan la constancia (regla 60);
// - las que llegan a PRECIOS ponen en memoria las otras fiestas que ofrece;
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
      // Los reemplazos de la venta en memoria puestos de verdad (no alcanza con
      // crear la venta en memoria y no ponerla).
      final enMemoria = s.contains('reemplazosDelCierre(') ||
          RegExp(r'(EntradasEnMemoria\(\)|\b_?venta|\bentradas)\.reemplazos')
              .hasMatch(s);
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

  test('el papel de la caja de entregas y la planilla de entrega no van a la carpeta del '
      'programa', () {
    // Revisión del 20-nov-2026: la ventana de la venta de entradas dejaba los dos
    // en Documentos\Junior Eventos con IMPRIMIR y PLANILLA.
    final faltan = <String>[];
    for (final ruta in ventanas) {
      final n = _nombre(ruta);
      final s = _leer(ruta);
      // `reemplazosDelCierre(` solo cuenta como llamada de verdad, no nombrado
      // en un comentario.
      final conLosDelCierre =
          RegExp(r'(overrides:\s*|\.\.\.)reemplazosDelCierre\(').hasMatch(s);
      if (s.contains('CierreCajaScreen(') &&
          !conLosDelCierre &&
          !s.contains('imprimirEntregasSinCargoProvider.overrideWith')) {
        faltan.add('$n: imprimirEntregasSinCargoProvider');
      }
      final muestraLaEntrega = [
        'VenderEntradasScreen',
        'RetiroEntradasScreen',
        'EntradasHomeScreen(',
      ].any(s.contains);
      if (muestraLaEntrega && !s.contains('imprimirPlanillaDeEntregaProvider.overrideWith')) {
        faltan.add('$n: imprimirPlanillaDeEntregaProvider');
      }
      // Un reemplazo que llama al camino de la app escribe igual en la carpeta.
      for (final directo in [
        'PdfService.generarEntregasSinCargo',
        'PdfService.generarPlanillaEntrega',
      ]) {
        if (s.contains(directo)) faltan.add('$n: llama a $directo');
      }
    }
    expect(faltan, isEmpty,
        reason: 'Estas ventanas escriben en la carpeta de PDF del programa: $faltan');
  });

  // Regla 60 de las entradas para rendir (21-nov-2026): la constancia para firmar
  // sale al DAR y con CONSTANCIA, en PARA RENDIR (`ParaRendirScreen(`), que se
  // abre desde ENTRADAS de la fiesta (la oficina, `RetiroEntradasScreen(`, que se
  // abre desde la pantalla de la fiesta, `DetalleEventoMasivoScreen(`; el
  // mostrador no la tiene): una ventana con cualquiera de las tres llega ahí, y
  // sin reemplazarla la dejaría en la
  // carpeta de PDF del programa. Esto mira el texto; que el reemplazo llegue de
  // verdad a cada lado de la ventana de la venta lo prueba
  // `test/venta_entradas_prueba_test.dart`.
  test('la constancia de las entradas para rendir no va a la carpeta del programa', () {
    final faltan = <String>[];
    for (final ruta in ventanas) {
      final n = _nombre(ruta);
      final s = _leer(ruta);
      final llegaAParaRendir = [
        'RetiroEntradasScreen(',
        'ParaRendirScreen(',
        'DetalleEventoMasivoScreen(',
      ].any(s.contains);
      if (llegaAParaRendir &&
          !s.contains('abrirConstanciaParaRendirProvider.overrideWith')) {
        faltan.add('$n: abrirConstanciaParaRendirProvider');
      }
      // Un reemplazo que la entrega por el camino de la app escribe igual en la
      // carpeta.
      if (s.contains('ConstanciaParaRendirPdf') && s.contains('PdfService.entregarPdf')) {
        faltan.add('$n: entrega la constancia con PdfService.entregarPdf');
      }
    }
    expect(faltan, isEmpty,
        reason: 'Estas ventanas escriben la constancia en la carpeta de PDF del '
            'programa: $faltan');
    // Y la regla mira algo: la ventana de la venta de entradas llega a PARA
    // RENDIR (el jefe, en ENTRADAS de la fiesta).
    expect(
      ventanas.map(_nombre),
      contains('venta_entradas_prueba.dart'),
    );
    expect(_leer('tool/venta_entradas_prueba.dart'), contains('RetiroEntradasScreen('));
  });

  // PRECIOS → "¿Poner estos precios también en otras fiestas?" (22-nov-2026) lee
  // las fiestas que vienen de la base (`fiestasParaLosPreciosProvider`). Una
  // ventana que llega a PRECIOS (ENTRADAS de la fiesta en la oficina,
  // `RetiroEntradasScreen(`, o la pantalla de la fiesta) las pone en memoria: con
  // la base cerrada no se rompe nada, pero el cartel no se vería nunca (así estaba
  // la de la venta de entradas). `EntregaEnMemoria.reemplazos()` ya las pone.
  test('las que llegan a PRECIOS ponen en memoria las otras fiestas', () {
    final faltan = <String>[];
    for (final ruta in ventanas) {
      final s = _leer(ruta);
      final llegaAPrecios =
          ['RetiroEntradasScreen(', 'DetalleEventoMasivoScreen('].any(s.contains);
      final enMemoria = s.contains('fiestasParaLosPreciosProvider.overrideWith') ||
          RegExp(r'\b_?(e|entrega)\.reemplazos\(').hasMatch(s);
      if (llegaAPrecios && !enMemoria) faltan.add(_nombre(ruta));
    }
    expect(faltan, isEmpty,
        reason: 'Estas ventanas leen las fiestas de PRECIOS de la base: $faltan');
    // Y la regla mira algo: la de la venta de entradas llega a PRECIOS.
    expect(_leer('tool/venta_entradas_prueba.dart'), contains('RetiroEntradasScreen('));
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
