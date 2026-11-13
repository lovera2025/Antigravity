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
    // Crear el link, apagarlo, sacar a un delegado y aceptar lo que mandaron
    // pasan todos por `linkDelDelegadoProvider`. Solo lo lee la pantalla de la
    // fiesta, y adentro de la función que ya tiene las llaves del modo jefe:
    // así lo del link queda detrás de las mismas tres llaves que el Excel.
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
    final i = fiesta.indexOf(
      'Future<void> _abrirAcompanantesYMusica({bool traerDelLink = false}) async {',
    );
    final cuerpo = fiesta.substring(i, fiesta.indexOf('\n  }\n', i));
    expect('linkDelDelegadoProvider'.allMatches(fiesta), hasLength(1));
    expect(cuerpo, contains('link: ref.read(linkDelDelegadoProvider),'));
    // Y aceptar lo del link guarda por el mismo `onImportar` del Excel: la
    // ventana no tiene otro camino a la grilla.
    final ventana =
        leer('lib/features/eventos/widgets/acompanantes_musica_dialog.dart');
    expect('widget.onImportar('.allMatches(ventana), hasLength(1));
    expect(ventana, isNot(contains('contratosRepositoryProvider')));
    expect(ventana, isNot(contains('cargarAcompanantesYMusica')));
    // La alerta del inicio llega por la misma función, con sus llaves.
    expect(
      fiesta,
      contains('if (mounted) _abrirAcompanantesYMusica(traerDelLink: true);'),
    );
  });

  test('el Excel del delegado lo carga solo el jefe, con las tres llaves', () {
    // 1. El renglón de PLANILLAS llega apagado sin modo jefe.
    final barra =
        leer('lib/features/eventos/widgets/grupo_fiesta_toolbar.dart');
    expect(barra, contains('accion: esJefe ? onAcompanantesYMusica : null,'));

    final fiesta = leer(pantallaFiesta);
    final i = fiesta.indexOf(
      'Future<void> _abrirAcompanantesYMusica({bool traerDelLink = false}) async {',
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
}
