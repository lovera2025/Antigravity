import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lo que cambia el salón lo hace solo el jefe: armar y personalizar el plano,
/// sortear, deshacer, restaurar, y cambiar o mudar familias de mesa (ver
/// `lib/features/common/utils/solo_jefe.dart`).
///
/// Los botones llegan apagados sin modo jefe, y eso lo prueban los tests de la
/// barra y de la pantalla del plano. Acá se cuida la segunda llave: **cada
/// función que guarda el salón pregunta por el modo jefe antes de guardar**.
///
/// Las dos pantallas leen de la base con Riverpod y no se pueden montar en un
/// test, así que se leen del texto del archivo, igual que
/// `sync_tablas_v73_test` lee el motor. Importa porque es lo que evita que dos
/// PCs se pisen el plano: la fila sube entera, y con una sola PC cambiándola no
/// hay a quién pisar.
void main() {
  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantallaFiesta = 'lib/features/eventos/detalle_evento_masivo_screen.dart';
  const pantallaPlano = 'lib/features/plano/plano_evento_screen.dart';
  const mesaNuevaSolaDeLaApp =
      'lib/features/plano/services/mesa_nueva_sola_de_la_app.dart';

  /// Las dos llamadas por las que se guarda el salón: los números de mesa (con
  /// su renglón y, si hace falta, el plano) y el plano solo.
  final guardado = RegExp(r'\basignarNumerosMesa\(|\bplanos\.guardar\(');

  /// Donde empieza cada función de la pantalla.
  final funcion = RegExp(r'^  Future<void> (\w+)\(', multiLine: true);

  /// Las funciones de [ruta] que guardan el salón, cada una con si pregunta
  /// por el modo jefe **antes** de guardar.
  Map<String, bool> guardanElSalon(String ruta) {
    final fuente = leer(ruta);
    final funciones = funcion.allMatches(fuente).toList();
    final resultado = <String, bool>{};
    for (final g in guardado.allMatches(fuente)) {
      final donde = funciones.lastWhere(
        (f) => f.start < g.start,
        orElse: () => fail('un guardado fuera de una función, en $ruta'),
      );
      final hastaElGuardado = fuente.substring(donde.start, g.start);
      resultado[donde.group(1)!] =
          hastaElGuardado.contains('_frenaSinModoJefe()');
    }
    return resultado;
  }

  test('la fiesta: sortear, deshacer y restaurar preguntan por el modo jefe', () {
    final funciones = guardanElSalon(pantallaFiesta);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan el salón sin preguntar por el modo jefe',
    );
    // Si aparece una función nueva que guarda, que pregunte y se sume acá.
    expect(funciones.keys.toSet(), {
      '_ejecutarSorteo',
      '_ejecutarSorteoConPlano',
      '_deshacerSorteoMesas',
      '_restaurarSorteoAnterior',
    });
  });

  test('el plano: armar, personalizar y cambiar familias preguntan por el modo '
      'jefe', () {
    final funciones = guardanElSalon(pantallaPlano);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan el salón sin preguntar por el modo jefe',
    );
    expect(funciones.keys.toSet(), {'_guardar', '_cambiarConfig', '_cambiarMesas'});
  });

  test('OPERADORES: crear, cambiar, eliminar y dar permisos preguntan por el modo '
      'jefe', () {
    const ruta = 'lib/features/caja_sesiones/widgets/operadores_caja_screen.dart';
    final fuente = leer(ruta);
    final funciones = funcion.allMatches(fuente).toList();
    final escribe = RegExp(r'\.(crear|actualizar|eliminar)\(|\.guardar\(\s*operadorId');
    final encontradas = <String>{};
    for (final g in escribe.allMatches(fuente)) {
      final donde = funciones.lastWhere((f) => f.start < g.start);
      encontradas.add(donde.group(1)!);
      expect(
        fuente.substring(donde.start, g.start),
        contains('_frenaSinModoJefe()'),
        reason: '${donde.group(1)} escribe sin preguntar por el modo jefe',
      );
    }
    expect(encontradas, {'_eliminar', '_editar'});

    final i = fuente.indexOf('bool _frenaSinModoJefe() {');
    expect(i, greaterThan(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
    expect(cuerpo, contains('if (ref.read(esRolJefeProvider)) return false;'));
    expect(cuerpo, contains('return true;'));
  });

  test('los permisos los guarda solo la pantalla de OPERADORES', () {
    final guardan = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final fuente = f.readAsStringSync();
      if (fuente.contains('permisosOperadorRepositoryProvider') &&
          RegExp(r'\.guardar\(\s*operadorId').hasMatch(fuente)) {
        guardan.add(f.path.replaceAll('\\', '/'));
      }
    }
    expect(guardan, ['lib/features/caja_sesiones/widgets/operadores_caja_screen.dart']);
  });

  test('los predios (6.1.0): guardarlos, renombrarlos y borrarlos pregunta por '
      'el modo jefe', () {
    final fuente = leer(pantallaPlano);
    // Renombrar y borrar contestan qué pasó: no son `Future<void>`.
    final funciones = RegExp(r'^  Future<\w+> (\w+)\(', multiLine: true)
        .allMatches(fuente)
        .toList();
    final resultado = <String, bool>{};
    for (final g in RegExp(r'\bprediosRepo\.guardar\(').allMatches(fuente)) {
      final donde = funciones.lastWhere((f) => f.start < g.start);
      resultado[donde.group(1)!] = fuente
          .substring(donde.start, g.start)
          .contains('_frenaSinModoJefe()');
    }
    expect(
      resultado.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan un predio sin preguntar por el modo jefe',
    );
    // GUARDAR COMO PREDIO, y Renombrar y Borrar (los dos por `_cambiarPredio`).
    expect(resultado.keys.toSet(), {'_guardarComoPredio', '_cambiarPredio'});
    expect(fuente, contains('Future<CambioDePredios> _renombrarPredio('));
    expect(fuente, contains('Future<CambioDePredios> _borrarPredio('));
    expect(
      RegExp(r'_renombrarPredio\(Predio predio, String nombre\) =>\s+'
              r'_cambiarPredio\(')
          .hasMatch(fuente),
      isTrue,
    );
    expect(
      RegExp(r'_borrarPredio\(Predio predio\) => _cambiarPredio\(')
          .hasMatch(fuente),
      isTrue,
    );
  });

  test('nadie más guarda los predios', () {
    Set<String> archivosCon(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };
    const repo = 'lib/features/plano/repositories/predios_repository.dart';
    expect(archivosCon('prediosRepositoryProvider'), {pantallaPlano, repo});
    // Solo el repositorio lo llama, por dentro.
    expect(archivosCon('PrediosRepository.guardarEn('), isEmpty);
    // Quien solo los lee entra por una puerta que no deja guardar.
    expect(
      leer(repo),
      contains('(ref) => ref.watch(prediosRepositoryProvider).todos,'),
    );
  });

  test('BARRA del jefe (etapa 7): el catálogo, los precios, el recargo, anular y '
      'reimprimir preguntan por el modo jefe antes de guardar', () {
    final escribe = RegExp(
      r'\.(guardarProducto|guardarPrecio|guardarRecargo|anular)\(|\banotarValeQueSalio\(',
    );
    final funcion = RegExp(r'^  Future<\w+> (\w+)\(', multiLine: true);
    final encontradas = <String>{};
    final carpeta = Directory('lib/features/barra/jefe');
    for (final f in carpeta.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final fuente = leer(ruta);
      final funciones = funcion.allMatches(fuente).toList();
      for (final g in escribe.allMatches(fuente)) {
        final donde = funciones.lastWhere(
          (x) => x.start < g.start,
          orElse: () => fail('un guardado fuera de una función, en $ruta'),
        );
        encontradas.add(donde.group(1)!);
        expect(
          fuente.substring(donde.start, g.start),
          contains('_frenaSinModoJefe()'),
          reason: '${donde.group(1)} ($ruta) guarda sin preguntar por el modo jefe',
        );
      }
      if (escribe.hasMatch(fuente)) {
        final i = fuente.indexOf('bool _frenaSinModoJefe() {');
        expect(i, greaterThanOrEqualTo(0), reason: 'falta la llave en $ruta');
        final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
        // CAJAS (anular y reimprimir) es también de la Encargada de barra (6.4.0); el
        // catálogo, los precios y el recargo, solo del jefe.
        final llave = ruta.endsWith('/cajas_de_la_fiesta.dart')
            ? 'if (ref.read(mandaEnLaBarraProvider)) return false;'
            : 'if (ref.read(esRolJefeProvider)) return false;';
        expect(cuerpo, contains(llave), reason: ruta);
        expect(cuerpo, contains('return true;'), reason: ruta);
      }
    }
    // Si aparece otra función que guarda, que pregunte y se sume acá.
    expect(encontradas, {'_guardarProducto', '_guardar', '_anular', '_reimprimir'});
  });

  test('quien manda en las cajas de la barra es el jefe en modo jefe o la encargada, '
      'y nadie más', () {
    final fuente = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = fuente.indexOf('final mandaEnLaBarraProvider = Provider<bool>((ref) {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n});', i));
    expect(cuerpo, contains('if (ref.watch(esRolJefeProvider)) return true;'));
    expect(cuerpo, contains('return ref.watch(appRoleProvider).esEncargadaDeBarra;'));
    expect(
      fuente,
      contains('bool get esEncargadaDeBarra => esBarra && permisos.encargadaBarra;'),
    );
    // El catálogo y los precios no se abren a la encargada.
    for (final ruta in [
      'lib/features/barra/jefe/catalogo_del_jefe.dart',
      'lib/features/barra/jefe/precios_de_la_fiesta.dart',
    ]) {
      expect(leer(ruta), isNot(contains('mandaEnLaBarraProvider')), reason: ruta);
    }
  });

  test('la llave pregunta por el modo jefe de verdad', () {
    for (final ruta in [pantallaFiesta, pantallaPlano]) {
      final fuente = leer(ruta);
      final i = fuente.indexOf('bool _frenaSinModoJefe() {');
      expect(i, greaterThanOrEqualTo(0), reason: 'falta la llave en $ruta');
      final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
      expect(
        cuerpo,
        contains('if (ref.read(esRolJefeProvider)) return false;'),
        reason: ruta,
      );
      expect(cuerpo, contains('return true;'), reason: ruta);
    }
  });

  test('Editar alumno: el número de mesa escrito a mano pasa por la llave', () {
    final fuente =
        leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    // Lo escrito en el casillero se lee en un solo lugar: lo que se le pasa a
    // `numeroMesaParaGuardar`, que sin modo jefe devuelve el que ya tenía.
    expect(
      RegExp(r'_numeroMesaCtrl\.text').allMatches(fuente).length,
      1,
      reason: 'el casillero se lee por fuera de numeroMesaParaGuardar',
    );
    expect(
      fuente,
      contains('''
      final numeroMesa = numeroMesaParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.numeroMesa,
        escrito: _numeroMesaCtrl.text,
      );'''),
    );
    // Y el casillero se dibuja con el modo jefe de la sesión.
    expect(fuente, contains('final esJefe = ref.watch(esRolJefeProvider);'));
    expect(fuente, contains('CasilleroNumeroMesa('));
  });

  test('nadie más guarda el salón', () {
    // Los números de mesa, el renglón del cambio y el plano se escriben por
    // estos caminos. Si otra pantalla empieza a usarlos, tiene que preguntar
    // por el modo jefe y sumarse a los tests de arriba.
    Set<String> archivosCon(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };

    // La excepción, desde la 6.5.1: la mesa nueva que el programa le da sola a
    // quien pagó después del sorteo. Tiene su test aparte, acá abajo.
    expect(archivosCon('asignarNumerosMesa('), {
      pantallaFiesta,
      pantallaPlano,
      'lib/features/eventos/repositories/contratos_repository.dart',
      mesaNuevaSolaDeLaApp,
    });
    expect(archivosCon('planosEventoRepositoryProvider'), {
      pantallaFiesta,
      pantallaPlano,
      'lib/features/plano/repositories/planos_evento_repository.dart',
      mesaNuevaSolaDeLaApp,
    });
    // El tótem lee el plano por una puerta que solo deja leer.
    expect(
      File('lib/features/plano/repositories/planos_evento_repository.dart')
          .readAsStringSync(),
      contains('(ref) => ref.watch(planosEventoRepositoryProvider).obtener,'),
    );
    expect(archivosCon('PlanosEventoRepository.guardarEn('), {
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
    expect(archivosCon('MesasMovimientosRepository.registrarEn('), {
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
    // En la fiesta el plano solo se lee: guardarlo, lo guarda el sorteo junto
    // con los números, por `asignarNumerosMesa`.
    expect(leer(pantallaFiesta), isNot(contains('planos.guardar(')));
  });

  test('la mesa nueva sola (6.5.1) es lo único del salón que se guarda sin modo '
      'jefe, y es angosta', () {
    // Lo pidió el usuario el 10-nov-2026: a quien paga después del sorteo, el
    // programa le da su mesa sin que el jefe apriete SORTEO. Cambia la regla
    // de este archivo, y por eso queda escrito qué se le permite.
    Set<String> archivosCon(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };
    final adaptador = leer(mesaNuevaSolaDeLaApp);
    final servicio = leer('lib/features/plano/services/mesa_nueva_sola.dart');

    // El adaptador no decide nada: lee, y guarda una sola vez, por el mismo
    // camino del sorteo (todo junto, en una transacción).
    expect('asignarNumerosMesa('.allMatches(adaptador).length, 1);
    expect(adaptador, isNot(contains('_planos.guardar(')));
    expect(adaptador, isNot(contains('MesasNuevasAlFondo')));
    expect(adaptador, isNot(contains('SorteoConPlano')));
    expect(adaptador, isNot(contains('esRolJefeProvider')));

    // Lo que decide está en el servicio, con sus frenos:
    // se apaga en un solo lugar;
    expect(
      servicio,
      contains('if (!kMesaNuevaSolaHabilitada) return ResultadoMesaNueva.nada;'),
    );
    // la misma cuenta del candado, sin excepciones tildadas;
    expect(servicio, contains('soloPagado: true,'));
    expect(servicio, isNot(contains('incluirBase')));
    expect(servicio, isNot(contains('incluirExtras')));
    // solo a quien pagó después del último sorteo que hizo el jefe;
    expect(servicio, contains('final desde = ultimoDelJefe(registros);'));
    expect(servicio, contains('if (desde == null) return null;'));
    expect(servicio, contains('if (r.automatico) continue;'));
    // o a quien acaba de agregar una mesa, y solo con una cuota entera de su
    // contrato paga (regla del usuario, 11-nov);
    expect(
      servicio,
      contains('if (tieneUnaCuotaPaga(a, pagos[id] ?? const [])) id,'),
    );
    expect(servicio, contains(').cuotasBase >=\n      1;'));
    // solo con internet y sin mesas de otra PC por bajar;
    expect(servicio, contains('if (distintos == null) {'));
    expect(servicio, contains('if (distintos > 0) {'));
    expect(servicio, contains('EstadoMesaNueva.esperar,'));
    // y solo una mesa suya (una nueva, o una que el jefe le había fijado):
    // nunca una mesa libre del salón.
    expect(servicio, contains('if (!recibe.every(suyas.contains)) {'));

    // Quién la llama: el cobro de la fiesta, Editar alumno (al agregar una
    // mesa), y el que mira al abrir y cuando baja algo.
    expect(archivosCon('mesaNuevaSolaProvider'), {
      pantallaFiesta,
      'lib/features/eventos/widgets/modal_alumno_premium.dart',
      mesaNuevaSolaDeLaApp,
    });
    // Editar alumno la pide solo si la edición es "agregó una mesa".
    final modal = leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    expect(modal, contains('agregoUnaMesa = MesaNuevaSola.agregoUnaMesa('));
    expect(modal, contains('if (agregoUnaMesa) {'));
    expect(modal, contains('agregaron: {alumnoId},'));
    expect(archivosCon('vigiaDeLaMesaNuevaProvider'), {
      mesaNuevaSolaDeLaApp,
      'lib/features/common/widgets/operational_sync_coordinator.dart',
    });
  });

  test('Editar alumno: acompañantes y música pasan por la llave', () {
    final fuente =
        leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    final guardar = fuente.substring(fuente.indexOf('void _submit() async {'));
    final hastaElDibujo = guardar.substring(0, guardar.indexOf('Widget build('));
    // Al guardar, lo escrito en la ficha se lee en un solo lugar: lo que se le
    // pasa a cada llave, que sin modo jefe devuelve lo que el alumno ya tenía.
    expect(
      hastaElDibujo,
      contains('''
      final acompanantes = acompanantesParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.nombresAcompanantes,
        escritos: _acompanantes,
      );'''),
    );
    expect(
      hastaElDibujo,
      contains('''
      final musica = musicaParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.musicaElegida,
        escrita: _musicaElegidaCtrl.text,
      ).trim();'''),
    );
    expect(
      RegExp(r'_musicaElegidaCtrl\.text').allMatches(hastaElDibujo).length,
      1,
      reason: 'la música se lee por fuera de musicaParaGuardar',
    );
    expect(
      RegExp(r'\b_acompanantes\b').allMatches(hastaElDibujo).length,
      1,
      reason: 'los acompañantes se leen por fuera de acompanantesParaGuardar',
    );
    // En la ficha, sin modo jefe no se agregan ni se sacan.
    expect(fuente, contains('enabled: esJefe,'));
    expect(fuente, contains('onPressed: !esJefe'));
    expect(fuente, contains('onDeleted: !esJefe'));
  });

  test('el link del delegado se maneja solo desde la ventana del jefe', () {
    // Crear el link, cerrarlo, reabrirlo, sacar a un delegado y aceptar lo que
    // mandaron pasan todos por `linkDelDelegadoProvider`. Solo lo lee la
    // pantalla de la fiesta, y adentro de la función que abre la ventana del
    // link (6.9.2), después de preguntar por el modo jefe.
    final quienes = <String>{
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('linkDelDelegadoProvider'))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {
      'lib/features/delegado/delegado_providers.dart',
      pantallaFiesta,
    });
    final fiesta = leer(pantallaFiesta);
    final i = fiesta.indexOf('Future<void> _abrirLinkDeLosDelegados() async {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fiesta.substring(i, fiesta.indexOf('\n  }\n', i));
    // Aparece dos veces: en la explicación de la función y donde se lee.
    expect('ref.read(linkDelDelegadoProvider)'.allMatches(fiesta), hasLength(1));
    final llave = cuerpo.indexOf('if (!ref.read(esRolJefeProvider)) {');
    expect(llave, greaterThanOrEqualTo(0));
    expect(
      cuerpo.indexOf('final link = ref.read(linkDelDelegadoProvider);'),
      greaterThan(llave),
      reason: 'el link se lee recién después de la llave',
    );
    expect(cuerpo.indexOf('LinkDelDelegadoVentana('), greaterThan(llave));
    // TRAER LO CARGADO abre el "Antes de guardar" de siempre, con sus llaves.
    expect(
      cuerpo,
      contains('onTraer: () => _abrirAcompanantesYMusica(traerDe: link),'),
    );

    // El renglón de PLANILLAS llega apagado sin modo jefe.
    final barra =
        leer('lib/features/eventos/widgets/grupo_fiesta_toolbar.dart');
    expect(barra, contains('accion: esJefe ? onLinkDeLosDelegados : null,'));

    // La ventana del link no tiene ningún camino a la grilla: no guarda
    // alumnos, solo le habla al link que le pasaron.
    final delLink =
        leer('lib/features/eventos/widgets/link_del_delegado_ventana.dart');
    for (final prohibido in [
      'onImportar',
      'contratosRepositoryProvider',
      'cargarAcompanantesYMusica',
      'linkDelDelegadoProvider',
      'ConsumerStatefulWidget',
    ]) {
      expect(delLink, isNot(contains(prohibido)), reason: prohibido);
    }
    // Y aceptar lo del link guarda por el mismo `onImportar` del Excel.
    final ventana =
        leer('lib/features/eventos/widgets/acompanantes_musica_dialog.dart');
    expect('widget.onImportar('.allMatches(ventana), hasLength(1));
    expect(ventana, isNot(contains('contratosRepositoryProvider')));
    expect(ventana, isNot(contains('cargarAcompanantesYMusica')));
    // La alerta del inicio llega por la misma función, con su llave.
    expect(fiesta, contains('if (mounted) _abrirLinkDeLosDelegados();'));
  });

  test('el Excel del delegado lo carga solo el jefe, con las tres llaves', () {
    // 1. El renglón de PLANILLAS llega apagado sin modo jefe.
    final barra =
        leer('lib/features/eventos/widgets/grupo_fiesta_toolbar.dart');
    expect(barra, contains('accion: esJefe ? onAcompanantesYMusica : null,'));

    final fiesta = leer(pantallaFiesta);
    final i = fiesta.indexOf(
      'Future<void> _abrirAcompanantesYMusica({LinkDelDelegado? traerDe}) async {',
    );
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fiesta.substring(i, fiesta.indexOf('\n  }\n', i));
    // 2. Al abrir.
    expect(cuerpo, contains('if (!ref.read(esRolJefeProvider)) return soloJefe();'));
    // 3. Otra vez justo antes de guardar, y antes que el guardado.
    final llave = cuerpo.indexOf('''
          if (!ref.read(esRolJefeProvider)) {
            throw StateError(kSoloEnModoJefe);
          }''');
    expect(llave, greaterThanOrEqualTo(0));
    expect(
      cuerpo.indexOf('cargarAcompanantesYMusica('),
      greaterThan(llave),
    );
  });

  test('nadie más carga acompañantes y música de a muchos', () {
    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('cargarAcompanantesYMusica('))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {
      pantallaFiesta,
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
  });

  // ── La venta de entradas (6.9.0) ───────────────────────────────────────────

  // 21-nov-2026, regla 50 de las entradas para rendir: dar entradas para
  // rendir, marcar las que no volvieron y anular un bloque, un "devolvió" o un
  // "no volvieron" (PARA RENDIR) son del jefe, con la misma llave.
  test('la venta de entradas: los precios, anular, "Pago verificado" y lo de las '
      'entradas para rendir (dar, no volvieron, anular) preguntan por el modo jefe '
      'antes de guardar', () {
    final escribe = RegExp(
      r'\.(guardarConfig|anular|verificar|darParaRendir|noVolvieron|anularDeParaRendir)\(',
    );
    final funcion = RegExp(r'^  Future<\w+> (\w+)\(', multiLine: true);
    final encontradas = <String>{};
    final carpeta = Directory('lib/features/entradas/widgets');
    for (final f in carpeta.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final fuente = leer(ruta);
      final funciones = funcion.allMatches(fuente).toList();
      for (final g in escribe.allMatches(fuente)) {
        final donde = funciones.lastWhere(
          (x) => x.start < g.start,
          orElse: () => fail('un guardado fuera de una función, en $ruta'),
        );
        encontradas.add(donde.group(1)!);
        expect(
          fuente.substring(donde.start, g.start),
          contains('_frenaSinModoJefe()'),
          reason: '${donde.group(1)} ($ruta) guarda sin preguntar por el modo jefe',
        );
      }
      if (escribe.hasMatch(fuente)) {
        final i = fuente.indexOf('bool _frenaSinModoJefe() {');
        expect(i, greaterThanOrEqualTo(0), reason: 'falta la llave en $ruta');
        final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
        // Son solo del jefe: quien vende no pone precios, no anula ni verifica.
        expect(cuerpo, contains('if (ref.read(esRolJefeProvider)) return false;'),
            reason: ruta);
        expect(cuerpo, contains('return true;'), reason: ruta);
        expect(fuente, isNot(contains('puedeVenderEntradasProvider)) return false')),
            reason: '$ruta: la llave del jefe no se abre a quien vende');
      }
    }
    // Si aparece otra función que guarda, que pregunte y se sume acá: PRECIOS
    // (`_guardar`) y sus mismos precios en otras fiestas (`_poner`, 22-nov-2026);
    // en VENTAS, anular y "Pago verificado"; y en PARA RENDIR, dar, las que no
    // volvieron y anular.
    expect(encontradas, {
      '_guardar',
      '_poner',
      '_anular',
      '_verificar',
      '_dar',
      '_noVolvieron',
      '_anularMovimiento',
    });
  });

  // 21-nov-2026: con una ventana en el medio, la llave del principio no
  // alcanza: el jefe puede salir del modo jefe (o vencerse el PIN) con la
  // ventana abierta y confirmar igual. Así que **después de la última ventana,
  // antes de escribir, la llave otra vez** (como RENDIR en VENDER).
  test('la venta de entradas: lo del jefe que abre una ventana antes de guardar vuelve '
      'a preguntar por el modo jefe después de ella', () {
    final escribe = RegExp(
      r'\.(guardarConfig|anular|verificar|darParaRendir|noVolvieron|anularDeParaRendir)\(',
    );
    final ventana = RegExp(
      r'await (showDialog|showModalBottomSheet|showDatePicker|mostrar\w*|pedir\w*|elegir\w*)\b',
    );
    final funcion = RegExp(r'^  Future<\w+> (\w+)\(', multiLine: true);
    final conVentana = <String>{};
    for (final f in Directory('lib/features/entradas/widgets').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final fuente = leer(ruta);
      final funciones = funcion.allMatches(fuente).toList();
      for (final g in escribe.allMatches(fuente)) {
        final donde = funciones.lastWhere((x) => x.start < g.start);
        final antes = fuente.substring(donde.start, g.start);
        final ventanas = ventana.allMatches(antes).toList();
        if (ventanas.isEmpty) continue;
        conVentana.add(donde.group(1)!);
        expect(
          antes.substring(ventanas.last.end),
          contains('if (_frenaSinModoJefe()) return;'),
          reason: '${donde.group(1)} ($ruta) guarda después de una ventana sin volver a '
              'preguntar por el modo jefe',
        );
      }
    }
    // Las que abren una ventana: en VENTAS, anular; en PARA RENDIR, dar, las
    // que no volvieron y anular. Si la regla no encontrara ninguna, no estaría
    // mirando nada.
    expect(conVentana, {'_anular', '_dar', '_noVolvieron', '_anularMovimiento'});
  });

  // 21-nov-2026: las ventanas de las entradas para rendir **no escriben**
  // (DAR y RENDIR devuelven lo elegido y guarda quien las abrió, con su llave).
  // Si una se pusiera a guardar, la llave quedaría del lado equivocado.
  test('las ventanas de DAR y RENDIR no guardan nada', () {
    final guarda = RegExp(
      r'\.(darParaRendir|noVolvieron|anularDeParaRendir|rendir|vender|abrirCaja)\(|'
      r'entradasDelJefeProvider|entradasDeLaCajaProvider',
    );
    for (final ruta in [
      'lib/features/entradas/widgets/dar_para_rendir_dialog.dart',
      'lib/features/entradas/widgets/rendir_entradas_dialog.dart',
      'lib/features/entradas/widgets/vender_para_rendir.dart',
    ]) {
      expect(guarda.hasMatch(leer(ruta)), isFalse, reason: '$ruta guarda');
    }
  });

  test('quien puede vender entradas es el jefe en modo jefe o quien tiene "Vende '
      'entradas", y nadie más', () {
    final fuente = leer('lib/features/caja_sesiones/providers/app_role_provider.dart');
    final i = fuente
        .indexOf('final puedeVenderEntradasProvider = Provider<bool>((ref) {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n});', i));
    expect(cuerpo, contains('if (ref.watch(esRolJefeProvider)) return true;'));
    expect(
      cuerpo,
      contains('return app.operador != null && app.permisos.vendeEntradas;'),
    );
    // Quien solo entrega no vende: la llave no mira el permiso de Entradas.
    expect(cuerpo, isNot(contains('PermisoOperador.entradas')));
  });

  // 20-nov-2026: VENDER también entrega lo sin cargo (GRATIS, en dos partes),
  // por `EntregarParte.entregar`: es otro guardado de la carpeta, con la misma
  // llave (`_entregar`).
  //
  // Revisión del 20-nov-2026: VENDER también pone al día la fila de
  // `entradas_retiro` (`EntregarParte.completarLaFila`, `_completarLaFila`), y la
  // regla no lo veía. Es automático (lo llama la lectura), así que su llave va
  // callada, sin cartel: `if (!ref.read(puedeVenderEntradasProvider)) return;`.
  //
  // 21-nov-2026, regla 51 de las entradas para rendir: RENDIR (en VENDER,
  // `_rendir`) guarda una venta y lo devuelto: pide el permiso de vender.
  test('la venta de entradas: abrir una caja, vender, entregar lo sin cargo, poner al '
      'día la fila de la entrega, rendir y cerrarla preguntan por el permiso de '
      'vender antes de guardar', () {
    final escribe = RegExp(
      r'\.(abrirCaja|cerrarCaja|vender|guardarEn|entregar|completarLaFila|rendir)\(',
    );
    final funcion = RegExp(r'^  Future<\w+> (\w+)\(', multiLine: true);
    // Las que corren solas, sin que nadie toque un botón: la llave sin cartel.
    const automaticas = {'_completarLaFila'};
    const llaveCallada = 'if (!ref.read(puedeVenderEntradasProvider)) return;';
    final encontradas = <String>{};
    final carpeta = Directory('lib/features/entradas/widgets');
    for (final f in carpeta.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final ruta = f.path.replaceAll('\\', '/');
      final fuente = leer(ruta);
      final funciones = funcion.allMatches(fuente).toList();
      for (final g in escribe.allMatches(fuente)) {
        final donde = funciones.lastWhere(
          (x) => x.start < g.start,
          orElse: () => fail('un guardado fuera de una función, en $ruta'),
        );
        final nombre = donde.group(1)!;
        encontradas.add(nombre);
        expect(
          fuente.substring(donde.start, g.start),
          contains(automaticas.contains(nombre) ? llaveCallada : '_frenaSinPermiso()'),
          reason: '$nombre ($ruta) guarda sin preguntar si puede vender',
        );
      }
      if (escribe.hasMatch(fuente)) {
        final i = fuente.indexOf('bool _frenaSinPermiso() {');
        expect(i, greaterThanOrEqualTo(0), reason: 'falta la llave en $ruta');
        final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
        expect(
          cuerpo,
          contains('if (ref.read(puedeVenderEntradasProvider)) return false;'),
          reason: ruta,
        );
        expect(cuerpo, contains('return true;'), reason: ruta);
      }
    }
    // Si aparece otra función que guarda, que pregunte y se sume acá.
    expect(
      encontradas,
      {'_abrir', '_cobrar', '_cerrarDeVerdad', '_entregar', '_completarLaFila', '_rendir'},
    );
  });

  test('PRECIOS se abre solo desde ENTRADAS de la fiesta, y con la llave', () {
    const pantallaEntradas = 'lib/features/eventos/retiro_entradas_screen.dart';
    final fuente = leer(pantallaEntradas);
    final i = fuente.indexOf('Future<void> _abrirPrecios() async {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
    final llave = cuerpo.indexOf('if (!ref.read(esRolJefeProvider)) return;');
    expect(llave, greaterThanOrEqualTo(0));
    expect(cuerpo.indexOf('mostrarPreciosDeEntradas('), greaterThan(llave));

    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('mostrarPreciosDeEntradas('))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {
      pantallaEntradas,
      'lib/features/entradas/widgets/precios_de_entradas_dialog.dart',
    });
  });

  // 6.9.0, etapa 7: VENDER, VENDERLE ESAS ENTRADAS y VENTAS se abren desde la
  // entrega con su llave, antes de la pantalla (el botón ya viene apagado: es la
  // segunda llave, por si el permiso cambió con el cartel abierto).
  //
  // 21-nov-2026, regla 52: PARA RENDIR también, con la llave del jefe (como
  // VENTAS).
  test('VENDER, VENDERLE ESAS ENTRADAS, VENTAS y PARA RENDIR se abren desde la entrega '
      'con su llave', () {
    final fuente = leer('lib/features/eventos/retiro_entradas_screen.dart');
    for (final (funcion, llave) in [
      (
        'Future<void> _abrirParaRendir() async {',
        'if (!ref.read(esRolJefeProvider)) return;'
      ),
      (
        'Future<void> _venderAlCincuenta(ContratoAlumno a) async {',
        'if (!ref.read(puedeVenderEntradasProvider)) return;'
      ),
      (
        'Future<void> _abrirVender() async {',
        'if (!ref.read(puedeVenderEntradasProvider)) return;'
      ),
      (
        'Future<void> _abrirVentas() async {',
        'if (!ref.read(esRolJefeProvider)) return;'
      ),
    ]) {
      final i = fuente.indexOf(funcion);
      expect(i, greaterThanOrEqualTo(0), reason: 'no está $funcion');
      final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
      final donde = cuerpo.indexOf(llave);
      expect(donde, greaterThanOrEqualTo(0), reason: '$funcion sin su llave');
      expect(cuerpo.indexOf('Navigator.of(context).push('), greaterThan(donde),
          reason: '$funcion abre la pantalla antes de la llave');
    }
  });

  // 21-nov-2026, regla 52: PARA RENDIR tiene una sola puerta, ENTRADAS de la
  // fiesta, y el botón se prende solo con el modo jefe (y en el equipo). Otra
  // pantalla que la abriera se saltearía la primera llave.
  test('PARA RENDIR se abre solo desde ENTRADAS de la fiesta, con el botón del jefe',
      () {
    const pantallaEntradas = 'lib/features/eventos/retiro_entradas_screen.dart';
    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('ParaRendirScreen('))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {
      pantallaEntradas,
      'lib/features/entradas/widgets/para_rendir_screen.dart',
    });
    final fuente = leer(pantallaEntradas);
    final i = fuente.indexOf('get _paraRendir {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
    expect(cuerpo, contains('prendido: esJefe && enElEquipo,'));
    expect(fuente, contains('onPressed: prendido ? _abrirParaRendir : null,'));
    // En el mostrador no está: va con PRECIOS, VENDER y VENTAS.
    final barra = fuente.indexOf('if (!widget.enElMostrador) ...[');
    expect(barra, greaterThanOrEqualTo(0));
    expect(
      fuente.substring(barra, fuente.indexOf('],', barra)),
      contains('_botonParaRendir()'),
    );
  });

  // 17-nov-2026: aceptar la lista de PRECIOS de una fiesta ya sorteada le
  // agrega `_lugares` al renglón del sorteo. **Es lo único que toca un renglón
  // ya escrito del registro**, y desde ahí decide qué entradas van con
  // descuento en todas las PCs: lo hace solo el jefe, por un solo camino.
  test('los lugares al sorteo de una fiesta ya sorteada los acepta solo el jefe, '
      'por un solo camino', () {
    const repo = 'lib/features/eventos/repositories/sorteos_mesas_repository.dart';
    const adaptador =
        'lib/features/eventos/repositories/revision_de_lugares_de_la_app.dart';
    const ventana = 'lib/features/eventos/widgets/lugares_al_sorteo_dialog.dart';
    const entradas = 'lib/features/eventos/retiro_entradas_screen.dart';

    Set<String> quienesNombran(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };

    // El guardado: el repositorio lo define y solo el adaptador lo llama.
    expect(quienesNombran('completarLugares'), {repo, adaptador});
    // El adaptador lo usa solo la ventana de la lista.
    expect(quienesNombran('revisionDeLugaresProvider'), {adaptador, ventana});
    // Y la ventana se abre solo desde ENTRADAS de la fiesta.
    expect(quienesNombran('mostrarRevisionDeLugares('), {ventana, entradas});

    // La ventana: la segunda llave, antes de pedirle nada a la revisión.
    final v = leer(ventana);
    final llave = v.indexOf('bool _frenaSinModoJefe() {');
    expect(llave, greaterThanOrEqualTo(0));
    final cuerpoLlave = v.substring(llave, v.indexOf('\n  }', llave));
    expect(cuerpoLlave, contains('if (ref.read(esRolJefeProvider)) return false;'));
    expect(cuerpoLlave, contains('return true;'));
    final aceptar = v.indexOf('Future<void> _aceptar() async {');
    expect(aceptar, greaterThanOrEqualTo(0));
    final cuerpoAceptar = v.substring(aceptar, v.indexOf('\n  }', aceptar));
    final frena = cuerpoAceptar.indexOf('if (_frenaSinModoJefe()) return;');
    expect(frena, greaterThanOrEqualTo(0));
    expect(cuerpoAceptar.indexOf('.aceptar('), greaterThan(frena));
    expect(
      RegExp(r'\.aceptar\(').allMatches(v).length,
      1,
      reason: 'un solo lugar acepta, y es detrás de la llave',
    );

    // ENTRADAS: la abre con su llave, antes de la ventana.
    final e = leer(entradas);
    final abre = e.indexOf('Future<FotoDeLosLugares?> _revisarLugares(');
    expect(abre, greaterThanOrEqualTo(0));
    final cuerpoAbre = e.substring(abre, e.indexOf('\n  }', abre));
    final llaveAbre =
        cuerpoAbre.indexOf('if (!ref.read(esRolJefeProvider)) return null;');
    expect(llaveAbre, greaterThanOrEqualTo(0));
    expect(cuerpoAbre.indexOf('mostrarRevisionDeLugares('), greaterThan(llaveAbre));
  });

  test('el registro de sorteos: solo se agregan renglones, y lo único que se le '
      'suma a uno ya escrito son los lugares', () {
    final repo =
        leer('lib/features/eventos/repositories/sorteos_mesas_repository.dart');
    expect(RegExp(r'\.(delete|rawDelete|rawUpdate)\(').hasMatch(repo), isFalse);
    final ediciones = RegExp(r'\.update\(').allMatches(repo).toList();
    expect(ediciones, hasLength(1));
    final desde = repo.indexOf('static Future<bool> completarLugaresEn(');
    final hasta = repo.indexOf('\n  }\n', desde);
    expect(ediciones.single.start, inInclusiveRange(desde, hasta));
    final cuerpo = repo.substring(desde, hasta);
    // Reescribe el texto crudo con la clave agregada: no pasa por el modelo,
    // que perdería una clave que esta versión no conozca.
    expect(cuerpo, contains('SorteoMesasRegistro.resultadoConLugares('));
    expect(cuerpo, isNot(contains('.toMap()')));
    // Solo cambia el texto y la fecha de la fila.
    expect(cuerpo, contains("{'resultado': fila['resultado'], 'updated_at': fila['updated_at']}"));
    // Y sube.
    expect(cuerpo, contains('SyncQueue.enqueue('));

    // Fuera del repositorio nadie escribe la tabla a mano.
    final aMano = RegExp("(insert|update|delete)\\(\\s*'sorteos_mesas'");
    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            aMano.hasMatch(f.readAsStringSync()))
          f.path.replaceAll('\\', '/'),
    };
    expect(
      quienes.difference({
        'lib/features/eventos/repositories/sorteos_mesas_repository.dart',
        // El motor, al bajar de la nube.
        'lib/core/services/sync_engine.dart',
      }),
      isEmpty,
    );
  });

  test('la mesa adicional "a confirmar" (6.9.2): cobrarla y anularla se hace '
      'solo en el PLANO y en modo jefe, y la ficha se edita por un solo camino',
      () {
    Set<String> archivosCon(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };
    const cuerpoDelPlano = 'lib/features/plano/widgets/plano_evento_cuerpo.dart';
    const edicion = 'lib/features/eventos/services/edicion_de_alumno.dart';
    const ficha = 'lib/features/eventos/widgets/modal_alumno_premium.dart';
    final plano = leer(pantallaPlano);

    String funcionDe(String nombre) {
      final i = plano.indexOf('  Future<void> $nombre(');
      expect(i, greaterThan(0), reason: nombre);
      return plano.substring(i, plano.indexOf('\n  }\n', i));
    }

    // Las dos preguntan por el modo jefe antes de hacer nada.
    for (final nombre in ['_cobrarAConfirmar', '_anularAConfirmar']) {
      final cuerpo = funcionDe(nombre);
      final llave = cuerpo.indexOf('_frenaSinModoJefe()');
      expect(llave, greaterThan(0), reason: nombre);
      expect(llave, lessThan(cuerpo.indexOf('await ')), reason: nombre);
    }
    // Y el cuerpo del plano las recibe solo en modo jefe (`acciones: esJefe`).
    expect(plano, contains('onCobrarAConfirmar: _cobrarAConfirmar,'));
    expect(plano, contains('onAnularAConfirmar: _anularAConfirmar,'));
    expect(archivosCon('onAnularAConfirmar'), {pantallaPlano, cuerpoDelPlano});
    expect(archivosCon('onCobrarAConfirmar'), {pantallaPlano, cuerpoDelPlano});

    // COBRAR no guarda nada: cierra el plano y la fiesta abre el cobro de
    // siempre.
    final cobrar = funcionDe('_cobrarAConfirmar');
    expect(cobrar, contains('navegador.pop(CobrarDesdeElPlano(alumnoId))'));
    for (final guarda in ['_cambiarMesas(', 'guardarEdicionDeAlumno(', 'Repository']) {
      expect(cobrar, isNot(contains(guarda)), reason: guarda);
    }
    final fiesta = leer(pantallaFiesta);
    final abrir = fiesta.substring(
      fiesta.indexOf('  Future<void> _abrirPlano('),
      fiesta.indexOf('  Future<void> _cargarPagosExtras('),
    );
    expect(abrir, contains('alCerrar is! CobrarDesdeElPlano'));
    expect(abrir, contains('await _mostrarModalPagoAlumno(aQuien);'));
    expect(archivosCon('CobrarDesdeElPlano'), {pantallaFiesta, pantallaPlano});

    // ANULAR: la mesa, por el guardado de mesas de siempre (con su llave, su
    // renglón y la puerta al día); solo con internet y con lo último bajado.
    final anular = funcionDe('_anularAConfirmar');
    expect(anular, contains('await _cambiarMesas('));
    expect(anular, contains('CambiosDeMesa.soltarUna('));
    expect(anular, contains('motivoFijo: CambiosDeMesa.motivoAnulada,'));
    expect(anular, contains('sinInternetNoSeHace: sinInternet,'));
    expect(
      anular,
      contains('if (!await motor.bajarParaLosLugares()) return sinInternet;'),
    );
    // Con algo pagado no se anula, y si después no se va a poder bajar del
    // contrato, la mesa no se suelta.
    expect(anular, contains('if (!x.sePuedeAnular) {'));
    expect(anular, contains('final baja = BajaDeAdicional.de(a);'));
    expect(archivosCon('CambiosDeMesa.soltarUna('), {pantallaPlano});
    expect(archivosCon('BajaDeAdicional.de('), {pantallaPlano});

    // El contrato se baja por el camino de Editar alumno, que es uno solo.
    expect(archivosCon('guardarEdicionDeAlumno('), {
      edicion,
      ficha,
      pantallaPlano,
    });
    expect('guardarEdicionDeAlumno('.allMatches(plano).length, 1);
    expect(anular, contains('await guardarEdicionDeAlumno('));
    expect('guardarEdicionDeAlumno('.allMatches(leer(ficha)).length, 1);
    final servicio = leer(edicion);
    final guardar = servicio.substring(
      servicio.indexOf('Future<void> guardarEdicionDeAlumno('),
      servicio.indexOf('class BajaDeAdicional'),
    );
    expect(guardar, contains('datosEdicionAlumno('));
    expect(guardar, contains('repo.recalcularProgresoContrato(antes.id)'));
    expect(guardar, contains('repo.reconciliarMesasEstadoContrato(antes.id)'));
    // La ventana de Editar alumno ya no arma la ficha por su cuenta.
    expect(leer(ficha), isNot(contains('repo.actualizarContrato(')));
    // La pantalla del plano no escribe la ficha por ningún otro lado.
    expect(plano, isNot(contains('actualizarContrato(')));

    // En la puerta nadie cobra ni anula.
    for (final f in Directory('lib/features/recepcion').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final fuente = f.readAsStringSync();
      for (final no in ['AConfirmar(alumnoId', 'BajaDeAdicional', 'soltarUna(']) {
        expect(fuente, isNot(contains(no)), reason: '${f.path}: $no');
      }
    }
  });
}
